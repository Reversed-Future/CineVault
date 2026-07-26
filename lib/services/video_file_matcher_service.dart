import 'dart:io';

import 'package:path/path.dart' as path;

class VideoFileMatcherService {
  static const List<String> videoExtensions = [
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.wmv',
    '.flv',
    '.webm',
    '.m4v',
    '.ts',
  ];

  static const Set<String> _systemDirectories = {
    'System Volume Information',
    '@eaDir',
    r'$RECYCLE.BIN',
    'Recycler',
    'Trash',
    'lost+found',
    '.Trash',
    '.Trash-1000',
  };

  static bool _shouldSkipDirectory(String dirName) {
    final lowerName = dirName.toLowerCase();
    return lowerName.startsWith('.') ||
        lowerName.startsWith(r'$') ||
        _systemDirectories.contains(dirName);
  }

  static String normalizeMovieCode(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fa5]+'), '');
  }

  static String? extractCodeFromFileName(String fileName) {
    final stem = path.basenameWithoutExtension(fileName).trim();
    return stem.isEmpty ? null : stem;
  }

  static String? extractCodeFromPath(String videoPath) {
    final ext = path.extension(videoPath).toLowerCase();
    if (!videoExtensions.contains(ext)) return null;
    return extractCodeFromFileName(path.basename(videoPath));
  }

  static Future<List<String>> findVideoFilesInDirectory(
    String directory,
  ) async {
    return _findVideoFilesInDir(Directory(directory));
  }

  static Future<List<String>> _findVideoFilesInDir(Directory dir) async {
    final videoFiles = <String>[];
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          final ext = path.extension(entity.path).toLowerCase();
          if (videoExtensions.contains(ext)) {
            videoFiles.add(entity.path);
          }
        } else if (entity is Directory) {
          final dirName = path.basename(entity.path);
          if (!_shouldSkipDirectory(dirName)) {
            videoFiles.addAll(await _findVideoFilesInDir(entity));
          }
        }
      }
    } catch (e) {
      print('[VideoFileMatcher] Skip inaccessible directory: ${dir.path}');
    }
    return videoFiles;
  }

  static bool _matchesIdentifier(String identifier, String videoPath) {
    final normalizedIdentifier = normalizeMovieCode(identifier);
    if (normalizedIdentifier.isEmpty) return false;

    final fileStem = path.basenameWithoutExtension(videoPath);
    final parentName = path.basename(path.dirname(videoPath));
    final searchable = normalizeMovieCode('$fileStem $parentName');
    return searchable.contains(normalizedIdentifier);
  }

  static List<String> matchVideosForCode(
    String code,
    List<String> videoFiles,
  ) {
    final matches = <String>[];
    final addedPaths = <String>{};

    for (final videoPath in videoFiles) {
      if (_matchesIdentifier(code, videoPath) && addedPaths.add(videoPath)) {
        matches.add(videoPath);
      }
    }

    return matches;
  }

  static Future<Map<String, List<String>>> matchAllVideos(
    List<String> codes,
    List<String> directories,
  ) async {
    print('[VideoFileMatcher] ====================');
    print('[VideoFileMatcher] Start matching local video files');
    print('[VideoFileMatcher] Source folders: ${directories.length}');
    print('[VideoFileMatcher] Items to match: ${codes.length}');

    final allVideoFiles = <String>[];

    for (var i = 0; i < directories.length; i++) {
      final dir = directories[i];
      print('[VideoFileMatcher] Scan folder ${i + 1}/${directories.length}: $dir');
      final files = await findVideoFilesInDirectory(dir);
      allVideoFiles.addAll(files);
      print('[VideoFileMatcher]   Found ${files.length} video files');
    }

    print('[VideoFileMatcher] Total video files: ${allVideoFiles.length}');

    final matches = <String, List<String>>{};
    var matchedCount = 0;
    var totalMatchedFiles = 0;

    for (var i = 0; i < codes.length; i++) {
      final code = codes[i];
      final matchedFiles = matchVideosForCode(code, allVideoFiles);
      matches[code] = matchedFiles;

      if (matchedFiles.isNotEmpty) {
        matchedCount++;
        totalMatchedFiles += matchedFiles.length;
      }

      if (codes.isNotEmpty && (i % 10 == 0 || i == codes.length - 1)) {
        final progress = ((i + 1) * 100) ~/ codes.length;
        print(
          '[VideoFileMatcher] Progress: ${i + 1}/${codes.length} ($progress%)',
        );
      }
    }

    print('[VideoFileMatcher] Match complete');
    print('[VideoFileMatcher]   Matched items: $matchedCount');
    print('[VideoFileMatcher]   Matched files: $totalMatchedFiles');
    print('[VideoFileMatcher] ====================');

    return matches;
  }
}
