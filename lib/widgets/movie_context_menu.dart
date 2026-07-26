import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import '../models/cast.dart';
import '../models/custom_movie_tag.dart';
import '../models/named_item.dart';
import '../services/database_service.dart';
import '../providers/tmdb_provider.dart';
import '../providers/movie_providers.dart';
import 'smart_image.dart';
import '../services/image_cache_service.dart';
import 'movie_data_compare_dialog.dart';
import 'subtitle_manager_dialog.dart';
import '../screens/player_screen.dart';

/// 图片裁剪对话框
class _ImageCropperDialog extends StatefulWidget {
  final String imageUrl;
  final VoidCallback onCancel;
  final void Function(String) onConfirm;

  const _ImageCropperDialog({
    required this.imageUrl,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  State<_ImageCropperDialog> createState() => _ImageCropperDialogState();
}

class _ImageCropperDialogState extends State<_ImageCropperDialog> {
  final _cropController = CropController();
  Uint8List? _imageData;
  bool _isLoading = true;
  bool _isCropping = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final cachedPath = await ImageCacheService.getCachedImagePath(
      widget.imageUrl,
      category: CacheCategory.covers,
    );
    if (cachedPath != null) {
      try {
        _imageData = await File(cachedPath).readAsBytes();
        setState(() => _isLoading = false);
        return;
      } catch (_) {}
    }

    try {
      final settings = await DatabaseService.getSettingsAsync();
      final httpClient = HttpClient();
      httpClient.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;

      if (settings.proxyEnabled &&
          settings.proxyHost != null &&
          settings.proxyPort != null) {
        httpClient.findProxy = (uri) {
          return 'PROXY ${settings.proxyHost}:${settings.proxyPort}';
        };
      }

      final uri = Uri.parse(widget.imageUrl);
      final request = await httpClient.getUrl(uri);
      request.headers.add('User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
      request.headers.add('Accept',
          'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8');
      request.headers.add('Accept-Language', 'zh-CN,zh;q=0.9,en;q=0.8');

      final response = await request.close();
      if (response.statusCode == 200) {
        final bytes = await response
            .fold<List<int>>([], (prev, elem) => prev..addAll(elem));
        _imageData = Uint8List.fromList(bytes);
        await ImageCacheService.cacheImage(
          widget.imageUrl,
          _imageData!,
          category: CacheCategory.covers,
        );
      }
    } catch (e) {
      print('[ImageCropper] Error loading image: $e');
    }

    setState(() => _isLoading = false);
  }

  void _onCropped(Uint8List croppedData) async {
    setState(() => _isCropping = false);

    try {
      await ImageCacheService.cacheImage(
        widget.imageUrl,
        croppedData,
        category: CacheCategory.covers,
        isCropped: true,
      );
      widget.onConfirm(widget.imageUrl);
    } catch (e) {
      print('[ImageCropper] Error cropping image: $e');
      widget.onConfirm(widget.imageUrl);
    }
  }

  void _confirmCrop() {
    if (_imageData == null) return;
    setState(() => _isCropping = true);
    _cropController.crop();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: screenSize.width * 0.9,
        height: screenSize.height * 0.9,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.crop, size: 24),
                const SizedBox(width: 12),
                const Text(
                  '裁剪封面图',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onCancel,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _imageData != null
                      ? Crop(
                          image: _imageData!,
                          controller: _cropController,
                          onCropped: _onCropped,
                          aspectRatio: 3 / 4, // 纵向4:3 (宽度/高度=3/4)
                          initialSize: 0.8,
                          onMoved: (newRect) {},
                          onStatusChanged: (status) {},
                          cornerDotBuilder: (size, edgeAlignment) =>
                              const DotControl(color: Colors.blue),
                          maskColor: Colors.black.withValues(alpha: 0.6),
                          radius: 8,
                        )
                      : const Center(
                          child: Icon(Icons.broken_image, size: 64),
                        ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_isCropping)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                TextButton(
                  onPressed: _isCropping ? null : widget.onCancel,
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isCropping ? null : _confirmCrop,
                  child: const Text('确认裁剪'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 影片右键菜单组件
class MovieContextMenu extends StatelessWidget {
  final Widget child;
  final Movie movie;
  final VoidCallback? onDelete;
  final VoidCallback? onFavoriteChanged;
  final VoidCallback? onPropertiesChanged;

  const MovieContextMenu({
    super.key,
    required this.child,
    required this.movie,
    this.onDelete,
    this.onFavoriteChanged,
    this.onPropertiesChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        // 右键或菜单键显示上下文菜单
        const SingleActivator(LogicalKeyboardKey.contextMenu): () {
          _showContextMenu(context);
        },
      },
      child: Focus(
        autofocus: true,
        child: GestureDetector(
          onSecondaryTapUp: (details) {
            _showContextMenuAt(context, details.globalPosition);
          },
          child: child,
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box != null) {
      final position = box.localToGlobal(Offset.zero) +
          Offset(box.size.width / 2, box.size.height / 2);
      _showContextMenuAt(context, position);
    }
  }

  void _showContextMenuAt(BuildContext context, Offset position) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => _ContextMenuOverlay(
        position: position,
        movie: movie,
        onDelete: () {
          entry.remove();
          onDelete?.call();
        },
        onFavoriteChanged: () {
          entry.remove();
          onFavoriteChanged?.call();
        },
        onCustomTags: () {
          entry.remove();
          _showCustomTagsDialog(context);
        },
        onSubtitles: () {
          entry.remove();
          _showSubtitleDialog(context);
        },
        onProperties: () {
          entry.remove();
          _showPropertiesDialog(context);
        },
        onDismiss: () {
          entry.remove();
        },
      ),
    );

    overlay.insert(entry);
  }

  void _showPropertiesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => MoviePropertiesDialog(
        movie: movie,
        onSaved: onPropertiesChanged,
      ),
    );
  }

  void _showCustomTagsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _MovieCustomTagDialog(
        movie: movie,
        onSaved: onPropertiesChanged,
      ),
    );
  }

  void _showSubtitleDialog(BuildContext context) {
    final parentContext = context;
    showDialog(
      context: parentContext,
      builder: (dialogContext) => SubtitleManagerDialog(
        movie: movie,
        initialVideoPath: movie.videoFilePaths?.firstOrNull,
        onMovieChanged: (_) => onPropertiesChanged?.call(),
        onPlay: (updatedMovie, subtitlePath) {
          Navigator.of(dialogContext).pop();
          final videoPath = updatedMovie.videoFilePaths?.firstOrNull;
          if (videoPath == null || videoPath.isEmpty) return;
          Navigator.of(parentContext).push(
            MaterialPageRoute(
              builder: (_) => PlayerScreen(
                movie: updatedMovie,
                videoPath: videoPath,
                subtitlePath: subtitlePath,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 影片自定义标签对话框
class _MovieCustomTagDialog extends ConsumerStatefulWidget {
  final Movie movie;
  final VoidCallback? onSaved;

  const _MovieCustomTagDialog({
    required this.movie,
    this.onSaved,
  });

  @override
  ConsumerState<_MovieCustomTagDialog> createState() =>
      _MovieCustomTagDialogState();
}

class _MovieCustomTagDialogState extends ConsumerState<_MovieCustomTagDialog> {
  final TextEditingController _newTagController = TextEditingController();
  late List<CustomMovieTag> _tags;
  late Set<String> _selectedTagIds;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tags = DatabaseService.getAllCustomMovieTags();
    _selectedTagIds = DatabaseService.getCustomTagIdsForMovie(widget.movie.id);
  }

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.bookmark_add_outlined),
          SizedBox(width: 12),
          Text('添加到标签'),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.movie.code,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newTagController,
                    decoration: const InputDecoration(
                      labelText: '新建标签',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _createTag(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.add),
                  tooltip: '新建标签',
                  onPressed: _createTag,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: _tags.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          '暂无自定义标签',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _tags.length,
                      itemBuilder: (context, index) {
                        final tag = _tags[index];
                        return CheckboxListTile(
                          value: _selectedTagIds.contains(tag.id),
                          title: Text(tag.name),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                _selectedTagIds.add(tag.id);
                              } else {
                                _selectedTagIds.remove(tag.id);
                              }
                            });
                          },
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
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }

  Future<void> _createTag() async {
    final name = _newTagController.text.trim();
    if (name.isEmpty) return;

    try {
      final tag = await DatabaseService.createCustomMovieTag(name);
      final tags = DatabaseService.getAllCustomMovieTags();
      if (!mounted) return;
      setState(() {
        _tags = tags;
        _selectedTagIds.add(tag.id);
        _newTagController.clear();
      });
      refreshCustomMovieTags(ref);
    } catch (e) {
      _showSnackBar('新建标签失败: $e');
    }
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
    });

    try {
      await DatabaseService.setMovieCustomTags(
        widget.movie.id,
        _selectedTagIds,
      );
      refreshCustomMovieTags(ref);
      widget.onSaved?.call();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      _showSnackBar('保存标签失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _ContextMenuOverlay extends StatelessWidget {
  final Offset position;
  final Movie movie;
  final VoidCallback onDelete;
  final VoidCallback onFavoriteChanged;
  final VoidCallback onCustomTags;
  final VoidCallback onSubtitles;
  final VoidCallback onProperties;
  final VoidCallback onDismiss;

  const _ContextMenuOverlay({
    required this.position,
    required this.movie,
    required this.onDelete,
    required this.onFavoriteChanged,
    required this.onCustomTags,
    required this.onSubtitles,
    required this.onProperties,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 点击外部关闭菜单
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: Container(color: Colors.transparent),
          ),
        ),
        // 菜单（内部处理定位）
        _ContextMenu(
          position: position,
          movie: movie,
          onDelete: onDelete,
          onFavoriteChanged: onFavoriteChanged,
          onCustomTags: onCustomTags,
          onSubtitles: onSubtitles,
          onProperties: onProperties,
        ),
      ],
    );
  }
}

/// 右键菜单内容
class _ContextMenu extends StatefulWidget {
  final Movie movie;
  final VoidCallback onDelete;
  final VoidCallback onFavoriteChanged;
  final VoidCallback onCustomTags;
  final VoidCallback onSubtitles;
  final VoidCallback onProperties;
  final Offset position;

  const _ContextMenu({
    required this.movie,
    required this.onDelete,
    required this.onFavoriteChanged,
    required this.onCustomTags,
    required this.onSubtitles,
    required this.onProperties,
    required this.position,
  });

  @override
  State<_ContextMenu> createState() => _ContextMenuState();
}

class _ContextMenuState extends State<_ContextMenu> {
  final GlobalKey _menuKey = GlobalKey();
  Offset? _adjustedPosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_adjustPosition);
  }

  void _adjustPosition(Duration duration) {
    final screenSize = MediaQuery.of(context).size;
    final renderBox = _menuKey.currentContext?.findRenderObject() as RenderBox?;

    if (renderBox != null) {
      final menuSize = renderBox.size;
      double left = widget.position.dx;
      double top = widget.position.dy;

      // 确保菜单不超出右边界
      if (left + menuSize.width > screenSize.width) {
        left = screenSize.width - menuSize.width - 10;
      }

      // 确保菜单不超出下边界
      if (top + menuSize.height > screenSize.height) {
        top = screenSize.height - menuSize.height - 10;
      }

      // 确保菜单不超出左边界
      if (left < 10) left = 10;

      // 确保菜单不超出上边界
      if (top < 10) top = 10;

      setState(() {
        _adjustedPosition = Offset(left, top);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final position = _adjustedPosition ?? widget.position;

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: Material(
        key: _menuKey,
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).colorScheme.surface,
        child: Container(
          constraints: BoxConstraints(
            minWidth: 120,
            maxWidth: 220,
            maxHeight: screenSize.height * 0.8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MenuItem(
                icon: widget.movie.safeIsFavorite
                    ? Icons.favorite
                    : Icons.favorite_border,
                label: widget.movie.safeIsFavorite ? '取消收藏' : '收藏',
                iconColor: widget.movie.safeIsFavorite ? Colors.red : null,
                onTap: widget.onFavoriteChanged,
              ),
              _MenuItem(
                icon: Icons.bookmark_add_outlined,
                label: '添加到标签',
                onTap: widget.onCustomTags,
              ),
              _MenuItem(
                icon: Icons.subtitles_outlined,
                label: '字幕',
                onTap: widget.onSubtitles,
              ),
              _MenuDivider(),
              _MenuItem(
                icon: Icons.info_outline,
                label: '属性',
                onTap: widget.onProperties,
              ),
              _MenuDivider(),
              _MenuItem(
                icon: Icons.delete_outline,
                label: '删除',
                iconColor: Colors.red,
                labelColor: Colors.red,
                onTap: widget.onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 菜单项
class _MenuItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;
  final Color? labelColor;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    this.iconColor,
    this.labelColor,
    required this.onTap,
  });

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          color: _isHovered
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 16,
                color:
                    widget.iconColor ?? Theme.of(context).colorScheme.onSurface,
              ),
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  color: widget.labelColor ??
                      Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 菜单分隔线
class _MenuDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
    );
  }
}

/// 删除确认对话框
class DeleteConfirmDialog extends StatelessWidget {
  final Movie movie;
  final VoidCallback onConfirm;

  const DeleteConfirmDialog({
    super.key,
    required this.movie,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.red,
            size: 28,
          ),
          const SizedBox(width: 12),
          const Text('确认删除'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('确定要删除以下影片吗？此操作无法撤销。'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                if (movie.coverUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SmartImage(
                      url: movie.coverUrl!,
                      width: 60,
                      height: 80,
                      fit: BoxFit.cover,
                      cacheCategory: CacheCategory.covers,
                      errorWidget: Container(
                        width: 60,
                        height: 80,
                        color: Theme.of(context).colorScheme.surface,
                        child: Icon(Icons.movie),
                      ),
                      placeholder: Container(
                        width: 60,
                        height: 80,
                        color: Theme.of(context).colorScheme.surface,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 60,
                    height: 80,
                    color: Theme.of(context).colorScheme.surface,
                    child: Icon(Icons.movie),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        movie.code,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        movie.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            onConfirm();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('确认删除'),
        ),
      ],
    );
  }
}

/// 影片属性编辑对话框
class MoviePropertiesDialog extends ConsumerStatefulWidget {
  final Movie movie;
  final VoidCallback? onSaved;

  const MoviePropertiesDialog({
    super.key,
    required this.movie,
    this.onSaved,
  });

  @override
  ConsumerState<MoviePropertiesDialog> createState() =>
      _MoviePropertiesDialogState();
}

class _MoviePropertiesDialogState extends ConsumerState<MoviePropertiesDialog>
    with SingleTickerProviderStateMixin {
  late Movie _movie;
  late TabController _tabController;
  bool _isDirty = false;
  String? _initialCoverUrl; // 保存初始状态的封面URL，用于 originalCoverUrl
  String? _lastSavedCoverUrl; // 保存上次保存时的封面URL，用于检测变化

  // 封面相关
  int? _selectedCoverIndex;

  @override
  void initState() {
    super.initState();
    _movie = widget.movie;
    _tabController = TabController(length: 2, vsync: this);

    // 保存初始状态的封面URL
    _initialCoverUrl = _movie.coverUrl;
    _lastSavedCoverUrl = _movie.coverUrl;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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
    controller.dispose();

    if (result == null || result == _movie.code) return;

    try {
      final updatedMovie = DatabaseService.copyMovieWithUpdatedCode(
        _movie,
        result,
      );
      setState(() {
        _movie = updatedMovie;
        _isDirty = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('修改失败: ${e.toString()}')),
      );
    }
  }

  void _showCropper(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => _ImageCropperDialog(
        imageUrl: imageUrl,
        onCancel: () {
          Navigator.of(context).pop();
        },
        onConfirm: (croppedUrl) {
          Navigator.of(context).pop();
          setState(() {
            _movie = _movie.copyWith(
              coverUrl: croppedUrl,
              isCoverCropped: true,
            );
            _selectedCoverIndex = null;
            _isDirty = true;
          });
        },
      ),
    );
  }

  void _cropSelectedImage() {
    String? imageUrl;

    if (_selectedCoverIndex != null) {
      if (_selectedCoverIndex! >= 0) {
        // 从预览图中选择
        final samples = _movie.samples ?? [];
        if (_selectedCoverIndex! < samples.length) {
          imageUrl = samples[_selectedCoverIndex!].src;
        }
      } else {
        // 从快捷选项中选择
        final coverOptions = _buildCoverOptions();
        final index = -_selectedCoverIndex! - 1;
        if (index >= 0 && index < coverOptions.length) {
          imageUrl = coverOptions[index].url;
        }
      }
    }

    if (imageUrl != null) {
      _showCropper(imageUrl);
    }
  }

  List<_CoverOption> _buildCoverOptions() {
    List<_CoverOption> coverOptions = [];

    if (_movie.coverUrl != null) {
      coverOptions.add(_CoverOption(
        type: 'current',
        url: _movie.coverUrl!,
        label: '当前封面',
        aspectRatio: 3 / 4,
      ));
    }

    if (_movie.originalCoverUrl != null &&
        _movie.originalCoverUrl != _movie.coverUrl) {
      coverOptions.add(_CoverOption(
        type: 'original',
        url: _movie.originalCoverUrl!,
        label: '原始图片',
        aspectRatio: 16 / 9,
      ));
    }

    return coverOptions;
  }

  Movie _mergeEditableFields(Movie latestMovie, Movie editedMovie) {
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

  Future<void> _saveChanges() async {
    // 如果选择了新封面，更新封面URL
    if (_selectedCoverIndex != null) {
      String? newCoverUrl;

      if (_selectedCoverIndex! < 0) {
        final coverOptions = _buildCoverOptions();
        final optionIndex = -_selectedCoverIndex! - 1;
        if (optionIndex >= 0 && optionIndex < coverOptions.length) {
          newCoverUrl = coverOptions[optionIndex].url;
        }
      } else {
        // 预览图
        final samples = _movie.samples ?? [];
        if (_selectedCoverIndex! < samples.length) {
          newCoverUrl = samples[_selectedCoverIndex!].src;
        }
      }

      if (newCoverUrl != null) {
        setState(() {
          // 如果 originalCoverUrl 还没有设置，保存初始状态的封面作为原始封面
          if (_movie.originalCoverUrl == null && _initialCoverUrl != null) {
            _movie = _movie.copyWith(
              coverUrl: newCoverUrl,
              originalCoverUrl: _initialCoverUrl,
            );
          } else {
            // originalCoverUrl 已经有值了，只更新 coverUrl
            _movie = _movie.copyWith(coverUrl: newCoverUrl);
          }
        });
      }
    }

    // 如果有修改，显示保存确认
    if (_isDirty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认保存'),
          content: const Text('确定要保存修改吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('保存'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    // 如果封面已更新且不是裁剪后的图片
    if (_movie.coverUrl != null && !_movie.safeIsCoverCropped) {
      // 检查封面是否发生变化（与上次保存时比较）
      final isCoverChanged = _lastSavedCoverUrl != _movie.coverUrl;

      if (isCoverChanged) {
        // 清除上次保存URL的缓存（如果存在）
        if (_lastSavedCoverUrl != null && _lastSavedCoverUrl!.isNotEmpty) {
          try {
            await ImageCacheService.deleteCachedImage(
              _lastSavedCoverUrl!,
              category: CacheCategory.covers,
            );
            // 同时删除裁剪版本
            await ImageCacheService.deleteCachedImage(
              _lastSavedCoverUrl!,
              category: CacheCategory.covers,
              isCropped: true,
            );
            print(
                '[MoviePropertiesDialog] Cleared old cover cache for: $_lastSavedCoverUrl');
          } catch (e) {
            print('[MoviePropertiesDialog] Error clearing old cover cache: $e');
          }
        }

        // 【关键】清除新封面URL的现有缓存！
        // 新封面可能之前在搜索时已被缓存，需要确保重新下载最新的
        try {
          await ImageCacheService.deleteCachedImage(
            _movie.coverUrl!,
            category: CacheCategory.covers,
          );
          await ImageCacheService.deleteCachedImage(
            _movie.coverUrl!,
            category: CacheCategory.covers,
            isCropped: true,
          );
          // 同时也尝试清除 search 分类下的缓存（因为搜索结果通常缓存到 search）
          await ImageCacheService.deleteCachedImage(
            _movie.coverUrl!,
            category: CacheCategory.search,
          );
          print(
              '[MoviePropertiesDialog] Cleared existing cache for new cover: $_movie.coverUrl');
        } catch (e) {
          print('[MoviePropertiesDialog] Error clearing new cover cache: $e');
        }
      }

      // 下载并缓存新封面
      try {
        final settings = await DatabaseService.getSettingsAsync();
        final httpClient = HttpClient();
        httpClient.badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;

        // 使用代理配置
        if (settings.proxyEnabled &&
            settings.proxyHost != null &&
            settings.proxyPort != null) {
          httpClient.findProxy = (uri) {
            return 'PROXY ${settings.proxyHost}:${settings.proxyPort}';
          };
        }

        final uri = Uri.parse(_movie.coverUrl!);
        final request = await httpClient.getUrl(uri);
        request.headers.add('User-Agent',
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
        request.headers.add('Accept',
            'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8');
        request.headers.add('Accept-Language', 'zh-CN,zh;q=0.9,en;q=0.8');

        // 设置超时时间
        final response =
            await request.close().timeout(const Duration(seconds: 30));
        if (response.statusCode == 200) {
          final bytes = await response
              .fold<List<int>>([], (prev, elem) => prev..addAll(elem));
          // 缓存新封面（覆盖旧缓存）
          await ImageCacheService.cacheImage(
            _movie.coverUrl!,
            Uint8List.fromList(bytes),
            category: CacheCategory.covers,
          );
          print('[MoviePropertiesDialog] Cover cached: ${_movie.coverUrl}');
        } else {
          print(
              '[MoviePropertiesDialog] Failed to download cover: HTTP ${response.statusCode}');
        }
        httpClient.close();
      } catch (e) {
        print('[MoviePropertiesDialog] Error caching cover image: $e');
        // 网络错误不阻止保存
      }
    }

    // 保存到数据库
    final savedMovie = await DatabaseService.updateMovieWithLatest(
      _movie.id,
      (latestMovie) => _mergeEditableFields(latestMovie, _movie),
    );
    _movie = savedMovie;

    // 刷新影片列表
    refreshMovies(ref);

    // 更新上次保存的封面URL
    _lastSavedCoverUrl = _movie.coverUrl;

    if (mounted) {
      // 触发图片刷新信号，强制所有 SmartImage 重新加载
      ref.read(imageRefreshSignal.notifier).state++;

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存成功')),
      );
      widget.onSaved?.call();
    }
  }

  Future<void> _refreshFromApi() async {
    final code = _movie.code;
    if (code.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法获取数据：缺少 TMDB ID')),
        );
      }
      return;
    }

    // 直接从数据库读取API配置，确保配置已加载
    String? baseUrl;
    String? authToken;
    try {
      final box = await Hive.openBox('tmdb_config');
      baseUrl = box.get('base_url', defaultValue: '') as String;
      authToken = box.get('auth_token', defaultValue: '') as String;
    } catch (e) {
      print('[MoviePropertiesDialog] Error loading config: $e');
    }

    if (baseUrl == null || baseUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API未配置，请先在设置中配置TMDB API地址')),
        );
      }
      return;
    }

    setState(() => _isDirty = true);

    try {
      // 使用配置好的API服务
      final apiService = ref.read(tmdbApiServiceProvider);

      // 确保API服务已经配置好
      apiService.configure(
        baseUrl: baseUrl,
        authToken: authToken,
      );

      print('[MoviePropertiesDialog] Fetching data for code: $code');
      final newData = await apiService.getMovieDetail(code);
      print('[MoviePropertiesDialog] API data received:');
      print('[MoviePropertiesDialog] - title: ${newData.title}');
      print('[MoviePropertiesDialog] - img: ${newData.img}');
      print('[MoviePropertiesDialog] - date: ${newData.date}');
      print('[MoviePropertiesDialog] - videoLength: ${newData.videoLength}');
      print('[MoviePropertiesDialog] - gid: ${newData.gid}');
      print('[MoviePropertiesDialog] - uc: ${newData.uc}');
      print('[MoviePropertiesDialog] - director: ${newData.director}');
      print('[MoviePropertiesDialog] - producer: ${newData.producer}');
      print('[MoviePropertiesDialog] - publisher: ${newData.publisher}');
      print('[MoviePropertiesDialog] - series: ${newData.series}');
      print('[MoviePropertiesDialog] - genres count: ${newData.genres.length}');
      for (var i = 0; i < newData.genres.length; i++) {
        print(
            '[MoviePropertiesDialog]   - genre[$i]: id=${newData.genres[i].id}, name=${newData.genres[i].name}');
      }
      print('[MoviePropertiesDialog] - stars count: ${newData.stars.length}');
      for (var i = 0; i < newData.stars.length; i++) {
        print(
            '[MoviePropertiesDialog]   - star[$i]: id=${newData.stars[i].id}, name=${newData.stars[i].name}, avatar=${newData.stars[i].avatar}');
      }
      print(
          '[MoviePropertiesDialog] - samples count: ${newData.samples.length}');

      // 从数据库获取最新的现有数据，确保显示的是原始数据
      final latestMovie = DatabaseService.getMovie(_movie.id);

      final result = await showDialog<Map<String, bool>?>(
        context: context,
        builder: (context) => MovieDataCompareDialog(
          existingMovie: latestMovie ?? _movie,
          newData: newData,
        ),
      );

      if (result != null) {
        // 调试：打印返回结果
        print('[DEBUG] Dialog returned result: $result');

        // 调试：打印 newData 内容
        print('[DEBUG] newData content:');
        print('[DEBUG]   - director: ${newData.director}');
        print('[DEBUG]   - producer: ${newData.producer}');
        print('[DEBUG]   - publisher: ${newData.publisher}');
        print('[DEBUG]   - series: ${newData.series}');
        print('[DEBUG]   - genres: ${newData.genres}');

        // 直接在 setState 外部更新，避免异步问题
        Movie updatedMovie =
            DatabaseService.getMovie(_movie.id) ?? latestMovie ?? _movie;
        print('[DEBUG] Initial updatedMovie:');
        print('[DEBUG]   - director: ${updatedMovie.director}');
        print('[DEBUG]   - producer: ${updatedMovie.producer}');

        if (result['updateTitle'] == true) {
          print('[DEBUG] Updating title...');
          updatedMovie = updatedMovie.copyWith(name: newData.title);
        }
        if (result['updateCover'] == true &&
            newData.img != null &&
            updatedMovie.coverUrl != newData.img) {
          print('[DEBUG] Updating cover...');
          // 如果之前没有保存过原始封面，保存当前封面
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
          print('[DEBUG] Updating date...');
          updatedMovie = updatedMovie.copyWith(releaseDate: newData.date);
        }
        if (result['updateLength'] == true && newData.videoLength != null) {
          print('[DEBUG] Updating length...');
          updatedMovie = updatedMovie.copyWith(length: newData.videoLength!);
        }
        if (result['updateTags'] == true && newData.genres.isNotEmpty) {
          print('[DEBUG] Updating tags (with IDs)...');
          // 更新标签（包含ID）
          final tags = newData.genres
              .map((g) => NamedItem(id: g.id, name: g.name))
              .toList();
          updatedMovie = updatedMovie.copyWith(tags: tags);
        }
        if (result['updateSamples'] == true && newData.samples.isNotEmpty) {
          print('[DEBUG] Updating samples...');
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
          print('[DEBUG] Updating stars...');
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
          print('[DEBUG] Updating director: ${newData.director}');
          updatedMovie = updatedMovie.copyWith(
            director: NamedItem(
                id: newData.director!.id, name: newData.director!.name),
          );
        }
        if (result['updateProducer'] == true &&
            newData.producer != null &&
            newData.producer!.id.isNotEmpty) {
          print('[DEBUG] Updating producer: ${newData.producer}');
          updatedMovie = updatedMovie.copyWith(
            producer: NamedItem(
                id: newData.producer!.id, name: newData.producer!.name),
          );
        }
        if (result['updatePublisher'] == true &&
            newData.publisher != null &&
            newData.publisher!.id.isNotEmpty) {
          print('[DEBUG] Updating publisher: ${newData.publisher}');
          updatedMovie = updatedMovie.copyWith(
            publisher: NamedItem(
                id: newData.publisher!.id, name: newData.publisher!.name),
          );
        }
        if (result['updateSeries'] == true &&
            newData.series != null &&
            newData.series!.id.isNotEmpty) {
          print('[DEBUG] Updating series: ${newData.series}');
          updatedMovie = updatedMovie.copyWith(
            series:
                NamedItem(id: newData.series!.id, name: newData.series!.name),
          );
        }
        print('[DEBUG] After all updates, updatedMovie:');
        print('[DEBUG]   - director: ${updatedMovie.director}');
        print('[DEBUG]   - producer: ${updatedMovie.producer}');
        print('[DEBUG]   - publisher: ${updatedMovie.publisher}');
        print('[DEBUG]   - series: ${updatedMovie.series}');
        print('[DEBUG]   - tags: ${updatedMovie.tags}');
        print('[DEBUG]   - magnets: ${updatedMovie.magnets}');

        // 更新状态
        setState(() {
          _movie = updatedMovie;
        });

        // 直接使用 updatedMovie 打印和保存
        print('[MoviePropertiesDialog] Updating movie in database:');
        print('[MoviePropertiesDialog] - director: ${updatedMovie.director}');
        print('[MoviePropertiesDialog] - producer: ${updatedMovie.producer}');
        print('[MoviePropertiesDialog] - publisher: ${updatedMovie.publisher}');
        print('[MoviePropertiesDialog] - series: ${updatedMovie.series}');
        print(
            '[MoviePropertiesDialog] - tags count: ${updatedMovie.tags?.length}');
        if (updatedMovie.tags != null) {
          for (var i = 0; i < updatedMovie.tags!.length; i++) {
            print(
                '[MoviePropertiesDialog]   - tag[$i]: id=${updatedMovie.tags![i].id}, name=${updatedMovie.tags![i].name}');
          }
        }
        print(
            '[MoviePropertiesDialog] - cast count: ${updatedMovie.cast.length}');
        for (var i = 0; i < updatedMovie.cast.length; i++) {
          print(
              '[MoviePropertiesDialog]   - cast[$i]: id=${updatedMovie.cast[i].id}, name=${updatedMovie.cast[i].name}, imageUrl=${updatedMovie.cast[i].imageUrl}');
        }
        print(
            '[MoviePropertiesDialog] - magnets count: ${updatedMovie.magnets?.length}');
        if (updatedMovie.magnets != null) {
          for (var i = 0; i < updatedMovie.magnets!.length; i++) {
            print(
                '[MoviePropertiesDialog]   - magnet[$i]: id=${updatedMovie.magnets![i].id}, title=${updatedMovie.magnets![i].title}');
          }
        }

        // 处理封面缓存
        if (result['updateCover'] == true &&
            newData.img != null &&
            _lastSavedCoverUrl != newData.img) {
          // 清除旧封面缓存
          if (_lastSavedCoverUrl != null && _lastSavedCoverUrl!.isNotEmpty) {
            try {
              await ImageCacheService.deleteCachedImage(
                _lastSavedCoverUrl!,
                category: CacheCategory.covers,
              );
              await ImageCacheService.deleteCachedImage(
                _lastSavedCoverUrl!,
                category: CacheCategory.covers,
                isCropped: true,
              );
              print(
                  '[MoviePropertiesDialog] Cleared old cover cache for: $_lastSavedCoverUrl');
            } catch (e) {
              print(
                  '[MoviePropertiesDialog] Error clearing old cover cache: $e');
            }
          }

          // 【关键】清除新封面URL的现有缓存
          try {
            await ImageCacheService.deleteCachedImage(
              newData.img!,
              category: CacheCategory.covers,
            );
            await ImageCacheService.deleteCachedImage(
              newData.img!,
              category: CacheCategory.covers,
              isCropped: true,
            );
            await ImageCacheService.deleteCachedImage(
              newData.img!,
              category: CacheCategory.search,
            );
            print(
                '[MoviePropertiesDialog] Cleared existing cache for new cover: ${newData.img}');
          } catch (e) {
            print('[MoviePropertiesDialog] Error clearing new cover cache: $e');
          }

          // 下载并缓存新封面
          try {
            final settings = await DatabaseService.getSettingsAsync();
            final httpClient = HttpClient();
            httpClient.badCertificateCallback =
                (X509Certificate cert, String host, int port) => true;

            // 使用代理配置
            if (settings.proxyEnabled &&
                settings.proxyHost != null &&
                settings.proxyPort != null) {
              httpClient.findProxy = (uri) {
                return 'PROXY ${settings.proxyHost}:${settings.proxyPort}';
              };
            }

            final uri = Uri.parse(newData.img!);
            final request = await httpClient.getUrl(uri);
            request.headers.add('User-Agent',
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
            request.headers.add('Accept',
                'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8');
            request.headers.add('Accept-Language', 'zh-CN,zh;q=0.9,en;q=0.8');

            final response =
                await request.close().timeout(const Duration(seconds: 30));
            if (response.statusCode == 200) {
              final bytes = await response
                  .fold<List<int>>([], (prev, elem) => prev..addAll(elem));
              await ImageCacheService.cacheImage(
                newData.img!,
                Uint8List.fromList(bytes),
                category: CacheCategory.covers,
              );
              print('[MoviePropertiesDialog] New cover cached: ${newData.img}');
            }
            httpClient.close();
          } catch (e) {
            print('[MoviePropertiesDialog] Error caching new cover: $e');
          }

          // 更新上次保存的封面URL
          _lastSavedCoverUrl = newData.img;
        }

        // 保存到数据库
        final savedMovie = await DatabaseService.updateMovieWithLatest(
          updatedMovie.id,
          (latestMovie) => _mergeEditableFields(latestMovie, updatedMovie),
        );
        _movie = savedMovie;

        // 刷新影片列表
        refreshMovies(ref);

        if (mounted) {
          // 触发图片刷新信号，强制所有 SmartImage 重新加载
          ref.read(imageRefreshSignal.notifier).state++;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('数据更新成功')),
          );
          // 通知父组件数据已更新，触发刷新
          widget.onSaved?.call();
        }
      }
    } catch (e) {
      print('[MoviePropertiesDialog] Error refreshing from API: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取数据失败: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_isDirty) {
            _showDiscardDialog();
          } else {
            Navigator.of(context).pop();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          child: Container(
            width: 800,
            height: 600,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题栏
                Row(
                  children: [
                    const Icon(Icons.movie_filter, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      '影片属性 - ${_movie.code}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    if (_isDirty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '未保存',
                          style: TextStyle(color: Colors.orange),
                        ),
                      ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        if (_isDirty) {
                          _showDiscardDialog();
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Tab栏
                TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: '基本信息'),
                    Tab(text: '封面图'),
                  ],
                ),
                const SizedBox(height: 16),
                // 内容区
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildBasicInfoTab(),
                      _buildCoverTab(),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // 操作按钮
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_selectedCoverIndex != null)
                      ElevatedButton.icon(
                        onPressed: _cropSelectedImage,
                        icon: const Icon(Icons.crop),
                        label: const Text('裁剪'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                    if (_selectedCoverIndex != null) const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _refreshFromApi,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新获取数据'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () {
                        if (_isDirty) {
                          _showDiscardDialog();
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _saveChanges,
                      icon: const Icon(Icons.save),
                      label: const Text('保存'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBasicInfoTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoSection(
            title: '基本信息',
            children: [
              _InfoRow(
                label: 'TMDB ID',
                value: _movie.code,
                trailing: IconButton(
                  tooltip: '编辑 TMDB ID',
                  icon: const Icon(Icons.edit, size: 18),
                  onPressed: _editMovieCode,
                ),
              ),
              _InfoRow(label: '标题', value: _movie.name),
              if (_movie.translatedName != null)
                _InfoRow(label: '译文', value: _movie.translatedName!),
              if (_movie.releaseDate != null)
                _InfoRow(label: '发行日期', value: _movie.releaseDate!),
              if (_movie.safeLength > 0)
                _InfoRow(label: '时长', value: '${_movie.safeLength} 分钟'),
            ],
          ),
          // 导演、制作商、发行商、系列
          if (_movie.director != null ||
              _movie.producer != null ||
              _movie.publisher != null ||
              _movie.series != null) ...[
            const SizedBox(height: 16),
            _InfoSection(
              title: 'Tmdb信息',
              children: [
                if (_movie.director != null && _movie.director!.name.isNotEmpty)
                  _InfoRow(label: '导演', value: _movie.director!.name),
                if (_movie.producer != null && _movie.producer!.name.isNotEmpty)
                  _InfoRow(label: '制作商', value: _movie.producer!.name),
                if (_movie.publisher != null &&
                    _movie.publisher!.name.isNotEmpty)
                  _InfoRow(label: '发行商', value: _movie.publisher!.name),
                if (_movie.series != null && _movie.series!.name.isNotEmpty)
                  _InfoRow(label: '系列', value: _movie.series!.name),
              ],
            ),
          ],
          const SizedBox(height: 16),
          _InfoSection(
            title: '标签',
            children: (_movie.tags == null || _movie.tags!.isEmpty)
                ? [const _InfoRow(label: '', value: '暂无标签')]
                : _movie.tags!
                    .map((tag) => _InfoRow(
                          label: tag.name,
                          value: tag.id.isNotEmpty ? 'ID: ${tag.id}' : '',
                        ))
                    .toList(),
          ),
          const SizedBox(height: 16),
          _InfoSection(
            title: '演员',
            children: _movie.cast.isEmpty
                ? [const _InfoRow(label: '', value: '暂无演员信息')]
                : _movie.cast.map((cast) => _CastInfoRow(cast: cast)).toList(),
          ),
          const SizedBox(height: 16),
          _InfoSection(
            title: '文件信息',
            children: [
              _InfoRow(
                label: '媒体库路径',
                value: _movie.path ?? '未设置',
              ),
              if (_movie.videoFilePaths != null &&
                  _movie.videoFilePaths!.isNotEmpty)
                _InfoRow(
                  label: '视频文件',
                  value: '${_movie.videoFilePaths!.length} 个文件',
                ),
              if (_movie.videoFilePaths != null &&
                  _movie.videoFilePaths!.isNotEmpty)
                ..._movie.videoFilePaths!.asMap().entries.map(
                      (entry) => _InfoRow(
                        label: '视频 ${entry.key + 1}',
                        value: entry.value,
                      ),
                    ),
              if (_movie.subtitleFilePaths != null &&
                  _movie.subtitleFilePaths!.isNotEmpty)
                _InfoRow(
                  label: '字幕文件',
                  value: '${_movie.subtitleFilePaths!.length} 个文件',
                ),
              if (_movie.subtitleFilePaths != null &&
                  _movie.subtitleFilePaths!.isNotEmpty)
                ..._movie.subtitleFilePaths!.asMap().entries.map(
                      (entry) => _InfoRow(
                        label: '字幕 ${entry.key + 1}',
                        value: entry.value,
                      ),
                    ),
              if (_movie.size != null)
                _InfoRow(
                  label: '大小',
                  value: _formatSize(_movie.size!),
                ),
              _InfoRow(
                label: '收藏状态',
                value: _movie.safeIsFavorite ? '已收藏' : '未收藏',
              ),
              _InfoRow(
                label: '播放次数',
                value: '${_movie.safePlayCount} 次',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _InfoSection(
            title: '图片URL',
            children: [
              _InfoRow(
                label: '封面图',
                value: _movie.coverUrl ?? '无',
                isUrl: true,
              ),
            ],
          ),
          if (_movie.samples != null && _movie.samples!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _InfoSection(
              title: '预览图 (${_movie.samples!.length}张)',
              children: _movie.samples!
                  .take(5)
                  .map((sample) => _InfoRow(
                        label: sample.alt.isNotEmpty ? sample.alt : '预览图',
                        value: sample.src,
                        isUrl: true,
                      ))
                  .toList(),
            ),
          ],
          if (_movie.magnets != null && _movie.magnets!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _InfoSection(
              title: '磁力链接 (${_movie.magnets!.length}条)',
              children: _movie.magnets!
                  .take(3)
                  .map((magnet) => _InfoRow(
                        label: '${magnet.title} ${magnet.isHD ? "[HD]" : ""}',
                        value: magnet.link,
                        isUrl: true,
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCoverTab() {
    final samples = _movie.samples ?? [];

    List<_CoverOption> coverOptions = [];

    if (_movie.coverUrl != null) {
      coverOptions.add(_CoverOption(
        type: 'current',
        url: _movie.coverUrl!,
        label: '当前封面',
        aspectRatio: 3 / 4,
      ));
    }

    if (_movie.originalCoverUrl != null &&
        _movie.originalCoverUrl != _movie.coverUrl) {
      coverOptions.add(_CoverOption(
        type: 'original',
        url: _movie.originalCoverUrl!,
        label: '原始图片',
        aspectRatio: 16 / 9,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '选择一张图片作为新封面',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          '顶部为快捷封面选项，下方为预览图',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),

        // 快捷封面选项（当前封面、横向封面、纵向封面）
        if (coverOptions.isNotEmpty) ...[
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: coverOptions.length,
              itemBuilder: (context, index) {
                final option = coverOptions[index];
                final isSelected = _selectedCoverIndex != null &&
                    _selectedCoverIndex! < 0 &&
                    _selectedCoverIndex! == -(index + 1);

                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 90,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedCoverIndex = -(index + 1);
                          _isDirty = true;
                        });
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(5)),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  SmartImage(
                                    url: option.url,
                                    fit: BoxFit.cover,
                                    cacheCategory: CacheCategory.covers,
                                    placeholder: Container(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainer,
                                      child: const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    ),
                                    errorWidget: Container(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainer,
                                      child: const Icon(Icons.broken_image),
                                    ),
                                  ),
                                  if (isSelected)
                                    Container(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.3),
                                      child: const Center(
                                        child: Icon(
                                          Icons.check_circle,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(6),
                            child: Text(
                              option.label,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 预览图网格
        if (samples.isNotEmpty) ...[
          const Divider(),
          const SizedBox(height: 16),
          Text(
            '预览图 (${samples.length}张)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 16 / 9,
              ),
              itemCount: samples.length,
              itemBuilder: (context, index) {
                final sample = samples[index];
                final isSelected = _selectedCoverIndex == index;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedCoverIndex = index;
                      _isDirty = true;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          SmartImage(
                            url: sample.src,
                            fit: BoxFit.cover,
                            cacheCategory: CacheCategory.samples,
                            placeholder: Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainer,
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                            errorWidget: Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainer,
                              child: const Icon(Icons.broken_image),
                            ),
                          ),
                          if (isSelected)
                            Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.3),
                              child: const Center(
                                child: Icon(
                                  Icons.check_circle,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],

        // 空状态提示
        if (samples.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.image_not_supported,
                    size: 48,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '暂无预览图',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '可从上方的快捷选项中选择封面',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

        const SizedBox(height: 16),
        if (_selectedCoverIndex != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _getSelectedCoverLabel(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _getSelectedCoverLabel() {
    if (_selectedCoverIndex == null) {
      return '请选择一张图片作为封面';
    }

    if (_selectedCoverIndex! < 0) {
      // 快捷选项
      switch (-_selectedCoverIndex! - 1) {
        case 0:
          return '已选择「当前封面」作为新封面';
        case 1:
          return '已选择「横向封面」作为新封面';
        case 2:
          return '已选择「纵向封面」作为新封面';
        default:
          return '已选择快捷封面选项';
      }
    } else {
      return '已选择预览图 ${_selectedCoverIndex! + 1} 作为新封面';
    }
  }

  Future<void> _showDiscardDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃修改'),
        content: const Text('确定要放弃未保存的修改吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('放弃'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  String _formatSize(double bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// 封面选项数据类
class _CoverOption {
  final String type;
  final String url;
  final String label;
  final double aspectRatio;

  const _CoverOption({
    required this.type,
    required this.url,
    required this.label,
    required this.aspectRatio,
  });
}

/// 信息区块
class _InfoSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _InfoSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }
}

/// 演员信息行（带头像）
class _CastInfoRow extends StatelessWidget {
  final Cast cast;

  const _CastInfoRow({required this.cast});

  /// 是否有可用的头像 URL
  bool _hasAvatar() {
    return cast.imageUrl != null && cast.imageUrl!.isNotEmpty;
  }

  /// 获取演员头像 URL
  /// 优先使用 imageUrl，否则显示占位头像
  String? _getAvatarUrl() {
    if (cast.imageUrl != null && cast.imageUrl!.isNotEmpty) {
      return cast.imageUrl;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // 演员头像
          if (_hasAvatar())
            SizedBox(
              width: 30,
              height: 30,
              child: ClipOval(
                child: SmartImage(
                  url: _getAvatarUrl()!,
                  fit: BoxFit.cover,
                  cacheCategory: CacheCategory.actors,
                  useCache: false, // 新数据不从缓存读取
                  errorWidget: Container(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.person, size: 16),
                  ),
                ),
              ),
            )
          else
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, size: 16),
            ),
          const SizedBox(width: 8),
          // 演员名称
          Text(
            cast.name,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 8),
          // 演员ID
          if (cast.id.isNotEmpty)
            Text(
              'ID: ${cast.id}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }
}

/// 信息行
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isUrl;
  final Widget? trailing;

  const _InfoRow({
    required this.label,
    required this.value,
    this.isUrl = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty && value.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          '暂无数据',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty)
            SizedBox(
              width: 100,
              child: Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Expanded(
            child: isUrl && value.isNotEmpty && value != '无'
                ? SelectableText(
                    value,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  )
                : SelectableText(
                    value.isEmpty ? '-' : value,
                    style: TextStyle(
                      color: value.isEmpty || value == '无'
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : null,
                    ),
                  ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}
