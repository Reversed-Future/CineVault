import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ai/local_translator.dart';
import '../ai/model_manager.dart';
import '../ai/movie_ai_tagger.dart';
import '../models/ai_tagging_result.dart';
import '../models/custom_movie_tag.dart';
import '../models/movie.dart';
import '../providers/movie_providers.dart';
import '../services/database_service.dart';
import '../widgets/movie_card.dart';
import 'movie_detail_screen.dart';

class CustomMovieTagsScreen extends ConsumerStatefulWidget {
  const CustomMovieTagsScreen({super.key});

  @override
  ConsumerState<CustomMovieTagsScreen> createState() =>
      _CustomMovieTagsScreenState();
}

class _CustomMovieTagsScreenState extends ConsumerState<CustomMovieTagsScreen> {
  static const double _sidebarWidth = 280;
  static const double _movieGridMaxWidth = 200;

  final TextEditingController _searchController = TextEditingController();
  String _searchKeyword = '';
  String? _selectedTagId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchKeyword = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tagsAsync = ref.watch(customMovieTagsProvider);
    final linksAsync = ref.watch(movieCustomTagLinksProvider);
    final moviesAsync = ref.watch(moviesProvider);

    final error = tagsAsync.asError?.error ??
        linksAsync.asError?.error ??
        moviesAsync.asError?.error;
    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('自定义标签')),
        body: Center(child: Text('加载失败: $error')),
      );
    }

    final tags = tagsAsync.asData?.value;
    final links = linksAsync.asData?.value;
    final movies = moviesAsync.asData?.value;
    if (tags == null || links == null || movies == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('自定义标签')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final selectedTag = _findSelectedTag(tags);
    final tagCounts = _buildTagCounts(links, movies);
    final allTaggedMovieCount = _buildAllTaggedMovieIds(links, movies).length;
    final visibleMovies = _buildVisibleMovies(links, movies);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Row(
        children: [
          _buildSidebar(tags, tagCounts, allTaggedMovieCount),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(
                  selectedTag,
                  visibleMovies.length,
                  movies,
                  tags,
                ),
                Expanded(child: _buildMovieGrid(visibleMovies)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  CustomMovieTag? _findSelectedTag(List<CustomMovieTag> tags) {
    if (_selectedTagId == null) return null;
    for (final tag in tags) {
      if (tag.id == _selectedTagId) return tag;
    }
    return null;
  }

  Map<String, int> _buildTagCounts(
    List<MovieCustomTagLink> links,
    List<Movie> movies,
  ) {
    final existingMovieIds = movies.map((movie) => movie.id).toSet();
    final counts = <String, int>{};
    for (final link in links) {
      if (!existingMovieIds.contains(link.movieId)) continue;
      counts[link.tagId] = (counts[link.tagId] ?? 0) + 1;
    }
    return counts;
  }

  Set<String> _buildAllTaggedMovieIds(
    List<MovieCustomTagLink> links,
    List<Movie> movies,
  ) {
    final existingMovieIds = movies.map((movie) => movie.id).toSet();
    return links
        .where((link) => existingMovieIds.contains(link.movieId))
        .map((link) => link.movieId)
        .toSet();
  }

  List<Movie> _buildVisibleMovies(
    List<MovieCustomTagLink> links,
    List<Movie> movies,
  ) {
    final movieIds = _selectedTagId == null
        ? _buildAllTaggedMovieIds(links, movies)
        : links
            .where((link) => link.tagId == _selectedTagId)
            .map((link) => link.movieId)
            .toSet();

    final visibleMovies =
        movies.where((movie) => movieIds.contains(movie.id)).where((movie) {
      if (_searchKeyword.isEmpty) return true;
      final tagText = movie.tags?.map((tag) => tag.name).join(' ') ?? '';
      final castText = movie.cast.map((cast) => cast.name).join(' ');
      final text =
          '${movie.code} ${movie.name} $tagText $castText'.toLowerCase();
      return text.contains(_searchKeyword);
    }).toList();

    visibleMovies.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return visibleMovies;
  }

  Widget _buildSidebar(
    List<CustomMovieTag> tags,
    Map<String, int> tagCounts,
    int allTaggedMovieCount,
  ) {
    return Container(
      width: _sidebarWidth,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.arrow_back),
                    tooltip: '返回',
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '自定义标签',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.add),
                    tooltip: '新建标签',
                    onPressed: _createTag,
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 16),
          _buildAllTagsTile(allTaggedMovieCount),
          const SizedBox(height: 4),
          Expanded(
            child: tags.isEmpty
                ? _buildEmptyTagList()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: tags.length,
                    itemBuilder: (context, index) {
                      final tag = tags[index];
                      return _buildTagTile(tag, tagCounts[tag.id] ?? 0);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllTagsTile(int count) {
    final isSelected = _selectedTagId == null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: _CustomTagTile(
        isSelected: isSelected,
        icon: Icons.bookmarks_outlined,
        label: '全部标签影片',
        count: count,
        onTap: () {
          setState(() {
            _selectedTagId = null;
          });
        },
      ),
    );
  }

  Widget _buildTagTile(CustomMovieTag tag, int count) {
    final isSelected = _selectedTagId == tag.id;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _CustomTagTile(
        isSelected: isSelected,
        icon: Icons.label_outline,
        label: tag.name,
        count: count,
        onTap: () {
          setState(() {
            _selectedTagId = tag.id;
          });
        },
        trailing: PopupMenuButton<String>(
          tooltip: '标签操作',
          onSelected: (value) {
            if (value == 'rename') {
              _renameTag(tag);
            } else if (value == 'delete') {
              _deleteTag(tag);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'rename',
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('重命名'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.red),
                title: Text('删除', style: TextStyle(color: Colors.red)),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyTagList() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.label_off_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              '还没有自定义标签',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(
    CustomMovieTag? selectedTag,
    int movieCount,
    List<Movie> allMovies,
    List<CustomMovieTag> allTags,
  ) {
    final title = selectedTag?.name ?? '全部标签影片';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(child: _buildSearchBar()),
          const SizedBox(width: 12),
          _TagSummaryChip(
            icon: selectedTag == null
                ? Icons.bookmarks_outlined
                : Icons.label_outline,
            label: title,
            count: movieCount,
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'AI自动分类',
            onPressed: () => _openAiTaggingDialog(allMovies, allTags),
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建标签',
            onPressed: _createTag,
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: '搜索标签内影片...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchKeyword.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                tooltip: '清空',
                onPressed: _searchController.clear,
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.3),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _buildMovieGrid(List<Movie> movies) {
    if (movies.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.movie_outlined,
              size: 72,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无关联影片',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _movieGridMaxWidth,
        mainAxisSpacing: 24,
        crossAxisSpacing: 16,
        childAspectRatio: 0.67,
      ),
      itemCount: movies.length,
      itemBuilder: (context, index) {
        final movie = movies[index];
        return MovieCard(
          key: ValueKey(movie.id),
          movie: movie,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MovieDetailScreen(movie: movie),
              ),
            );
          },
          onPropertiesChanged: () {
            refreshMovies(ref);
            refreshCustomMovieTags(ref);
          },
        );
      },
    );
  }

  Future<void> _createTag() async {
    final name = await _showTagNameDialog(title: '新建标签');
    if (name == null) return;
    try {
      final tag = await DatabaseService.createCustomMovieTag(name);
      refreshCustomMovieTags(ref);
      if (!mounted) return;
      setState(() {
        _selectedTagId = tag.id;
      });
    } catch (e) {
      _showSnackBar('新建标签失败: $e');
    }
  }

  Future<void> _renameTag(CustomMovieTag tag) async {
    final name = await _showTagNameDialog(
      title: '重命名标签',
      initialValue: tag.name,
    );
    if (name == null) return;
    try {
      await DatabaseService.renameCustomMovieTag(tag.id, name);
      refreshCustomMovieTags(ref);
    } catch (e) {
      _showSnackBar('重命名失败: $e');
    }
  }

  Future<void> _deleteTag(CustomMovieTag tag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除标签'),
        content: Text('确定删除“${tag.name}”吗？关联关系会一起移除，影片自身标签不会变化。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await DatabaseService.deleteCustomMovieTag(tag.id);
    refreshCustomMovieTags(ref);
    if (!mounted) return;
    if (_selectedTagId == tag.id) {
      setState(() {
        _selectedTagId = null;
      });
    }
  }

  Future<String?> _showTagNameDialog({
    required String title,
    String initialValue = '',
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '标签名称',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            final name = controller.text.trim();
            if (name.isNotEmpty) Navigator.of(context).pop(name);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) Navigator.of(context).pop(name);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result?.trim().isEmpty == true ? null : result?.trim();
  }

  Future<void> _openAiTaggingDialog(
    List<Movie> movies,
    List<CustomMovieTag> tags,
  ) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AiTaggingDialog(
        movies: movies,
        customTags: tags,
      ),
    );
    if (changed != true) return;
    refreshMovies(ref);
    refreshCustomMovieTags(ref);
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _AiTaggingDialog extends StatefulWidget {
  final List<Movie> movies;
  final List<CustomMovieTag> customTags;

  const _AiTaggingDialog({
    required this.movies,
    required this.customTags,
  });

  @override
  State<_AiTaggingDialog> createState() => _AiTaggingDialogState();
}

class _AiTaggingDialogState extends State<_AiTaggingDialog> {
  final MovieAiTagger _tagger = MovieAiTagger();
  bool _onlyWithoutCustomTags = true;
  bool _isRunning = false;
  bool _cancelRequested = false;
  int _total = 0;
  int _processed = 0;
  int _applied = 0;
  int _pending = 0;
  int _failed = 0;
  String _currentMovieLabel = '';
  String? _message;
  final List<AiTaggingResult> _recentResults = [];

  @override
  Widget build(BuildContext context) {
    final targetCount = _isRunning ? _total : _buildTargetMovies().length;
    final progress = _total == 0 ? 0.0 : _processed / _total;

    return AlertDialog(
      title: const Text('AI自动分类'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('仅处理未打自定义标签影片'),
              value: _onlyWithoutCustomTags,
              onChanged: _isRunning
                  ? null
                  : (value) {
                      setState(() {
                        _onlyWithoutCustomTags = value;
                      });
                    },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _AiTaggingStat(label: '待处理', value: '$targetCount'),
                _AiTaggingStat(label: '已处理', value: '$_processed'),
                _AiTaggingStat(label: '已应用', value: '$_applied'),
                _AiTaggingStat(label: '待确认', value: '$_pending'),
                _AiTaggingStat(label: '失败', value: '$_failed'),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _isRunning ? progress : null),
            const SizedBox(height: 12),
            Text(
              _currentMovieLabel.isEmpty
                  ? '置信度不低于85%的结果会自动应用'
                  : '正在处理：$_currentMovieLabel',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(
                _message!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ],
            if (_recentResults.isNotEmpty) ...[
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _recentResults.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final result = _recentResults[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        _statusIcon(result.status),
                        size: 20,
                        color: _statusColor(context, result.status),
                      ),
                      title: Text(
                        result.movieId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(_statusLabel(result.status)),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isRunning
              ? () {
                  setState(() {
                    _cancelRequested = true;
                    _message = '当前影片处理完成后停止';
                  });
                }
              : () => Navigator.of(context).pop(_processed > 0),
          child: Text(_isRunning ? '停止' : '关闭'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.auto_awesome),
          onPressed: _isRunning ? null : _start,
          label: const Text('开始'),
        ),
      ],
    );
  }

  List<Movie> _buildTargetMovies() {
    if (!_onlyWithoutCustomTags) {
      return List<Movie>.from(widget.movies);
    }
    return widget.movies.where((movie) {
      return DatabaseService.getCustomTagIdsForMovie(movie.id).isEmpty;
    }).toList();
  }

  Future<void> _start() async {
    if (widget.customTags.isEmpty) {
      setState(() {
        _message = '请先创建自定义标签';
      });
      return;
    }

    final settings = DatabaseService.getSettings();
    final shouldUnloadModelAfterAiTagging =
        settings.unloadModelAfterAiTagging;
    final modelId = settings.selectedModelId?.trim();
    if (modelId == null || modelId.isEmpty) {
      setState(() {
        _message = '请先在AI设置中选择本地模型';
      });
      return;
    }

    final targetMovies = _buildTargetMovies();
    if (targetMovies.isEmpty) {
      setState(() {
        _message = '没有需要处理的影片';
      });
      return;
    }

    await ModelManager().setCustomModelsPath(settings.customModelsPath);
    if (!mounted) return;

    setState(() {
      _isRunning = true;
      _cancelRequested = false;
      _total = targetMovies.length;
      _processed = 0;
      _applied = 0;
      _pending = 0;
      _failed = 0;
      _currentMovieLabel = '';
      _message = null;
      _recentResults.clear();
    });

    String? unloadMessage;
    try {
      for (final movie in targetMovies) {
      if (_cancelRequested) break;
      if (!mounted) return;

      setState(() {
        _currentMovieLabel = '${movie.code} ${movie.name}'.trim();
      });

      AiTaggingResult? result;
      try {
        result = await _tagger.analyzeStoreAndApply(
          movie: movie,
          customTags: widget.customTags,
          modelId: modelId,
        );
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _failed++;
          _message = '处理失败：${movie.code}';
        });
      }

      if (!mounted) return;
      setState(() {
        if (result != null) {
          _recentResults.insert(0, result);
          if (_recentResults.length > 6) {
            _recentResults.removeRange(6, _recentResults.length);
          }
          if (result.status == AiTaggingResult.statusApplied) {
            _applied++;
          } else if (result.status == AiTaggingResult.statusPendingReview) {
            _pending++;
          } else if (result.status == AiTaggingResult.statusFailed) {
            _failed++;
          }
        }
        _processed++;
      });
      }
    } finally {
      if (shouldUnloadModelAfterAiTagging) {
        try {
          await LocalTranslator().unloadModel();
          unloadMessage = '模型已卸载';
        } catch (error) {
          unloadMessage = '模型卸载失败: $error';
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _isRunning = false;
      _currentMovieLabel = '';
      if (_cancelRequested) {
        _message = unloadMessage == null ? '已停止' : '已停止，$unloadMessage';
      } else if (unloadMessage != null) {
        _message = unloadMessage;
      }
    });
  }

  IconData _statusIcon(String status) {
    if (status == AiTaggingResult.statusApplied) {
      return Icons.check_circle_outline;
    }
    if (status == AiTaggingResult.statusFailed) {
      return Icons.error_outline;
    }
    return Icons.pending_outlined;
  }

  Color _statusColor(BuildContext context, String status) {
    if (status == AiTaggingResult.statusApplied) {
      return Colors.green;
    }
    if (status == AiTaggingResult.statusFailed) {
      return Theme.of(context).colorScheme.error;
    }
    return Theme.of(context).colorScheme.primary;
  }

  String _statusLabel(String status) {
    if (status == AiTaggingResult.statusApplied) {
      return '已应用';
    }
    if (status == AiTaggingResult.statusFailed) {
      return '失败';
    }
    return '待确认';
  }
}

class _AiTaggingStat extends StatelessWidget {
  final String label;
  final String value;

  const _AiTaggingStat({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _TagSummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;

  const _TagSummaryChip({
    required this.icon,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$count',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomTagTile extends StatefulWidget {
  final bool isSelected;
  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;
  final Widget? trailing;

  const _CustomTagTile({
    required this.isSelected,
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
    this.trailing,
  });

  @override
  State<_CustomTagTile> createState() => _CustomTagTileState();
}

class _CustomTagTileState extends State<_CustomTagTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final baseColor =
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.15);
    final hoverColor =
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.25);
    final backgroundColor = widget.isSelected
        ? (_isHovered ? hoverColor : baseColor)
        : _isHovered
            ? Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.3)
            : Colors.transparent;
    final foregroundColor = widget.isSelected
        ? Theme.of(context).colorScheme.primary
        : (_isHovered
            ? Theme.of(context).colorScheme.onSurface
            : Theme.of(context).colorScheme.onSurfaceVariant);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 20, color: foregroundColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foregroundColor,
                    fontWeight:
                        widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${widget.count}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: widget.isSelected
                          ? foregroundColor
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: 2),
                SizedBox(width: 32, height: 32, child: widget.trailing),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
