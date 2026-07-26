import 'package:flutter_test/flutter_test.dart';
import 'package:cine_vault/models/cast.dart';
import 'package:cine_vault/models/movie.dart';
import 'package:cine_vault/models/named_item.dart';
import 'package:cine_vault/services/remote/remote_movie_serializer.dart';

void main() {
  test('serializes movie fields used by the mobile client', () {
    final movie = Movie(
      id: 'm1',
      name: 'Movie title',
      createdAt: 1000,
      cast: [Cast(id: 'c1', name: 'Actor 1')],
      tags: [NamedItem(id: 't1', name: 'Tag 1')],
      coverUrl: 'http://cover',
      backdropUrl: 'http://backdrop',
      code: 'ABC-001',
      releaseDate: '2026-01-01',
      length: 120,
      videoFilePaths: ['D:/video.mp4'],
      isFavorite: true,
      lastWatchPosition: 56.4,
      translatedPlot: 'Summary',
    );

    final json = RemoteMovieSerializer.toMobileJson(movie);

    expect(json['id'], 'm1');
    expect(json['title'], 'Movie title');
    expect(json['name'], 'Movie title');
    expect(json['code'], 'ABC-001');
    expect(json['coverUrl'], 'http://cover');
    expect(json['backdropUrl'], 'http://backdrop');
    expect((json['movieInfo'] as Map<String, dynamic>)['backdrop'],
        'http://backdrop');
    expect(json['favorite'], isTrue);
    expect(json['isFavorite'], isTrue);
    expect(json['watchProgress'], 56);
    expect(json['hasLocalVideo'], isTrue);
    expect(json['summary'], 'Summary');
    expect(json['cast'], [
      {'id': 'c1', 'name': 'Actor 1', 'imageUrl': null, 'avatarUrl': null},
    ]);
    expect(json['tags'], [
      {'id': 't1', 'name': 'Tag 1'},
    ]);
  });
}
