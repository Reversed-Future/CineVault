import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cine_vault/models/cast.dart';
import 'package:cine_vault/models/movie.dart';
import 'package:cine_vault/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('editing movie code preserves existing title and local paths', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('cine_vault_code_edit_');
    await DatabaseService.init(customPath: tempDir.path);

    const videoPath = 'D:\\Videos\\ABC-123.mp4';
    final movie = Movie(
      id: 'ABC-123',
      name: 'Existing Movie Title',
      code: 'ABC-123',
      createdAt: 1000,
      cast: const <Cast>[],
      videoFilePaths: const [videoPath],
    );
    await DatabaseService.addMovie(movie);

    final updatedMovie = await DatabaseService.updateMovieCode(
      movie,
      'def-456',
    );

    expect(updatedMovie.id, 'ABC-123');
    expect(updatedMovie.code, 'DEF-456');
    expect(updatedMovie.name, 'Existing Movie Title');
    expect(updatedMovie.videoFilePaths, const [videoPath]);

    final savedMovie = DatabaseService.getMovie('ABC-123')!;
    expect(savedMovie.code, 'DEF-456');
    expect(savedMovie.name, 'Existing Movie Title');
    expect(savedMovie.videoFilePaths, const [videoPath]);
  });

  test('editing placeholder movie code also updates placeholder title',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('cine_vault_code_edit_');
    await DatabaseService.init(customPath: tempDir.path);

    final movie = Movie(
      id: 'BAD-111',
      name: 'BAD-111',
      code: 'BAD-111',
      createdAt: 1000,
      cast: const <Cast>[],
    );
    await DatabaseService.addMovie(movie);

    final updatedMovie = await DatabaseService.updateMovieCode(
      movie,
      'abc-123',
    );

    expect(updatedMovie.id, 'BAD-111');
    expect(updatedMovie.code, 'ABC-123');
    expect(updatedMovie.name, 'ABC-123');
  });
}
