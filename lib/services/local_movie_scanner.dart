import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../models/cast.dart';
import '../models/movie.dart';
import '../models/notification.dart';
import 'database_service.dart';

class ScannedMovieEntry {
  final String movieCode;
  final String folderPath;
  final List<String> filePaths;
  final String matchedFolderName;
  final String matchedFileName;

  ScannedMovieEntry({
    required this.movieCode,
    required this.folderPath,
    required this.filePaths,
    required this.matchedFolderName,
    required this.matchedFileName,
  });
}

class ScanResult {
  final int totalMovies;
  final int scannedMovies;
  final List<ScannedMovieEntry> foundInLibrary;
  final List<ScannedMovieEntry> notInLibrary;
  final int durationMs;

  ScanResult({
    required this.totalMovies,
    required this.scannedMovies,
    required this.foundInLibrary,
    required this.notInLibrary,
    required this.durationMs,
  });
}

class LocalMovieScanner {
  static const _videoExtensions = {
    '.mp4',
    '.mkv',
    '.avi',
    '.wmv',
    '.mov',
    '.flv',
    '.webm',
    '.m4v',
    '.ts',
    '.m2ts',
    '.mpg',
    '.mpeg',
    '.rmvb',
    '.rm',
    '.3gp',
    '.asf',
  };

  static const _systemDirectories = {
    'System Volume Information',
    '@eaDir',
    r'$RECYCLE.BIN',
    'Recycler',
    'Trash',
    'lost+found',
    '.Trash',
    '.Trash-1000',
  };

  static ScanResult? _lastResult;

  static ScanResult? get lastResult => _lastResult;

  static bool _shouldSkipDirectory(String dirName) {
    final lowerName = dirName.toLowerCase();
    return lowerName.startsWith('.') ||
        lowerName.startsWith(r'$') ||
        _systemDirectories.contains(dirName);
  }

  static void removePendingCodes(Set<String> codes) {
    final result = _lastResult;
    if (result == null || codes.isEmpty) return;

    final normalizedCodes = codes.map(normalizeCode).toSet();
    final remainingPending = result.notInLibrary
        .where((entry) =>
            !normalizedCodes.contains(normalizeCode(entry.movieCode)))
        .toList(growable: false);

    _lastResult = ScanResult(
      totalMovies: result.totalMovies,
      scannedMovies: result.scannedMovies,
      foundInLibrary: result.foundInLibrary,
      notInLibrary: remainingPending,
      durationMs: result.durationMs,
    );
  }

  static void clearPendingEntries() {
    final result = _lastResult;
    if (result == null) return;

    _lastResult = ScanResult(
      totalMovies: result.totalMovies,
      scannedMovies: result.scannedMovies,
      foundInLibrary: result.foundInLibrary,
      notInLibrary: const [],
      durationMs: result.durationMs,
    );
  }

  static String normalizeCode(String code) {
    return code
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fa5]+'), '');
  }

  static bool containsCode(String text, String code) {
    if (code.isEmpty) return false;
    final normalizedCode = normalizeCode(code);
    if (normalizedCode.isEmpty) return false;
    return normalizeCode(text).contains(normalizedCode);
  }

  static String _cleanIdentifier(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'\[[^\]]+\]'), ' ')
        .replaceAll(
            RegExp(r'\((?:720|1080|2160|4320)p\)', caseSensitive: false), ' ')
        .replaceAll(
          RegExp(
            r'\b(?:720p|1080p|2160p|4320p|bluray|webdl|web-dl|bdrip|hdrip|x264|x265|hevc|aac|dts)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'[_\.]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? value.trim() : cleaned;
  }

  static (String?, bool) _extractCodeFromPath(String filePath) {
    final ext = path.extension(filePath).toLowerCase();
    if (!_videoExtensions.contains(ext)) {
      return (null, false);
    }

    final fileStem = _cleanIdentifier(path.basenameWithoutExtension(filePath));
    if (fileStem.isNotEmpty) {
      return (fileStem, false);
    }

    final folderName = _cleanIdentifier(path.basename(path.dirname(filePath)));
    return folderName.isEmpty ? (null, false) : (folderName, false);
  }

  static Future<ScanResult> startScan({
    required List<String> videoFolders,
    required dynamic notificationNotifier,
    void Function(ScanResult result)? onCompleted,
  }) async {
    final stopwatch = Stopwatch()..start();
    final allMovies = DatabaseService.getAllMovies();
    final totalMovies = allMovies.length;
    final existingFolders = <String>[];

    for (final folder in videoFolders) {
      if (await Directory(folder).exists()) {
        existingFolders.add(folder);
      } else {
        await _sendNotification(
          notifier: notificationNotifier,
          title: '文件夹不存在',
          message: folder,
          type: AppNotificationType.warning,
        );
      }
    }

    if (existingFolders.isEmpty) {
      final result = ScanResult(
        totalMovies: totalMovies,
        scannedMovies: 0,
        foundInLibrary: const [],
        notInLibrary: const [],
        durationMs: stopwatch.elapsedMilliseconds,
      );
      _lastResult = result;
      await _sendNotification(
        notifier: notificationNotifier,
        title: '扫描中止',
        message: '没有可用的视频文件夹',
        type: AppNotificationType.error,
      );
      return result;
    }

    final videoFileMap = <String, List<String>>{};
    final folderMap = <String, String>{};
    final folderNameMap = <String, String>{};
    final fileNameMap = <String, String>{};

    final notificationId = await notificationNotifier.addProgressNotification(
      title: '扫描本地电影',
      message: '正在统计视频文件...',
      type: AppNotificationType.info,
      initialProgress: 0,
      taskType: 'local_scan',
    );

    var totalFiles = 0;
    for (final folder in existingFolders) {
      totalFiles += await _countVideoFilesInDir(Directory(folder));
    }

    for (final folder in existingFolders) {
      await _scanDirectoryForVideos(
        Directory(folder),
        videoFileMap,
        folderMap,
        folderNameMap,
        fileNameMap,
        notificationId,
        notificationNotifier,
        totalFiles,
      );
    }

    final foundInLibrary = <ScannedMovieEntry>[];
    final notInLibrary = <ScannedMovieEntry>[];
    final movieLookup = <String, Movie>{};

    for (final movie in allMovies) {
      final normalizedCode = normalizeCode(movie.code);
      if (normalizedCode.isNotEmpty) {
        movieLookup[normalizedCode] = movie;
      }
      final normalizedName = normalizeCode(movie.name);
      if (normalizedName.isNotEmpty) {
        movieLookup.putIfAbsent(normalizedName, () => movie);
      }
    }

    final matchedMovieIds = <String>{};
    var processedGroups = 0;

    for (final entry in videoFileMap.entries) {
      processedGroups++;
      final identifier = entry.key;
      final filePaths = entry.value;
      final normalizedIdentifier = normalizeCode(identifier);
      final movie = movieLookup[normalizedIdentifier];
      final progress = videoFileMap.isEmpty
          ? 100
          : ((processedGroups * 100) ~/ videoFileMap.length);

      await notificationNotifier.updateNotification(
        notificationId: notificationId,
        message: '正在匹配... $processedGroups/${videoFileMap.length}',
        progress: progress,
      );

      if (movie != null) {
        matchedMovieIds.add(movie.id);
        foundInLibrary.add(
          ScannedMovieEntry(
            movieCode: movie.code,
            folderPath: folderMap[identifier]!,
            filePaths: filePaths,
            matchedFolderName: folderNameMap[identifier]!,
            matchedFileName: fileNameMap[identifier]!,
          ),
        );
        await _updateMovieVideoPathsIfChanged(movie, filePaths);
      } else {
        notInLibrary.add(
          ScannedMovieEntry(
            movieCode: identifier,
            folderPath: folderMap[identifier]!,
            filePaths: filePaths,
            matchedFolderName: folderNameMap[identifier]!,
            matchedFileName: fileNameMap[identifier]!,
          ),
        );
      }
    }

    for (final movie in allMovies) {
      if (matchedMovieIds.contains(movie.id)) continue;

      final currentPaths = movie.videoFilePaths ?? const <String>[];
      if (currentPaths.isEmpty) continue;

      final existingPaths = <String>[];
      for (final filePath in currentPaths) {
        if (await File(filePath).exists()) {
          existingPaths.add(filePath);
        }
      }
      await _updateMovieVideoPathsIfChanged(movie, existingPaths);
    }

    await notificationNotifier.updateNotification(
      notificationId: notificationId,
      message: '扫描完成，正在处理结果...',
      progress: 100,
      isProgressing: false,
    );

    stopwatch.stop();
    final result = ScanResult(
      totalMovies: totalMovies,
      scannedMovies: videoFileMap.length,
      foundInLibrary: foundInLibrary,
      notInLibrary: notInLibrary,
      durationMs: stopwatch.elapsedMilliseconds,
    );
    _lastResult = result;

    final resultSeconds = (result.durationMs / 1000).toStringAsFixed(1);
    await _sendNotification(
      notifier: notificationNotifier,
      title: '本地扫描完成',
      message: notInLibrary.isEmpty
          ? '扫描完成（${resultSeconds}s）：已处理 $totalMovies 部电影，找到 ${foundInLibrary.length} 个匹配'
          : '扫描完成（${resultSeconds}s）：找到 ${foundInLibrary.length} 个匹配，${notInLibrary.length} 个不在库中待处理',
      type: notInLibrary.isEmpty
          ? AppNotificationType.success
          : AppNotificationType.warning,
    );

    onCompleted?.call(result);
    return result;
  }

  static Future<Movie> createPlaceholderMovie(
    ScannedMovieEntry entry, {
    String? movieCode,
  }) async {
    final resolvedMovieCode = (movieCode ?? entry.movieCode).trim();
    if (resolvedMovieCode.isEmpty) {
      throw ArgumentError.value(movieCode, 'movieCode', 'Movie code is empty');
    }
    final existingMovie = DatabaseService.findMovieByCode(resolvedMovieCode);
    if (existingMovie != null) {
      throw StateError('Movie code already exists: $resolvedMovieCode');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final movie = Movie(
      id: resolvedMovieCode,
      name: resolvedMovieCode,
      path: null,
      size: null,
      createdAt: now,
      cast: const <Cast>[],
      tags: null,
      coverUrl: null,
      originalCoverUrl: null,
      isCoverCropped: null,
      backdropUrl: null,
      code: resolvedMovieCode,
      releaseDate: null,
      length: null,
      videoFilePaths: entry.filePaths,
      isFavorite: false,
      lastWatchPosition: null,
      lastWatchedAt: null,
      playCount: null,
      translatedName: null,
      translatedTags: null,
      translatedPlot: null,
      samples: null,
      magnets: null,
      director: null,
      producer: null,
      publisher: null,
      series: null,
    );
    await DatabaseService.addMovie(movie);
    return movie;
  }

  static Future<int> removeVideoPathsUnderFolder(String folder) async {
    var updatedCount = 0;
    for (final movie in DatabaseService.getAllMovies()) {
      final latestMovie = DatabaseService.getMovie(movie.id) ?? movie;
      final currentPaths = latestMovie.videoFilePaths ?? const <String>[];
      if (currentPaths.isEmpty) continue;

      final keptPaths = currentPaths
          .where((filePath) => !_isPathInsideFolder(filePath, folder))
          .toList();
      if (!_samePathSet(currentPaths, keptPaths)) {
        await DatabaseService.updateMovieWithLatest(
          latestMovie.id,
          (savedMovie) => _copyMovieWithVideoPaths(savedMovie, keptPaths),
        );
        updatedCount++;
      }
    }
    return updatedCount;
  }

  static Future<void> _updateMovieVideoPathsIfChanged(
    Movie movie,
    List<String> paths,
  ) async {
    final latestMovie = DatabaseService.getMovie(movie.id) ?? movie;
    final currentPaths = latestMovie.videoFilePaths ?? const <String>[];
    if (_samePathSet(currentPaths, paths)) return;

    await DatabaseService.updateMovieWithLatest(
      latestMovie.id,
      (savedMovie) => _copyMovieWithVideoPaths(savedMovie, paths),
    );
  }

  static bool _samePathSet(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final bSet = b.toSet();
    return a.every(bSet.contains);
  }

  static bool _isPathInsideFolder(String filePath, String folder) {
    var normalizedFilePath = path.normalize(filePath);
    var normalizedFolder = path.normalize(folder);

    if (Platform.isWindows) {
      normalizedFilePath = normalizedFilePath.toLowerCase();
      normalizedFolder = normalizedFolder.toLowerCase();
    }

    if (normalizedFilePath == normalizedFolder) return true;

    final folderPrefix = normalizedFolder.endsWith(path.separator)
        ? normalizedFolder
        : '$normalizedFolder${path.separator}';
    return normalizedFilePath.startsWith(folderPrefix);
  }

  static Movie _copyMovieWithVideoPaths(Movie movie, List<String> paths) {
    return Movie(
      id: movie.id,
      name: movie.name,
      path: movie.path,
      size: movie.size,
      createdAt: movie.createdAt,
      cast: movie.cast,
      tags: movie.tags,
      coverUrl: movie.coverUrl,
      originalCoverUrl: movie.originalCoverUrl,
      isCoverCropped: movie.isCoverCropped,
      backdropUrl: movie.backdropUrl,
      code: movie.code,
      releaseDate: movie.releaseDate,
      length: movie.length,
      videoFilePaths: paths,
      subtitleFilePaths: movie.subtitleFilePaths,
      isFavorite: movie.isFavorite,
      lastWatchPosition: movie.lastWatchPosition,
      lastWatchedAt: movie.lastWatchedAt,
      playCount: movie.playCount,
      translatedName: movie.translatedName,
      translatedTags: movie.translatedTags,
      translatedPlot: movie.translatedPlot,
      samples: movie.samples,
      magnets: movie.magnets,
      director: movie.director,
      producer: movie.producer,
      publisher: movie.publisher,
      series: movie.series,
    );
  }

  static Future<void> _sendNotification({
    required dynamic notifier,
    required String title,
    required String message,
    AppNotificationType type = AppNotificationType.info,
  }) async {
    try {
      await notifier.addNotification(
        title: title,
        message: message,
        type: type,
      );
    } catch (e) {
      print('[LocalMovieScanner] Failed to send notification: $e');
    }
  }

  static Future<int> _countVideoFilesInDir(Directory dir) async {
    var count = 0;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          final ext = path.extension(entity.path).toLowerCase();
          if (_videoExtensions.contains(ext)) {
            count++;
          }
        } else if (entity is Directory) {
          final dirName = path.basename(entity.path);
          if (!_shouldSkipDirectory(dirName)) {
            count += await _countVideoFilesInDir(entity);
          }
        }
      }
    } catch (e) {
      print('[LocalMovieScanner] Skip inaccessible directory: ${dir.path}');
    }
    return count;
  }

  static Future<void> _scanDirectoryForVideos(
    Directory dir,
    Map<String, List<String>> videoFileMap,
    Map<String, String> folderMap,
    Map<String, String> folderNameMap,
    Map<String, String> fileNameMap,
    String notificationId,
    dynamic notificationNotifier,
    int totalFiles,
  ) async {
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          final ext = path.extension(entity.path).toLowerCase();
          if (_videoExtensions.contains(ext)) {
            final processedFiles =
                videoFileMap.values.fold(0, (sum, paths) => sum + paths.length);
            final progress =
                totalFiles > 0 ? ((processedFiles * 100) ~/ totalFiles) : 0;

            await notificationNotifier.updateNotification(
              notificationId: notificationId,
              message: '正在扫描... $processedFiles/$totalFiles',
              progress: progress,
            );

            final (code, _) = _extractCodeFromPath(entity.path);
            if (code != null) {
              videoFileMap.putIfAbsent(code, () => <String>[]);
              folderMap.putIfAbsent(code, () => path.dirname(entity.path));
              folderNameMap.putIfAbsent(
                code,
                () => path.basename(path.dirname(entity.path)),
              );
              fileNameMap.putIfAbsent(code, () => path.basename(entity.path));
              videoFileMap[code]!.add(entity.path);
            }
          }
        } else if (entity is Directory) {
          final dirName = path.basename(entity.path);
          if (!_shouldSkipDirectory(dirName)) {
            await _scanDirectoryForVideos(
              entity,
              videoFileMap,
              folderMap,
              folderNameMap,
              fileNameMap,
              notificationId,
              notificationNotifier,
              totalFiles,
            );
          }
        }
      }
    } catch (e) {
      print('[LocalMovieScanner] Skip inaccessible directory: ${dir.path}');
    }
  }
}
