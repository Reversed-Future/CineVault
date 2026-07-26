import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 获取应用程序执行目录
/// 使用 Platform.resolvedExecutable 获取可执行文件路径，然后提取目录
String getApplicationExecutableDirectory() {
  final executablePath = Platform.resolvedExecutable;
  return path.dirname(executablePath);
}

enum CacheCategory {
  covers,
  actors,
  samples,
  search,
}

extension CacheCategoryExtension on CacheCategory {
  String get directoryName {
    switch (this) {
      case CacheCategory.covers:
        return 'covers';
      case CacheCategory.actors:
        return 'actors';
      case CacheCategory.samples:
        return 'samples';
      case CacheCategory.search:
        return 'search';
    }
  }

  String get displayName {
    switch (this) {
      case CacheCategory.covers:
        return '封面图';
      case CacheCategory.actors:
        return '演员图';
      case CacheCategory.samples:
        return '预览图';
      case CacheCategory.search:
        return '搜索结果';
    }
  }
}

class ImageCacheService {
  static const int defaultMaxCacheSizeMB = 512;
  static const int defaultMaxCacheFiles = 5000;
  static const int _legacyDefaultMaxCacheSizeMB = 50;
  static const int _legacyDefaultMaxCacheFiles = 200;
  static const Duration _cleanupInterval = Duration(minutes: 10);

  static String? _cacheDirectoryPath;
  static String? _oldCacheDirectoryPath;
  static int _maxCacheSizeBytes = defaultMaxCacheSizeMB * 1024 * 1024;
  static int _maxCacheFiles = defaultMaxCacheFiles;
  static bool _enabled = true;
  static bool _migrationChecked = false;
  static DateTime? _lastCleanupStartedAt;
  static Future<void>? _cleanupFuture;

  static int effectiveMaxCacheSizeMB(int value) {
    return value == _legacyDefaultMaxCacheSizeMB
        ? defaultMaxCacheSizeMB
        : value;
  }

  static int effectiveMaxCacheFiles(int value) {
    return value == _legacyDefaultMaxCacheFiles ? defaultMaxCacheFiles : value;
  }

  static void configure({
    bool? enabled,
    String? cachePath,
    int? maxCacheSizeMB,
    int? maxCacheFiles,
  }) {
    if (enabled != null) _enabled = enabled;
    if (cachePath != null) {
      final trimmedPath = cachePath.trim();
      _cacheDirectoryPath =
          trimmedPath.isEmpty ? null : path.normalize(trimmedPath);
    }
    if (maxCacheSizeMB != null) {
      final migratedSizeMB = effectiveMaxCacheSizeMB(maxCacheSizeMB);
      final safeSizeMB = migratedSizeMB < 1 ? 1 : migratedSizeMB;
      _maxCacheSizeBytes = safeSizeMB * 1024 * 1024;
    }
    if (maxCacheFiles != null) {
      final migratedMaxFiles = effectiveMaxCacheFiles(maxCacheFiles);
      _maxCacheFiles = migratedMaxFiles < 1 ? 1 : migratedMaxFiles;
    }
  }

  /// 获取缓存目录（与 models 路径逻辑一致）
  /// 使用可执行文件所在目录作为基准路径
  static Future<String?> getCacheDirectoryPath() async {
    if (_cacheDirectoryPath != null) {
      final cacheDir = Directory(_cacheDirectoryPath!);
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      return _cacheDirectoryPath;
    }

    try {
      // 使用可执行文件所在目录作为基准路径
      final exeDir = Directory(getApplicationExecutableDirectory());
      final cacheDir = Directory(path.join(exeDir.path, 'cache'));
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      _cacheDirectoryPath = cacheDir.path;
      print('缓存目录: $_cacheDirectoryPath');
      return _cacheDirectoryPath;
    } catch (e) {
      print('获取程序根目录失败: $e');
    }

    // 降级方案：使用应用支持目录
    final appDir = await getApplicationSupportDirectory();
    final cacheDir = Directory(path.join(appDir.path, 'image-cache'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    _cacheDirectoryPath = cacheDir.path;
    print('缓存目录(降级): $_cacheDirectoryPath');
    return _cacheDirectoryPath;
  }

  /// 获取旧的缓存目录路径（用于迁移）
  static String? getOldCacheDirectoryPath() {
    if (_oldCacheDirectoryPath != null) {
      return _oldCacheDirectoryPath;
    }

    final possiblePaths = [
      path.join(Directory.current.parent.path, 'local-asset-manager', 'data',
          'image-cache'),
      path.join(
          Directory.current.path, 'local-asset-manager', 'data', 'image-cache'),
      path.join(Directory.current.path, 'image-cache'),
    ];

    for (final p in possiblePaths) {
      if (Directory(p).existsSync()) {
        _oldCacheDirectoryPath = p;
        return p;
      }
    }

    return null;
  }

  /// 检查并迁移旧缓存
  static Future<void> checkAndMigrateCache() async {
    if (_migrationChecked) return;
    _migrationChecked = true;

    final oldPath = getOldCacheDirectoryPath();
    if (oldPath == null) return;

    final newPath = await getCacheDirectoryPath();
    if (newPath == null || oldPath == newPath) return;

    await migrateCache(oldPath, newPath);
  }

  /// 迁移缓存从旧路径到新路径
  static Future<void> migrateCache(String fromPath, String toPath) async {
    try {
      final fromDir = Directory(fromPath);
      if (!await fromDir.exists()) return;

      final toDir = Directory(toPath);
      if (!await toDir.exists()) {
        await toDir.create(recursive: true);
      }

      await for (final entity in fromDir.list()) {
        if (entity is Directory) {
          final destDir =
              Directory(path.join(toPath, path.basename(entity.path)));
          if (!await destDir.exists()) {
            await entity.rename(destDir.path);
          }
        } else if (entity is File) {
          final destFile = File(path.join(toPath, path.basename(entity.path)));
          if (!await destFile.exists()) {
            await entity.rename(destFile.path);
          }
        }
      }

      try {
        if (await fromDir.exists() && await fromDir.list().isEmpty) {
          await fromDir.delete();
        }
      } catch (_) {}

      print('缓存已迁移: $fromPath -> $toPath');
    } catch (e) {
      print('缓存迁移失败: $e');
    }
  }

  /// 从 URL 生成 MD5 哈希
  static String generateMD5Hash(String url) {
    return md5.convert(utf8.encode(url)).toString();
  }

  /// 获取文件扩展名
  static String getFileExtension(String url) {
    try {
      final uri = Uri.tryParse(url);
      if (uri != null && uri.path.isNotEmpty) {
        final ext = path.extension(uri.path).toLowerCase();
        if (ext.isNotEmpty) {
          return ext;
        }
      }
    } catch (_) {}
    return '.jpg';
  }

  /// 根据 URL 获取缓存的图片路径
  static Future<String?> getCachedImagePath(String url,
      {CacheCategory category = CacheCategory.search,
      bool isCropped = false}) async {
    if (!_enabled) return null;

    final cachePath = await getCacheDirectoryPath();
    if (cachePath == null) {
      return null;
    }

    final categoryPath = path.join(cachePath, category.directoryName);
    await Directory(categoryPath).create(recursive: true);

    final hash = generateMD5Hash(url);
    final extension = getFileExtension(url);
    final croppedSuffix = isCropped ? '_cropped' : '';
    final cachedFile =
        File(path.join(categoryPath, '$hash$croppedSuffix$extension'));

    if (await cachedFile.exists()) {
      await cachedFile.setLastModified(DateTime.now());
      return cachedFile.path;
    }

    return null;
  }

  /// 检查图片是否已缓存
  static Future<bool> isImageCached(String url) async {
    final cachedPath = await getCachedImagePath(url);
    return cachedPath != null;
  }

  /// 缓存图片数据
  static Future<void> cacheImage(String url, Uint8List data,
      {CacheCategory category = CacheCategory.search,
      bool isCropped = false}) async {
    if (!_enabled) return;

    final cachePath = await getCacheDirectoryPath();
    if (cachePath == null) {
      return;
    }

    final categoryPath = path.join(cachePath, category.directoryName);
    await Directory(categoryPath).create(recursive: true);

    final hash = generateMD5Hash(url);
    final extension = getFileExtension(url);
    final croppedSuffix = isCropped ? '_cropped' : '';
    final cacheFile =
        File(path.join(categoryPath, '$hash$croppedSuffix$extension'));

    // 删除旧文件，确保完全覆盖
    if (await cacheFile.exists()) {
      try {
        await cacheFile.delete();
      } catch (e) {
        print('[ImageCacheService] Failed to delete old cache file: $e');
      }
    }

    // 写入新数据
    await cacheFile.writeAsBytes(data);
    print(
        '[ImageCacheService] Cached image: $url (category: ${category.directoryName}, cropped: $isCropped)');
    _scheduleCleanupIfNeeded();
  }

  static void _scheduleCleanupIfNeeded() {
    if (_cleanupFuture != null) {
      return;
    }

    final now = DateTime.now();
    final lastCleanupStartedAt = _lastCleanupStartedAt;
    if (lastCleanupStartedAt != null &&
        now.difference(lastCleanupStartedAt) < _cleanupInterval) {
      return;
    }

    _lastCleanupStartedAt = now;
    _cleanupFuture = _cleanupCacheIfNeeded().catchError((Object error) {
      print('[ImageCacheService] Cache cleanup failed: $error');
    }).whenComplete(() {
      _cleanupFuture = null;
    });
    unawaited(_cleanupFuture);
  }

  /// 清理缓存（如果超过限制）
  static Future<void> _cleanupCacheIfNeeded() async {
    final cachePath = await getCacheDirectoryPath();
    if (cachePath == null) {
      return;
    }

    final cacheDir = Directory(cachePath);
    if (!await cacheDir.exists()) {
      return;
    }

    final allFiles = await _listCacheFiles(cacheDir);
    if (allFiles.isEmpty) {
      return;
    }

    allFiles
        .sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

    final filesToDelete = <File>[];
    if (allFiles.length > _maxCacheFiles) {
      filesToDelete.addAll(allFiles.sublist(_maxCacheFiles));
    }

    var totalSize = 0;
    for (final file in allFiles) {
      if (filesToDelete.contains(file)) {
        continue;
      }
      totalSize += await file.length();
    }

    if (totalSize > _maxCacheSizeBytes) {
      final keptFiles = allFiles
          .take(allFiles.length > _maxCacheFiles
              ? _maxCacheFiles
              : allFiles.length)
          .toList()
          .reversed;
      for (final file in keptFiles) {
        if (totalSize <= _maxCacheSizeBytes) {
          break;
        }
        if (filesToDelete.contains(file)) {
          continue;
        }
        totalSize -= await file.length();
        filesToDelete.add(file);
      }
    }

    for (final file in filesToDelete) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  /// 清理所有缓存
  static Future<void> clearAllCache() async {
    final cachePath = await getCacheDirectoryPath();
    if (cachePath == null) {
      return;
    }

    final cacheDir = Directory(cachePath);
    if (await cacheDir.exists()) {
      await _deleteFiles(await _listCacheFiles(cacheDir));
    }
  }

  /// 获取缓存大小（字节）
  static Future<int> getCacheSize() async {
    final cachePath = await getCacheDirectoryPath();
    if (cachePath == null) {
      return 0;
    }

    final cacheDir = Directory(cachePath);
    if (!await cacheDir.exists()) {
      return 0;
    }

    // 递归遍历所有子目录
    return await _calculateDirectorySize(cacheDir);
  }

  /// 递归计算目录大小
  static Future<int> _calculateDirectorySize(Directory dir) async {
    int totalSize = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }
    return totalSize;
  }

  /// 获取指定分类的缓存大小（字节）
  static Future<int> getCacheSizeByCategory(CacheCategory category) async {
    final cachePath = await getCacheDirectoryPath();
    if (cachePath == null) {
      return 0;
    }

    final categoryPath = path.join(cachePath, category.directoryName);
    final categoryDir = Directory(categoryPath);

    if (!await categoryDir.exists()) {
      return 0;
    }

    int totalSize = 0;
    await for (final entity in categoryDir.list()) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }

    return totalSize;
  }

  /// 获取所有分类的缓存大小
  static Future<Map<CacheCategory, int>> getAllCacheSizes() async {
    final sizes = <CacheCategory, int>{};
    for (final category in CacheCategory.values) {
      sizes[category] = await getCacheSizeByCategory(category);
    }
    return sizes;
  }

  /// 删除指定URL的缓存图片
  static Future<void> deleteCachedImage(String url,
      {CacheCategory category = CacheCategory.search,
      bool isCropped = false}) async {
    final cachePath = await getCacheDirectoryPath();
    if (cachePath == null) {
      return;
    }

    final categoryPath = path.join(cachePath, category.directoryName);
    final hash = generateMD5Hash(url);
    final extension = getFileExtension(url);
    final croppedSuffix = isCropped ? '_cropped' : '';

    final cacheFile =
        File(path.join(categoryPath, '$hash$croppedSuffix$extension'));

    if (await cacheFile.exists()) {
      try {
        await cacheFile.delete();
        print('[ImageCacheService] Deleted cache file: ${cacheFile.path}');
      } catch (e) {
        print('[ImageCacheService] Error deleting cache: $e');
      }
    } else {
      print('[ImageCacheService] Cache file not found: ${cacheFile.path}');
    }
  }

  /// 清理指定分类的缓存
  static Future<void> clearCacheByCategory(CacheCategory category) async {
    final cachePath = await getCacheDirectoryPath();
    if (cachePath == null) {
      return;
    }

    final categoryPath = path.join(cachePath, category.directoryName);
    final categoryDir = Directory(categoryPath);

    if (await categoryDir.exists()) {
      await _deleteFiles(await _listCacheFiles(categoryDir));
      await categoryDir.create(recursive: true);
    }
  }

  static Future<List<File>> _listCacheFiles(Directory dir) async {
    final files = <File>[];
    if (!await dir.exists()) {
      return files;
    }

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        files.add(entity);
      }
    }
    return files;
  }

  static Future<void> _deleteFiles(List<File> files) async {
    for (final file in files) {
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        print('[ImageCacheService] Failed to delete cache file: $e');
      }
    }
  }
}
