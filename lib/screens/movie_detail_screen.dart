import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../models/movie.dart';
import '../models/cast.dart';
import '../models/custom_movie_tag.dart';
import '../models/named_item.dart';
import '../services/database_service.dart';
import '../services/image_cache_service.dart';
import '../services/magnet_downloader.dart';
import '../services/video_file_matcher_service.dart';
import '../widgets/magnet_file_picker_dialog.dart';
import '../providers/tmdb_provider.dart';
import '../providers/movie_providers.dart';
import '../widgets/video_file_selector.dart';
import '../widgets/movie_card.dart';
import '../widgets/smart_image.dart';
import '../widgets/movie_data_compare_dialog.dart';
import '../widgets/subtitle_manager_dialog.dart';
import 'player_screen.dart';
import 'movie_filter_screen.dart';

class MovieDetailScreen extends ConsumerStatefulWidget {
  final Movie movie;

  const MovieDetailScreen({
    super.key,
    required this.movie,
  });

  @override
  ConsumerState<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends ConsumerState<MovieDetailScreen> {
  late Movie _movie;
  String? _selectedVideoPath;
  int _currentImageIndex = 0;
  final ScrollController _detailScrollController = ScrollController();
  final ScrollController _thumbnailScrollController = ScrollController();
  final double _thumbnailWidth = 80;
  final double _thumbnailSpacing = 8;
  bool _isLoadingRelatedMovies = false;
  List<Movie> _relatedMovies = const [];
  String? _copiedMagnet;
  bool _magnetsExpanded = false; // 磁力链接默认收起
  double? _horizontalCoverAspectRatio;

  /// 获取可用于横向裁剪的封面 URL（优先使用原始封面）
  String? _getHorizontalCoverUrl() {
    return _getHorizontalCoverUrlFor(_movie);
  }

  String? _getHorizontalCoverUrlFor(Movie movie) {
    final backdropUrl = movie.backdropUrl?.trim();
    if (backdropUrl != null && backdropUrl.isNotEmpty) {
      return backdropUrl;
    }

    final samples = movie.samples ?? const <SampleInfo>[];
    for (final sample in samples) {
      final src = sample.src.trim();
      if (src.isNotEmpty) return src;

      final thumbnail = sample.thumbnail.trim();
      if (thumbnail.isNotEmpty) return thumbnail;
    }

    final originalCoverUrl = movie.originalCoverUrl?.trim();
    if (originalCoverUrl != null && originalCoverUrl.isNotEmpty) {
      return originalCoverUrl;
    }

    final coverUrl = movie.coverUrl?.trim();
    return coverUrl != null && coverUrl.isNotEmpty ? coverUrl : null;
  }

  String? _getPosterCoverUrl() {
    final coverUrl = _movie.coverUrl?.trim();
    if (coverUrl != null && coverUrl.isNotEmpty) {
      return coverUrl;
    }

    final originalCoverUrl = _movie.originalCoverUrl?.trim();
    return originalCoverUrl != null && originalCoverUrl.isNotEmpty
        ? originalCoverUrl
        : null;
  }

  double _posterPreviewHeight(BuildContext context) {
    final viewportWidth = MediaQuery.of(context).size.width;
    final aspectRatio = _horizontalCoverAspectRatio ?? 16 / 9;
    return viewportWidth / (aspectRatio > 0 ? aspectRatio : 16 / 9);
  }

  void _handleHorizontalCoverLoaded(double width, double height) {
    if (!mounted || width <= 0 || height <= 0) return;

    final aspectRatio = width / height;
    if ((aspectRatio - (_horizontalCoverAspectRatio ?? 0)).abs() < 0.01) {
      return;
    }

    setState(() {
      _horizontalCoverAspectRatio = aspectRatio;
    });
  }

  void _resetHorizontalCoverAspectRatioIfChanged(Movie movie) {
    if (_getHorizontalCoverUrlFor(movie) == _getHorizontalCoverUrl()) {
      return;
    }
    _horizontalCoverAspectRatio = null;
  }

  Movie _mergeMetadataFields(Movie latestMovie, Movie editedMovie) {
    return latestMovie.copyWith(
      name: editedMovie.name,
      cast: editedMovie.cast,
      tags: editedMovie.tags,
      coverUrl: editedMovie.coverUrl,
      originalCoverUrl: editedMovie.originalCoverUrl,
      isCoverCropped: editedMovie.isCoverCropped,
      backdropUrl: editedMovie.backdropUrl,
      code: editedMovie.code,
      releaseDate: editedMovie.releaseDate,
      length: editedMovie.length,
      samples: editedMovie.samples,
      magnets: editedMovie.magnets,
      director: editedMovie.director,
      producer: editedMovie.producer,
      publisher: editedMovie.publisher,
      series: editedMovie.series,
    );
  }

  @override
  void initState() {
    super.initState();
    _movie = widget.movie;
    _selectedVideoPath = widget.movie.videoFilePaths?.firstOrNull;
    _reloadMovieFromDatabase();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleInitialDetailScroll();
    });
  }

  @override
  void dispose() {
    _detailScrollController.dispose();
    _thumbnailScrollController.dispose();
    super.dispose();
  }

  void _scheduleInitialDetailScroll() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted || !_detailScrollController.hasClients) return;

      final position = _detailScrollController.position;
      if (position.pixels > 8) return;

      final target = (_posterPreviewHeight(context) - kToolbarHeight)
          .clamp(0.0, position.maxScrollExtent)
          .toDouble();
      _detailScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _reloadMovieFromDatabase() async {
    if (!mounted) {
      return;
    }

    final latestMovie = DatabaseService.getMovie(_movie.id) ?? _movie;
    final currentVideoPath = _selectedVideoPath;
    final hasCurrentVideo = currentVideoPath != null &&
        latestMovie.videoFilePaths?.contains(currentVideoPath) == true;
    _resetHorizontalCoverAspectRatioIfChanged(latestMovie);
    _movie = latestMovie;
    _selectedVideoPath = hasCurrentVideo
        ? currentVideoPath
        : latestMovie.videoFilePaths?.firstOrNull;
    await _loadRelatedMovies();
  }

  void _setCurrentMovie(Movie movie) {
    _resetHorizontalCoverAspectRatioIfChanged(movie);
    final currentVideoPath = _selectedVideoPath;
    _selectedVideoPath =
        movie.videoFilePaths?.contains(currentVideoPath) == true
            ? currentVideoPath
            : movie.videoFilePaths?.firstOrNull;
    _movie = movie;
  }

  Future<void> _loadRelatedMovies() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoadingRelatedMovies = true;
    });

    final relatedIds = DatabaseService.getMovieRelatedIds(_movie.id);
    final related = <Movie>[];
    final seen = <String>{};

    for (final relatedId in relatedIds) {
      final relatedMovie = _findMovieByRelationId(relatedId);
      if (relatedMovie == null || relatedMovie.id == _movie.id) {
        continue;
      }
      if (seen.add(relatedMovie.id)) {
        related.add(relatedMovie);
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _relatedMovies = related;
      _isLoadingRelatedMovies = false;
    });
  }

  Movie? _findMovieByRelationId(String relatedId) {
    return DatabaseService.findMovieByRelationId(
      relatedId,
      excludeMovieId: _movie.id,
    );
  }

  Future<void> _toggleFavorite() async {
    await DatabaseService.toggleFavorite(_movie.id);
    final updatedMovie = DatabaseService.getMovie(_movie.id);
    if (updatedMovie == null || !mounted) return;
    setState(() {
      _setCurrentMovie(updatedMovie);
    });
  }

  /// 编辑影片资料 ID
  Future<void> _editMovieCode() async {
    final controller = TextEditingController(text: _movie.code);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑 TMDB ID'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'TMDB ID',
                hintText: '例如：550',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Text(
              '修改 TMDB ID 后会保留当前本地视频路径。',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final newCode = controller.text.trim();
              if (newCode.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('TMDB ID 不能为空')),
                );
                return;
              }
              Navigator.pop(context, newCode);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (result == null || result == _movie.code) return;

    try {
      final updatedMovie = await DatabaseService.updateMovieCode(
        _movie,
        result,
      );

      // 刷新 UI
      setState(() {
        _setCurrentMovie(updatedMovie);
      });
      refreshMovies(ref);

      // 通知用户
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('TMDB ID 已修改为 $result'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      print('[MovieDetailScreen] Error updating movie code: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('修改失败: ${e.toString()}')),
      );
    }
  }

  void _playVideo({String? subtitlePath}) {
    if (_selectedVideoPath != null) {
      _checkAndPlayVideo(_selectedVideoPath!, subtitlePath: subtitlePath);
    }
  }

  Future<void> _checkAndPlayVideo(
    String videoPath, {
    String? subtitlePath,
  }) async {
    // 检查文件是否存在
    final file = File(videoPath);
    if (await file.exists()) {
      // 文件存在，直接播放
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            movie: _movie,
            videoPath: videoPath,
            subtitlePath: subtitlePath,
          ),
        ),
      );
    } else {
      // 文件不存在，弹窗提醒
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('文件不存在'),
          content: Text(
            '视频文件不存在或已被删除：\n\n$videoPath\n\n是否删除该视频路径并重新扫描？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除并重新扫描'),
            ),
          ],
        ),
      );

      if (result == true) {
        // 删除路径并重新扫描
        await _removeVideoPathAndRescan(videoPath);
      }
    }
  }

  Future<void> _removeVideoPathAndRescan(String videoPath) async {
    try {
      final pathRemovedMovie = await DatabaseService.updateMovieWithLatest(
        _movie.id,
        (latestMovie) {
          final updatedPaths = latestMovie.videoFilePaths
                  ?.where((path) => path != videoPath)
                  .toList() ??
              [];
          return latestMovie.copyWith(videoFilePaths: updatedPaths);
        },
      );

      // 重新扫描该影片
      await _rescanMovie(pathRemovedMovie);
      final updatedMovie =
          DatabaseService.getMovie(_movie.id) ?? pathRemovedMovie;
      // 刷新 UI
      setState(() {
        _setCurrentMovie(updatedMovie);
      });

      // 显示成功提示
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('路径已删除并重新扫描'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('[MovieDetailScreen] Error removing path and rescanning: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('操作失败: ${e.toString()}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<List<String>> _rescanMovie([Movie? sourceMovie]) async {
    // 对单个影片执行重新扫描
    try {
      final movie =
          sourceMovie ?? DatabaseService.getMovie(_movie.id) ?? _movie;
      print('[MovieDetailScreen] Rescanning movie: ${movie.code}');

      final settings = DatabaseService.getSettings();
      if (settings.videoFolders.isEmpty) {
        print('[MovieDetailScreen] No video folders configured');
        return const [];
      }

      // 使用 VideoFileMatcherService 扫描该影片
      final matches = await VideoFileMatcherService.matchAllVideos(
        [movie.code],
        settings.videoFolders,
      );

      final matchedFiles = matches[movie.code];
      if (matchedFiles != null && matchedFiles.isNotEmpty) {
        // 更新数据库
        await DatabaseService.updateMovieWithLatest(
          movie.id,
          (latestMovie) => latestMovie.copyWith(videoFilePaths: matchedFiles),
        );

        print(
            '[MovieDetailScreen] Rescan completed: found ${matchedFiles.length} files');
        return matchedFiles;
      } else {
        print('[MovieDetailScreen] Rescan completed: no files found');
      }
    } catch (e) {
      print('[MovieDetailScreen] Error rescanning: $e');
    }
    return const [];
  }

  Future<void> _openSubtitleManager() async {
    final parentContext = context;
    await showDialog<void>(
      context: parentContext,
      builder: (dialogContext) => SubtitleManagerDialog(
        movie: _movie,
        initialVideoPath: _selectedVideoPath,
        onMovieChanged: (updatedMovie) {
          if (!mounted) return;
          setState(() {
            _setCurrentMovie(updatedMovie);
          });
          _loadRelatedMovies();
          refreshMovies(ref);
        },
        onPlay: (updatedMovie, subtitlePath) {
          Navigator.of(dialogContext).pop();
          setState(() {
            _setCurrentMovie(updatedMovie);
          });
          _playVideo(subtitlePath: subtitlePath);
        },
      ),
    );
  }

  void _scrollToImage(int index) {
    setState(() {
      _currentImageIndex = index;
    });
    _thumbnailScrollController.animateTo(
      (index * (_thumbnailWidth + _thumbnailSpacing)) - 20,
      duration: const Duration(milliseconds: 300),
      curve: Curves.ease,
    );
  }

  Future<void> _copyMagnet(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    setState(() {
      _copiedMagnet = link;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('磁力链接已复制')),
    );
    Future.delayed(const Duration(seconds: 2), () {
      setState(() {
        _copiedMagnet = null;
      });
    });
  }

  /// 通过 aria2 下载磁力链接
  Future<void> _downloadViaAria2(MagnetInfo magnet) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => MagnetFilePickerDialog(
        magnetLink: magnet.link,
        movieCode: _movie.code,
        magnetTitle: magnet.title,
      ),
    );

    if (result == null) return;
    if (!mounted) return;

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '已添加到 aria2 下载队列 (${result['selectedFiles']?.length ?? 0} 个文件)'),
          backgroundColor: Colors.purple,
        ),
      );
    } else if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('下载失败: ${result['error']}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 通过系统下载器打开磁力链接
  Future<void> _openWithSystemDownloader(MagnetInfo magnet) async {
    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('使用系统下载器'),
        content: const Text(
          '将打开系统默认的磁力链接处理器（如 qBittorrent、迅雷等）。\n\n确认继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('打开', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final downloader = MagnetDownloader();
    final result = await downloader.openWithSystemDownloader(
      magnet: magnet.link,
      movieCode: _movie.code,
    );

    if (!mounted) return;

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已唤起系统下载器'),
          backgroundColor: Colors.blue,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('唤起失败: ${result.errorMessage}'),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: '复制',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: magnet.link));
            },
          ),
        ),
      );
    }
  }

  Future<void> _refreshFromApi() async {
    final code = _movie.code;
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法获取数据：缺少 TMDB ID')),
      );
      return;
    }

    // 检查API配置（从Hive直接读取最新值，确保已加载）
    String? baseUrl;
    try {
      final box = await Hive.openBox('tmdb_config');
      baseUrl = box.get('base_url', defaultValue: '') as String;
    } catch (e) {
      print('[MovieDetailScreen] Error loading config: $e');
    }

    if (baseUrl == null || baseUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API未配置，请先在设置中配置TMDB API地址')),
        );
      }
      return;
    }

    try {
      // 使用配置好的API服务
      final apiService = ref.read(tmdbApiServiceProvider);

      // 确保API服务已经配置好
      String? authToken;
      try {
        final box = await Hive.openBox('tmdb_config');
        authToken = box.get('auth_token', defaultValue: '') as String;
      } catch (e) {
        print('[MovieDetailScreen] Error loading auth token: $e');
      }

      apiService.configure(
        baseUrl: baseUrl,
        authToken: authToken,
      );

      final newData = await apiService.getMovieDetail(code);

      // 从数据库获取最新的现有数据
      final latestMovie = DatabaseService.getMovie(_movie.id);

      final result = await showDialog<Map<String, bool>?>(
        context: context,
        builder: (context) => MovieDataCompareDialog(
          existingMovie: latestMovie ?? _movie,
          newData: newData,
        ),
      );

      if (result != null) {
        // 直接在 setState 外部更新，避免异步问题
        Movie updatedMovie =
            DatabaseService.getMovie(_movie.id) ?? latestMovie ?? _movie;

        if (result['updateTitle'] == true) {
          updatedMovie = updatedMovie.copyWith(name: newData.title);
        }
        if (result['updateCover'] == true &&
            newData.img != null &&
            updatedMovie.coverUrl != newData.img) {
          if (updatedMovie.originalCoverUrl == null) {
            updatedMovie = updatedMovie.copyWith(
              coverUrl: newData.img,
              originalCoverUrl: updatedMovie.coverUrl,
            );
          } else {
            updatedMovie = updatedMovie.copyWith(coverUrl: newData.img);
          }
        }
        if (result['updateCover'] == true &&
            newData.backdropUrl != null &&
            newData.backdropUrl!.isNotEmpty) {
          updatedMovie = updatedMovie.copyWith(
            backdropUrl: newData.backdropUrl,
          );
        }
        if (result['updateDate'] == true) {
          updatedMovie = updatedMovie.copyWith(releaseDate: newData.date);
        }
        if (result['updateLength'] == true && newData.videoLength != null) {
          updatedMovie = updatedMovie.copyWith(length: newData.videoLength!);
        }
        if (result['updateTags'] == true && newData.genres.isNotEmpty) {
          // 更新标签（包含ID）
          final tags = newData.genres
              .map((g) => NamedItem(id: g.id, name: g.name))
              .toList();
          updatedMovie = updatedMovie.copyWith(tags: tags);
        }
        if (result['updateSamples'] == true && newData.samples.isNotEmpty) {
          final samples = newData.samples
              .map((s) => SampleInfo(
                    id: s.id,
                    src: s.src,
                    thumbnail: s.thumbnail,
                    alt: s.alt,
                  ))
              .toList();
          updatedMovie = updatedMovie.copyWith(samples: samples);
        }
        if (result['updateStars'] == true && newData.stars.isNotEmpty) {
          final List<Cast> cast = newData.stars
              .map<Cast>((star) => Cast(
                    id: star.id,
                    name: star.name,
                    imageUrl: star.avatar,
                  ))
              .toList();
          updatedMovie = updatedMovie.copyWith(cast: cast);
        }
        // 更新导演、制作商、发行商、系列
        if (result['updateDirector'] == true &&
            newData.director != null &&
            newData.director!.id.isNotEmpty) {
          updatedMovie = updatedMovie.copyWith(
            director: NamedItem(
                id: newData.director!.id, name: newData.director!.name),
          );
        }
        if (result['updateProducer'] == true &&
            newData.producer != null &&
            newData.producer!.id.isNotEmpty) {
          updatedMovie = updatedMovie.copyWith(
            producer: NamedItem(
                id: newData.producer!.id, name: newData.producer!.name),
          );
        }
        if (result['updatePublisher'] == true &&
            newData.publisher != null &&
            newData.publisher!.id.isNotEmpty) {
          updatedMovie = updatedMovie.copyWith(
            publisher: NamedItem(
                id: newData.publisher!.id, name: newData.publisher!.name),
          );
        }
        if (result['updateSeries'] == true &&
            newData.series != null &&
            newData.series!.id.isNotEmpty) {
          updatedMovie = updatedMovie.copyWith(
            series:
                NamedItem(id: newData.series!.id, name: newData.series!.name),
          );
        }
        // 更新状态
        setState(() {
          _setCurrentMovie(updatedMovie);
        });

        // 保存到数据库
        final savedMovie = await DatabaseService.updateMovieWithLatest(
          updatedMovie.id,
          (latestMovie) => _mergeMetadataFields(latestMovie, updatedMovie),
        );
        if (mounted) {
          setState(() {
            _setCurrentMovie(savedMovie);
          });
          _loadRelatedMovies();
        }

        // 刷新影片列表
        refreshMovies(ref);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('数据更新成功')),
          );
        }
      }
    } catch (e) {
      print('[MovieDetailScreen] Error refreshing from API: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取数据失败: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        controller: _detailScrollController,
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTitleSection(),
                  const SizedBox(height: 18),
                  _buildOverviewPanel(),
                  _buildSearchFiltersSection(),
                  if (_movie.tags?.isNotEmpty ?? false) _buildTagsSection(),
                  if (_movie.cast.isNotEmpty) _buildCastSection(),
                  if (_relatedMovies.isNotEmpty || _isLoadingRelatedMovies) ...[
                    _buildRelatedMoviesSection(),
                  ],
                  const SizedBox(height: 24),
                  if (_movie.samples != null && _movie.samples!.isNotEmpty)
                    _buildSamplesSection(),
                  const SizedBox(height: 24),
                  if (_movie.magnets != null && _movie.magnets!.isNotEmpty)
                    _buildMagnetsSection(),
                  const SizedBox(height: 24),
                  _buildVideoFileSelector(),
                  const SizedBox(height: 12),
                  _buildSubtitleAction(),
                  if (_selectedVideoPath != null) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _playVideo,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('播放影片'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar() {
    final horizontalCoverUrl = _getHorizontalCoverUrl();
    final previewHeight = _posterPreviewHeight(context);
    return SliverAppBar(
      expandedHeight: previewHeight,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          color: Theme.of(context).colorScheme.surface,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (horizontalCoverUrl != null && horizontalCoverUrl.isNotEmpty)
                Positioned.fill(
                  child: SmartImage(
                    url: horizontalCoverUrl,
                    fit: BoxFit.cover,
                    cacheCategory: CacheCategory.covers,
                    onImageLoaded: _handleHorizontalCoverLoaded,
                    errorWidget: _buildPlaceholderCover(),
                  ),
                )
              else
                _buildPlaceholderCover(),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Theme.of(context).scaffoldBackgroundColor.withAlpha(210),
                    ],
                    stops: const [0.78, 1.0],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(
            _movie.safeIsFavorite ? Icons.favorite : Icons.favorite_border,
            color: _movie.safeIsFavorite ? Colors.red : null,
          ),
          onPressed: _toggleFavorite,
        ),
        IconButton(
          icon: const Icon(Icons.edit),
          onPressed: _editMovieCode,
          tooltip: '编辑 TMDB ID',
        ),
        IconButton(
          icon: const Icon(Icons.subtitles),
          onPressed: _openSubtitleManager,
          tooltip: '字幕',
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _refreshFromApi,
          tooltip: '重新获取数据',
        ),
      ],
    );
  }

  Widget _buildPlaceholderCover() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.image,
        size: 80,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildVideoFileSelector() {
    return VideoFileSelector(
      movie: _movie,
      onVideoSelected: (path) {
        setState(() {
          _selectedVideoPath = path;
        });
      },
    );
  }

  Widget _buildSubtitleAction() {
    final count = _movie.subtitleFilePaths?.length ?? 0;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _openSubtitleManager,
        icon: const Icon(Icons.subtitles_outlined),
        label: Text(count > 0 ? '字幕管理（$count）' : '搜索、下载或匹配字幕'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildTitleSection() {
    final posterCoverUrl = _getPosterCoverUrl();
    final hasLocalVideo =
        _movie.videoFilePaths != null && _movie.videoFilePaths!.isNotEmpty;
    final meta = <String>[
      if (_movie.releaseDate != null && _movie.releaseDate!.isNotEmpty)
        _movie.releaseDate!.substring(0, 10),
      if (_movie.safeLength > 0) '${_movie.safeLength} 分钟',
      if (_movie.safePlayCount > 0) '观看 ${_movie.safePlayCount} 次',
      if (_movie.code.isNotEmpty) 'TMDB ${_movie.code}',
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 132,
          height: 198,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: posterCoverUrl != null && posterCoverUrl.isNotEmpty
                ? SmartImage(
                    url: posterCoverUrl,
                    fit: BoxFit.contain,
                    cacheCategory: CacheCategory.covers,
                    isCropped: _movie.safeIsCoverCropped,
                    errorWidget: _buildPlaceholderCover(),
                  )
                : _buildPlaceholderCover(),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _movie.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (_movie.translatedName != null &&
                  _movie.translatedName!.isNotEmpty &&
                  _movie.translatedName != _movie.name)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _movie.translatedName!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  meta.join('  ·  '),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (_movie.code.isNotEmpty)
                    Chip(
                      avatar: const Icon(Icons.confirmation_number, size: 16),
                      label: Text('TMDB ${_movie.code}'),
                    ),
                  if (hasLocalVideo)
                    FilledButton.icon(
                      onPressed: () {
                        final videoPath = _movie.videoFilePaths!.first;
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PlayerScreen(
                              movie: _movie,
                              videoPath: videoPath,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('播放'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _openSubtitleManager,
                    icon: const Icon(Icons.subtitles_outlined),
                    label: const Text('字幕'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _refreshFromApi,
                    icon: const Icon(Icons.refresh),
                    label: const Text('刷新资料'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewPanel() {
    final overview = _movie.translatedPlot?.trim();
    return _Section(
      title: '简介',
      icon: Icons.subject,
      child: SelectableText(
        overview == null || overview.isEmpty ? '暂无简介' : overview,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.55),
      ),
    );
  }

  Widget _buildSearchFiltersSection() {
    final customTags = DatabaseService.getCustomTagsForMovie(_movie.id);
    final groups = <Widget>[
      if (_movie.director != null && _movie.director!.name.isNotEmpty)
        _buildNamedFilterRow(
          label: '导演',
          item: _movie.director!,
          filterType: MovieFilterType.director,
        ),
      if (_movie.producer != null && _movie.producer!.name.isNotEmpty)
        _buildNamedFilterRow(
          label: '制片',
          item: _movie.producer!,
          filterType: MovieFilterType.producer,
        ),
      if (_movie.publisher != null && _movie.publisher!.name.isNotEmpty)
        _buildNamedFilterRow(
          label: '发行商',
          item: _movie.publisher!,
          filterType: MovieFilterType.publisher,
        ),
      if (_movie.series != null && _movie.series!.name.isNotEmpty)
        _buildNamedFilterRow(
          label: '系列',
          item: _movie.series!,
          filterType: MovieFilterType.series,
        ),
      if (customTags.isNotEmpty)
        _buildCustomTagFilterRowList(
          label: '自定义标签',
          tags: customTags,
        ),
    ];

    if (groups.isEmpty) return const SizedBox.shrink();

    return _Section(
      title: '可搜索资料',
      icon: Icons.manage_search,
      child: Column(children: groups),
    );
  }

  Widget _buildNamedFilterRow({
    required String label,
    required NamedItem item,
    required MovieFilterType filterType,
  }) {
    return _FilterRow(
      label: label,
      children: [
        _SearchChip(
          label: item.name,
          subtitle: item.id.isEmpty ? null : 'ID: ${item.id}',
          onTap: () => _openFilter(
            filterType: filterType,
            value: item.name,
            id: item.id,
          ),
        ),
      ],
    );
  }

  Widget _buildCustomTagFilterRowList({
    required String label,
    required List<CustomMovieTag> tags,
  }) {
    final chips = tags
        .where((tag) => tag.name.trim().isNotEmpty)
        .map(
          (tag) => _SearchChip(
            label: tag.name,
            subtitle: tag.id.isEmpty ? null : 'ID: ${tag.id}',
            onTap: () => _openFilter(
              filterType: MovieFilterType.customTag,
              value: tag.name,
              id: tag.id,
            ),
          ),
        )
        .toList();
    if (chips.isEmpty) return const SizedBox.shrink();
    return _FilterRow(label: label, children: chips);
  }

  void _openFilter({
    required MovieFilterType filterType,
    required String value,
    String? id,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MovieFilterScreen(
          filterType: filterType,
          filterValue: value,
          filterId: id,
        ),
      ),
    );
  }

  Widget _buildInfoSection() {
    // 如果已经自定义裁剪过封面，则不再应用横向裁剪
    final useHorizontalCrop = !_movie.safeIsCoverCropped;
    // 获取横向封面URL（仅当未自定义裁剪时使用）
    final horizontalCoverUrl =
        useHorizontalCrop ? _getHorizontalCoverUrl() : null;
    // 检查是否有本地视频文件
    final hasLocalVideo =
        _movie.videoFilePaths != null && _movie.videoFilePaths!.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            if (horizontalCoverUrl != null && horizontalCoverUrl.isNotEmpty)
              SizedBox(
                width: 140,
                height: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SmartImage(
                    url: horizontalCoverUrl,
                    fit: BoxFit.cover,
                    cacheCategory: CacheCategory.covers,
                    horizontalCrop: useHorizontalCrop, // 仅当未自定义裁剪时应用横向裁剪
                    errorWidget: _buildPlaceholderCover(),
                  ),
                ),
              )
            else if (_movie.coverUrl != null && _movie.coverUrl!.isNotEmpty)
              SizedBox(
                width: 140,
                height: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SmartImage(
                    url: _movie.coverUrl!,
                    fit: BoxFit.cover,
                    cacheCategory: CacheCategory.covers,
                    isCropped: _movie.safeIsCoverCropped,
                    errorWidget: _buildPlaceholderCover(),
                  ),
                ),
              ),
            // 方形播放按钮
            if (hasLocalVideo)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: 140,
                  height: 36,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final videoPath = _movie.videoFilePaths!.first;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PlayerScreen(
                            movie: _movie,
                            videoPath: videoPath,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('播放'),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_movie.code.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _movie.code,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                _movie.name,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              if (_movie.translatedName != null &&
                  _movie.translatedName!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  _movie.translatedName!,
                  style: TextStyle(
                    color: const Color.fromRGBO(102, 102, 102, 1.0),
                    fontSize:
                        Theme.of(context).textTheme.titleLarge?.fontSize != null
                            ? Theme.of(context)
                                    .textTheme
                                    .titleLarge!
                                    .fontSize! *
                                0.85
                            : 16,
                    height: 1.4,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
              const SizedBox(height: 12),
              _buildMetaRow(),
              _buildTmdbInfoSection(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetaRow() {
    final items = <Widget>[];

    if (_movie.releaseDate != null && _movie.releaseDate!.isNotEmpty) {
      items.add(_MetaItem(
        icon: Icons.calendar_today,
        label: '发行',
        value: _movie.releaseDate!.substring(0, 10),
      ));
    }

    if (_movie.safeLength > 0) {
      items.add(_MetaItem(
        icon: Icons.access_time,
        label: '时长',
        value: '${_movie.safeLength} 分钟',
      ));
    }

    if (_movie.safePlayCount > 0) {
      items.add(_MetaItem(
        icon: Icons.play_circle_outline,
        label: '观看',
        value: '${_movie.safePlayCount} 次',
      ));
    }

    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: items,
    );
  }

  Widget _buildTmdbInfoSection() {
    // 收集需要显示的信息
    final infoItems = <Widget>[];

    // 导演
    if (_movie.director != null && _movie.director!.name.isNotEmpty) {
      infoItems.add(_TmdbInfoItem(
        label: '导演',
        value: _movie.director!.name,
        id: _movie.director!.id,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MovieFilterScreen(
                filterType: MovieFilterType.director,
                filterValue: _movie.director!.name,
                filterId: _movie.director!.id,
              ),
            ),
          );
        },
      ));
    }

    // 制造商
    if (_movie.producer != null && _movie.producer!.name.isNotEmpty) {
      infoItems.add(_TmdbInfoItem(
        label: '制作商',
        value: _movie.producer!.name,
        id: _movie.producer!.id,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MovieFilterScreen(
                filterType: MovieFilterType.producer,
                filterValue: _movie.producer!.name,
                filterId: _movie.producer!.id,
              ),
            ),
          );
        },
      ));
    }

    // 发行商
    if (_movie.publisher != null && _movie.publisher!.name.isNotEmpty) {
      infoItems.add(_TmdbInfoItem(
        label: '发行商',
        value: _movie.publisher!.name,
        id: _movie.publisher!.id,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MovieFilterScreen(
                filterType: MovieFilterType.publisher,
                filterValue: _movie.publisher!.name,
                filterId: _movie.publisher!.id,
              ),
            ),
          );
        },
      ));
    }

    // 系列
    if (_movie.series != null && _movie.series!.name.isNotEmpty) {
      infoItems.add(_TmdbInfoItem(
        label: '系列',
        value: _movie.series!.name,
        id: _movie.series!.id,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MovieFilterScreen(
                filterType: MovieFilterType.series,
                filterValue: _movie.series!.name,
                filterId: _movie.series!.id,
              ),
            ),
          );
        },
      ));
    }

    if (infoItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        ...infoItems,
      ],
    );
  }

  Widget _buildTagsSection() {
    if (_movie.tags == null || _movie.tags!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '标签',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _movie.tags!.map((tag) {
            return _HoverTag(
              tag: tag,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MovieFilterScreen(
                      filterType: MovieFilterType.tag,
                      filterValue: tag.name,
                      filterId: tag.id,
                    ),
                  ),
                );
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCastSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '演员',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _movie.cast.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final cast = _movie.cast[index];
              return _HoverCastItem(
                cast: cast,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MovieFilterScreen(
                        filterType: MovieFilterType.cast,
                        filterValue: cast.name,
                        filterId: cast.id,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRelatedMoviesSection() {
    if (_isLoadingRelatedMovies) {
      return const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_relatedMovies.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '相关影片',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 230,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _relatedMovies.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final movie = _relatedMovies[index];
              return SizedBox(
                width: 155,
                child: MovieCard(
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
                    final updatedMovie = DatabaseService.getMovie(movie.id);
                    if (updatedMovie == null) {
                      if (!mounted) return;
                      setState(() {
                        _relatedMovies
                            .removeWhere((item) => item.id == movie.id);
                      });
                      return;
                    }

                    setState(() {
                      final index = _relatedMovies
                          .indexWhere((item) => item.id == updatedMovie.id);
                      if (index >= 0) {
                        _relatedMovies[index] = updatedMovie;
                      }
                    });
                    _loadRelatedMovies();
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSamplesSection() {
    final samples = _movie.samples!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.image, size: 16),
            const SizedBox(width: 8),
            const Text('预览图', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(
              '${_currentImageIndex + 1}/${samples.length}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildMainPreview(samples),
        const SizedBox(height: 12),
        _buildThumbnailStrip(samples),
      ],
    );
  }

  Widget _buildMainPreview(List<SampleInfo> samples) {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: SmartImage(
                url: samples[_currentImageIndex].src,
                fit: BoxFit.contain,
                cacheCategory: CacheCategory.samples,
                placeholder: Container(
                  color: Colors.transparent,
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
                errorWidget: Container(
                  color: Colors.transparent,
                  child: Center(
                    child: Icon(
                      Icons.broken_image,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (samples.length > 1) ...[
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _buildNavButton(
                  icon: Icons.chevron_left,
                  onPressed: _currentImageIndex > 0
                      ? () => _scrollToImage(_currentImageIndex - 1)
                      : null,
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _buildNavButton(
                  icon: Icons.chevron_right,
                  onPressed: _currentImageIndex < samples.length - 1
                      ? () => _scrollToImage(_currentImageIndex + 1)
                      : null,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNavButton({required IconData icon, VoidCallback? onPressed}) {
    final isEnabled = onPressed != null;
    return Material(
      color: isEnabled
          ? Theme.of(context).colorScheme.surface.withAlpha(230)
          : Theme.of(context).colorScheme.surface.withAlpha(100),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withAlpha(50),
            ),
          ),
          child: Icon(
            icon,
            color: isEnabled
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.onSurface.withAlpha(100),
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailStrip(List<SampleInfo> samples) {
    return SizedBox(
      height: 70,
      child: ListView.builder(
        controller: _thumbnailScrollController,
        scrollDirection: Axis.horizontal,
        itemCount: samples.length,
        itemBuilder: (context, index) {
          final sample = samples[index];
          final isSelected = index == _currentImageIndex;
          return Padding(
            padding: EdgeInsets.only(right: _thumbnailSpacing),
            child: GestureDetector(
              onTap: () => _scrollToImage(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _thumbnailWidth,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      SmartImage(
                        url: sample.src,
                        fit: BoxFit.cover,
                        cacheCategory: CacheCategory.samples,
                        placeholder: Container(
                          color: Theme.of(context).colorScheme.surfaceContainer,
                          child: const Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                        errorWidget: Container(
                          color: Theme.of(context).colorScheme.surfaceContainer,
                          child: Icon(
                            Icons.broken_image,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                        ),
                      ),
                      if (isSelected)
                        Container(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withAlpha(30),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 构建磁力链接操作按钮
  Widget _buildActionChip({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          border: Border.all(color: color.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMagnetsSection() {
    final magnets = _movie.magnets!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _magnetsExpanded = !_magnetsExpanded;
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.link,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  '磁力链接',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${magnets.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(
                  _magnetsExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (_magnetsExpanded) ...[
          const SizedBox(height: 8),
          if (magnets.isEmpty)
            const Center(child: Text('暂无磁力链接'))
          else
            Column(
              children: magnets.map((magnet) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      magnet.title,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (magnet.isHD)
                                    Container(
                                      margin: const EdgeInsets.only(left: 8),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.blue,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'HD',
                                        style: TextStyle(
                                            color: Colors.white, fontSize: 10),
                                      ),
                                    ),
                                  if (magnet.hasSubtitle)
                                    Container(
                                      margin: const EdgeInsets.only(left: 4),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        '字幕',
                                        style: TextStyle(
                                            color: Colors.white, fontSize: 10),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text('大小: ${magnet.size}'),
                                  const SizedBox(width: 16),
                                  Text('上传日期: ${magnet.shareDate}'),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // 三个操作按钮
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  _buildActionChip(
                                    context: context,
                                    icon: _copiedMagnet == magnet.link
                                        ? Icons.check
                                        : Icons.copy,
                                    label: _copiedMagnet == magnet.link
                                        ? '已复制'
                                        : '复制',
                                    color: _copiedMagnet == magnet.link
                                        ? Colors.green
                                        : Colors.blueGrey,
                                    onPressed: () => _copyMagnet(magnet.link),
                                  ),
                                  const SizedBox(width: 6),
                                  _buildActionChip(
                                    context: context,
                                    icon: Icons.bolt,
                                    label: 'aria2',
                                    color: Colors.purple,
                                    onPressed: () => _downloadViaAria2(magnet),
                                  ),
                                  const SizedBox(width: 6),
                                  _buildActionChip(
                                    context: context,
                                    icon: Icons.open_in_new,
                                    label: '系统',
                                    color: Colors.blue,
                                    onPressed: () =>
                                        _openWithSystemDownloader(magnet),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ] else ...[
          // 收起状态时显示提示
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '点击展开查看磁力链接',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _Section({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const _FilterRow({
    required this.label,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchChip extends StatefulWidget {
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  const _SearchChip({
    required this.label,
    this.subtitle,
    required this.onTap,
  });

  @override
  State<_SearchChip> createState() => _SearchChipState();
}

class _SearchChipState extends State<_SearchChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: ActionChip(
        avatar: Icon(
          Icons.search,
          size: 16,
          color: _isHovered ? Theme.of(context).colorScheme.primary : null,
        ),
        label: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.label),
            if (widget.subtitle != null)
              Text(
                widget.subtitle!,
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
        onPressed: widget.onTap,
        backgroundColor: _isHovered
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetaItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(
          '$label: $value',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _TmdbInfoItem extends StatelessWidget {
  final String label;
  final String value;
  final String? id;
  final VoidCallback onTap;

  const _TmdbInfoItem({
    required this.label,
    required this.value,
    this.id,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 13,
                      ),
                    ),
                    if (id != null)
                      Text(
                        'ID: $id',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HoverTag extends StatefulWidget {
  final NamedItem tag;
  final VoidCallback onTap;

  const _HoverTag({
    required this.tag,
    required this.onTap,
  });

  @override
  State<_HoverTag> createState() => _HoverTagState();
}

class _HoverTagState extends State<_HoverTag> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          scale: _isHovered ? 1.05 : 1.0,
          child: Chip(
            label: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.tag.name),
                if (widget.tag.id.isNotEmpty)
                  Text(
                    'ID: ${widget.tag.id}',
                    style: const TextStyle(fontSize: 10),
                  ),
              ],
            ),
            backgroundColor: _isHovered
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      ),
    );
  }
}

class _HoverCastItem extends StatefulWidget {
  final Cast cast;
  final VoidCallback onTap;

  const _HoverCastItem({
    required this.cast,
    required this.onTap,
  });

  @override
  State<_HoverCastItem> createState() => _HoverCastItemState();
}

class _HoverCastItemState extends State<_HoverCastItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          scale: _isHovered ? 1.1 : 1.0,
          child: SizedBox(
            width: 80,
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: _isHovered
                        ? [
                            BoxShadow(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withAlpha(100),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: ClipOval(
                    child: _buildCastImage(context),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.cast.name,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _isHovered
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建演员头像组件
  /// 优先使用 imageUrl，否则显示占位头像
  Widget _buildCastImage(BuildContext context) {
    final hasImageUrl =
        widget.cast.imageUrl != null && widget.cast.imageUrl!.isNotEmpty;
    if (hasImageUrl) {
      return SmartImage(
        url: widget.cast.imageUrl!,
        fit: BoxFit.cover,
        cacheCategory: CacheCategory.actors,
        errorWidget: _buildPlaceholder(context),
      );
    }
    return _buildPlaceholder(context);
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.person,
        size: 32,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
