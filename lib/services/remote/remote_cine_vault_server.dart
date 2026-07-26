import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../database_service.dart';
import 'remote_auth.dart';
import 'remote_movie_serializer.dart';
import 'remote_server_settings.dart';

class RemoteCineVaultServer {
  RemoteCineVaultServer({
    RemoteServerSettingsService? settingsService,
  }) : _settingsService = settingsService ?? RemoteServerSettingsService();

  final RemoteServerSettingsService _settingsService;
  HttpServer? _server;
  RemoteServerSettings? _settings;
  StreamSubscription<HttpRequest>? _subscription;

  bool get isRunning => _server != null;
  RemoteServerSettings? get currentSettings => _settings;

  Future<RemoteServerSettings> loadSettings() => _settingsService.load();

  Future<void> startFromSettings() async {
    final settings = await _settingsService.load();
    await start(settings);
  }

  Future<void> start(RemoteServerSettings settings) async {
    await stop();
    _settings = settings;
    if (!settings.enabled) return;

    _server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      settings.port,
      shared: true,
    );
    _subscription = _server!.listen(_handleRequest);
    debugPrint('[RemoteServer] Listening on http://0.0.0.0:${settings.port}');
  }

  Future<void> restart(RemoteServerSettings settings) async {
    await _settingsService.save(settings);
    await start(settings);
  }

  Future<RemoteServerSettings> regenerateTokenAndRestart() async {
    final settings = await _settingsService.regenerateToken();
    await start(settings);
    return settings;
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    _addCorsHeaders(request.response);
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    try {
      final path = request.uri.path;
      if (path == '/health' || path == '/api/health') {
        await _writeJson(request, {
          'ok': true,
          'service': 'CineVault',
        });
        return;
      }

      if (!_isAuthorized(request)) {
        await _writeJson(
          request,
          {'error': 'unauthorized'},
          statusCode: HttpStatus.unauthorized,
        );
        return;
      }

      if (path == '/api/movies' && request.method == 'GET') {
        await _handleMovies(request);
        return;
      }

      if (path.startsWith('/api/movies/') && request.method == 'GET') {
        final id = Uri.decodeComponent(path.substring('/api/movies/'.length));
        await _handleMovieDetail(request, id);
        return;
      }

      if (path == '/api/image' && request.method == 'GET') {
        await _handleImageProxy(request);
        return;
      }

      await _writeJson(
        request,
        {'error': 'not_found'},
        statusCode: HttpStatus.notFound,
      );
    } catch (error, stackTrace) {
      debugPrint('[RemoteServer] Request failed: $error\n$stackTrace');
      await _writeJson(
        request,
        {'error': 'internal_error', 'message': error.toString()},
        statusCode: HttpStatus.internalServerError,
      );
    }
  }

  bool _isAuthorized(HttpRequest request) {
    final token = _settings?.token ?? '';
    return RemoteAuth.isAuthorized(
          authorizationHeader: request.headers.value(HttpHeaders.authorizationHeader),
          expectedToken: token,
        ) ||
        RemoteAuth.isTokenAuthorized(
          providedToken: request.uri.queryParameters['token'],
          expectedToken: token,
        );
  }

  Future<void> _handleMovies(HttpRequest request) async {
    final page = _parsePositiveInt(request.uri.queryParameters['page'], 1);
    final pageSize =
        _parsePositiveInt(request.uri.queryParameters['pageSize'], 30)
            .clamp(1, 100);
    final keyword = request.uri.queryParameters['keyword']?.trim().toLowerCase() ?? '';
    final allMovies = DatabaseService.getAllMovies()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final filtered = keyword.isEmpty
        ? allMovies
        : allMovies.where((movie) {
            return movie.name.toLowerCase().contains(keyword) ||
                movie.code.toLowerCase().contains(keyword) ||
                movie.id.toLowerCase().contains(keyword);
          }).toList();

    final start = (page - 1) * pageSize;
    final end = (start + pageSize).clamp(0, filtered.length);
    final items = start >= filtered.length ? const [] : filtered.sublist(start, end);

    await _writeJson(request, {
      'movies': items.map((movie) {
        return RemoteMovieSerializer.toMobileJson(
          movie,
          imageProxyBaseUrl: _imageProxyBaseUrl(request),
        );
      }).toList(),
      'pagination': {
        'page': page,
        'pageSize': pageSize,
        'total': filtered.length,
        'hasNextPage': end < filtered.length,
      },
    });
  }

  Future<void> _handleMovieDetail(HttpRequest request, String id) async {
    final movie = DatabaseService.getMovie(id);
    if (movie == null) {
      await _writeJson(
        request,
        {'error': 'movie_not_found'},
        statusCode: HttpStatus.notFound,
      );
      return;
    }

    await _writeJson(
      request,
      RemoteMovieSerializer.toMobileJson(
        movie,
        imageProxyBaseUrl: _imageProxyBaseUrl(request),
      ),
    );
  }

  Future<void> _handleImageProxy(HttpRequest request) async {
    final url = request.uri.queryParameters['url']?.trim() ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final client = HttpClient();
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    try {
      final proxyRequest = await client.getUrl(uri);
      proxyRequest.headers.set(
        HttpHeaders.userAgentHeader,
        'CineVault/1.0',
      );
      final proxyResponse = await proxyRequest.close();
      request.response.statusCode = proxyResponse.statusCode;
      final contentType = proxyResponse.headers.contentType;
      if (contentType != null) {
        request.response.headers.contentType = contentType;
      }
      await proxyResponse.pipe(request.response);
    } finally {
      client.close(force: false);
    }
  }

  String _imageProxyBaseUrl(HttpRequest request) {
    final host = request.headers.value(HttpHeaders.hostHeader) ??
        'localhost:${_settings?.port ?? RemoteServerSettingsService.defaultPort}';
    final token = _settings?.token ?? '';
    return 'http://$host/api/image?token=${Uri.encodeQueryComponent(token)}&url=';
  }

  int _parsePositiveInt(String? value, int fallback) {
    final parsed = int.tryParse(value ?? '');
    if (parsed == null || parsed < 1) return fallback;
    return parsed;
  }

  void _addCorsHeaders(HttpResponse response) {
    response.headers
      ..set(HttpHeaders.accessControlAllowOriginHeader, '*')
      ..set(HttpHeaders.accessControlAllowHeadersHeader, 'Authorization, Content-Type')
      ..set(HttpHeaders.accessControlAllowMethodsHeader, 'GET, OPTIONS');
  }

  Future<void> _writeJson(
    HttpRequest request,
    Object body, {
    int statusCode = HttpStatus.ok,
  }) async {
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }
}

final remoteCineVaultServer = RemoteCineVaultServer();
