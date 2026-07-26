import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import '../services/database_service.dart';
import 'smart_image.dart';
import '../services/image_cache_service.dart';
import 'movie_context_menu.dart';
import '../providers/movie_providers.dart';

class MovieCard extends ConsumerStatefulWidget {
  final Movie movie;
  final VoidCallback onTap;
  final double maxScale;
  final double maxRotationAngle;
  final Duration duration;

  /// 是否启用右键菜单
  final bool enableContextMenu;

  /// 卡片尺寸比例（用于封面裁剪），默认 3:4
  final double aspectRatio;

  /// 属性修改后的回调
  final VoidCallback? onPropertiesChanged;

  const MovieCard({
    super.key,
    required this.movie,
    required this.onTap,
    this.maxScale = 1.15,
    this.maxRotationAngle = 5.0,
    this.duration = const Duration(milliseconds: 350),
    this.enableContextMenu = true,
    this.aspectRatio = 3 / 4,
    this.onPropertiesChanged,
  });

  @override
  ConsumerState<MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends ConsumerState<MovieCard>
    with SingleTickerProviderStateMixin {
  double _x = 0.0;
  double _y = 0.0;
  bool _isHovered = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotateXAnimation;
  late Animation<double> _rotateYAnimation;
  late Movie _movie;

  @override
  void initState() {
    super.initState();
    _movie = widget.movie;
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: widget.maxScale).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _rotateXAnimation =
        Tween<double>(begin: 0.0, end: widget.maxRotationAngle).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _rotateYAnimation =
        Tween<double>(begin: 0.0, end: widget.maxRotationAngle).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(covariant MovieCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.movie.id != widget.movie.id ||
        oldWidget.movie.coverUrl != widget.movie.coverUrl) {
      setState(() {
        _movie = widget.movie;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHoverUpdate(PointerEvent event, BoxConstraints constraints) {
    final localX = event.localPosition.dx;
    final localY = event.localPosition.dy;
    final centerX = constraints.maxWidth / 2;
    final centerY = constraints.maxHeight / 2;

    setState(() {
      _x = (localX - centerX) / centerX;
      _y = (localY - centerY) / centerY;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget cardContent = LayoutBuilder(
      builder: (context, constraints) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) {
            setState(() => _isHovered = true);
            _controller.forward();
          },
          onExit: (_) {
            setState(() {
              _isHovered = false;
              _x = 0.0;
              _y = 0.0;
            });
            _controller.reverse();
          },
          onHover: (event) => _onHoverUpdate(event, constraints),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final scale = _scaleAnimation.value;
              final rotateX = -_y * _rotateXAnimation.value;
              final rotateY = _x * _rotateYAnimation.value;

              return Transform(
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateX(rotateX * 3.1415927 / 180)
                  ..rotateY(rotateY * 3.1415927 / 180),
                alignment: FractionalOffset.center,
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Theme.of(context).colorScheme.surface,
                      border: Border.all(
                        color: _isHovered
                            ? Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.5)
                            : Theme.of(context).colorScheme.surfaceContainer,
                        width: _isHovered ? 2 : 1,
                      ),
                      boxShadow: _isHovered
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 20,
                                spreadRadius: 3,
                                offset: Offset(_x * 12, _y * 12 + 8),
                              ),
                              BoxShadow(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.15),
                                blurRadius: 15,
                                spreadRadius: 1,
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 4,
                                spreadRadius: 0,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                    child: InkWell(
                      onTap: widget.onTap,
                      borderRadius: BorderRadius.circular(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildCover(context),
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
      },
    );

    // 如果启用右键菜单，包装 ContextMenu
    if (widget.enableContextMenu) {
      cardContent = MovieContextMenu(
        movie: _movie,
        onDelete: _handleDelete,
        onFavoriteChanged: _handleFavoriteToggle,
        onPropertiesChanged: _handlePropertiesChanged,
        child: cardContent,
      );
    }

    return cardContent;
  }

  void _handleDelete() {
    // 显示删除确认对话框
    showDialog(
      context: context,
      builder: (context) => DeleteConfirmDialog(
        movie: _movie,
        onConfirm: () async {
          await DatabaseService.deleteMovie(_movie.id);

          // 刷新影片列表
          refreshMovies(ref);
          refreshCustomMovieTags(ref);
          widget.onPropertiesChanged?.call();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('影片已删除'),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
      ),
    );
  }

  void _handleFavoriteToggle() async {
    await DatabaseService.toggleFavorite(_movie.id);
    final updatedMovie = DatabaseService.getMovie(_movie.id);
    if (updatedMovie == null) return;

    // 刷新影片列表
    refreshMovies(ref);

    setState(() {
      _movie = updatedMovie;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updatedMovie.safeIsFavorite ? '已添加到收藏' : '已取消收藏',
          ),
          backgroundColor: updatedMovie.safeIsFavorite ? Colors.green : null,
        ),
      );
    }
  }

  Future<void> _handlePropertiesChanged() async {
    final updatedMovie = DatabaseService.getMovie(widget.movie.id);
    if (updatedMovie != null) {
      setState(() {
        _movie = updatedMovie;
      });
    }
    // 通知父组件刷新
    widget.onPropertiesChanged?.call();
  }

  Widget _buildCover(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_movie.coverUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SmartImage(
                key:
                    ValueKey('${_movie.coverUrl}_${_movie.safeIsCoverCropped}'),
                url: _movie.coverUrl!,
                fit: BoxFit.contain,
                cacheCategory: CacheCategory.covers,
                isCropped: _movie.safeIsCoverCropped,
                errorWidget: _buildPlaceholder(context),
                placeholder: _buildPlaceholder(context),
              ),
            )
          else
            _buildPlaceholder(context),
          if (_movie.safeIsFavorite || _movie.safeLastWatchPosition > 0)
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                children: [
                  if (_movie.safeIsFavorite)
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.favorite,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  if (_movie.safeIsFavorite && _movie.safeLastWatchPosition > 0)
                    const SizedBox(width: 4),
                  if (_movie.safeLastWatchPosition > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _formatDuration(_movie.safeLastWatchPosition),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Center(
      child: Icon(
        Icons.movie,
        size: 48,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  String _formatDuration(double seconds) {
    final duration = Duration(seconds: seconds.toInt());
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    if (hours > 0) {
      return '$hours:$minutes';
    }
    return '0:$minutes';
  }
}
