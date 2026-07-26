import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/tracker_updater.dart';

/// 添加 trackers 源弹窗
///
/// 用户输入 URL 后，自动下载并解析 trackers，然后追加到现有列表中
class AddTrackerSourceDialog extends StatefulWidget {
  /// 现有的 trackers 列表（用于去重和追加）
  final String currentTrackersText;

  const AddTrackerSourceDialog({
    super.key,
    required this.currentTrackersText,
  });

  @override
  State<AddTrackerSourceDialog> createState() =>
      _AddTrackerSourceDialogState();
}

class _AddTrackerSourceDialogState extends State<AddTrackerSourceDialog> {
  final TextEditingController _urlController = TextEditingController();
  final TrackerUpdater _trackerUpdater = TrackerUpdater();

  bool _isLoading = false;
  String? _errorMessage;
  List<String> _newTrackers = [];
  Set<String> _selectedTrackers = {};

  @override
  void initState() {
    super.initState();
    _urlController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  /// 解析 URL，下载并解析 trackers
  Future<void> _fetchAndParse() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _errorMessage = '请输入 URL';
      });
      return;
    }

    // 简单 URL 验证
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      setState(() {
        _errorMessage = 'URL 必须以 http:// 或 https:// 开头';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _newTrackers = [];
      _selectedTrackers = {};
    });

    try {
      final trackers = await _trackerUpdater.updateTrackers(
        sources: [url],
      );

      if (trackers.isEmpty) {
        setState(() {
          _errorMessage = '未能从该 URL 解析到任何 trackers';
          _isLoading = false;
        });
        return;
      }

      // 过滤掉已存在的 trackers
      final existingTrackers = widget.currentTrackersText
          .split(RegExp(r'[\n,;\s]+'))
          .where((t) => t.trim().isNotEmpty)
          .toSet();

      final newTrackers =
          trackers.where((t) => !existingTrackers.contains(t)).toList();

      if (newTrackers.isEmpty) {
        setState(() {
          _errorMessage = '该源中的所有 trackers 都已存在（共解析到 ${trackers.length} 个，全部重复）';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _newTrackers = newTrackers;
        // 默认全选
        _selectedTrackers = newTrackers.toSet();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '解析失败: $e';
        _isLoading = false;
      });
    }
  }

  /// 确认导入
  void _confirmImport() {
    if (_selectedTrackers.isEmpty) {
      Navigator.of(context).pop(null);
      return;
    }

    // 合并到现有列表
    final existingText = widget.currentTrackersText.trim();
    final newTrackersText = _selectedTrackers.join('\n');

    final combined = existingText.isEmpty
        ? newTrackersText
        : '$existingText\n$newTrackersText';

    // 返回合并后的 trackers 列表 + 源 URL（用于加入订阅名单）
    Navigator.of(context).pop({
      'trackers': combined,
      'sourceUrl': _urlController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 700),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                const Icon(Icons.cloud_download, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '添加 Trackers 源',
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
            const SizedBox(height: 8),
            Text(
              '从 GitHub 等网站上的 txt 文件 URL 自动解析并导入 trackers',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),

            // URL 输入
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'Trackers 源 URL',
                hintText: 'https://cf.trackerslist.com/all.txt',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.link),
                suffixIcon: _urlController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: '清空',
                        onPressed: () {
                          _urlController.clear();
                          setState(() {
                            _newTrackers = [];
                            _selectedTrackers = {};
                            _errorMessage = null;
                          });
                        },
                      )
                    : null,
              ),
              enabled: !_isLoading,
              maxLines: 2,
              minLines: 1,
            ),
            const SizedBox(height: 12),

            // 解析按钮
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _fetchAndParse,
                    icon: _isLoading
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
                      _isLoading ? '解析中...' : '解析 URL',
                      style: const TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      disabledBackgroundColor: Colors.grey,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 粘贴板按钮
                OutlinedButton.icon(
                  onPressed: _isLoading
                      ? null
                      : () async {
                          final clip = await Clipboard.getData('text/plain');
                          if (clip?.text != null) {
                            _urlController.text = clip!.text!;
                          }
                        },
                  icon: const Icon(Icons.paste, size: 18),
                  label: const Text('粘贴'),
                ),
              ],
            ),

            // 错误信息
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 解析结果
            if (_newTrackers.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    '解析结果：共 ${_newTrackers.length} 个新 trackers',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        if (_selectedTrackers.length == _newTrackers.length) {
                          _selectedTrackers.clear();
                        } else {
                          _selectedTrackers = _newTrackers.toSet();
                        }
                      });
                    },
                    child: Text(
                      _selectedTrackers.length == _newTrackers.length
                          ? '全不选'
                          : '全选',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _newTrackers.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final tracker = _newTrackers[index];
                            final isSelected =
                                _selectedTrackers.contains(tracker);
                            return CheckboxListTile(
                              dense: true,
                              value: isSelected,
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _selectedTrackers.add(tracker);
                                  } else {
                                    _selectedTrackers.remove(tracker);
                                  }
                                });
                              },
                              title: Text(
                                tracker,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              controlAffinity:
                                  ListTileControlAffinity.leading,
                            );
                          },
                        ),
                      ),
                      // 底部统计
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              '已选择 ${_selectedTrackers.length}/${_newTrackers.length}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (!_isLoading && _errorMessage == null) ...[
              const SizedBox(height: 24),
              // 提示信息
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .tertiaryContainer
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          size: 18,
                          color: Theme.of(context)
                              .colorScheme
                              .onTertiaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '常用 trackers 源',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context)
                                .colorScheme
                                .onTertiaryContainer,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildPresetUrl(
                      'https://cf.trackerslist.com/all.txt',
                    ),
                    _buildPresetUrl(
                      'https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_best.txt',
                    ),
                    _buildPresetUrl(
                      'https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_all.txt',
                    ),
                    _buildPresetUrl(
                      'https://raw.githubusercontent.com/DeSireFire/freeNodeTracker/master/all.txt',
                    ),
                    _buildPresetUrl(
                      'https://raw.githubusercontent.com/XIU2/TrackersListCollection/master/all.txt',
                    ),
                  ],
                ),
              ),
            ],

            // 底部按钮
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: (_isLoading || _selectedTrackers.isEmpty)
                        ? null
                        : _confirmImport,
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: Text(
                      '导入选中 (${_selectedTrackers.length})',
                      style: const TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
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

  Widget _buildPresetUrl(String url) {
    return InkWell(
      onTap: _isLoading
          ? null
          : () {
              _urlController.text = url;
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            const Icon(Icons.link, size: 14, color: Colors.blue),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                url,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
