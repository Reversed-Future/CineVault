import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cine_vault/models/cast.dart';
import 'package:cine_vault/models/movie.dart';
import 'package:cine_vault/models/notification.dart';
import 'package:cine_vault/providers/unregistered_movies_provider.dart';
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
    return 'unregistered_movies_provider_test';
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

  test('pending entries recover from the latest local scan result', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('cine_vault_pending_');
    await DatabaseService.init(customPath: tempDir.path);

    final videoDir =
        await Directory('${tempDir.path}${Platform.pathSeparator}videos')
            .create();
    await File('${videoDir.path}${Platform.pathSeparator}DEF-456.mp4')
        .writeAsString('video');

    await DatabaseService.addMovie(
      Movie(
        id: 'ABC-123',
        name: 'ABC-123',
        code: 'ABC-123',
        createdAt: 1000,
        cast: const <Cast>[],
      ),
    );

    await LocalMovieScanner.startScan(
      videoFolders: [videoDir.path],
      notificationNotifier: _FakeNotificationNotifier(),
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(unregisteredMoviesProvider), isEmpty);

    final recovered = container.read(effectiveUnregisteredMoviesProvider);
    expect(recovered.map((entry) => entry.movieCode), contains('DEF-456'));

    container.read(unregisteredMoviesProvider.notifier).restoreFromLastScan();
    expect(
      container
          .read(unregisteredMoviesProvider)
          .map((entry) => entry.movieCode),
      contains('DEF-456'),
    );
  });
}
