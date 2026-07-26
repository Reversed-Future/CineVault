import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/movie_card.dart';
import '../widgets/toast_notification.dart';
import '../widgets/notification_center.dart';
import '../providers/movie_providers.dart';
import '../providers/notification_provider.dart';
import '../providers/translation_provider.dart';
import 'import_screen.dart';
import 'settings_screen.dart';
import 'movie_detail_screen.dart';
import 'tag_list_screen.dart';
import 'custom_movie_tags_screen.dart';
import 'tmdb_search_screen.dart';
import '../models/movie.dart';
import '../models/app_settings.dart';
import '../services/database_service.dart';
import '../services/video_file_matcher_service.dart';

class AnimatedButton extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final Color? hoverBackgroundColor;
  final double? hoverScale;
  final Duration duration;

  const AnimatedButton({
    super.key,
    required this.onTap,
    required this.child,
    this.borderRadius,
    this.backgroundColor,
    this.hoverBackgroundColor,
    this.hoverScale = 1.02,
    this.duration = const Duration(milliseconds: 250),
  });

  @override
  State<AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<AnimatedButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: TweenAnimationBuilder<double>(
          duration: widget.duration,
          curve: Curves.easeOut,
          tween: Tween(begin: 1.0, end: _isHovered ? widget.hoverScale : 1.0),
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              child: AnimatedContainer(
                duration: widget.duration,
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: _isHovered
                      ? widget.hoverBackgroundColor ??
                          (widget.backgroundColor != null
                              ? widget.backgroundColor!.withValues(alpha: 0.8)
                              : null)
                      : widget.backgroundColor,
                  borderRadius:
                      widget.borderRadius ?? BorderRadius.circular(12),
                  boxShadow: _isHovered
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [],
                ),
                child: child,
              ),
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  int _currentViewIndex = 0;

  // 本地影片扫描时间戳（避免频繁扫描）
  DateTime? _lastLocalScanTime;
  static const _scanInterval = Duration(minutes: 5); // 扫描间隔：5分钟

  @override
  void initState() {
    super.initState();
    // 监听新通知
    ref.listenManual<NotificationState>(notificationProvider, (previous, next) {
      if (next.latestNotification != null &&
          next.latestNotification != previous?.latestNotification) {
        // 通知已经在 provider 里面，我们不需要在这里做额外处理，
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showNotificationCenter() {
    showDialog(
      context: context,
      builder: (context) => const NotificationCenter(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final moviesAsync = ref.watch(moviesProvider);
    final filteredMovies = ref.watch(filteredMoviesProvider);
    final notificationState = ref.watch(notificationProvider);
    final hasUnread = notificationState.unreadNotifications.isNotEmpty;
    final latestNotification = notificationState.latestNotification;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Row(
            children: [
              _buildSidebar(),
              Expanded(
                child: Column(
                  children: [
                    _buildAppBar(hasUnread),
                    Expanded(
                      child: moviesAsync.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (error, stack) => Center(
                          child: Text('加载失败: $error'),
                        ),
                        data: (movies) {
                          if (movies.isEmpty) {
                            return _buildEmptyState();
                          }
                          return _buildMoviesGrid(filteredMovies);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (latestNotification != null)
            ToastNotification(
              notification: latestNotification,
              onDismissed: () {
                ref
                    .read(notificationProvider.notifier)
                    .clearLatestNotification();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 280,
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
                Icon(
                  Icons.movie_filter,
                  size: 32,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'CineVault',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          Divider(
              height: 1,
              color: Theme.of(context).colorScheme.surfaceContainerHighest),
          const SizedBox(height: 16),
          _buildSidebarItem(0, Icons.grid_view, '全部'),
          _buildSidebarLink(
            icon: Icons.bookmarks_outlined,
            label: '自定义标签',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CustomMovieTagsScreen(),
                ),
              );
            },
          ),
          _buildSidebarItem(1, Icons.access_time, '最近'),
          _buildSidebarItem(2, Icons.new_releases, '最新'),
          _buildSidebarItem(3, Icons.folder_open, '本地电影'),
          const SizedBox(height: 8),
          _buildSidebarLink(
            icon: Icons.tag,
            label: '类型',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TagListScreen()),
              );
            },
          ),
          _buildSidebarLink(
            icon: Icons.search,
            label: 'TMDB',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TmdbSearchScreen()),
              );
            },
          ),
          const Spacer(),
          _buildTranslationSection(),
          Divider(
              height: 1,
              color: Theme.of(context).colorScheme.surfaceContainerHighest),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildSidebarAction(
                  icon: Icons.download,
                  label: '导入电影',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ImportScreen()),
                    );
                  },
                ),
                const SizedBox(height: 8),
                _buildSidebarAction(
                  icon: Icons.settings,
                  label: '设置',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranslationSection() {
    final translationState = ref.watch(backgroundTranslationProvider);

    // 用 ConstrainedBox + SingleChildScrollView 限制最大高度
    // 避免翻译进度展开时溢出侧边栏
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 240),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '翻译管理',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              if (translationState.isTranslating) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            translationState.isPaused ? '翻译已暂停' : '正在翻译',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: translationState.isPaused
                                  ? Colors.orange
                                  : Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          if (translationState.currentMovie != null)
                            Icon(
                              translationState.isPaused
                                  ? Icons.pause_circle
                                  : Icons.play_circle,
                              size: 16,
                              color: translationState.isPaused
                                  ? Colors.orange
                                  : Theme.of(context).colorScheme.primary,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: translationState.totalMovies > 0
                            ? translationState.completedMovies /
                                translationState.totalMovies
                            : 0,
                        borderRadius: BorderRadius.circular(8),
                        minHeight: 6,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${translationState.completedMovies}/${translationState.totalMovies}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (translationState.currentMovie != null)
                            Expanded(
                              child: Text(
                                translationState.currentMovie!,
                                style: Theme.of(context).textTheme.bodySmall,
                                textAlign: TextAlign.right,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _TranslationControlButton(
                              icon: translationState.isPaused
                                  ? Icons.play_arrow
                                  : Icons.pause,
                              label: translationState.isPaused ? '继续' : '暂停',
                              onTap: () {
                                if (translationState.isPaused) {
                                  ref
                                      .read(backgroundTranslationProvider
                                          .notifier)
                                      .resumeTranslation();
                                } else {
                                  ref
                                      .read(backgroundTranslationProvider
                                          .notifier)
                                      .pauseTranslation();
                                }
                              },
                              backgroundColor: translationState.isPaused
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                              foregroundColor: translationState.isPaused
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _TranslationControlButton(
                            icon: Icons.stop,
                            label: '停止',
                            onTap: () {
                              ref
                                  .read(backgroundTranslationProvider.notifier)
                                  .stopTranslation();
                            },
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ] else ...[
                _buildSidebarAction(
                  icon: Icons.translate,
                  label: '翻译现有内容',
                  onTap: () {
                    ref
                        .read(backgroundTranslationProvider.notifier)
                        .startBackgroundTranslation();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarItem(int index, IconData icon, String label) {
    final isSelected = _currentViewIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: _SidebarItem(
        isSelected: isSelected,
        icon: icon,
        label: label,
        onTap: () {
          setState(() {
            _currentViewIndex = index;
          });
          // 切换到本地影片视图时触发扫描（如果距离上次扫描超过5分钟）
          if (index == 3) {
            _scanLocalMoviesIfNeeded();
          }
        },
      ),
    );
  }

  /// 检查是否需要扫描本地影片（避免频繁扫描）
  void _scanLocalMoviesIfNeeded() {
    final now = DateTime.now();
    if (_lastLocalScanTime != null &&
        now.difference(_lastLocalScanTime!) < _scanInterval) {
      final elapsed = now.difference(_lastLocalScanTime!);
      print(
          '[HomeScreen] Skip scan: last scan was ${elapsed.inSeconds}s ago (interval: ${_scanInterval.inMinutes}min)');
      return;
    }
    _scanLocalMovies();
  }

  /// 扫描本地视频文件并匹配影片，保存结果到数据库
  Future<void> _scanLocalMovies() async {
    try {
      await DatabaseService.init();
      final settings = DatabaseService.getSettings();
      if (settings.videoFolders.isEmpty) {
        print('[HomeScreen] No video folders configured');
        return;
      }

      final movies = ref.read(moviesProvider).when(
            data: (data) => data,
            loading: () => <Movie>[],
            error: (_, __) => <Movie>[],
          );

      if (movies.isEmpty) {
        print('[HomeScreen] No movies to match');
        return;
      }

      final codes = movies.map((m) => m.code).toList();
      final matches = await VideoFileMatcherService.matchAllVideos(
        codes,
        settings.videoFolders,
      );

      // 将匹配结果保存到数据库
      int updatedCount = 0;
      for (final movie in movies) {
        final latestMovie = DatabaseService.getMovie(movie.id) ?? movie;
        final matchedFiles = matches[movie.code];
        if (matchedFiles != null && matchedFiles.isNotEmpty) {
          // 如果影片没有 videoFilePaths 或路径已过期，更新它
          if (!_samePathSet(
              latestMovie.videoFilePaths ?? const [], matchedFiles)) {
            await DatabaseService.updateMovieWithLatest(
              movie.id,
              (savedMovie) => savedMovie.copyWith(videoFilePaths: matchedFiles),
            );
            updatedCount++;
          }
        } else {
          final existingPaths =
              await _filterExistingVideoPaths(latestMovie.videoFilePaths);
          if (!_samePathSet(
              latestMovie.videoFilePaths ?? const [], existingPaths)) {
            await DatabaseService.updateMovieWithLatest(
              movie.id,
              (savedMovie) =>
                  savedMovie.copyWith(videoFilePaths: existingPaths),
            );
            updatedCount++;
          }
        }
      }

      // 刷新 provider 以更新 UI
      refreshMovies(ref);

      // 更新扫描时间戳
      _lastLocalScanTime = DateTime.now();

      print(
          '[HomeScreen] Local movie scan completed: ${matches.length} matches, $updatedCount movies updated');
      for (final entry in matches.entries.take(5)) {
        if (entry.value.isNotEmpty) {
          print('[HomeScreen]   ${entry.key}: ${entry.value.length} files');
        }
      }
    } catch (e) {
      print('[HomeScreen] Error scanning local movies: $e');
    }
  }

  Future<List<String>> _filterExistingVideoPaths(List<String>? paths) async {
    if (paths == null || paths.isEmpty) return const [];

    final existingPaths = <String>[];
    for (final filePath in paths) {
      if (await File(filePath).exists()) {
        existingPaths.add(filePath);
      }
    }
    return existingPaths;
  }

  bool _samePathSet(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final bSet = b.toSet();
    return a.every(bSet.contains);
  }

  Widget _buildSidebarAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return _SidebarAction(
      icon: icon,
      label: label,
      onTap: onTap,
    );
  }

  Widget _buildSidebarLink({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: _SidebarLink(
        icon: icon,
        label: label,
        onTap: onTap,
      ),
    );
  }

  Widget _buildAppBar(bool hasUnread) {
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
          _buildNotificationButton(hasUnread),
        ],
      ),
    );
  }

  Widget _buildNotificationButton(bool hasUnread) {
    return Stack(
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          onPressed: _showNotificationCenter,
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.3),
          ),
        ),
        if (hasUnread)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: '搜索影片...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchController.text.isNotEmpty
            ? _AnimatedSearchButton(
                icon: Icons.close,
                onTap: () {
                  _searchController.clear();
                  ref.read(searchQueryProvider.notifier).state = '';
                },
              )
            : null,
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
      onChanged: (value) {
        ref.read(searchQueryProvider.notifier).state = value;
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.movie_creation,
            size: 80,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 24),
          Text(
            '还没有影片',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            '点击左侧导入按钮开始添加影片',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoviesGrid(List<Movie> movies) {
    final gridMovies = _filterMoviesByView(movies);

    if (gridMovies.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '没有找到匹配的影片',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 24,
        crossAxisSpacing: 16,
        childAspectRatio: 0.67,
      ),
      itemCount: gridMovies.length,
      itemBuilder: (context, index) {
        final movie = gridMovies[index];
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
            // 刷新 moviesProvider
            ref.read(moviesRefreshSignal.notifier).state++;
          },
        );
      },
    );
  }

  List<Movie> _filterMoviesByView(List<Movie> movies) {
    switch (_currentViewIndex) {
      case 1:
        return movies.where((m) => m.safeLastWatchedAt > 0).toList()
          ..sort((a, b) => b.safeLastWatchedAt.compareTo(a.safeLastWatchedAt));
      case 2:
        // 最新保存的影片，按创建时间倒序排列
        return List<Movie>.from(movies)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case 3:
        // 有本地视频文件的影片（直接从数据库的 videoFilePaths 读取）
        final localMovies = movies
            .where(
                (m) => m.videoFilePaths != null && m.videoFilePaths!.isNotEmpty)
            .toList();

        print(
            '[HomeScreen] Local movies: ${localMovies.length} / ${movies.length}');

        return localMovies;
      default:
        return movies;
    }
  }
}

class _SidebarItem extends StatefulWidget {
  final bool isSelected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.isSelected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final baseColor =
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.15);
    final hoverColor =
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.25);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          tween: Tween(begin: 1.0, end: _isHovered ? 1.02 : 1.0),
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? (_isHovered ? hoverColor : baseColor)
                      : (_isHovered
                          ? Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.3)
                          : Colors.transparent),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _isHovered && widget.isSelected
                      ? [
                          BoxShadow(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: child,
              ),
            );
          },
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: Icon(
                  widget.icon,
                  color: widget.isSelected
                      ? Theme.of(context).colorScheme.primary
                      : (_isHovered
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 12),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                style: TextStyle(
                  fontWeight:
                      widget.isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: widget.isSelected
                      ? Theme.of(context).colorScheme.primary
                      : (_isHovered
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                child: Text(widget.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SidebarAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_SidebarAction> createState() => _SidebarActionState();
}

class _SidebarActionState extends State<_SidebarAction> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final baseColor = Theme.of(context)
        .colorScheme
        .surfaceContainerHighest
        .withValues(alpha: 0.3);
    final hoverColor = Theme.of(context)
        .colorScheme
        .surfaceContainerHighest
        .withValues(alpha: 0.5);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          tween: Tween(begin: 1.0, end: _isHovered ? 1.02 : 1.0),
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _isHovered ? hoverColor : baseColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _isHovered
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: child,
              ),
            );
          },
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: Icon(
                  widget.icon,
                  color: _isHovered
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                style: TextStyle(
                  color: _isHovered
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: _isHovered ? FontWeight.w500 : FontWeight.normal,
                ),
                child: Text(widget.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarLink extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SidebarLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_SidebarLink> createState() => _SidebarLinkState();
}

class _SidebarLinkState extends State<_SidebarLink> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final baseColor = Theme.of(context)
        .colorScheme
        .surfaceContainerHighest
        .withValues(alpha: 0.3);
    final hoverColor = Theme.of(context)
        .colorScheme
        .surfaceContainerHighest
        .withValues(alpha: 0.5);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          tween: Tween(begin: 1.0, end: _isHovered ? 1.02 : 1.0),
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _isHovered ? hoverColor : baseColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _isHovered
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: child,
              ),
            );
          },
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: Icon(
                  widget.icon,
                  color: _isHovered
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                style: TextStyle(
                  color: _isHovered
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: _isHovered ? FontWeight.w500 : FontWeight.normal,
                ),
                child: Text(widget.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedSearchButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _AnimatedSearchButton({
    required this.icon,
    required this.onTap,
  });

  @override
  State<_AnimatedSearchButton> createState() => _AnimatedSearchButtonState();
}

class _AnimatedSearchButtonState extends State<_AnimatedSearchButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          tween: Tween(begin: 1.0, end: _isHovered ? 1.1 : 1.0),
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _isHovered
                      ? Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.8)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: child,
              ),
            );
          },
          child: Icon(
            widget.icon,
            color: _isHovered
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _TranslationControlButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color backgroundColor;
  final Color foregroundColor;

  const _TranslationControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  State<_TranslationControlButton> createState() =>
      _TranslationControlButtonState();
}

class _TranslationControlButtonState extends State<_TranslationControlButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          tween: Tween(begin: 1.0, end: _isHovered ? 0.98 : 1.0),
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _isHovered
                      ? widget.backgroundColor.withOpacity(0.9)
                      : widget.backgroundColor,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: _isHovered
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: child,
              ),
            );
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: widget.foregroundColor,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.foregroundColor,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
