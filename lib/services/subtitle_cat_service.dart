import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'database_service.dart';

typedef SubtitleCatByteFetcher = Future<List<int>> Function(
  Uri uri,
  Map<String, String> headers,
);

class SubtitleSearchResult {
  final String title;
  final String href;
  final String? downloadUrl;
  final int downloads;
  final int comments;
  final String language;

  const SubtitleSearchResult({
    required this.title,
    required this.href,
    this.downloadUrl,
    required this.downloads,
    required this.comments,
    required this.language,
  });

  SubtitleSearchResult copyWith({
    String? title,
    String? href,
    String? downloadUrl,
    int? downloads,
    int? comments,
    String? language,
  }) {
    return SubtitleSearchResult(
      title: title ?? this.title,
      href: href ?? this.href,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      downloads: downloads ?? this.downloads,
      comments: comments ?? this.comments,
      language: language ?? this.language,
    );
  }
}

class SubtitleDownloadResult {
  final String subtitlePath;
  final bool downloaded;
  final SubtitleSearchResult source;

  const SubtitleDownloadResult({
    required this.subtitlePath,
    required this.downloaded,
    required this.source,
  });
}

class SubtitleCatService {
  static const String baseUrl = 'https://subtitlecat.com';
  static const int _maxRequestAttempts = 3;
  static const List<String> subtitleExtensions = [
    '.srt',
    '.ass',
    '.ssa',
    '.vtt',
  ];

  static final RegExp _qualitySuffixPattern = RegExp(
    r'-(?:4k|bd|1080p|720p|2160p|hdr|uhd|remux|bluray|web-dl|webrip|bdrip)$',
    caseSensitive: false,
  );

  static final RegExp _rowPattern = RegExp(
    r'<tr\b[^>]*>(.*?)</tr>',
    caseSensitive: false,
    dotAll: true,
  );

  static final RegExp _cellPattern = RegExp(
    r'<td\b[^>]*>(.*?)</td>',
    caseSensitive: false,
    dotAll: true,
  );

  static final RegExp _anchorPattern = RegExp(
    r'<a\b([^>]*)>(.*?)</a>',
    caseSensitive: false,
    dotAll: true,
  );

  const SubtitleCatService({
    SubtitleCatByteFetcher? byteFetcher,
    Duration retryDelay = const Duration(milliseconds: 500),
  })  : _byteFetcher = byteFetcher,
        _retryDelay = retryDelay;

  final SubtitleCatByteFetcher? _byteFetcher;
  final Duration _retryDelay;

  Future<List<SubtitleSearchResult>> search(
    String keyword, {
    int limit = 10,
  }) async {
    final cleanedKeyword = cleanFileNameForSearch(keyword);
    if (cleanedKeyword.trim().isEmpty) return const [];

    final uri = Uri.https('subtitlecat.com', '/index.php', {
      'search': cleanedKeyword,
    });
    final html = await _getText(uri, headers: _htmlHeaders);
    return parseSearchResults(html, cleanedKeyword).take(limit).toList();
  }

  Future<SubtitleSearchResult> loadDownloadUrl(
    SubtitleSearchResult result,
  ) async {
    if (result.downloadUrl != null && result.downloadUrl!.isNotEmpty) {
      return result;
    }

    final uri = Uri.parse(baseUrl).resolve(result.href);
    final html = await _getText(uri, headers: _htmlHeaders);
    final href = parseDownloadUrl(html, result.language);
    if (href == null || href.isEmpty) {
      throw StateError('未找到字幕下载链接');
    }

    return result.copyWith(
      downloadUrl: Uri.parse(baseUrl).resolve(href).toString(),
    );
  }

  Future<SubtitleDownloadResult> downloadForVideo({
    required SubtitleSearchResult result,
    required String videoPath,
  }) async {
    final resultWithUrl = await loadDownloadUrl(result);
    final downloadUrl = resultWithUrl.downloadUrl;
    if (downloadUrl == null || downloadUrl.isEmpty) {
      throw StateError('字幕下载链接为空');
    }

    final bytes =
        await _getBytes(Uri.parse(downloadUrl), headers: _fileHeaders);
    if (!isValidSubtitleContent(bytes)) {
      throw StateError('下载内容不是有效字幕文件');
    }

    final extension = detectSubtitleExtension(
      downloadUrl: downloadUrl,
      content: bytes,
    );
    final targetPath = await resolveSubtitleSavePath(videoPath, extension);
    final targetFile = File(targetPath);

    if (await targetFile.exists()) {
      return SubtitleDownloadResult(
        subtitlePath: targetPath,
        downloaded: false,
        source: resultWithUrl,
      );
    }

    await targetFile.writeAsBytes(bytes, flush: true);
    return SubtitleDownloadResult(
      subtitlePath: targetPath,
      downloaded: true,
      source: resultWithUrl,
    );
  }

  Future<String> _getText(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    final bytes = await _getBytes(uri, headers: headers);
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<List<int>> _getBytes(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    for (var attempt = 1; attempt <= _maxRequestAttempts; attempt++) {
      try {
        return await _getBytesOnce(uri, headers: headers);
      } catch (error) {
        if (attempt >= _maxRequestAttempts || !_shouldRetryRequest(error)) {
          rethrow;
        }
        if (_retryDelay > Duration.zero) {
          await Future<void>.delayed(_retryDelay * attempt);
        }
      }
    }

    throw StateError('字幕请求失败');
  }

  Future<List<int>> _getBytesOnce(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    final byteFetcher = _byteFetcher;
    if (byteFetcher != null) {
      return byteFetcher(uri, headers);
    }

    final client = HttpClient();
    try {
      client.connectionTimeout = const Duration(seconds: 30);
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;

      final settings = DatabaseService.getSettings();
      if (settings.proxyEnabled &&
          settings.proxyHost != null &&
          settings.proxyHost!.isNotEmpty &&
          settings.proxyPort != null) {
        client.findProxy = (_) {
          return 'PROXY ${settings.proxyHost}:${settings.proxyPort}';
        };
      }

      final request = await client.getUrl(uri).timeout(
            const Duration(seconds: 30),
          );
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(
            const Duration(seconds: 120),
          );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP ${response.statusCode}',
          uri: uri,
        );
      }

      return response.fold<List<int>>(
        <int>[],
        (previous, element) => previous..addAll(element),
      );
    } finally {
      client.close(force: true);
    }
  }

  static bool _shouldRetryRequest(Object error) {
    if (error is TimeoutException ||
        error is SocketException ||
        error is HandshakeException) {
      return true;
    }
    if (error is HttpException) {
      return !error.message.startsWith('HTTP ');
    }
    return false;
  }

  static String cleanFileNameForSearch(String fileName) {
    final trimmed = fileName.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed.replaceAll(_qualitySuffixPattern, '');
  }

  static List<SubtitleSearchResult> parseSearchResults(
    String html,
    String keyword,
  ) {
    final results = <SubtitleSearchResult>[];

    for (final rowMatch in _rowPattern.allMatches(html)) {
      final rowHtml = rowMatch.group(1) ?? '';
      final cells = _cellPattern
          .allMatches(rowHtml)
          .map((match) => match.group(1) ?? '')
          .toList();
      if (cells.length < 3) continue;

      final anchor = _anchorPattern.firstMatch(cells.first);
      if (anchor == null) continue;

      final href = _readAttribute(anchor.group(1) ?? '', 'href');
      if (href == null || href.isEmpty) continue;

      final title = _normalizeText(anchor.group(2) ?? '');
      if (title.isEmpty || !isSearchMatch(title, keyword)) continue;

      results.add(SubtitleSearchResult(
        title: title,
        href: href,
        downloads: _parseNumber(cells[1]),
        comments: _parseNumber(cells[2]),
        language: cells.length >= 4 ? _normalizeText(cells[3]) : 'zh-CN',
      ));
    }

    results.sort((a, b) {
      final commentOrder = b.comments.compareTo(a.comments);
      if (commentOrder != 0) return commentOrder;
      return b.downloads.compareTo(a.downloads);
    });
    return results;
  }

  static String? parseDownloadUrl(String html, String language) {
    final anchors = _anchorPattern.allMatches(html);
    final preferredLanguage = language.toLowerCase();

    for (final anchor in anchors) {
      final attributes = anchor.group(1) ?? '';
      final href = _readAttribute(attributes, 'href');
      if (href == null || href.isEmpty) continue;

      final id = _readAttribute(attributes, 'id')?.toLowerCase() ?? '';
      final className =
          _readAttribute(attributes, 'class')?.toLowerCase() ?? '';

      if (id == 'download_zh-cn' ||
          id == 'download_zh' ||
          id == 'download_$preferredLanguage' ||
          className.split(RegExp(r'\s+')).contains('download-link')) {
        return href;
      }
    }

    for (final anchor in _anchorPattern.allMatches(html)) {
      final href = _readAttribute(anchor.group(1) ?? '', 'href');
      if (href == null || href.isEmpty) continue;
      final lowerHref = href.toLowerCase();
      if (lowerHref.contains('download') ||
          subtitleExtensions.any(lowerHref.contains)) {
        return href;
      }
    }

    return null;
  }

  static bool isSearchMatch(String title, String keyword) {
    if (title.trim().isEmpty || keyword.trim().isEmpty) return false;

    final lowerTitle = title.toLowerCase();
    final lowerKeyword = keyword.toLowerCase();
    final cleanedTitle = cleanFileNameForSearch(lowerTitle);
    final cleanedKeyword = cleanFileNameForSearch(lowerKeyword);

    return lowerTitle.contains(lowerKeyword) ||
        lowerKeyword.contains(lowerTitle) ||
        cleanedTitle.contains(lowerKeyword) ||
        lowerKeyword.contains(cleanedTitle) ||
        lowerTitle.contains(cleanedKeyword) ||
        cleanedKeyword.contains(lowerTitle);
  }

  static bool isValidSubtitleContent(List<int> content) {
    if (content.length < 20) return false;

    final text = utf8.decode(content, allowMalformed: true).trim();
    final lower = text.toLowerCase();
    if (lower.startsWith('<!doctype html') || lower.startsWith('<html')) {
      return false;
    }
    if (lower.contains('<html') &&
        lower.contains('<head') &&
        lower.contains('<body')) {
      return false;
    }
    if (lower.contains('error') && lower.contains('server')) {
      return false;
    }

    final hasTimeCode = lower.contains('-->') ||
        RegExp(r'\d{2}:\d{2}:\d{2}[,.]\d{3}').hasMatch(lower);
    final hasFormatHeader = lower.contains('[script info]') ||
        lower.contains('[v4+ styles]') ||
        lower.startsWith('webvtt');

    return hasTimeCode || hasFormatHeader;
  }

  static String detectSubtitleExtension({
    required String downloadUrl,
    required List<int> content,
  }) {
    final lowerUrl = downloadUrl.toLowerCase();
    for (final extension in subtitleExtensions) {
      if (lowerUrl.contains(extension)) {
        return extension.substring(1);
      }
    }

    final text = utf8.decode(content, allowMalformed: true).trim();
    final lower = text.toLowerCase();
    if (lower.contains('[script info]') || lower.contains('[v4+ styles]')) {
      return 'ass';
    }
    if (lower.startsWith('webvtt')) {
      return 'vtt';
    }
    if (lower.contains('-->')) {
      return 'srt';
    }
    return 'srt';
  }

  static Future<String> resolveSubtitleSavePath(
    String videoPath,
    String extension,
  ) async {
    final directory = path.dirname(videoPath);
    final baseName = path.basenameWithoutExtension(videoPath);
    final normalizedExtension = extension.startsWith('.')
        ? extension.substring(1).toLowerCase()
        : extension.toLowerCase();
    final primaryPath = path.join(directory, '$baseName.$normalizedExtension');
    final primaryFile = File(primaryPath);

    if (!await primaryFile.exists()) return primaryPath;

    var index = 1;
    while (true) {
      final nextPath = path.join(
        directory,
        '$baseName.subtitlecat.$index.$normalizedExtension',
      );
      if (!await File(nextPath).exists()) return nextPath;
      index++;
    }
  }

  static Future<List<String>> findLocalSubtitleFilesForVideo(
    String videoPath,
  ) async {
    final directory = Directory(path.dirname(videoPath));
    if (!await directory.exists()) return const [];

    final videoBaseName =
        path.basenameWithoutExtension(videoPath).toLowerCase();
    final exact = <String>[];
    final languageSuffix = <String>[];

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;

      final extension = path.extension(entity.path).toLowerCase();
      if (!subtitleExtensions.contains(extension)) continue;

      final subtitleBaseName =
          path.basenameWithoutExtension(entity.path).toLowerCase();
      if (subtitleBaseName == videoBaseName) {
        exact.add(entity.path);
      } else if (subtitleBaseName.startsWith('$videoBaseName.')) {
        languageSuffix.add(entity.path);
      }
    }

    exact.sort();
    languageSuffix.sort();
    return [...exact, ...languageSuffix];
  }

  static List<String> mergeSubtitlePaths(Iterable<String?> paths) {
    final result = <String>[];
    final seen = <String>{};
    for (final item in paths) {
      final value = item?.trim();
      if (value == null || value.isEmpty || seen.contains(value)) continue;
      seen.add(value);
      result.add(value);
    }
    return result;
  }

  static int _parseNumber(String text) {
    final normalized = _normalizeText(text);
    final match = RegExp(r'\d+').firstMatch(normalized);
    if (match == null) return 0;
    return int.tryParse(match.group(0) ?? '') ?? 0;
  }

  static String _normalizeText(String html) {
    return _decodeHtmlEntities(
      html.replaceAll(RegExp(r'<[^>]+>'), ' '),
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String? _readAttribute(String attributes, String name) {
    final pattern = RegExp(
      "$name\\s*=\\s*\"([^\"]*)\"|$name\\s*=\\s*'([^']*)'",
      caseSensitive: false,
      dotAll: true,
    );
    final match = pattern.firstMatch(attributes);
    return match == null
        ? null
        : _decodeHtmlEntities(match.group(1) ?? match.group(2) ?? '');
  }

  static String _decodeHtmlEntities(String value) {
    final named = value
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');

    return named.replaceAllMapped(
      RegExp(r'&#(x?[0-9A-Fa-f]+);'),
      (match) {
        final raw = match.group(1) ?? '';
        final radix = raw.startsWith('x') || raw.startsWith('X') ? 16 : 10;
        final digits = radix == 16 ? raw.substring(1) : raw;
        final codePoint = int.tryParse(digits, radix: radix);
        if (codePoint == null) return match.group(0) ?? '';
        return String.fromCharCode(codePoint);
      },
    );
  }

  static const Map<String, String> _htmlHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.8,en-US;q=0.5,en;q=0.3',
    'Connection': 'keep-alive',
    'Upgrade-Insecure-Requests': '1',
  };

  static const Map<String, String> _fileHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
    'Accept': '*/*',
    'Accept-Language': 'zh-CN,zh;q=0.8,en-US;q=0.5,en;q=0.3',
    'Connection': 'keep-alive',
  };
}
