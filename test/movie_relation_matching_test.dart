import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cine_vault/models/cast.dart';
import 'package:cine_vault/models/movie.dart';
import 'package:cine_vault/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('relation lookup does not match unrelated movies by digits only',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('cine_vault_relations_');
    await DatabaseService.init(customPath: tempDir.path);

    await DatabaseService.addMovie(
      Movie(
        id: 'local-xyz-123',
        name: 'XYZ-123',
        code: 'XYZ-123',
        createdAt: 1000,
        cast: const <Cast>[],
      ),
    );

    final matched = DatabaseService.findMovieByRelationId('ABC-123');

    expect(matched, isNull);
  });

  test('relation lookup matches a TMDB id stored as local code', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('cine_vault_relations_');
    await DatabaseService.init(customPath: tempDir.path);

    await DatabaseService.addMovie(
      Movie(
        id: 'local-550',
        name: 'Fight Club',
        code: '550',
        createdAt: 1000,
        cast: const <Cast>[],
      ),
    );

    final matched = DatabaseService.findMovieByRelationId('550');

    expect(matched?.id, 'local-550');
  });
}
