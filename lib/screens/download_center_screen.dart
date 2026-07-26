import 'dart:async';
import 'package:flutter/material.dart';
import '../ai/model_manager.dart';

class DownloadCenterScreen extends StatefulWidget {
  const DownloadCenterScreen({super.key});

  @override
  State<DownloadCenterScreen> createState() => _DownloadCenterScreenState();
}

class _DownloadCenterScreenState extends State<DownloadCenterScreen> {
  final ModelManager _modelManager = ModelManager();
  List<DownloadTask> _downloadTasks = [];
  final ScrollController _scrollController = ScrollController();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _downloadTasks = _modelManager.downloadTasks;
    _startRefreshTimer();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _stopRefreshTimer();
    super.dispose();
  }

  void _startRefreshTimer() {
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) {
        setState(() {
          _downloadTasks = _modelManager.downloadTasks;
        });
      }
    });
  }

  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '未知大小';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  double _getOverallProgress(DownloadTask task) {
    if (task.files.isEmpty) return 0.0;
    final totalSize = task.files.fold<int>(0, (sum, file) => sum + file.size);
    final downloadedSize = task.files.fold<double>(0, (sum, file) {
      if (file.isDownloaded) return sum + file.size;
      if (file.isDownloading && file.progress != null && file.size > 0) {
        return sum + (file.size * file.progress!);
      }
      return sum;
    });
    return totalSize > 0 ? downloadedSize / totalSize : 0.0;
  }

  /// 构建下载引擎徽章（aria2 / dio）
  Widget _buildEngineBadge(DownloadTask task) {
    // 模型市场下载总是走 aria2（如果启用）
    // URL 下载的 task.repositoryUrl 是 http 开头
    final isModelMarket = task.repositoryUrl.startsWith('model-market://');
    if (!isModelMarket) {
      // URL 下载会根据设置使用 aria2 或 dio
      // 这里简单判断：检查 _aria2Status（如果有）
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.purple.withOpacity(0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt, size: 10, color: Colors.purple[700]),
          const SizedBox(width: 3),
          Text(
            'aria2',
            style: TextStyle(
              color: Colors.purple[700],
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 格式化下载速度
  String _formatSpeed(int bytesPerSec) {
    if (bytesPerSec <= 0) return '';
    if (bytesPerSec < 1024) return '$bytesPerSec B/s';
    if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(2)} MB/s';
  }

  Widget _buildTaskCard(DownloadTask task) {
    final overallProgress = _getOverallProgress(task);
    final isDownloading = task.files.any((f) => f.isDownloading);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: task.isCompleted
                        ? Colors.green.withOpacity(0.1)
                        : task.errorMessage != null
                            ? Colors.red.withOpacity(0.1)
                            : Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: task.isCompleted
                        ? const Icon(Icons.check_circle,
                            color: Colors.green, size: 28)
                        : task.errorMessage != null
                            ? const Icon(Icons.error,
                                color: Colors.red, size: 28)
                            : isDownloading
                                ? const SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 3),
                                  )
                                : const Icon(Icons.download,
                                    color: Colors.blue, size: 28),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              task.modelName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // aria2 标识徽章
                          _buildEngineBadge(task),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        task.repositoryUrl,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: task.isCompleted
                        ? Colors.green.withOpacity(0.1)
                        : task.errorMessage != null
                            ? Colors.red.withOpacity(0.1)
                            : Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    task.isCompleted
                        ? '已完成'
                        : task.errorMessage != null
                            ? '失败'
                            : isDownloading
                                ? '下载中'
                                : '等待中',
                    style: TextStyle(
                      color: task.isCompleted
                          ? Colors.green
                          : task.errorMessage != null
                              ? Colors.red
                              : Colors.blue,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (isDownloading && overallProgress > 0) ...[
              Row(
                children: [
                  const Text(
                    '总体进度:',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: overallProgress,
                      backgroundColor: Colors.grey[200],
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.blue),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${(overallProgress * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            ...task.files.map((file) {
              return _buildFileItem(file, task);
            }),
            if (task.errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '下载失败: ${task.errorMessage}',
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (task.isCompleted) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle,
                        color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '所有文件已成功下载！',
                        style: const TextStyle(
                          color: Colors.green,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFileItem(ModelFileInfo file, DownloadTask task) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey[100]!),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: file.isDownloaded
                  ? Colors.green.withOpacity(0.1)
                  : file.isDownloading
                      ? Colors.blue.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: file.isDownloaded
                  ? const Icon(Icons.check_circle,
                      color: Colors.green, size: 20)
                  : file.isDownloading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_present,
                          color: Colors.grey, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        file.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: file.isDownloaded
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _formatFileSize(file.size),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (file.isDownloading && file.progress != null)
                  Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: file.progress,
                          backgroundColor: Colors.grey[200],
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(Colors.blue),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${(file.progress! * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                if (file.isDownloaded)
                  const Text(
                    '✓ 下载完成',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green,
                    ),
                  ),
              ],
            ),
          ),
          if (file.isDownloading)
            IconButton(
              icon: const Icon(Icons.cancel, color: Colors.red, size: 20),
              onPressed: () {
                _modelManager.cancelFileDownload(task.id, file.name);
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载中心'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _downloadTasks.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.download_done, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    '暂无下载任务',
                    style: TextStyle(fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '从设置 → 下载中心添加下载任务',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            )
          : Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              thickness: 8,
              radius: const Radius.circular(4),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 16),
                itemCount: _downloadTasks.length,
                itemBuilder: (context, index) {
                  return _buildTaskCard(_downloadTasks[index]);
                },
              ),
            ),
    );
  }
}
