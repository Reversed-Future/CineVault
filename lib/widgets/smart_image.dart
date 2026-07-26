import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_settings.dart';
import '../services/image_cache_service.dart';
import '../providers/movie_providers.dart';

class SmartImage extends ConsumerStatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  // 图片加载完成回调，返回图片实际尺寸
  final void Function(double width, double height)? onImageLoaded;
  // 缓存分类
  final CacheCategory cacheCategory;
  // 是否为裁剪后的图片
  final bool isCropped;
  // 是否使用缓存
  final bool useCache;
  // 是否对横向封面进行9:1:9裁剪（取右侧9份）
  final bool horizontalCrop;

  const SmartImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit,
    this.placeholder,
    this.errorWidget,
    this.onImageLoaded,
    this.cacheCategory = CacheCategory.search,
    this.isCropped = false,
    this.useCache = true,
    this.horizontalCrop = false,
  });

  @override
  ConsumerState<SmartImage> createState() => _SmartImageState();
}

class _SmartImageState extends ConsumerState<SmartImage> {
  static final Map<String, Future<Uint8List>> _inFlightNetworkLoads =
      <String, Future<Uint8List>>{};

  bool _isLoading = true;
  Uint8List? _imageData;
  String? _error;
  int? _lastImageRefreshValue;
  Key? _imageKey; // 添加一个 Key，强制 Image 组件重建
  int _loadGeneration = 0;
  Uint8List? _decodedImageSource;
  Future<ui.Image>? _decodedImageFuture;

  @override
  void initState() {
    super.initState();
    _lastImageRefreshValue = ref.read(imageRefreshSignal);
    _imageKey = UniqueKey();
    _loadImage();
  }

  @override
  void didUpdateWidget(SmartImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.useCache != widget.useCache ||
        oldWidget.isCropped != widget.isCropped) {
      _isLoading = true;
      _imageData = null;
      _error = null;
      _decodedImageSource = null;
      _decodedImageFuture = null;
      _imageKey = UniqueKey(); // 更换 key，强制重建
      _loadImage();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听图片刷新信号
    ref.listen<int>(imageRefreshSignal, (previous, next) {
      if (next != _lastImageRefreshValue) {
        _lastImageRefreshValue = next;
        // 强制重新加载图片
        if (mounted) {
          setState(() {
            _isLoading = true;
            _imageData = null;
            _error = null;
            _decodedImageSource = null;
            _decodedImageFuture = null;
            _imageKey = UniqueKey(); // 关键：更换 key，强制 Image 组件重建
          });
          _loadImage();
        }
      }
    });

    if (_isLoading) {
      return widget.placeholder ??
          Container(
            width: widget.width,
            height: widget.height,
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: const Center(child: CircularProgressIndicator()),
          );
    }

    if (_error != null) {
      return widget.errorWidget ??
          Container(
            width: widget.width,
            height: widget.height,
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: const Icon(Icons.broken_image),
          );
    }

    if (_imageData != null) {
      return _buildImageWithCallback(_imageData!);
    }

    return widget.errorWidget ??
        Container(
          width: widget.width,
          height: widget.height,
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: const Icon(Icons.broken_image),
        );
  }

  Future<void> _loadImage() async {
    final generation = ++_loadGeneration;
    final url = widget.url;
    final cacheCategory = widget.cacheCategory;
    final isCropped = widget.isCropped;
    final useCache = widget.useCache;

    if (widget.useCache) {
      final cachedPath = await ImageCacheService.getCachedImagePath(
        url,
        category: cacheCategory,
        isCropped: isCropped,
      );
      if (!_isCurrentLoad(generation, url)) {
        return;
      }
      if (cachedPath != null) {
        try {
          final imageData = await File(cachedPath).readAsBytes();
          if (_isCurrentLoad(generation, url)) {
            setState(() {
              _imageData = imageData;
              _isLoading = false;
            });
          }
          return;
        } catch (_) {}
      }
    }

    await _fetchFromNetwork(
      generation: generation,
      url: url,
      cacheCategory: cacheCategory,
      isCropped: isCropped,
      useCache: useCache,
    );
  }

  bool _isCurrentLoad(int generation, String url) {
    return mounted && generation == _loadGeneration && widget.url == url;
  }

  Future<void> _fetchFromNetwork({
    required int generation,
    required String url,
    required CacheCategory cacheCategory,
    required bool isCropped,
    required bool useCache,
  }) async {
    try {
      final settings = ref.read(proxyConfigProvider);
      final proxyKey =
          '${settings.proxyEnabled}|${settings.proxyHost}|${settings.proxyPort}';
      final loadKey = '$proxyKey|$url';
      final imageData = await _inFlightNetworkLoads.putIfAbsent(
        loadKey,
        () => _fetchBytesFromNetwork(url, settings).whenComplete(() {
          _inFlightNetworkLoads.remove(loadKey);
        }),
      );

      if (!_isCurrentLoad(generation, url)) {
        return;
      }

      _imageData = imageData;
      if (useCache) {
        await ImageCacheService.cacheImage(
          url,
          imageData,
          category: cacheCategory,
          isCropped: isCropped,
        );
      }
    } catch (e) {
      if (_isCurrentLoad(generation, url)) {
        _error = e.toString();
      }
      print('[SmartImage] Error loading $url: $e');
    } finally {
      if (_isCurrentLoad(generation, url)) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<Uint8List> _fetchBytesFromNetwork(
    String url,
    AppSettings settings,
  ) async {
    final httpClient = HttpClient();
    httpClient.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    httpClient.idleTimeout = const Duration(seconds: 30);

    try {
      if (settings.proxyEnabled &&
          settings.proxyHost != null &&
          settings.proxyPort != null) {
        httpClient.findProxy = (uri) {
          return 'PROXY ${settings.proxyHost}:${settings.proxyPort}';
        };
      }

      final uri = Uri.parse(url);
      final request = await httpClient.getUrl(uri);
      request.headers.add('User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
      request.headers.add('Accept',
          'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8');
      request.headers.add('Accept-Language', 'zh-CN,zh;q=0.9,en;q=0.8');

      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final bytes = await response
          .fold<List<int>>([], (prev, elem) => prev..addAll(elem));
      return Uint8List.fromList(bytes);
    } finally {
      httpClient.close(force: false);
    }
  }

  /// 构建带有加载完成回调的图片组件
  Widget _buildImageWithCallback(Uint8List imageData) {
    // 如果启用横向裁剪（9:1:9，取右侧9份）
    if (widget.horizontalCrop) {
      // 9:1:9 裁剪比例：右侧9份占整个宽度的 9/(9+1+9) = 9/19 ≈ 0.4737
      const cropRatio = 9 / 19;

      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: FutureBuilder<ui.Image>(
          future: _decodeImageOnce(imageData),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return widget.placeholder ??
                  Container(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: const Center(child: CircularProgressIndicator()),
                  );
            }

            final image = snapshot.data!;
            return CustomPaint(
              painter: _HorizontalCropPainter(
                image: image,
                cropRatio: cropRatio,
              ),
            );
          },
        ),
      );
    }

    final imageProvider = MemoryImage(imageData);
    return Image(
      key: _imageKey, // 添加 key，强制重建
      image: imageProvider,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorBuilder: (context, error, stackTrace) {
        return widget.errorWidget ??
            Container(
              width: widget.width,
              height: widget.height,
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: const Icon(Icons.broken_image),
            );
      },
    );
  }

  /// 解码图片
  Future<ui.Image> _decodeImage(Uint8List data) async {
    final codec = await ui.instantiateImageCodec(data);
    final frameInfo = await codec.getNextFrame();
    return frameInfo.image;
  }

  Future<ui.Image> _decodeImageOnce(Uint8List data) {
    if (!identical(_decodedImageSource, data) || _decodedImageFuture == null) {
      _decodedImageSource = data;
      _decodedImageFuture = _decodeImage(data);
    }
    return _decodedImageFuture!;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 监听图片加载完成事件
    if (_imageData != null && widget.onImageLoaded != null) {
      final imageProvider = MemoryImage(_imageData!);
      final imageStream =
          imageProvider.resolve(createLocalImageConfiguration(context));
      imageStream.addListener(ImageStreamListener(
        (ImageInfo info, bool synchronousCall) {
          // 图片加载完成，获取实际尺寸
          widget.onImageLoaded!(
              info.image.width.toDouble(), info.image.height.toDouble());
        },
        onError: (exception, stackTrace) {
          // 忽略错误
        },
      ));
    }
  }
}

/// 自定义绘制器，用于横向裁剪图片（9:1:9，取右侧9份）
class _HorizontalCropPainter extends CustomPainter {
  final ui.Image image;
  final double cropRatio; // 裁剪比例，右侧9份占9/19

  _HorizontalCropPainter({
    required this.image,
    required this.cropRatio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 9:1:9 裁剪：取右侧9份（9/19 ≈ 0.4737）
    // 源图片宽度 × (9/19) = 要取出的宽度
    final srcWidth = image.width * (9 / 19);
    final srcX = image.width - srcWidth; // 从右侧开始
    const srcY = 0.0;
    final srcHeight = image.height.toDouble();

    // 目标区域：填满整个容器
    final dstRect = Rect.fromLTWH(0, 0, size.width, size.height);

    // 源区域：从右侧取9/19
    final srcRect = Rect.fromLTWH(srcX, srcY, srcWidth, srcHeight);

    canvas.drawImageRect(
      image,
      srcRect,
      dstRect,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(_HorizontalCropPainter oldDelegate) {
    return oldDelegate.image != image || oldDelegate.cropRatio != cropRatio;
  }
}
