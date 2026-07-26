import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cine_vault/models/cast.dart';
import 'package:cine_vault/models/movie.dart';
import 'package:cine_vault/services/subtitle_cat_service.dart';

void main() {
  group('SubtitleCatService', () {
    test('cleans quality suffixes before searching', () {
      expect(
          SubtitleCatService.cleanFileNameForSearch('OAE-276-4K'), 'OAE-276');
      expect(SubtitleCatService.cleanFileNameForSearch('ABC-123-BDRip'),
          'ABC-123');
      expect(SubtitleCatService.cleanFileNameForSearch('ABC-123'), 'ABC-123');
    });

    test('parses search result rows and sorts by comments then downloads', () {
      const html = '''
      <table>
        <tbody>
          <tr>
            <td><a href="subtitle/oae-276-low.html">OAE-276 low</a></td>
            <td>90 downloads</td>
            <td>1 comments</td>
            <td>zh-CN</td>
          </tr>
          <tr>
            <td><a href="/subtitle/oae-276-best.html">OAE-276 best</a></td>
            <td>20 downloads</td>
            <td>5 comments</td>
            <td>zh-CN</td>
          </tr>
          <tr>
            <td><a href="/subtitle/other.html">XYZ-999</a></td>
            <td>500 downloads</td>
            <td>99 comments</td>
            <td>zh-CN</td>
          </tr>
        </tbody>
      </table>
      ''';

      final results = SubtitleCatService.parseSearchResults(html, 'OAE-276');

      expect(results, hasLength(2));
      expect(results.first.title, 'OAE-276 best');
      expect(results.first.href, '/subtitle/oae-276-best.html');
      expect(results.first.downloads, 20);
      expect(results.first.comments, 5);
      expect(results.first.language, 'zh-CN');
      expect(results.last.title, 'OAE-276 low');
    });

    test('search retries when response body closes early', () async {
      var requests = 0;
      final service = SubtitleCatService(
        byteFetcher: (uri, headers) async {
          requests++;
          expect(
            uri,
            Uri.https('subtitlecat.com', '/index.php', {'search': 'SAVR-942'}),
          );

          if (requests == 1) {
            throw HttpException(
              'Connection closed while receiving data',
              uri: uri,
            );
          }

          return utf8.encode('''
      <table>
        <tbody>
          <tr>
            <td><a href="/subtitle/savr-942.html">SAVR-942 Chinese</a></td>
            <td>10 downloads</td>
            <td>2 comments</td>
            <td>zh-CN</td>
          </tr>
        </tbody>
      </table>
      ''');
        },
        retryDelay: Duration.zero,
      );

      final results = await service.search('SAVR-942');

      expect(requests, 2);
      expect(results, hasLength(1));
      expect(results.single.title, 'SAVR-942 Chinese');
    });

    test('parses Chinese download link from detail page', () {
      const html = '''
      <html>
        <body>
          <a id="download_en" href="/download/en/file.srt">English</a>
          <a id="download_zh-CN" href="/download/zh/file.srt">Chinese</a>
        </body>
      </html>
      ''';

      expect(
        SubtitleCatService.parseDownloadUrl(html, 'zh-CN'),
        '/download/zh/file.srt',
      );
    });

    test('detects valid subtitle content and extension', () {
      final srtBytes = '''
1
00:00:01,000 --> 00:00:02,000
line
'''
          .codeUnits;
      final assBytes = '''
[Script Info]
Title: test

[V4+ Styles]
Format: Name
'''
          .codeUnits;

      expect(SubtitleCatService.isValidSubtitleContent(srtBytes), isTrue);
      expect(
          SubtitleCatService.detectSubtitleExtension(
            downloadUrl: 'https://subtitlecat.com/download/file',
            content: srtBytes,
          ),
          'srt');
      expect(
          SubtitleCatService.detectSubtitleExtension(
            downloadUrl: 'https://subtitlecat.com/download/file',
            content: assBytes,
          ),
          'ass');
      expect(
        SubtitleCatService.isValidSubtitleContent(
            '<html>missing</html>'.codeUnits),
        isFalse,
      );
    });

    test('finds local subtitles by video basename', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('cine_vault_subtitle_');
      final video = File('${tempDir.path}${Platform.pathSeparator}ABC-123.mp4');
      final exact = File('${tempDir.path}${Platform.pathSeparator}ABC-123.srt');
      final language =
          File('${tempDir.path}${Platform.pathSeparator}ABC-123.zh.ass');
      final other = File('${tempDir.path}${Platform.pathSeparator}XYZ-999.srt');
      await video.writeAsString('video');
      await exact.writeAsString('subtitle');
      await language.writeAsString('subtitle');
      await other.writeAsString('subtitle');

      final matches =
          await SubtitleCatService.findLocalSubtitleFilesForVideo(video.path);

      expect(matches, [exact.path, language.path]);
    });

    test('download save path does not reuse existing valid subtitle', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('cine_vault_subtitle_');
      final video = File('${tempDir.path}${Platform.pathSeparator}ABC-123.mp4');
      final existing =
          File('${tempDir.path}${Platform.pathSeparator}ABC-123.srt');
      await video.writeAsString('video');
      await existing.writeAsString('''
1
00:00:01,000 --> 00:00:02,000
old line
''');

      final savePath =
          await SubtitleCatService.resolveSubtitleSavePath(video.path, 'srt');

      expect(
        savePath,
        '${tempDir.path}${Platform.pathSeparator}ABC-123.subtitlecat.1.srt',
      );
    });
  });

  test('movie stores subtitle file paths independently from video paths', () {
    const subtitlePath = 'D:\\Videos\\ABC-123.srt';
    final movie = Movie(
      id: 'ABC-123',
      name: 'ABC-123',
      code: 'ABC-123',
      createdAt: 1000,
      cast: const <Cast>[],
      videoFilePaths: const ['D:\\Videos\\ABC-123.mp4'],
      subtitleFilePaths: const [subtitlePath],
    );

    final updated = movie.copyWith(name: 'renamed');

    expect(updated.videoFilePaths, movie.videoFilePaths);
    expect(updated.subtitleFilePaths, [subtitlePath]);
  });
}
