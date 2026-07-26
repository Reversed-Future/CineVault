import 'dart:async';

import 'aria2_service.dart';

/// aria2 下载进度回调
typedef Aria2ProgressCallback = void Function(int received, int total);

/// aria2 下载结果
class Aria2DownloadResult {
  final bool success;
  final String? errorMessage;
  final String? localPath;

  Aria2DownloadResult({
    required this.success,
    this.errorMessage,
    this.localPath,
  });
}

/// aria2 下载辅助类
///
/// 提供基于 aria2 的下载功能：
/// - 通过轮询 RPC 接口获取进度
/// - 自动等待任务完成或失败
class Aria2Downloader {
  static final Aria2Downloader _instance = Aria2Downloader._internal();
  factory Aria2Downloader() => _instance;
  Aria2Downloader._internal();

  final Aria2Service _service = Aria2Service();

  /// 检查 aria2 是否可用
  Future<bool> isAvailable() => _service.isAvailable();

  /// 下载单个文件（HTTP/FTP）
  ///
  /// [url] 下载 URL
  /// [savePath] 保存路径（包含文件名）
  /// [onProgress] 进度回调
  /// [trackers] 磁力链接 trackers（仅对磁力链接有效）
  Future<Aria2DownloadResult> downloadFile({
    required String url,
    required String savePath,
    Aria2ProgressCallback? onProgress,
    List<String>? trackers,
  }) async {
    if (!await _service.isAvailable()) {
      return Aria2DownloadResult(
        success: false,
        errorMessage: 'aria2 服务不可用',
      );
    }

    try {
      // 分离目录和文件名
      final dir = savePath.substring(0, savePath.lastIndexOf(r'\') + 1);
      final filename = savePath.substring(savePath.lastIndexOf(r'\') + 1);

      String gid;
      if (url.startsWith('magnet:')) {
        gid = await _service.addMagnet(
          url,
          dir: dir,
          trackers: trackers,
        );
      } else {
        gid = await _service.addUri(
          [url],
          dir: dir,
          filename: filename,
        );
      }

      // 轮询进度
      return await _waitForCompletion(gid, onProgress);
    } catch (e) {
      return Aria2DownloadResult(
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// 等待任务完成
  Future<Aria2DownloadResult> _waitForCompletion(
    String gid,
    Aria2ProgressCallback? onProgress,
  ) async {
    final maxDuration = const Duration(hours: 24);
    final startTime = DateTime.now();

    while (true) {
      if (DateTime.now().difference(startTime) > maxDuration) {
        try {
          await _service.forceRemove(gid);
        } catch (_) {}
        return Aria2DownloadResult(
          success: false,
          errorMessage: '下载超时',
        );
      }

      try {
        final status = await _service.tellStatus(gid);

        if (status.isComplete) {
          onProgress?.call(status.totalLength, status.totalLength);
          return Aria2DownloadResult(
            success: true,
            localPath: status.files.isNotEmpty ? status.files.first : null,
          );
        }

        if (status.isError) {
          return Aria2DownloadResult(
            success: false,
            errorMessage: status.errorMessage ?? '下载失败',
          );
        }

        if (status.isRemoved) {
          return Aria2DownloadResult(
            success: false,
            errorMessage: '任务已被移除',
          );
        }

        // 报告进度
        onProgress?.call(status.completedLength, status.totalLength);
      } on Aria2Exception catch (e) {
        // 任务可能已被清理
        if (e.code == 1) {
          // GID not found
          return Aria2DownloadResult(
            success: false,
            errorMessage: '任务不存在或已完成',
          );
        }
        return Aria2DownloadResult(
          success: false,
          errorMessage: e.message,
        );
      } catch (e) {
        // 忽略单次错误，继续轮询
      }

      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// 取消下载
  Future<void> cancel(String gid) async {
    try {
      await _service.forceRemove(gid);
    } catch (_) {}
  }
}
