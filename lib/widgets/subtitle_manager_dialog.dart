import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

import '../models/movie.dart';
import '../providers/movie_providers.dart';
import '../services/database_service.dart';
import '../services/subtitle_cat_service.dart';

class SubtitleManagerDialog extends ConsumerStatefulWidget {
  final Movie movie;
  final String? initialVideoPath;
  final void Function(Movie movie)? onMovieChanged;
  final void Function(Movie movie, String? subtitlePath)? onPlay;

  const SubtitleManagerDialog({
    super.key,
    required this.movie,
    this.initialVideoPath,
    this.onMovieChanged,
    this.onPlay,
  });

  @override
  ConsumerState<SubtitleManagerDialog> createState() =>
      _SubtitleManagerDialogState();
}

class _SubtitleManagerDialogState extends ConsumerState<SubtitleManagerDialog> {
  final _service = const SubtitleCatService();
  late final TextEditingController _keywordController;
  late Movie _movie;
  String? _videoPath;
  String? _selectedSubtitlePath;
  List<String> _subtitlePaths = const [];
  List<SubtitleSearchResult> _searchResults = const [];
  bool _isSearching = false;
  bool _isMatching = false;
  String? _downloadingHref;
  String? _message;

  @override
  void initState() {
    super.initState();
    _movie = widget.movie;
    _videoPath =
        widget.initialVideoPath ?? widget.movie.videoFilePaths?.firstOrNull;
    _keywordController = TextEditingController(text: _defaultKeyword());
    _refreshSubtitlePaths();
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  String _defaultKeyword() {
    if (_movie.code.trim().isNotEmpty) return _movie.code.trim();
    if (_videoPath != null && _videoPath!.isNotEmpty) {
      return path.basenameWithoutExtension(_videoPath!);
    }
    return _movie.name;
  }

  Future<void> _refreshSubtitlePaths() async {
    final stored = <String>[];
    for (final subtitlePath in _movie.subtitleFilePaths ?? const <String>[]) {
      if (subtitlePath.trim().isEmpty) continue;
      if (await File(subtitlePath).exists()) stored.add(subtitlePath);
    }

    final local = _videoPath == null
        ? const <String>[]
        : await SubtitleCatService.findLocalSubtitleFilesForVideo(_videoPath!);
    final merged = SubtitleCatService.mergeSubtitlePaths([...stored, ...local]);

    if (!mounted) return;
    setState(() {
      _subtitlePaths = merged;
      _selectedSubtitlePath = merged.contains(_selectedSubtitlePath)
          ? _selectedSubtitlePath
          : merged.firstOrNull;
    });
  }

  Future<void> _saveSubtitlePaths(List<String> subtitlePaths) async {
    final requested = SubtitleCatService.mergeSubtitlePaths(subtitlePaths);
    final updatedMovie = await DatabaseService.updateMovieWithLatest(
      _movie.id,
      (latestMovie) {
        final merged = SubtitleCatService.mergeSubtitlePaths([
          ...?latestMovie.subtitleFilePaths,
          ...requested,
        ]);
        return latestMovie.copyWith(subtitleFilePaths: merged);
      },
    );
    final merged = updatedMovie.subtitleFilePaths ?? const <String>[];
    refreshMovies(ref);

    if (!mounted) return;
    setState(() {
      _movie = updatedMovie;
      _subtitlePaths = merged;
      _selectedSubtitlePath = merged.contains(_selectedSubtitlePath)
          ? _selectedSubtitlePath
          : merged.firstOrNull;
    });
    widget.onMovieChanged?.call(updatedMovie);
  }

  Future<void> _matchLocalSubtitles() async {
    if (_videoPath == null || _videoPath!.isEmpty) {
      _showMessage('请先为影片匹配一个本地视频文件');
      return;
    }

    setState(() {
      _isMatching = true;
      _message = null;
    });

    try {
      final local =
          await SubtitleCatService.findLocalSubtitleFilesForVideo(_videoPath!);
      if (local.isEmpty) {
        _showMessage('未找到与当前视频同名的字幕文件');
        return;
      }

      await _saveSubtitlePaths([
        ...(_movie.subtitleFilePaths ?? const <String>[]),
        ...local,
      ]);
      _showMessage('已匹配 ${local.length} 个本地字幕文件');
    } catch (error) {
      _showMessage('匹配失败: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isMatching = false;
        });
      }
    }
  }

  Future<void> _pickSubtitleFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['srt', 'ass', 'ssa', 'vtt'],
      allowMultiple: false,
    );
    final filePath = result?.files.single.path;
    if (filePath == null || filePath.isEmpty) return;

    if (!mounted) return;
    setState(() {
      _selectedSubtitlePath = filePath;
    });
    await _saveSubtitlePaths([
      ...(_movie.subtitleFilePaths ?? const <String>[]),
      filePath,
    ]);
    _showMessage('字幕已绑定到影片');
  }

  Future<void> _searchSubtitles() async {
    final keyword = _keywordController.text.trim();
    if (keyword.isEmpty) {
      _showMessage('请输入搜索关键词');
      return;
    }

    setState(() {
      _isSearching = true;
      _message = null;
      _searchResults = const [];
    });

    try {
      final results = await _service.search(keyword);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _message = results.isEmpty ? '未找到字幕结果' : '找到 ${results.length} 个字幕结果';
      });
    } catch (error) {
      _showMessage('搜索失败: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _downloadSubtitle(SubtitleSearchResult result) async {
    if (_videoPath == null || _videoPath!.isEmpty) {
      _showMessage('请先为影片匹配一个本地视频文件');
      return;
    }

    setState(() {
      _downloadingHref = result.href;
      _message = null;
    });

    try {
      final download = await _service.downloadForVideo(
        result: result,
        videoPath: _videoPath!,
      );
      if (!mounted) return;
      setState(() {
        _selectedSubtitlePath = download.subtitlePath;
      });
      await _saveSubtitlePaths([
        ...(_movie.subtitleFilePaths ?? const <String>[]),
        download.subtitlePath,
      ]);
      _showMessage(download.downloaded ? '字幕已下载并绑定' : '已绑定现有字幕文件');
    } catch (error) {
      _showMessage('下载失败: $error');
    } finally {
      if (mounted) {
        setState(() {
          _downloadingHref = null;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    setState(() {
      _message = message;
    });
  }

  void _playWithSubtitle(String? subtitlePath) {
    widget.onPlay?.call(_movie, subtitlePath);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.subtitles_outlined),
          SizedBox(width: 12),
          Text('字幕'),
        ],
      ),
      content: SizedBox(
        width: 760,
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildVideoSummary(),
            const SizedBox(height: 12),
            _buildToolbar(),
            const SizedBox(height: 12),
            if (_message != null) _buildMessage(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildMatchedSubtitles()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildSearchResults()),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildVideoSummary() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.movie_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _movie.code.isEmpty ? _movie.name : _movie.code,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _videoPath ?? '尚未匹配本地视频文件',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (widget.onPlay != null && _videoPath != null)
            IconButton.filledTonal(
              tooltip: '播放',
              icon: const Icon(Icons.play_arrow),
              onPressed: () => _playWithSubtitle(_selectedSubtitlePath),
            ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _keywordController,
            decoration: const InputDecoration(
              labelText: '字幕搜索关键词',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _searchSubtitles(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _isSearching ? null : _searchSubtitles,
          icon: _isSearching
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.search),
          label: const Text('搜索'),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: '匹配本地字幕',
          icon: _isMatching
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
          onPressed: _isMatching ? null : _matchLocalSubtitles,
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: '选择字幕文件',
          icon: const Icon(Icons.folder_open),
          onPressed: _pickSubtitleFile,
        ),
      ],
    );
  }

  Widget _buildMessage() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        _message!,
        style: TextStyle(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  Widget _buildMatchedSubtitles() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '已匹配字幕',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _subtitlePaths.isEmpty
              ? _buildEmptyPanel('暂无字幕文件')
              : ListView.separated(
                  itemCount: _subtitlePaths.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final subtitlePath = _subtitlePaths[index];
                    final selected = subtitlePath == _selectedSubtitlePath;
                    return ListTile(
                      dense: true,
                      leading: Radio<String>(
                        value: subtitlePath,
                        groupValue: _selectedSubtitlePath,
                        onChanged: (value) {
                          setState(() {
                            _selectedSubtitlePath = value;
                          });
                        },
                      ),
                      title: Text(
                        path.basename(subtitlePath),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        subtitlePath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: widget.onPlay == null
                          ? null
                          : IconButton(
                              tooltip: '用此字幕播放',
                              icon: Icon(
                                selected
                                    ? Icons.play_circle
                                    : Icons.play_circle_outline,
                              ),
                              onPressed: () => _playWithSubtitle(subtitlePath),
                            ),
                      onTap: () {
                        setState(() {
                          _selectedSubtitlePath = subtitlePath;
                        });
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SubtitleCat',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _isSearching
              ? const Center(child: CircularProgressIndicator())
              : _searchResults.isEmpty
                  ? _buildEmptyPanel('输入关键词后搜索字幕')
                  : ListView.separated(
                      itemCount: _searchResults.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final result = _searchResults[index];
                        final downloading = _downloadingHref == result.href;
                        return ListTile(
                          dense: true,
                          title: Text(
                            result.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '下载 ${result.downloads} / 评论 ${result.comments}',
                          ),
                          trailing: FilledButton.tonalIcon(
                            onPressed: downloading
                                ? null
                                : () => _downloadSubtitle(result),
                            icon: downloading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.download),
                            label: const Text('下载'),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildEmptyPanel(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
