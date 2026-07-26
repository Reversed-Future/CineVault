import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cine_vault/models/cast.dart';
import 'package:cine_vault/models/movie.dart';
import 'package:cine_vault/models/named_item.dart';
import 'package:cine_vault/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('custom movie tags stay separate from movie source tags', () async {
    final tempDir = await Directory.systemTemp.createTemp('cine_vault_test_');
    await DatabaseService.init(customPath: tempDir.path);

    final movie = Movie(
      id: 'ABC-123',
      name: 'ABC-123',
      code: 'ABC-123',
      createdAt: 1000,
      cast: const <Cast>[],
      tags: [
        NamedItem(id: 'official-tag-id', name: 'Official Tag'),
      ],
    );
    await DatabaseService.addMovie(movie);

    final firstTag = await DatabaseService.createCustomMovieTag('Watch Later');
    final secondTag = await DatabaseService.createCustomMovieTag('Archive');

    await DatabaseService.setMovieCustomTags(
      movie.id,
      {firstTag.id, secondTag.id},
    );

    final customTags = DatabaseService.getCustomTagsForMovie(movie.id);
    expect(customTags.map((tag) => tag.name).toSet(), {
      'Watch Later',
      'Archive',
    });

    final savedMovie = DatabaseService.getMovie(movie.id)!;
    expect(savedMovie.tags!.single.id, 'official-tag-id');
    expect(savedMovie.tags!.single.name, 'Official Tag');

    final taggedMovies = DatabaseService.getMoviesForCustomTag(firstTag.id);
    expect(taggedMovies.map((movie) => movie.id), ['ABC-123']);

    await DatabaseService.deleteCustomMovieTag(secondTag.id);

    final remainingTags = DatabaseService.getCustomTagsForMovie(movie.id);
    expect(remainingTags.map((tag) => tag.id), [firstTag.id]);

    await DatabaseService.deleteMovie(movie.id);

    expect(DatabaseService.getCustomTagIdsForMovie(movie.id), isEmpty);
    expect(DatabaseService.getCustomMovieTagCounts()[firstTag.id], isNull);
  });
}
