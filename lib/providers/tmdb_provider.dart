import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../models/tmdb_models.dart';
import '../services/tmdb_api_service.dart';
import 'movie_providers.dart';

final tmdbApiServiceProvider = Provider<TmdbApiService>((ref) {
  final service = TmdbApiService();
  final config = ref.watch(tmdbConfigProvider);
  final settings = ref.watch(proxyConfigProvider);

  service.configure(
    baseUrl: config.baseUrl,
    readAccessToken: config.readAccessToken,
    apiKey: config.apiKey,
    language: config.language,
    region: config.region,
  );

  service.configureProxy(
    enabled: settings.proxyEnabled,
    type: settings.proxyType,
    host: settings.proxyHost,
    port: settings.proxyPort,
    username: settings.proxyUsername,
    password: settings.proxyPassword,
  );

  ref.onDispose(service.close);
  return service;
});

final tmdbConfigProvider =
    StateNotifierProvider<TmdbConfigNotifier, TmdbConfig>(
  (ref) => TmdbConfigNotifier(),
);

class TmdbConfig {
  final String baseUrl;
  final String readAccessToken;
  final String apiKey;
  final String language;
  final String region;

  const TmdbConfig({
    this.baseUrl = TmdbApiService.defaultBaseUrl,
    this.readAccessToken = '',
    this.apiKey = '',
    this.language = 'zh-CN',
    this.region = '',
  });

  bool get isConfigured => readAccessToken.isNotEmpty || apiKey.isNotEmpty;
  String get authToken => readAccessToken;
  bool get useAuth => readAccessToken.isNotEmpty;

  TmdbConfig copyWith({
    String? baseUrl,
    String? readAccessToken,
    String? apiKey,
    String? language,
    String? region,
  }) {
    return TmdbConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      readAccessToken: readAccessToken ?? this.readAccessToken,
      apiKey: apiKey ?? this.apiKey,
      language: language ?? this.language,
      region: region ?? this.region,
    );
  }
}

class TmdbConfigNotifier extends StateNotifier<TmdbConfig> {
  static const _boxName = 'tmdb_config';
  static const _baseUrlKey = 'base_url';
  static const _readAccessTokenKey = 'read_access_token';
  static const _apiKeyKey = 'api_key';
  static const _languageKey = 'language';
  static const _regionKey = 'region';

  TmdbConfigNotifier() : super(const TmdbConfig()) {
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final box = await Hive.openBox(_boxName);
      state = TmdbConfig(
        baseUrl: box.get(
          _baseUrlKey,
          defaultValue: TmdbApiService.defaultBaseUrl,
        ) as String,
        readAccessToken: box.get(
          _readAccessTokenKey,
          defaultValue: box.get('auth_token', defaultValue: ''),
        ) as String,
        apiKey: box.get(_apiKeyKey, defaultValue: '') as String,
        language: box.get(_languageKey, defaultValue: 'zh-CN') as String,
        region: box.get(_regionKey, defaultValue: '') as String,
      );
    } catch (_) {
      state = const TmdbConfig();
    }
  }

  Future<void> saveConfig({
    required String baseUrl,
    String readAccessToken = '',
    String apiKey = '',
    String? authToken,
    bool? useAuth,
    String language = 'zh-CN',
    String region = '',
  }) async {
    final normalizedReadAccessToken = readAccessToken.isNotEmpty
        ? readAccessToken
        : ((useAuth ?? false) ? (authToken ?? '') : (authToken ?? ''));
    final box = await Hive.openBox(_boxName);
    await box.put(_baseUrlKey, baseUrl);
    await box.put(_readAccessTokenKey, normalizedReadAccessToken);
    await box.put(_apiKeyKey, apiKey);
    await box.put(_languageKey, language);
    await box.put(_regionKey, region);
    await box.put('auth_token', normalizedReadAccessToken);
    await box.put('use_auth', normalizedReadAccessToken.isNotEmpty);

    state = TmdbConfig(
      baseUrl: baseUrl,
      readAccessToken: normalizedReadAccessToken,
      apiKey: apiKey,
      language: language,
      region: region,
    );
  }

  Future<void> clearConfig() async {
    final box = await Hive.openBox(_boxName);
    await box.clear();
    state = const TmdbConfig();
  }
}

final tmdbSearchProvider =
    StateNotifierProvider<TmdbSearchNotifier, TmdbSearchState>(
  (ref) => TmdbSearchNotifier(ref),
);

class TmdbSearchState {
  final List<TmdbMovie> movies;
  final bool isLoading;
  final String? error;
  final String? keyword;
  final String? year;
  final Pagination? pagination;

  const TmdbSearchState({
    this.movies = const [],
    this.isLoading = false,
    this.error,
    this.keyword,
    this.year,
    this.pagination,
  });

  TmdbSearchState copyWith({
    List<TmdbMovie>? movies,
    bool? isLoading,
    String? error,
    String? keyword,
    String? year,
    Pagination? pagination,
  }) {
    return TmdbSearchState(
      movies: movies ?? this.movies,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      keyword: keyword ?? this.keyword,
      year: year ?? this.year,
      pagination: pagination ?? this.pagination,
    );
  }
}

class TmdbSearchNotifier extends StateNotifier<TmdbSearchState> {
  final Ref ref;

  TmdbSearchNotifier(this.ref) : super(const TmdbSearchState());

  Future<void> search(String keyword, {String? year, int page = 1}) async {
    state = state.copyWith(
      isLoading: true,
      error: null,
      keyword: keyword,
      year: year,
    );

    try {
      final response = await ref.read(tmdbApiServiceProvider).searchMovies(
            keyword: keyword,
            year: year,
            page: page,
          );
      state = state.copyWith(
        movies:
            page == 1 ? response.movies : [...state.movies, ...response.movies],
        pagination: response.pagination,
        isLoading: false,
        error: null,
      );
    } on TmdbException catch (error) {
      state = state.copyWith(isLoading: false, error: error.message);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: '搜索失败: $error');
    }
  }

  Future<void> loadPopular({int page = 1}) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await ref.read(tmdbApiServiceProvider).getMovies(
            page: page,
          );
      state = state.copyWith(
        movies:
            page == 1 ? response.movies : [...state.movies, ...response.movies],
        pagination: response.pagination,
        isLoading: false,
        error: null,
      );
    } on TmdbException catch (error) {
      state = state.copyWith(isLoading: false, error: error.message);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: '加载失败: $error');
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.pagination?.hasNextPage != true) {
      return;
    }

    final nextPage =
        state.pagination?.nextPage ?? (state.pagination?.currentPage ?? 1) + 1;
    if (state.keyword != null && state.keyword!.trim().isNotEmpty) {
      await search(state.keyword!, year: state.year, page: nextPage);
      return;
    }
    await loadPopular(page: nextPage);
  }

  void clear() {
    state = const TmdbSearchState();
  }
}

final tmdbMovieDetailProvider =
    StateNotifierProvider<TmdbMovieDetailNotifier, TmdbMovieDetailState>(
  (ref) => TmdbMovieDetailNotifier(ref),
);

class TmdbMovieDetailState {
  final TmdbMovieDetail? movie;
  final bool isLoading;
  final String? error;

  const TmdbMovieDetailState({
    this.movie,
    this.isLoading = false,
    this.error,
  });

  TmdbMovieDetailState copyWith({
    TmdbMovieDetail? movie,
    bool? isLoading,
    String? error,
  }) {
    return TmdbMovieDetailState(
      movie: movie ?? this.movie,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class TmdbMovieDetailNotifier extends StateNotifier<TmdbMovieDetailState> {
  final Ref ref;
  bool _isRequesting = false;

  TmdbMovieDetailNotifier(this.ref) : super(const TmdbMovieDetailState());

  Future<void> loadMovieDetail(String movieId) async {
    if (_isRequesting) return;
    _isRequesting = true;
    state = state.copyWith(isLoading: true, error: null);

    try {
      final movie = await ref.read(tmdbApiServiceProvider).getMovieDetail(movieId);
      state = state.copyWith(movie: movie, isLoading: false, error: null);
    } on TmdbException catch (error) {
      state = state.copyWith(isLoading: false, error: error.message);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: '加载失败: $error');
    } finally {
      _isRequesting = false;
    }
  }

  void clear() {
    state = const TmdbMovieDetailState();
  }
}
