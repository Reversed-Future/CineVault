import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/unregistered_movies_provider.dart';
import '../services/database_service.dart';
import '../services/local_movie_scanner.dart';

/// 未注册影片对话框
///
/// 显示扫描到但未在库中的影片列表
/// 用户可勾选要保存为占位的影片，点击保存后批量创建占位 Movie
class UnregisteredMoviesDialog extends ConsumerStatefulWidget {
  final List<ScannedMovieEntry> entries;

  const UnregisteredMoviesDialog({
    super.key,
    required this.entries,
  });

  /// 无参构造函数：自动从全局 provider 读取 entries
  /// 用于从通知中心等无法直接传参的场景
  const UnregisteredMoviesDialog.fromProvider({super.key}) : entries = const [];

  /// 便捷方法：从全局 provider 弹出对话框（自动使用当前待审核列表）
  static Future<void> showFromProvider(
      BuildContext context, WidgetRef ref) async {
    ref.read(unregisteredMoviesProvider.notifier).restoreFromLastScan();
    final entries = ref.read(effectiveUnregisteredMoviesProvider);
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前没有待审核的影片'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => UnregisteredMoviesDialog(entries: entries),
    );
  }

  @override
  ConsumerState<UnregisteredMoviesDialog> createState() =>
      _UnregisteredMoviesDialogState();
}

class _UnregisteredMoviesDialogState
    extends ConsumerState<UnregisteredMoviesDialog> {
  final Set<String> _selectedCodes = {};
  final Map<String, TextEditingController> _codeControllers = {};
  bool _selectAll = true;
  bool _isSaving = false;

  List<ScannedMovieEntry> get _entries {
    // 如果是用 fromProvider 构造的，从全局 provider 读取
    if (widget.entries.isEmpty) {
      ref.read(unregisteredMoviesProvider.notifier).restoreFromLastScan();
      return ref.read(effectiveUnregisteredMoviesProvider);
    }
    return widget.entries;
  }

  @override
  void initState() {
    super.initState();
    // 默认全选
    _selectedCodes.addAll(_entries.map((e) => e.movieCode));
    for (final entry in _entries) {
      _controllerFor(entry);
    }
  }

  @override
  void dispose() {
    for (final controller in _codeControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(ScannedMovieEntry entry) {
    return _codeControllers.putIfAbsent(
      entry.movieCode,
      () => TextEditingController(text: entry.movieCode),
    );
  }

  void _toggleSelectAll() {
    setState(() {
      _selectAll = !_selectAll;
      if (_selectAll) {
        _selectedCodes.addAll(_entries.map((e) => e.movieCode));
      } else {
        _selectedCodes.clear();
      }
    });
  }

  void _toggleOne(String code) {
    setState(() {
      if (_selectedCodes.contains(code)) {
        _selectedCodes.remove(code);
        _selectAll = false;
      } else {
        _selectedCodes.add(code);
        if (_selectedCodes.length == _entries.length) {
          _selectAll = true;
        }
      }
    });
  }

  Future<void> _save() async {
    if (_selectedCodes.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    final entriesToSave = _entries
        .where((entry) => _selectedCodes.contains(entry.movieCode))
        .toList(growable: false);
    final editedCodes = <String, String>{};
    final normalizedCodes = <String>{};

    for (final entry in entriesToSave) {
      final editedCode = _controllerFor(entry).text.trim();
      if (editedCode.isEmpty) {
        _showSaveError('资料 ID 或标题不能为空');
        return;
      }

      final normalizedCode = LocalMovieScanner.normalizeCode(editedCode);
      if (normalizedCodes.contains(normalizedCode)) {
        _showSaveError('存在重复资料：$editedCode');
        return;
      }
      normalizedCodes.add(normalizedCode);

      final existingMovie = DatabaseService.findMovieByCode(editedCode);
      if (existingMovie != null) {
        _showSaveError('资料已存在：$editedCode');
        return;
      }

      editedCodes[entry.movieCode] = editedCode;
    }

    setState(() {
      _isSaving = true;
    });

    int savedCount = 0;
    final savedCodes = <String>{};
    for (final entry in entriesToSave) {
      try {
        await LocalMovieScanner.createPlaceholderMovie(
          entry,
          movieCode: editedCodes[entry.movieCode],
        );
        savedCodes.add(entry.movieCode);
        savedCount++;
      } catch (e) {
        print(
            '[UnregisteredMoviesDialog] Failed to save ${entry.movieCode}: $e');
      }
    }

    // 同步从全局 provider 移除已处理的条目
    ref.read(unregisteredMoviesProvider.notifier).removeByCodes(savedCodes);

    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();

    messenger.showSnackBar(
      SnackBar(
        content: Text('已添加 $savedCount 个影片占位，可在稍后更新影片数据'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSaveError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.movie_filter_outlined,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '扫描到 ${_entries.length} 个未注册的影片',
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '以下影片在本地视频文件夹中找到，但尚未在库中。'
              '勾选要保存为占位的影片，稍后可在影片列表中更新其详细信息。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _selectAll,
              onChanged: (_) => _toggleSelectAll(),
              title: const Text('全选'),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: _entries.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  final isSelected = _selectedCodes.contains(entry.movieCode);
                  final controller = _controllerFor(entry);

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: isSelected,
                          onChanged: (_) => _toggleOne(entry.movieCode),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                key:
                                    ValueKey('pending-code-${entry.movieCode}'),
                                controller: controller,
                                enabled: !_isSaving,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(
                                  labelText: '资料 ID / 标题',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '文件夹: ${entry.matchedFolderName}',
                                style: theme.textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '文件: ${entry.matchedFileName}'
                                '${entry.filePaths.length > 1 ? ' 等 ${entry.filePaths.length} 个' : ''}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('跳过'),
        ),
        FilledButton.icon(
          onPressed: _isSaving || _selectedCodes.isEmpty ? null : _save,
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_isSaving ? '保存中...' : '保存 ${_selectedCodes.length} 个占位'),
        ),
      ],
    );
  }
}
