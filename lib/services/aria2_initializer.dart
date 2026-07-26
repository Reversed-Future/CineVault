import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'aria2_manager.dart';
import 'aria2_service.dart';
import 'database_service.dart';
import 'tracker_updater.dart';

/// Aria2 初始化器
///
/// 重要：应用启动时只做轻量配置（RPC、trackers 配置），**不启动** aria2c 进程
/// 真正需要下载时再调用 [ensureAria2Running] 延迟启动
class Aria2Initializer {
  /// 是否已经预配置过
  static bool _initialized = false;

  /// 轻量级预配置（应用启动时调用）
  ///
  /// 只配置 RPC 客户端和 manager（trackers 等），不启动 aria2c 进程
  /// 避免每次开应用都启动一个后台进程浪费资源
  static Future<void> initialize() async {
    if (_initialized) return;
    final settings = DatabaseService.getSettings();
    if (settings == null) return;

    final manager = Aria2Manager();
    final service = Aria2Service();

    // 1. 配置 RPC 客户端（不发起请求，仅设置 host/port/secret）
    service.configure(
      host: '127.0.0.1',
      port: settings.aria2RpcPort,
      secret: settings.aria2RpcSecret,
    );

    // 2. 配置 manager（trackers 准备好，进程启动时直接用）
    final trackersForCli = _convertTrackersToAria2Format(
      settings.aria2TrackersList,
    );
    manager.configure(
      rpcSecret: settings.aria2RpcSecret ?? '',
      trackers: trackersForCli ?? '',
    );

    _initialized = true;
    print('[Aria2Initializer] Pre-configured (RPC + manager). aria2c NOT started.');

    // 3. 如果启用了自动更新 trackers，在后台静默更新（不依赖 aria2c 运行）
    if (settings.autoUpdateTrackers) {
      final lastUpdate = settings.lastTrackersUpdateTime;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (lastUpdate == null || (now - lastUpdate) > 24 * 60 * 60 * 1000) {
        print('[Aria2Initializer] Auto-updating trackers in background...');
        _autoUpdateTrackersInBackground();
      }
    }
  }

  /// 确保 aria2 正在运行
  ///
  /// 真正的下载/磁力解析需要 aria2c 运行。在以下场景调用：
  /// - 用户打开磁力文件选择弹窗前
  /// - 用户通过 URL 下载前
  /// - 用户在下载设置页点击"启动 aria2"按钮
  ///
  /// 如果已运行则直接返回 true
  /// 如果 aria2c 未安装，会返回 false
  static Future<bool> ensureAria2Running() async {
    // 先确保预配置完成（幂等）
    if (!_initialized) {
      await initialize();
    }

    final settings = DatabaseService.getSettings();
    if (settings == null) return false;

    final manager = Aria2Manager();
    final service = Aria2Service();

    // 检查是否已经在运行
    if (manager.status == Aria2ProcessStatus.running) {
      // 顺便再确认 RPC 可用
      if (await service.isAvailable()) {
        return true;
      }
    }

    // 检查 aria2c 是否已安装
    if (!await manager.isAria2Installed()) {
      print('[Aria2Initializer] aria2c not installed, cannot auto-start');
      return false;
    }

    // 启动 aria2c
    print('[Aria2Initializer] Lazy-starting aria2c...');
    final success = await manager.start();
    if (success) {
      print('[Aria2Initializer] aria2 started successfully');
      // 应用全局选项
      await _applyGlobalOptions(service, settings);
      return true;
    } else {
      print(
          '[Aria2Initializer] Failed to start aria2: ${manager.errorMessage}');
      return false;
    }
  }

  /// 应用全局选项到 aria2
  ///
  /// 注意：trackers 由 Aria2Manager 启动后通过 RPC 设置，避免重复设置导致
  /// bt-tracker 字符串超出 aria2 限制（64KB）返回 400 错误
  static Future<void> _applyGlobalOptions(
    Aria2Service service,
    settings,
  ) async {
    try {
      final options = Aria2GlobalOptions(
        maxConcurrentDownloads: settings.aria2MaxConcurrentDownloads,
        maxConnectionPerServer: settings.aria2MaxConnectionPerServer,
        maxOverallDownloadLimit:
            settings.aria2DownloadSpeedLimitKB * 1024, // KB/s -> 字节/秒
        maxOverallUploadLimit: settings.aria2UploadSpeedLimitKB * 1024,
        // 不再传 btTracker：Aria2Manager 启动时已经设置过了
        // 避免重复设置触发 64KB 限制
      );
      await service.changeGlobalOption(options);
    } catch (e) {
      print('[Aria2Initializer] Failed to apply global options: $e');
    }
  }

  /// 将 trackers 从换行/逗号格式转换为 aria2 需要的逗号格式
  static String? _convertTrackersToAria2Format(String? trackersString) {
    if (trackersString == null || trackersString.isEmpty) return null;
    // 按换行、逗号分号空白等分隔符分割
    final trackers = trackersString
        .split(RegExp(r'[\n,;\s]+'))
        .where((t) => t.trim().isNotEmpty)
        .toSet()
        .toList();
    if (trackers.isEmpty) return null;
    return trackers.join(',');
  }

  /// 后台更新 trackers
  ///
  /// 1. 使用订阅名单中的源（用户通过弹窗添加的）
  /// 2. 与现有 trackers 列表去重合并，保留已有内容
  static void _autoUpdateTrackersInBackground() {
    () async {
      try {
        final updater = TrackerUpdater();
        final settings = DatabaseService.getSettings()!;

        // 获取用户订阅的源（用户通过弹窗添加的源）
        List<String>? customSources;
        final sourceUrlsText = settings.trackersSourceUrls?.trim();
        if (sourceUrlsText != null && sourceUrlsText.isNotEmpty) {
          customSources = sourceUrlsText
              .split(RegExp(r'[\n,;\s]+'))
              .where((url) => url.trim().isNotEmpty)
              .toList();
        }

        final newTrackers = await updater.updateTrackers(sources: customSources);

        // 与现有 trackers 去重合并
        final existingTrackers = (settings.aria2TrackersList ?? '')
            .split(RegExp(r'[\n,;\s]+'))
            .where((t) => t.trim().isNotEmpty)
            .toSet();

        final addedTrackers = newTrackers
            .where((t) => !existingTrackers.contains(t))
            .toList();

        final mergedSet = <String>{...existingTrackers, ...addedTrackers};
        final mergedList = mergedSet.toList()..sort();
        final mergedText = mergedList.join('\n');

        final newSettings = settings.copyWith(
          aria2TrackersList: mergedText,
          lastTrackersUpdateTime: DateTime.now().millisecondsSinceEpoch,
        );
        await DatabaseService.saveSettings(newSettings);
        print(
            '[Aria2Initializer] Trackers updated: existing=${existingTrackers.length}, added=${addedTrackers.length}, total=${mergedList.length}');
      } catch (e) {
        print('[Aria2Initializer] Failed to update trackers: $e');
      }
    }();
  }

  /// 关闭时清理
  static Future<void> shutdown() async {
    final manager = Aria2Manager();
    await manager.stop();
  }
}

/// Aria2Initializer 初始化 Provider
final aria2InitProvider = Provider<Future<void>>((ref) async {
  await Aria2Initializer.initialize();
});
