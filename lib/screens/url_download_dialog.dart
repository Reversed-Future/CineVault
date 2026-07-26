import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../ai/model_manager.dart';
import 'download_center_screen.dart';

class UrlDownloadDialog extends StatefulWidget {
  const UrlDownloadDialog({super.key});

  @override
  State<UrlDownloadDialog> createState() => _UrlDownloadDialogState();
}

class _UrlDownloadDialogState extends State<UrlDownloadDialog> {
  final ModelManager _modelManager = ModelManager();
  final TextEditingController _urlController = TextEditingController();
  List<ModelFileInfo> _parsedFiles = [];
  final Set<String> _selectedFiles = {};
  bool _isParsing = false;
  bool _isDownloading = false;
  String? _errorMessage;
  bool _useMirrorSite = true;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _parseUrl() async {
    if (_urlController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = '请输入URL';
      });
      return;
    }

    setState(() {
      _isParsing = true;
      _errorMessage = null;
      _parsedFiles = [];
      _selectedFiles.clear();
    });

    try {
      final files = await _modelManager.parseHuggingFaceRepo(
        _urlController.text,
        preferMirror: _useMirrorSite,
      );
      
      if (files.isEmpty) {
        setState(() {
          _errorMessage = '仓库中未找到可下载的模型文件';
        });
        return;
      }

      setState(() {
        _parsedFiles = files;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '解析失败: $e';
      });
    } finally {
      setState(() {
        _isParsing = false;
      });
    }
  }

  Future<void> _startDownload() async {
    if (_selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一个文件')),
      );
      return;
    }

    setState(() {
      _isDownloading = true;
      _errorMessage = null;
    });

    try {
      for (final fileName in _selectedFiles) {
        final file = _parsedFiles.firstWhere((f) => f.name == fileName);
        final baseName = path.basenameWithoutExtension(file.name);
        
        final task = await _modelManager.createDownloadTask(
          repositoryUrl: _urlController.text,
          modelName: baseName,
          files: [file],
        );

        _modelManager.downloadFiles(
          taskId: task.id,
          filesToDownload: [file],
          modelName: baseName,
          onProgress: (f, received, total) {
            if (mounted) {
              setState(() {});
            }
          },
          onDone: () {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('下载完成')),
              );
            }
          },
          onError: (error) {
            if (mounted) {
              setState(() {
                _errorMessage = error.toString();
              });
            }
          },
        );
      }

      if (mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) {
              return const DownloadCenterScreen();
            },
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '未知大小';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.download, color: Colors.purple),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '从URL下载模型',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: '仓库URL',
                hintText: 'https://huggingface.co/用户名/仓库名',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
              onSubmitted: (_) => _parseUrl(),
              enabled: !_isDownloading,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('优先使用镜像站'),
                Switch(
                  value: _useMirrorSite,
                  onChanged: _isDownloading ? null : (value) {
                    setState(() {
                      _useMirrorSite = value;
                    });
                  },
                  activeColor: Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: (_isParsing || _isDownloading) ? null : _parseUrl,
              icon: _isParsing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(_isParsing ? '解析中...' : '解析仓库'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 16),
            if (_errorMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            if (_parsedFiles.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '选择模型文件:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: _parsedFiles.map((file) {
                      final baseName = path.basenameWithoutExtension(file.name);
                      return CheckboxListTile(
                        title: Text(file.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('模型文件夹名: $baseName'),
                            Text(_formatFileSize(file.size)),
                          ],
                        ),
                        value: _selectedFiles.contains(file.name),
                        onChanged: _isDownloading
                            ? null
                            : (value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedFiles.add(file.name);
                                  } else {
                                    _selectedFiles.remove(file.name);
                                  }
                                });
                              },
                        secondary: file.isDownloaded
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : file.isDownloading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.file_present, color: Colors.grey),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: (_isDownloading || _selectedFiles.isEmpty) ? null : _startDownload,
                icon: _isDownloading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.download),
                label: Text(_isDownloading ? '下载中...' : '开始下载'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
