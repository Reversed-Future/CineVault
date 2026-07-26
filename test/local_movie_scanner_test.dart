import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cine_vault/models/cast.dart';
import 'package:cine_vault/models/movie.dart';
import 'package:cine_vault/models/notification.dart';
import 'package:cine_vault/services/database_service.dart';
import 'package:cine_vault/services/local_movie_scanner.dart';

class _FakeNotificationNotifier {
  Future<String> addProgressNotification({
    required String title,
    required String message,
    required AppNotificationType type,
    int initialProgress = 0,
    String? taskType,
  }) async {
    return 'local_scan_test';
  }

  Future<void> updateNotification({
    required String notificationId,
    String? message,
    int? progress,
    bool? isProgressing,
  }) async {}

  Future<void> addNotification({
    required String title,
    required String message,
    required AppNotificationType type,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local scan replaces stale saved paths with scanned paths', () async {
    final tempDir = await Directory.systemTemp.createTemp('cine_vault_scan_');
    await DatabaseService.init(customPath: tempDir.path);

    final videoDir =
        await Directory('${tempDir.path}${Platform.pathSeparator}videos')
            .create();
    final stalePath = '${tempDir.path}${Platform.pathSeparator}missing.mp4';
    final subtitlePath = '${tempDir.path}${Platform.pathSeparator}ABC-123.srt';
    final scannedFile =
        File('${videoDir.path}${Platform.pathSeparator}ABC-123.mp4');
    await scannedFile.writeAsString('video');

    await DatabaseService.addMovie(
      Movie(
        id: 'ABC-123',
        name: 'ABC-123',
        code: 'ABC-123',
        createdAt: 1000,
        cast: const <Cast>[],
        videoFilePaths: [stalePath],
        subtitleFilePaths: [subtitlePath],
      ),
    );

    await LocalMovieScanner.startScan(
      videoFolders: [videoDir.path],
      notificationNotifier: _FakeNotificationNotifier(),
    );

    final savedMovie = DatabaseService.getMovie('ABC-123')!;
    expect(savedMovie.videoFilePaths, [scannedFile.path]);
    expect(savedMovie.subtitleFilePaths, [subtitlePath]);
  });
}
