import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cine_vault/services/tmdb_api_service.dart';

void main() {
  test('testConnection reports a readable timeout message', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) {});
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });

    final service = TmdbApiService(
      requestTimeout: const Duration(milliseconds: 100),
    );
    addTearDown(service.close);

    service.configure(
      baseUrl: 'http://${InternetAddress.loopbackIPv4.address}:${server.port}',
      apiKey: 'test-key',
    );

    await expectLater(
      service.testConnection(),
      throwsA(
        isA<TmdbConnectionException>().having(
          (error) => error.message,
          'message',
          contains('连接 TMDB 超时'),
        ),
      ),
    );
  });

  test('testConnection rejects unsupported socks5 proxy for TMDB requests',
      () async {
    final service = TmdbApiService(
      requestTimeout: const Duration(milliseconds: 100),
    );
    addTearDown(service.close);

    service.configure(
      baseUrl: 'http://127.0.0.1:1',
      apiKey: 'test-key',
    );
    service.configureProxy(
      enabled: true,
      type: 'socks5',
      host: '127.0.0.1',
      port: 1080,
    );

    await expectLater(
      service.testConnection(),
      throwsA(
        isA<TmdbConnectionException>().having(
          (error) => error.message,
          'message',
          contains('仅支持 HTTP 代理'),
        ),
      ),
    );
  });

  test('getMoviesByFilter sends genre id to discover movie', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <Uri>[];
    final subscription = server.listen((request) async {
      requests.add(request.uri);
      await _writeJson(
          request,
          switch (request.uri.path) {
            '/configuration' => _configurationJson,
            '/genre/movie/list' => _genreJson,
            '/discover/movie' => {
                'page': 1,
                'total_pages': 1,
                'results': [
                  {
                    'id': 100,
                    'title': 'Science Movie',
                    'poster_path': '/poster.jpg',
                    'backdrop_path': '/backdrop.jpg',
                    'release_date': '2026-01-01',
                    'genre_ids': [878],
                    'adult': false,
                  }
                ],
              },
            _ => <String, dynamic>{'status': 'not_found'},
          });
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });

    final service = TmdbApiService(
      requestTimeout: const Duration(seconds: 2),
    );
    addTearDown(service.close);
    service.configure(
      baseUrl: 'http://${InternetAddress.loopbackIPv4.address}:${server.port}',
      apiKey: 'test-key',
    );

    final response = await service.getMoviesByFilter(
      filterType: TmdbFilterType.genre,
      filterId: '878',
    );

    expect(response.movies.single.id, '100');
    final discoverRequest =
        requests.singleWhere((uri) => uri.path == '/discover/movie');
    expect(discoverRequest.queryParameters['with_genres'], '878');
    expect(discoverRequest.queryParameters['include_video'], 'false');
  });

  test('getMoviesByFilter filters director credits by person id', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <Uri>[];
    final subscription = server.listen((request) async {
      requests.add(request.uri);
      await _writeJson(
          request,
          switch (request.uri.path) {
            '/configuration' => _configurationJson,
            '/genre/movie/list' => _genreJson,
            '/person/7/movie_credits' => {
                'cast': const [],
                'crew': [
                  {
                    'id': 200,
                    'title': 'Directed Movie',
                    'job': 'Director',
                    'poster_path': '/director.jpg',
                    'release_date': '2025-01-01',
                    'adult': false,
                  },
                  {
                    'id': 201,
                    'title': 'Written Movie',
                    'job': 'Writer',
                    'poster_path': '/writer.jpg',
                    'release_date': '2026-01-01',
                    'adult': false,
                  },
                ],
              },
            _ => <String, dynamic>{'status': 'not_found'},
          });
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });

    final service = TmdbApiService(
      requestTimeout: const Duration(seconds: 2),
    );
    addTearDown(service.close);
    service.configure(
      baseUrl: 'http://${InternetAddress.loopbackIPv4.address}:${server.port}',
      apiKey: 'test-key',
    );

    final response = await service.getMoviesByFilter(
      filterType: TmdbFilterType.director,
      filterId: '7',
    );

    expect(response.movies.map((movie) => movie.id), ['200']);
    expect(
      requests.any((uri) => uri.path == '/person/7/movie_credits'),
      isTrue,
    );
  });
}

const Map<String, dynamic> _configurationJson = {
  'images': {
    'secure_base_url': 'https://image.tmdb.org/t/p/',
    'poster_sizes': ['w500'],
    'backdrop_sizes': ['w780'],
    'profile_sizes': ['w185'],
  },
};

const Map<String, dynamic> _genreJson = {
  'genres': [
    {'id': 878, 'name': 'Science Fiction'},
  ],
};

Future<void> _writeJson(
  HttpRequest request,
  Map<String, dynamic> body,
) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}
