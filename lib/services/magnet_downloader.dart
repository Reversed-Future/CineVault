import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'aria2_downloader.dart';
import 'aria2_initializer.dart';
import 'aria2_manager.dart';
import 'aria2_service.dart';
import 'database_service.dart';

/// 磁力链接文件信息（解析后）
class MagnetFileInfo {
  final int index;
  final String name;
  final String? fullPath; // 完整路径
  final int size; // 字节
  final String? ext;

  MagnetFileInfo({
    required this.index,
    required this.name,
    this.fullPath,
    this.size = 0,
  }) : ext = path.extension(name).isEmpty
            ? null
            : path.extension(name).toLowerCase().replaceFirst('.', '');

  String get formattedSize {
    if (size <= 0) return '未知';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// 磁力下载结果
class MagnetDownloadResult {
  final bool success;
  final String? errorMessage;
  final String? localDir;
  final int? totalSize;

  MagnetDownloadResult({
    required this.success,
    this.errorMessage,
    this.localDir,
    this.totalSize,
  });
}

/// 磁力解析状态
enum MagnetParseStatus {
  /// 成功获取到真实文件列表
  success,

  /// 元数据还在下载中（UI 应继续等待）
  loading,

  /// 元数据完整但确实没文件
  empty,

  /// 超时未找到任何 peers
  timeout,

  /// 链接无效/aria2 不可用/任务出错
  error,
}

/// 磁力解析结果（带状态机）
class MagnetParseResult {
  final MagnetParseStatus status;
  final List<MagnetFileInfo> files;
  final String? errorMessage;

  const MagnetParseResult({
    required this.status,
    this.files = const [],
    this.errorMessage,
  });

  bool get isSuccess => status == MagnetParseStatus.success;
  bool get isLoading => status == MagnetParseStatus.loading;
  bool get isTimeout => status == MagnetParseStatus.timeout;
  bool get isError => status == MagnetParseStatus.error;
  bool get isEmpty => status == MagnetParseStatus.empty;
}

/// 磁力链接下载辅助类
///
/// 提供以下功能：
/// 1. 通过 aria2 添加磁力下载任务
/// 2. 唤起系统默认下载器
/// 3. 下载路径选择与记忆
class MagnetDownloader {
  static final MagnetDownloader _instance = MagnetDownloader._internal();
  factory MagnetDownloader() => _instance;
  MagnetDownloader._internal();

  static const String _kLastDownloadDirKey = 'last_magnet_download_dir';

  final Aria2Service _aria2Service = Aria2Service();
  final Aria2Manager _aria2Manager = Aria2Manager();
  final Aria2Downloader _aria2Downloader = Aria2Downloader();

  /// 获取上次的下载目录
  Future<String?> getLastDownloadDir() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLastDownloadDirKey);
  }

  /// 保存下载目录
  Future<void> setLastDownloadDir(String dir) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastDownloadDirKey, dir);
  }

  /// 选择下载目录（弹出文件选择器）
  ///
  /// [initialPath] 初始路径
  /// 返回用户选择的目录路径，取消则返回 null
  Future<String?> pickDownloadDir({String? initialPath}) async {
    try {
      // file_picker 在新版中有 getDirectoryPath
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择下载保存目录',
        initialDirectory: initialPath,
      );
      return result;
    } catch (e) {
      print('[MagnetDownloader] pickDownloadDir error: $e');
      return null;
    }
  }

  /// 获取默认下载目录
  Future<String> getDefaultDownloadDir() async {
    // 1. 优先使用上次保存的路径
    final lastDir = await getLastDownloadDir();
    if (lastDir != null && await Directory(lastDir).exists()) {
      return lastDir;
    }

    // 2. 尝试使用 aria2 工作目录
    final aria2Dir = await _aria2Manager.aria2Dir;
    if (aria2Dir != null) return aria2Dir;

    // 3. 回退到临时目录
    final tempDir = Directory.systemTemp;
    final downloads =
        Directory(path.join(tempDir.path, 'cine_vault_downloads'));
    if (!await downloads.exists()) {
      await downloads.create(recursive: true);
    }
    return downloads.path;
  }

  /// 通过 aria2 添加磁力链接
  ///
  /// [magnet] 磁力链接
  /// [saveDir] 保存目录
  /// [trackers] 自定义 trackers（可选）
  /// [selectedIndices] 用户选择的文件索引列表（1-based，null=下载所有）
  Future<MagnetDownloadResult> downloadViaAria2({
    required String magnet,
    required String saveDir,
    List<String>? trackers,
    List<int>? selectedIndices,
  }) async {
    if (!await _aria2Service.isAvailable()) {
      // 尝试延迟启动
      print('[MagnetDownloader] aria2 not running, lazy-starting...');
      final started = await Aria2Initializer.ensureAria2Running();
      if (!started) {
        return MagnetDownloadResult(
          success: false,
          errorMessage: 'aria2 服务不可用，且未能自动启动（请先在下载设置中安装并启动）',
        );
      }
    }

    try {
      // 确保目录存在
      final dir = Directory(saveDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      String gid;
      if (trackers != null && trackers.isNotEmpty) {
        gid = await _aria2Service.addMagnet(
          magnet,
          dir: saveDir,
          trackers: trackers,
        );
      } else {
        gid = await _aria2Service.addUri(
          [magnet],
          dir: saveDir,
        );
      }

      // 如果用户指定了部分文件，等元数据就绪后设置 selected=false
      if (selectedIndices != null) {
        await _applyFileSelection(gid, selectedIndices);
      }

      return MagnetDownloadResult(
        success: true,
        localDir: saveDir,
      );
    } catch (e) {
      return MagnetDownloadResult(
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// 应用文件选择（通过 aria2.changeOption 设置 selected）
  ///
  /// aria2c 的 select-file 选项支持：
  /// - `select-file=1-5,8` 选择 1-5 和 8
  /// - `select-file=all` 选择所有
  Future<void> _applyFileSelection(
      String gid, List<int> selectedIndices) async {
    if (selectedIndices.isEmpty) return;
    try {
      // 等待元数据就绪（最多 60 秒）
      final startTime = DateTime.now();
      while (
          DateTime.now().difference(startTime) < const Duration(seconds: 60)) {
        try {
          final files = await _aria2Service.getFiles(gid);
          if (files.isNotEmpty) {
            // 构造 select-file 选项：选中的索引
            final selectFileStr = selectedIndices.join(',');
            await _aria2Service.changeOption(gid, {
              'select-file': selectFileStr,
            });
            print(
                '[MagnetDownloader] Applied select-file: $selectFileStr to gid=$gid');
            return;
          }
        } catch (e) {
          // 元数据未就绪
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    } catch (e) {
      print('[MagnetDownloader] _applyFileSelection error: $e');
    }
  }

  /// 通过系统下载器唤起磁力链接
  ///
  /// [magnet] 磁力链接
  /// [movieCode] 影片资料 ID（用于生成文件名前缀）
  Future<MagnetDownloadResult> openWithSystemDownloader({
    required String magnet,
    String? movieCode,
  }) async {
    try {
      // Windows 上 magnet:? 协议通常被 qBittorrent / uTorrent 等 BT 软件注册
      final uri = Uri.parse(magnet);

      if (await canLaunchUrl(uri)) {
        final launched =
            await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (launched) {
          return MagnetDownloadResult(success: true);
        }
      }

      // 备用方案：用 Process.start 调用 cmd
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', magnet],
            runInShell: true);
        return MagnetDownloadResult(success: true);
      }

      return MagnetDownloadResult(
        success: false,
        errorMessage: '未找到可用的磁力链接处理器',
      );
    } catch (e) {
      return MagnetDownloadResult(
        success: false,
        errorMessage: '唤起系统下载器失败: $e',
      );
    }
  }

  /// 解析磁力链接，获取文件列表
  ///
  /// 重要原则（基于真实 BT 客户端工作流程）：
  /// 1. 添加 magnet 后，aria2 进入 "waiting" 或 "active" 状态
  /// 2. aria2 通过 DHT/PEX/trackers 找 peers
  /// 3. peers 找到后开始下载 torrent 的 metadata（几十~几百 KB）
  /// 4. metadata 完整后，aria2 才知道真实的 file tree
  /// 5. 在 metadata 未完整时，getFiles() 可能返回 1 个 size=0 的 [METADATA]xxx 占位符
  ///
  /// **关键修复**：
  /// - 不再返回占位符给 UI
  /// - 严格判断 metadata ready：必须 totalLength > 0 且所有文件都有真实大小
  /// - 用状态枚举（loading/ready/error）让 UI 区分"等待中"和"无文件"
  ///
  /// 返回 MagnetParseResult 包含状态机：
  /// - [MagnetParseStatus.success] + files: 成功获取到真实文件列表
  /// - [MagnetParseStatus.loading]: 元数据还在下载中（UI 应继续等待）
  /// - [MagnetParseStatus.empty]: 元数据完整但确实没文件（理论上不会发生）
  /// - [MagnetParseStatus.timeout]: 超时未找到任何 peers
  /// - [MagnetParseStatus.error]: 链接无效/aria2 不可用/任务出错
  Future<MagnetParseResult> getMagnetFiles(String magnet) async {
    // 1. 基本格式检查
    if (!magnet.toLowerCase().startsWith('magnet:')) {
      print('[MagnetDownloader] Invalid magnet format');
      return MagnetParseResult(
        status: MagnetParseStatus.error,
        errorMessage: '磁力链接格式无效',
      );
    }
    if (!magnet.toLowerCase().contains('xt=urn:btih:') &&
        !magnet.toLowerCase().contains('xt=urn:btmh:')) {
      print('[MagnetDownloader] Missing info hash in magnet');
      return MagnetParseResult(
        status: MagnetParseStatus.error,
        errorMessage: '缺少 info hash',
      );
    }

    if (!await _aria2Service.isAvailable()) {
      // 尝试延迟启动 aria2c（应用启动时不再强制启动）
      print('[MagnetDownloader] aria2 not running, trying to start...');
      final started = await Aria2Initializer.ensureAria2Running();
      if (!started) {
        return MagnetParseResult(
          status: MagnetParseStatus.error,
          errorMessage: 'aria2 服务不可用，且未能自动启动（请在下载设置中检查）',
        );
      }
      // 再次确认 RPC 可用
      if (!await _aria2Service.isAvailable()) {
        return MagnetParseResult(
          status: MagnetParseStatus.error,
          errorMessage: 'aria2 启动后仍不可用',
        );
      }
    }

    String? gid;
    try {
      final saveDir = await getDefaultDownloadDir();

      // 2. 读取设置中的 trackers
      final settings = DatabaseService.getSettings();
      final trackersString = settings?.aria2TrackersList;
      List<String>? trackers;
      if (trackersString != null && trackersString.isNotEmpty) {
        final parsed = trackersString
            .split(RegExp(r'[\n,;\s]+'))
            .where((t) => t.trim().isNotEmpty)
            .toList();
        if (parsed.isNotEmpty) {
          trackers = parsed;
        }
      }

      // 3. 添加到 aria2（**不暂停**让它去获取元数据，带上 trackers）
      gid = await _aria2Service.addMagnet(
        magnet,
        dir: saveDir,
        trackers: trackers,
      );
      print(
          '[MagnetDownloader] Magnet added, gid=$gid, trackers=${trackers?.length ?? 0}, waiting for metadata...');

      // 4. 严格轮询：等待 metadata 真正 ready
      //    ready 条件：totalLength > 0 且 getFiles 返回所有 size > 0 的文件
      final startTime = DateTime.now();
      final maxDuration = const Duration(seconds: 120);
      int pollCount = 0;
      int consecutiveNoPeers = 0;

      while (DateTime.now().difference(startTime) < maxDuration) {
        pollCount++;
        try {
          final status = await _aria2Service.tellStatus(gid);

          // 任务出错
          if (status.isError) {
            print('[MagnetDownloader] Task error: ${status.errorMessage}');
            await _cleanupTask(gid);
            return MagnetParseResult(
              status: MagnetParseStatus.error,
              errorMessage: status.errorMessage ?? '任务出错',
            );
          }

          if (status.isRemoved) {
            print('[MagnetDownloader] Task was removed');
            return MagnetParseResult(
              status: MagnetParseStatus.error,
              errorMessage: '任务被移除',
            );
          }

          print(
              '[MagnetDownloader] Poll #$pollCount - status=${status.status}, totalLength=${status.totalLength}, hasBT=${status.isBitTorrent}');

          // 关键：只有当 totalLength > 0 时，metadata 才真正 ready
          // （bittorrent 字段出现不等于 ready，aria2 可能在找 peers 阶段就置上）
          if (status.totalLength > 0) {
            print(
                '[MagnetDownloader] ✓ Metadata ready! totalLength=${status.totalLength}');

            // 现在才调用 getFiles 获取真实文件列表
            try {
              final files = await _aria2Service.getFiles(gid);
              print(
                  '[MagnetDownloader] getFiles returned ${files.length} files');

              for (final f in files) {
                print(
                    '[MagnetDownloader]   - idx=${f.index} name=${f.name} size=${f.length} path=${f.path}');
              }

              // 过滤掉：
              // 1. 目录项（path 以 / 或 \ 结尾）
              // 2. size=0 的项（这些可能是占位符或目录）
              final realFiles = files.where((f) {
                if (f.path.endsWith('/') || f.path.endsWith('\\')) {
                  return false; // 目录
                }
                if (f.length <= 0) {
                  return false; // 占位符或空文件
                }
                // 排除 [METADATA] 占位符
                if (f.name.contains('METADATA') ||
                    f.path.contains('METADATA')) {
                  return false;
                }
                return true;
              }).toList();

              print(
                  '[MagnetDownloader] After strict filter: ${realFiles.length} real files');

              if (realFiles.isNotEmpty) {
                print(
                    '[MagnetDownloader] ✓ Found ${realFiles.length} real files, returning success');
                await _cleanupTask(gid);
                return MagnetParseResult(
                  status: MagnetParseStatus.success,
                  files: realFiles.map((f) {
                    return MagnetFileInfo(
                      index: f.index,
                      name: f.name,
                      fullPath: f.path,
                      size: f.length,
                    );
                  }).toList(),
                );
              }

              // totalLength > 0 但过滤后没文件（不太可能）
              // 可能是单文件 BT，文件 path 是不带 size 的奇怪格式
              // 尝试宽松模式：返回所有 size > 0 的（哪怕包含占位符）
              final fallbackFiles = files.where((f) {
                if (f.path.endsWith('/') || f.path.endsWith('\\')) return false;
                return f.length > 0;
              }).toList();

              if (fallbackFiles.isNotEmpty) {
                print(
                    '[MagnetDownloader] Using fallback: ${fallbackFiles.length} files');
                await _cleanupTask(gid);
                return MagnetParseResult(
                  status: MagnetParseStatus.success,
                  files: fallbackFiles.map((f) {
                    return MagnetFileInfo(
                      index: f.index,
                      name: f.name,
                      fullPath: f.path,
                      size: f.length,
                    );
                  }).toList(),
                );
              }
            } catch (e) {
              print('[MagnetDownloader] getFiles error: $e');
            }
          } else {
            // totalLength == 0，metadata 还没 ready
            // 检查是否有任何 peer 连接迹象
            if (status.isBitTorrent) {
              consecutiveNoPeers = 0; // aria2 还在找 peers
            } else {
              consecutiveNoPeers++;
            }
            // 如果 30 秒（约 15 次 poll）都没有 bittorrent 字段
            // 说明 DHT 完全没工作
            if (consecutiveNoPeers > 15 && pollCount > 15) {
              print(
                  '[MagnetDownloader] No BT activity for 30s, peers/trackers likely dead');
            }
          }
        } catch (e) {
          print('[MagnetDownloader] Poll error: $e');
        }

        await Future.delayed(const Duration(seconds: 2));
      }

      // 超时
      print(
          '[MagnetDownloader] Timeout after 120s, totalLength never became > 0');
      await _cleanupTask(gid);

      return MagnetParseResult(
        status: MagnetParseStatus.timeout,
        errorMessage: '元数据获取超时（120秒）',
      );
    } catch (e) {
      print('[MagnetDownloader] getMagnetFiles error: $e');
      if (gid != null) {
        await _cleanupTask(gid);
      }
      return MagnetParseResult(
        status: MagnetParseStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// 清理任务（暂停 + 移除 + 强制删除）
  Future<void> _cleanupTask(String gid) async {
    try {
      await _aria2Service.pause(gid);
    } catch (_) {}
    try {
      await _aria2Service.removeDownloadResult(gid);
    } catch (_) {}
    try {
      await _aria2Service.forceRemove(gid);
    } catch (_) {}
  }
}
