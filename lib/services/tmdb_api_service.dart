import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/tmdb_models.dart';

enum TmdbFilterType { genre, director, company, collection }

class TmdbApiService {
  static const String defaultBaseUrl = 'https://api.themoviedb.org/3';
  static const Duration defaultRequestTimeout = Duration(seconds: 20);

  final Duration requestTimeout;

  String _baseUrl = defaultBaseUrl;
  String _readAccessToken = '';
  String _apiKey = '';
  String _language = 'zh-CN';
  String _region = '';
  HttpClient? _httpClient;
  bool _proxyEnabled = false;
  String? _proxyType;
  String? _proxyHost;
  int? _proxyPort;
  String? _proxyUsername;
  String? _proxyPassword;
  bool _isClosed = false;

  String _imageBaseUrl = 'https://image.tmdb.org/t/p/';
  String _posterSize = 'w500';
  String _backdropSize = 'w780';
  String _profileSize = 'w185';
  bool _imageConfigLoaded = false;
  Map<int, String> _genreNames = const {};

  TmdbApiService({this.requestTimeout = defaultRequestTimeout});

  static String buildImageUrl(String baseUrl, String imagePath) {
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return imagePath;
    }
    final normalizedBase = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final normalizedPath =
        imagePath.startsWith('/') ? imagePath.substring(1) : imagePath;
    return '$normalizedBase$normalizedPath';
  }

  HttpClient _getClient() {
    if (_isClosed) {
      throw StateError('TmdbApiService has been closed');
    }
    _httpClient ??= _createHttpClient();
    return _httpClient!;
  }

  HttpClient _createHttpClient() {
    final client = HttpClient();
    client.connectionTimeout = requestTimeout;
    client.idleTimeout = requestTimeout;
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    _applyProxyConfig(client);
    return client;
  }

  void _applyProxyConfig(HttpClient client) {
    if (_proxyEnabled && _proxyHost != null && _proxyPort != null) {
      client.findProxy = (uri) {
        return 'PROXY $_proxyHost:$_proxyPort';
      };

      if (_proxyUsername != null && _proxyPassword != null) {
        client.addProxyCredentials(
          _proxyHost!,
          _proxyPort!,
          '',
          HttpClientBasicCredentials(_proxyUsername!, _proxyPassword!),
        );
      }
    } else {
      client.findProxy = null;
    }
  }

  void _validateProxyConfig() {
    if (!_proxyEnabled) return;

    if (_proxyHost == null ||
        _proxyHost!.trim().isEmpty ||
        _proxyPort == null) {
      throw const TmdbConnectionException('代理已启用，但代理服务器或端口未配置');
    }

    final proxyType = (_proxyType ?? 'http').trim().toLowerCase();
    if (proxyType == 'socks5') {
      throw const TmdbConnectionException(
        'TMDB 请求当前仅支持 HTTP 代理。请在代理配置中选择 HTTP，或关闭代理后重试。',
      );
    }
  }

  void configureProxy({
    bool enabled = false,
    String? type,
    String? host,
    int? port,
    String? username,
    String? password,
  }) {
    _proxyEnabled = enabled;
    _proxyType = type;
    _proxyHost = host;
    _proxyPort = port;
    _proxyUsername = username;
    _proxyPassword = password;

    if (_httpClient != null) {
      _applyProxyConfig(_httpClient!);
    }
  }

  void configure({
    String baseUrl = defaultBaseUrl,
    String? authToken,
    String? readAccessToken,
    String? apiKey,
    String language = 'zh-CN',
    String? region,
  }) {
    _baseUrl = baseUrl.trim().isEmpty ? defaultBaseUrl : baseUrl.trim();
    _readAccessToken = (readAccessToken ?? authToken ?? '').trim();
    _apiKey = (apiKey ?? '').trim();
    _language = language.trim().isEmpty ? 'zh-CN' : language.trim();
    _region = (region ?? '').trim();
  }

  bool get isConfigured => _readAccessToken.isNotEmpty || _apiKey.isNotEmpty;

  String get baseUrl => _baseUrl;

  String? get authToken => _readAccessToken.isEmpty ? null : _readAccessToken;

  String get language => _language;

  String get region => _region;

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[TmdbApi] $message');
    }
  }

  void printDebugInfo() {
    _log('baseUrl=$_baseUrl');
    _log('hasReadAccessToken=${_readAccessToken.isNotEmpty}');
    _log('hasApiKey=${_apiKey.isNotEmpty}');
    _log('language=$_language');
    _log('region=$_region');
  }

  Future<HttpClientRequest> _createRequest(
    String path, {
    required String method,
    Map<String, String>? queryParams,
  }) async {
    if (!isConfigured) {
      throw const TmdbAuthException('请先配置 TMDB Read Access Token 或 API Key');
    }

    _validateProxyConfig();

    final normalizedBase = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    final mergedParams = <String, String>{...?queryParams};
    if (_readAccessToken.isEmpty && _apiKey.isNotEmpty) {
      mergedParams['api_key'] = _apiKey;
    }

    final uri = Uri.parse('$normalizedBase/$normalizedPath');
    final finalUri =
        mergedParams.isEmpty ? uri : uri.replace(queryParameters: mergedParams);

    final request = await _withConnectionHandling(
      _getClient().openUrl(method, finalUri),
    );
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (_readAccessToken.isNotEmpty) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $_readAccessToken',
      );
    }
    return request;
  }

  Future<Map<String, dynamic>> _sendMap(
    String path, {
    Map<String, String>? queryParams,
  }) async {
    try {
      final request =
          await _createRequest(path, method: 'GET', queryParams: queryParams);
      final response = await _withConnectionHandling(request.close());
      final responseBody = await _withConnectionHandling(
        utf8.decodeStream(response),
      );

      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        throw const TmdbAuthException('TMDB 授权失败，请检查访问凭据');
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw TmdbApiException(
          'TMDB 请求失败: ${response.statusCode}',
          responseBody,
        );
      }

      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) {
        throw const TmdbApiException('TMDB 响应格式错误', 'Expected JSON object');
      }
      return decoded;
    } on SocketException catch (error) {
      throw TmdbConnectionException('网络连接失败: ${error.message}');
    } on FormatException catch (error) {
      throw TmdbApiException('TMDB 响应格式错误', error.message);
    } catch (error) {
      if (error is TmdbException) rethrow;
      _log(error.toString());
      throw TmdbApiException('TMDB 请求失败', error.toString());
    }
  }

  Future<T> _withConnectionHandling<T>(Future<T> operation) async {
    try {
      return await operation.timeout(requestTimeout);
    } on TimeoutException {
      throw TmdbConnectionException(
        '连接 TMDB 超时（${requestTimeout.inSeconds} 秒）。请检查 API 地址、网络连接或代理设置。',
      );
    } on SocketException catch (error) {
      throw TmdbConnectionException(_formatConnectionError(error.message));
    } on HandshakeException catch (error) {
      throw TmdbConnectionException('TMDB TLS 握手失败: ${error.message}');
    } on HttpException catch (error) {
      throw TmdbConnectionException('TMDB HTTP 连接失败: ${error.message}');
    }
  }

  String _formatConnectionError(String message) {
    final normalized = message.trim();
    if (normalized.contains('信号灯') ||
        normalized.toLowerCase().contains('timeout')) {
      return '连接 TMDB 超时。请检查 API 地址、网络连接或代理设置。原始错误: $normalized';
    }
    return '网络连接失败: $normalized';
  }

  Future<void> _ensureConfiguration() async {
    if (_imageConfigLoaded && _genreNames.isNotEmpty) {
      return;
    }

    final configuration = await _sendMap('/configuration');
    final images = configuration['images'] as Map<String, dynamic>? ?? const {};
    _imageBaseUrl =
        (images['secure_base_url'] as String?) ?? 'https://image.tmdb.org/t/p/';
    _posterSize = _chooseSize(images['poster_sizes'], 'w500');
    _backdropSize = _chooseSize(images['backdrop_sizes'], 'w780');
    _profileSize = _chooseSize(images['profile_sizes'], 'w185');
    _imageConfigLoaded = true;

    final genres = await _sendMap('/genre/movie/list', queryParams: {
      'language': _language,
    });
    _genreNames = {
      for (final item in (genres['genres'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>())
        if (item['id'] is int && item['name'] is String)
          item['id'] as int: item['name'] as String,
    };
  }

  String _chooseSize(Object? value, String preferred) {
    final sizes = (value as List<dynamic>? ?? const [])
        .whereType<String>()
        .where((size) => size.isNotEmpty)
        .toList();
    if (sizes.contains(preferred)) return preferred;
    return sizes.isNotEmpty ? sizes.last : preferred;
  }

  Future<MovieListResponse> getMovies({
    int page = 1,
    TmdbFilterType? filterType,
    String? filterValue,
  }) async {
    await _ensureConfiguration();
    final queryParams = <String, String>{
      'page': page.toString(),
      'language': _language,
      'include_adult': 'false',
    };
    if (_region.isNotEmpty) {
      queryParams['region'] = _region;
    }
    if (filterType == TmdbFilterType.genre &&
        filterValue != null &&
        filterValue.trim().isNotEmpty) {
      queryParams['with_genres'] = filterValue.trim();
    }

    final json = await _sendMap('/discover/movie', queryParams: queryParams);
    return MovieListResponse.fromTmdbJson(
      json,
      imageBaseUrl: _imageBaseUrl,
      posterSize: _posterSize,
      backdropSize: _backdropSize,
      genreNames: _genreNames,
    );
  }

  Future<SearchResponse> searchMovies({
    required String keyword,
    int page = 1,
    String? year,
  }) async {
    final trimmedKeyword = keyword.trim();
    if (trimmedKeyword.isEmpty) {
      return SearchResponse(
        movies: const [],
        pagination: const Pagination(
          currentPage: 1,
          hasNextPage: false,
          pages: [1],
        ),
        keyword: trimmedKeyword,
      );
    }

    await _ensureConfiguration();
    final queryParams = <String, String>{
      'query': trimmedKeyword,
      'page': page.toString(),
      'language': _language,
      'include_adult': 'false',
    };
    if (_region.isNotEmpty) {
      queryParams['region'] = _region;
    }
    if (year != null && year.trim().isNotEmpty) {
      queryParams['year'] = year.trim();
    }

    final json = await _sendMap('/search/movie', queryParams: queryParams);
    return SearchResponse.fromTmdbJson(
      json,
      keyword: trimmedKeyword,
      imageBaseUrl: _imageBaseUrl,
      posterSize: _posterSize,
      backdropSize: _backdropSize,
      genreNames: _genreNames,
    );
  }

  Future<TmdbMovieDetail> getMovieDetail(String movieId) async {
    final id = movieId.trim();
    if (id.isEmpty) {
      throw const TmdbApiException('缺少 TMDB 电影 ID', '');
    }

    await _ensureConfiguration();
    final json = await _sendMap(
      '/movie/${Uri.encodeComponent(id)}',
      queryParams: {
        'language': _language,
        'append_to_response': 'credits,images,external_ids,recommendations',
        'include_image_language': 'zh,en,null',
      },
    );

    return TmdbMovieDetail.fromJson(
      json,
      imageBaseUrl: _imageBaseUrl,
      posterSize: _posterSize,
      backdropSize: _backdropSize,
      profileSize: _profileSize,
    );
  }

  Future<bool> testConnection() async {
    await _sendMap('/configuration');
    return true;
  }

  void close() {
    if (_isClosed) return;
    _isClosed = true;
    _httpClient?.close(force: true);
    _httpClient = null;
  }
}

abstract class TmdbException implements Exception {
  final String message;

  const TmdbException(this.message);

  @override
  String toString() => message;
}

class TmdbConnectionException extends TmdbException {
  const TmdbConnectionException(super.message);
}

class TmdbAuthException extends TmdbException {
  const TmdbAuthException(super.message);
}

class TmdbApiException extends TmdbException {
  final String details;

  const TmdbApiException(super.message, this.details);

  @override
  String toString() => details.isEmpty ? message : '$message: $details';
}
