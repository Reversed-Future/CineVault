import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cine_vault/services/database_service.dart';
import 'package:cine_vault/services/local_movie_scanner.dart';
import 'package:cine_vault/widgets/unregistered_movies_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pending dialog exposes editable movie identifier field',
      (tester) async {
    final entry = ScannedMovieEntry(
      movieCode: 'BAD-111',
      folderPath: 'D:\\Videos',
      filePaths: const ['D:\\Videos\\ABC-123.mp4'],
      matchedFolderName: 'Videos',
      matchedFileName: 'ABC-123.mp4',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: UnregisteredMoviesDialog(entries: [entry]),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('pending-code-BAD-111')),
      'abc-123',
    );
    await tester.pump();

    expect(find.text('abc-123'), findsOneWidget);
  });

  test('placeholder save uses edited movie identifier', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('cine_vault_pending_dialog_');
    await DatabaseService.init(customPath: tempDir.path);

    const videoPath = 'D:\\Videos\\ABC-123.mp4';
    final entry = ScannedMovieEntry(
      movieCode: 'BAD-111',
      folderPath: 'D:\\Videos',
      filePaths: const [videoPath],
      matchedFolderName: 'Videos',
      matchedFileName: 'ABC-123.mp4',
    );

    await LocalMovieScanner.createPlaceholderMovie(
      entry,
      movieCode: 'abc-123',
    );

    expect(DatabaseService.getMovie('BAD-111'), isNull);

    final savedMovie = DatabaseService.getMovie('abc-123')!;
    expect(savedMovie.code, 'abc-123');
    expect(savedMovie.name, 'abc-123');
    expect(savedMovie.videoFilePaths, const [videoPath]);
  });
}
