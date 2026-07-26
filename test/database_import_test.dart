import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cine_vault/models/app_settings.dart';
import 'package:cine_vault/models/cast.dart';
import 'package:cine_vault/models/movie.dart';
import 'package:cine_vault/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('redacted import preserves local sensitive settings', () async {
    final tempDir = await Directory.systemTemp.createTemp('cine_vault_import_');
    await DatabaseService.init(customPath: tempDir.path);

    await DatabaseService.saveSettings(
      AppSettings(
        videoFolders: const ['D:\\local'],
        proxyEnabled: true,
        proxyType: 'http',
        proxyHost: '127.0.0.1',
        proxyPort: 7890,
        proxyUsername: 'local-user',
        proxyPassword: 'local-pass',
        useAria2ForDownloads: true,
        aria2RpcSecret: 'local-rpc-secret',
      ),
    );

    final importFile =
        File('${tempDir.path}${Platform.pathSeparator}backup.json');
    await importFile.writeAsString(
      jsonEncode({
        'version': 1,
        'sensitiveSettingsRedacted': true,
        'movies': [],
        'settings': {
          'videoFolders': ['D:\\imported'],
          'proxyEnabled': true,
          'proxyType': 'socks5',
          'proxyHost': '192.168.1.10',
          'proxyPort': 1080,
          'proxyUsername': null,
          'proxyPassword': null,
          'useAria2ForDownloads': true,
          'aria2RpcSecret': null,
        },
      }),
      encoding: utf8,
    );

    final result = await DatabaseService.importData(importFile.path);
    expect(result.success, isTrue);

    final settings = DatabaseService.getSettings();
    expect(settings.videoFolders, const ['D:\\imported']);
    expect(settings.proxyType, 'socks5');
    expect(settings.proxyHost, '192.168.1.10');
    expect(settings.proxyPort, 1080);
    expect(settings.proxyUsername, 'local-user');
    expect(settings.proxyPassword, 'local-pass');
    expect(settings.aria2RpcSecret, 'local-rpc-secret');
  });

  test('movie update callback receives latest saved movie', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('cine_vault_latest_update_');
    await DatabaseService.init(customPath: tempDir.path);

    await DatabaseService.addMovie(
      Movie(
        id: 'ABC-123',
        name: 'ABC-123',
        code: 'ABC-123',
        createdAt: 1000,
        cast: const <Cast>[],
        videoFilePaths: const ['D:\\Videos\\ABC-123.mp4'],
        playCount: 7,
      ),
    );

    Movie? callbackMovie;
    final updatedMovie = await DatabaseService.updateMovieWithLatest(
      'ABC-123',
      (latestMovie) {
        callbackMovie = latestMovie;
        return latestMovie.copyWith(translatedName: 'translated title');
      },
    );

    expect(callbackMovie?.playCount, 7);
    expect(updatedMovie.translatedName, 'translated title');

    final savedMovie = DatabaseService.getMovie('ABC-123')!;
    expect(savedMovie.videoFilePaths, const ['D:\\Videos\\ABC-123.mp4']);
    expect(savedMovie.playCount, 7);
    expect(savedMovie.translatedName, 'translated title');
  });
}
