import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import '../models/movie.dart';
import '../models/app_settings.dart';
import '../services/database_service.dart';
import '../services/video_file_matcher_service.dart';
import '../providers/movie_providers.dart';

class VideoFileSelector extends ConsumerStatefulWidget {
  final Movie movie;
  final Function(String) onVideoSelected;

  const VideoFileSelector({
    super.key,
    required this.movie,
    required this.onVideoSelected,
  });

  @override
  ConsumerState<VideoFileSelector> createState() => _VideoFileSelectorState();
}

class _VideoFileSelectorState extends ConsumerState<VideoFileSelector> {
  List<String> _matchedFiles = [];
  bool _isLoading = false;
  String? _selectedFile;

  @override
  void initState() {
    super.initState();
    _matchedFiles = List<String>.from(widget.movie.videoFilePaths ?? const []);
    _selectedFile = _matchedFiles.firstOrNull;
  }

  Future<void> _loadSettingsAndScan() async {
    await DatabaseService.init();
    final settings = DatabaseService.getSettings();
    if (settings.videoFolders.isNotEmpty) {
      await _scanForVideos(settings);
    }
  }

  Future<void> _scanForVideos(AppSettings settings) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final matches = await VideoFileMatcherService.matchAllVideos(
        [widget.movie.code],
        settings.videoFolders,
      );
      final matchedFiles = matches[widget.movie.code] ?? [];

      await DatabaseService.updateMovieWithLatest(
        widget.movie.id,
        (latestMovie) => latestMovie.copyWith(
          videoFilePaths: matchedFiles,
        ),
      );
      refreshMovies(ref);

      setState(() {
        _matchedFiles = matchedFiles;
        _selectedFile = matchedFiles.firstOrNull;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('扫描失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickManualFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      await _selectFile(result.files.single.path!);
    }
  }

  Future<void> _selectFile(String filePath) async {
    await DatabaseService.updateMovieWithLatest(
      widget.movie.id,
      (latestMovie) => latestMovie.copyWith(
        videoFilePaths: [filePath],
      ),
    );

    // 刷新影片列表
    refreshMovies(ref);

    setState(() {
      _matchedFiles = [filePath];
      _selectedFile = filePath;
    });

    if (mounted) {
      widget.onVideoSelected(filePath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '视频文件',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _loadSettingsAndScan,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新扫描'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _pickManualFile,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('选择文件'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_matchedFiles.isEmpty && _selectedFile == null)
              _buildEmptyState(context)
            else
              _buildFileList(context),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(
            Icons.video_file,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            '未找到匹配的视频文件',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '请在设置中配置视频文件夹，或手动选择文件',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList(BuildContext context) {
    final files = <String>[];
    if (_selectedFile != null && !_matchedFiles.contains(_selectedFile)) {
      files.add(_selectedFile!);
    }
    files.addAll(_matchedFiles);

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: files.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final filePath = files[index];
        final isSelected = filePath == _selectedFile;

        return ListTile(
          leading: Icon(
            Icons.video_file,
            color: isSelected ? Theme.of(context).colorScheme.primary : null,
          ),
          title: Text(
            path.basename(filePath),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            filePath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: isSelected
              ? Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                )
              : null,
          onTap: () => _selectFile(filePath),
          tileColor: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
              : null,
        );
      },
    );
  }
}
