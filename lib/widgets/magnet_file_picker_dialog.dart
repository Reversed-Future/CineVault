import 'package:flutter/material.dart';

import '../services/magnet_downloader.dart';

/// 磁力链接文件选择对话框
///
/// 解析磁力链接中的文件，让用户选择要下载的文件
class MagnetFilePickerDialog extends StatefulWidget {
  final String magnetLink;
  final String? movieCode;
  final String? magnetTitle;

  const MagnetFilePickerDialog({
    super.key,
    required this.magnetLink,
    this.movieCode,
    this.magnetTitle,
  });

  @override
  State<MagnetFilePickerDialog> createState() => _MagnetFilePickerDialogState();
}

class _MagnetFilePickerDialogState extends State<MagnetFilePickerDialog> {
  final MagnetDownloader _downloader = MagnetDownloader();
  final Set<int> _selectedIndices = {};
  List<MagnetFileInfo> _files = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _selectedDir;
  final TextEditingController _dirController = TextEditingController();
  bool _rememberDir = true;
  bool _downloading = false;
  String _filterText = '';

  @override
  void initState() {
    super.initState();
    _loadInitialDir();
    _loadFiles();
  }

  Future<void> _loadInitialDir() async {
    final dir = await _downloader.getDefaultDownloadDir();
    if (mounted) {
      setState(() {
        _selectedDir = dir;
        _dirController.text = dir;
      });
    }
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _downloader.getMagnetFiles(widget.magnetLink);
      if (!mounted) return;

      switch (result.status) {
        case MagnetParseStatus.success:
          // 成功获取到真实文件列表
          setState(() {
            _files = result.files;
            // 默认全选 - 使用文件的实际 index（aria2 的 1-based 索引）
            _selectedIndices
              ..clear()
              ..addAll(result.files.map((f) => f.index));
            _isLoading = false;
            _errorMessage = null;
          });
          break;

        case MagnetParseStatus.loading:
          // 仍在加载中（理论上不会到这里，因为 getMagnetFiles 内部轮询）
          setState(() {
            _isLoading = true;
            _errorMessage = '正在连接 peers 获取元数据...';
          });
          break;

        case MagnetParseStatus.empty:
          setState(() {
            _files = [];
            _isLoading = false;
            _errorMessage = '元数据已获取，但种子中没有文件';
          });
          break;

        case MagnetParseStatus.timeout:
          setState(() {
            _files = [];
            _isLoading = false;
            _errorMessage = '元数据获取超时（120秒）。可能原因：\n\n'
                '1. 没有活跃的 peers（种源稀少）\n'
                '2. 未配置有效的 trackers\n'
                '3. 网络连接 DHT/PEX 受限\n\n'
                '建议：\n'
                '• 在「下载设置 → BT Trackers」点击刷新获取最新 trackers\n'
                '• 或复制磁力链接到 qBittorrent 等专业客户端查看文件';
          });
          break;

        case MagnetParseStatus.error:
          setState(() {
            _files = [];
            _isLoading = false;
            _errorMessage = '解析失败：${result.errorMessage ?? "未知错误"}\n\n'
                '可能原因：\n'
                '1. 磁力链接格式无效（缺少 info hash）\n'
                '2. aria2 服务未运行\n'
                '3. DHT/PEX 网络无法连接\n'
                '4. 找不到任何 peers（种源稀少或全失效）\n'
                '5. trackers 配置错误或失效\n\n'
                '建议：\n'
                '• 在「下载设置 → BT Trackers」点击刷新获取最新 trackers\n'
                '• 或复制磁力链接到 qBittorrent 等专业客户端查看文件';
          });
          break;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '解析失败: $e';
      });
    }
  }

  Future<void> _pickDir() async {
    final dir = await _downloader.pickDownloadDir(initialPath: _selectedDir);
    if (dir != null && mounted) {
      setState(() {
        _selectedDir = dir;
        _dirController.text = dir;
      });
    }
  }

  List<MagnetFileInfo> get _filteredFiles {
    if (_filterText.isEmpty) return _files;
    final lower = _filterText.toLowerCase();
    return _files.where((f) => f.name.toLowerCase().contains(lower)).toList();
  }

  /// 计算已选文件的总大小（字节）
  int _getSelectedTotalSize() {
    return _files
        .where((f) => _selectedIndices.contains(f.index))
        .fold<int>(0, (sum, f) => sum + f.size);
  }

  /// 格式化总大小
  String _formatTotalSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _startDownload() async {
    if (_selectedDir == null || _selectedDir!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择下载目录')),
      );
      return;
    }

    if (_selectedIndices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一个文件')),
      );
      return;
    }

    setState(() {
      _downloading = true;
    });

    // 记忆下载目录
    if (_rememberDir) {
      await _downloader.setLastDownloadDir(_selectedDir!);
    }

    // _selectedIndices 已经是 aria2 的 1-based 索引，直接使用
    final result = await _downloader.downloadViaAria2(
      magnet: widget.magnetLink,
      saveDir: _selectedDir!,
      selectedIndices: _selectedIndices.toList(),
    );

    if (!mounted) return;

    setState(() {
      _downloading = false;
    });

    if (result.success) {
      Navigator.of(context).pop({
        'success': true,
        'saveDir': result.localDir,
        'selectedFiles': _selectedIndices.toList(),
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('下载失败: ${result.errorMessage}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _dirController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.85,
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 750),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                const Icon(Icons.bolt, color: Colors.purple),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '通过 aria2 下载',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      if (widget.magnetTitle != null)
                        Text(
                          widget.magnetTitle!,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 下载目录选择
            Text('下载目录', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dirController,
                    decoration: const InputDecoration(
                      hintText: '选择或粘贴下载目录',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      _selectedDir = v;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _pickDir,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('浏览'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _rememberDir,
              onChanged: (v) {
                setState(() {
                  _rememberDir = v ?? true;
                });
              },
              title:
                  const Text('记住此目录（下次自动使用）', style: TextStyle(fontSize: 12)),
            ),

            const Divider(height: 16),

            // 文件列表标题 + 过滤
            Row(
              children: [
                Text('选择文件', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                if (_files.isNotEmpty)
                  Text(
                    '已选 ${_selectedIndices.length}/${_files.length} · ${_formatTotalSize(_getSelectedTotalSize())}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12,
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.select_all, size: 18),
                  onPressed: _files.isEmpty
                      ? null
                      : () {
                          setState(() {
                            if (_selectedIndices.length == _files.length) {
                              _selectedIndices.clear();
                            } else {
                              _selectedIndices
                                ..clear()
                                ..addAll(_files.map((f) => f.index));
                            }
                          });
                        },
                  tooltip: '全选/全不选',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_files.length > 5)
              TextField(
                decoration: const InputDecoration(
                  hintText: '过滤文件...',
                  prefixIcon: Icon(Icons.filter_list, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  setState(() {
                    _filterText = v;
                  });
                },
              ),
            const SizedBox(height: 8),

            // 文件列表
            Expanded(
              child: _buildFileList(),
            ),

            const SizedBox(height: 12),

            // 底部按钮
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _downloading ? null : _loadFiles,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('重新解析'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: (_downloading ||
                            _selectedIndices.isEmpty ||
                            _selectedDir == null ||
                            _selectedDir!.isEmpty)
                        ? null
                        : _startDownload,
                    icon: _downloading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.download, color: Colors.white),
                    label: Text(
                      _downloading ? '添加中...' : '开始下载',
                      style: const TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      disabledBackgroundColor: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileList() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              '解析磁力链接中...',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '需要连接 DHT 网络获取元数据',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, color: Colors.orange, size: 48),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.orange),
              ),
              const SizedBox(height: 12),
              const Text(
                '提示：可以复制磁力链接到 qBittorrent 等客户端查看文件',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    if (_files.isEmpty) {
      return const Center(
        child: Text('未找到文件'),
      );
    }

    final filteredFiles = _filteredFiles;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // 列表头
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                // checkbox 列
                SizedBox(
                  width: 24,
                  child: Checkbox(
                    value: _selectedIndices.length == filteredFiles.length &&
                        filteredFiles.isNotEmpty,
                    tristate: _selectedIndices.isNotEmpty &&
                        _selectedIndices.length < filteredFiles.length,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selectedIndices
                            ..clear()
                            ..addAll(filteredFiles.map((f) => f.index));
                        } else {
                          _selectedIndices.clear();
                        }
                      });
                    },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                // 文件名列
                const Expanded(
                  flex: 5,
                  child: Text('文件名',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                // 类型列
                SizedBox(
                  width: 50,
                  child: Text('类型',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center),
                ),
                // 大小列
                SizedBox(
                  width: 80,
                  child: Text('大小',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.right),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 列表内容
          Expanded(
            child: ListView.separated(
              itemCount: filteredFiles.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final file = filteredFiles[index];
                final isSelected = _selectedIndices.contains(file.index);

                return InkWell(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedIndices.remove(file.index);
                      } else {
                        _selectedIndices.add(file.index);
                      }
                    });
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      children: [
                        // checkbox
                        SizedBox(
                          width: 24,
                          child: Checkbox(
                            value: isSelected,
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _selectedIndices.add(file.index);
                                } else {
                                  _selectedIndices.remove(file.index);
                                }
                              });
                            },
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 图标
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _getFileIcon(file.ext),
                        ),
                        // 文件名
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                file.name,
                                style: const TextStyle(fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (file.fullPath != null &&
                                  file.fullPath!.contains('\\'))
                                Text(
                                  file.fullPath!
                                      .split('\\')
                                      .sublist(0,
                                          file.fullPath!.split('\\').length - 1)
                                      .join('\\'),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        // 类型
                        SizedBox(
                          width: 50,
                          child: file.ext != null
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: _getExtColor(file.ext!)
                                        .withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    file.ext!,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: _getExtColor(file.ext!),
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        // 大小
                        SizedBox(
                          width: 80,
                          child: Text(
                            file.formattedSize,
                            style: TextStyle(
                              fontSize: 12,
                              color: file.size > 0
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget? _getFileIcon(String? ext) {
    if (ext == null) return const Icon(Icons.file_present);
    if (['mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm'].contains(ext)) {
      return const Icon(Icons.movie, color: Colors.blue);
    }
    if (['srt', 'ass', 'ssa', 'vtt', 'sub'].contains(ext)) {
      return const Icon(Icons.subtitles, color: Colors.green);
    }
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext)) {
      return const Icon(Icons.image, color: Colors.orange);
    }
    return const Icon(Icons.insert_drive_file);
  }

  /// 根据文件扩展名返回颜色（用于类型徽章）
  Color _getExtColor(String ext) {
    if (['mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm'].contains(ext)) {
      return Colors.blue;
    }
    if (['srt', 'ass', 'ssa', 'vtt', 'sub'].contains(ext)) {
      return Colors.green;
    }
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext)) {
      return Colors.orange;
    }
    if (['pdf', 'doc', 'docx', 'txt'].contains(ext)) {
      return Colors.brown;
    }
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
      return Colors.purple;
    }
    if (['html', 'htm'].contains(ext)) {
      return Colors.teal;
    }
    return Colors.grey;
  }
}
