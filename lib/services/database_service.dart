import 'dart:convert';
import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/movie.dart';
import '../models/cast.dart';
import '../models/app_settings.dart';
import '../models/notification.dart';
import '../models/named_item.dart';
import '../models/custom_movie_tag.dart';
import '../models/ai_tagging_result.dart';
import 'movie_lookup_resolver.dart';

class DatabaseService {
  static const String movieBox = 'movies';
  static const String settingsBox = 'settings';
  static const String notificationsBox = 'notifications';
  static const String customMovieTagsBox = 'custom_movie_tags';
  static const String movieCustomTagLinksBox = 'movie_custom_tag_links';
  static const String movieRelationsBox = 'movie_relations';
  static const String aiTaggingResultsBox = 'ai_tagging_results';
  static const String _legacyPersonDetailsBox = 'stars';
  static bool _isInitialized = false;
  static String? _customPath;
  static int _customMovieTagSequence = 0;

  static Future<void> init({String? customPath}) async {
    if (_isInitialized) return;

    _customPath = customPath;

    if (customPath != null) {
      Hive.init(customPath);
    } else {
      await Hive.initFlutter();
    }

    await _deleteLegacyBoxIfPresent(_legacyPersonDetailsBox);

    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(CastAdapter());
    }
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(MovieAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(AppSettingsAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(AppNotificationAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(AppNotificationTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(SampleInfoAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(MagnetInfoAdapter());
    }
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapter(NamedItemAdapter());
    }
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(CustomMovieTagAdapter());
    }
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(MovieCustomTagLinkAdapter());
    }
    if (!Hive.isAdapterRegistered(12)) {
      Hive.registerAdapter(AiTaggingResultAdapter());
    }

    try {
      // Open boxes without deleting user data on failure.
      await _openRequiredBox(movieBox, () => Hive.openBox<Movie>(movieBox));
      await _openRequiredBox(notificationsBox,
          () => Hive.openBox<AppNotification>(notificationsBox));
      await _openRequiredBox(customMovieTagsBox,
          () => Hive.openBox<CustomMovieTag>(customMovieTagsBox));
      await _openRequiredBox(movieCustomTagLinksBox,
          () => Hive.openBox<MovieCustomTagLink>(movieCustomTagLinksBox));
      await _openRequiredBox(
          movieRelationsBox, () => Hive.openBox(movieRelationsBox));
      await _openRequiredBox(aiTaggingResultsBox,
          () => Hive.openBox<AiTaggingResult>(aiTaggingResultsBox));

      final box = await _openRequiredBox(
          settingsBox, () => Hive.openBox<AppSettings>(settingsBox));
      final existing = box.get('settings');
      if (existing == null) {
        await box.put('settings', AppSettings());
      }
    } catch (_) {
      _isInitialized = false;
      _customPath = null;
      rethrow;
    }

    _isInitialized = true;
  }

  // Retry once for transient failures, but do not delete persisted boxes.
  static Future<T?> _safeOpenBox<T>(
      String boxName, Future<T> Function() openFn) async {
    try {
      return await openFn();
    } catch (e) {
      print('Error opening box $boxName: $e');
      try {
        // Retry once in case the first open failed due to a transient lock.
        print('Retrying box open without deleting data: $boxName');
        // 再次尝试打开
        return await openFn();
      } catch (e2) {
        print('Failed to recover box $boxName: $e2');
        return null;
      }
    }
  }

  static Future<T> _openRequiredBox<T>(
      String boxName, Future<T> Function() openFn) async {
    final box = await _safeOpenBox(boxName, openFn);
    if (box == null) {
      throw StateError('Failed to open required Hive box: $boxName');
    }
    return box;
  }

  static Future<void> _deleteLegacyBoxIfPresent(String boxName) async {
    try {
      if (await Hive.boxExists(boxName)) {
        await Hive.deleteBoxFromDisk(boxName);
      }
    } catch (e) {
      print('Error deleting legacy Hive box $boxName: $e');
    }
  }

  static String? get currentPath => _customPath;

  static Box<Movie> get movieBoxInstance => Hive.box<Movie>(movieBox);

  static Box<AppSettings>? get settingsBoxInstance {
    try {
      return Hive.box<AppSettings>(settingsBox);
    } catch (_) {
      return null;
    }
  }

  static List<Movie> getAllMovies() {
    return movieBoxInstance.values.toList();
  }

  static AppSettings getSettings() {
    try {
      final box = settingsBoxInstance;
      if (box != null && box.isOpen) {
        final settings = box.get('settings');
        if (settings != null) {
          return settings;
        }
      }
      return AppSettings();
    } catch (_) {
      return AppSettings();
    }
  }

  static Future<AppSettings> getSettingsAsync() async {
    try {
      final box = await Hive.openBox<AppSettings>(settingsBox);
      final settings = box.get('settings');
      return settings ?? AppSettings();
    } catch (_) {
      return AppSettings();
    }
  }

  static Future<void> saveSettings(AppSettings settings) async {
    try {
      print('[DatabaseService] saveSettings called');
      final box = settingsBoxInstance;
      if (box != null && box.isOpen) {
        print('[DatabaseService] Box is open, saving...');
        await box.put('settings', settings);
        print('[DatabaseService] Settings saved successfully');
      } else {
        print('[DatabaseService] Box not open, opening...');
        final newBox = await Hive.openBox<AppSettings>(settingsBox);
        await newBox.put('settings', settings);
        print(
            '[DatabaseService] Settings saved successfully after opening box');
      }
    } catch (e) {
      print('[DatabaseService] Error saving settings: $e');
      try {
        final box = await Hive.openBox<AppSettings>(settingsBox);
        await box.put('settings', settings);
        print('[DatabaseService] Settings saved successfully after recovering');
      } catch (_) {
        print('[DatabaseService] Failed to save settings after recovering');
        throw StateError('Failed to save settings: $e');
      }
    }
  }

  static Future<void> addMovie(Movie movie) async {
    print('[DatabaseService] addMovie called for id: ${movie.id}');
    print('[DatabaseService] - director: ${movie.director}');
    print('[DatabaseService] - producer: ${movie.producer}');
    print('[DatabaseService] - publisher: ${movie.publisher}');
    print('[DatabaseService] - series: ${movie.series}');
    print('[DatabaseService] - tags count: ${movie.tags?.length}');
    print('[DatabaseService] - cast count: ${movie.cast.length}');
    print('[DatabaseService] - magnets count: ${movie.magnets?.length}');
    await movieBoxInstance.put(movie.id, movie);
    print('[DatabaseService] Movie saved successfully');

    // 验证保存结果
    final saved = movieBoxInstance.get(movie.id);
    if (saved != null) {
      print('[DatabaseService] Verifying saved movie:');
      print('[DatabaseService]   - director: ${saved.director}');
      print('[DatabaseService]   - producer: ${saved.producer}');
      print('[DatabaseService]   - publisher: ${saved.publisher}');
      print('[DatabaseService]   - series: ${saved.series}');
      print('[DatabaseService]   - tags count: ${saved.tags?.length}');
      print('[DatabaseService]   - cast count: ${saved.cast.length}');
      print('[DatabaseService]   - magnets count: ${saved.magnets?.length}');
    } else {
      print('[DatabaseService] Error: Saved movie not found!');
    }
  }

  static Movie? getMovie(String id) {
    print('[DatabaseService] getMovie called for id: $id');
    final movie = movieBoxInstance.get(id);
    if (movie != null) {
      print('[DatabaseService] - director: ${movie.director}');
      print('[DatabaseService] - producer: ${movie.producer}');
      print('[DatabaseService] - publisher: ${movie.publisher}');
      print('[DatabaseService] - series: ${movie.series}');
      print('[DatabaseService] - tags count: ${movie.tags?.length}');
      print('[DatabaseService] - cast count: ${movie.cast.length}');
      print('[DatabaseService] - magnets count: ${movie.magnets?.length}');
    }
    return movie;
  }

  static Future<void> addMovies(List<Movie> movies) async {
    for (final movie in movies) {
      await movieBoxInstance.put(movie.id, movie);
    }
  }

  static Future<void> updateMovie(Movie movie) async {
    await movieBoxInstance.put(movie.id, movie);
  }

  static Future<Movie> updateMovieWithLatest(
    String movieId,
    Movie Function(Movie latestMovie) update,
  ) async {
    final latestMovie = getMovie(movieId);
    if (latestMovie == null) {
      throw StateError('Movie not found: $movieId');
    }

    final updatedMovie = update(latestMovie);
    if (updatedMovie.id != latestMovie.id) {
      throw StateError('Movie id cannot be changed here: $movieId');
    }

    await updateMovie(updatedMovie);
    return updatedMovie;
  }

  static Movie? findMovieByCode(String code, {String? excludeMovieId}) {
    final normalizedCode = _normalizeMovieCodeForLookup(code);
    if (normalizedCode.isEmpty) return null;

    for (final movie in movieBoxInstance.values) {
      if (excludeMovieId != null && movie.id == excludeMovieId) continue;
      if (_normalizeMovieCodeForLookup(movie.code) == normalizedCode) {
        return movie;
      }
    }
    return null;
  }

  static Movie? findMovieByRelationId(
    String relatedId, {
    String? excludeMovieId,
  }) {
    final trimmedRelatedId = relatedId.trim();
    if (trimmedRelatedId.isEmpty) {
      return null;
    }

    final directMatch = getMovie(trimmedRelatedId);
    if (directMatch != null && directMatch.id != excludeMovieId) {
      return directMatch;
    }

    final byCode = findMovieByCode(
      trimmedRelatedId,
      excludeMovieId: excludeMovieId,
    );
    if (byCode != null) {
      return byCode;
    }

    final relationLookupCode = _normalizeMovieCodeForLookup(
      normalizeMovieLookupId(trimmedRelatedId),
    );
    if (relationLookupCode.isEmpty) {
      return null;
    }

    for (final movie in movieBoxInstance.values) {
      if (excludeMovieId != null && movie.id == excludeMovieId) continue;
      final movieLookupCode = _normalizeMovieCodeForLookup(
        normalizeMovieLookupId(movie.code),
      );
      if (movieLookupCode == relationLookupCode) {
        return movie;
      }
    }
    return null;
  }

  static Movie copyMovieWithUpdatedCode(Movie movie, String newCode) {
    final normalizedNewCode = _sanitizeMovieCode(newCode);
    if (normalizedNewCode.isEmpty) {
      throw ArgumentError.value(newCode, 'newCode', 'Movie code is empty');
    }

    final existingMovie = findMovieByCode(
      normalizedNewCode,
      excludeMovieId: movie.id,
    );
    if (existingMovie != null) {
      throw StateError('Movie code already exists: $normalizedNewCode');
    }

    final shouldUpdateTitle = _normalizeMovieCodeForLookup(movie.name) ==
        _normalizeMovieCodeForLookup(movie.code);

    return movie.copyWith(
      code: normalizedNewCode,
      name: shouldUpdateTitle ? normalizedNewCode : movie.name,
    );
  }

  static Future<Movie> updateMovieCode(Movie movie, String newCode) async {
    final latestMovie = getMovie(movie.id) ?? movie;
    final updatedMovie = copyMovieWithUpdatedCode(latestMovie, newCode);
    await updateMovie(updatedMovie);
    return updatedMovie;
  }

  static Future<void> deleteMovie(String id) async {
    await movieBoxInstance.delete(id);
    await movieRelationsBoxInstance.delete(id);
    final linksToDelete = movieCustomTagLinksBoxInstance.values
        .where((link) => link.movieId == id)
        .toList();
    for (final link in linksToDelete) {
      await movieCustomTagLinksBoxInstance.delete(link.id);
    }
    final aiResultsToDelete = aiTaggingResultsBoxInstance.values
        .where((result) => result.movieId == id)
        .toList();
    for (final result in aiResultsToDelete) {
      await aiTaggingResultsBoxInstance.delete(result.id);
    }
  }

  static Future<void> toggleFavorite(String movieId) async {
    final movie = getMovie(movieId);
    if (movie != null) {
      final updated = movie.copyWith(isFavorite: !movie.safeIsFavorite);
      await updateMovie(updated);
    }
  }

  static String _sanitizeMovieCode(String code) {
    return code.trim().toUpperCase();
  }

  static String _normalizeMovieCodeForLookup(String code) {
    return code.replaceAll(RegExp(r'[-_\s]'), '').toLowerCase();
  }

  static Future<void> updateWatchProgress(
    String movieId,
    double positionInSeconds,
  ) async {
    final movie = getMovie(movieId);
    if (movie != null) {
      final updated = movie.copyWith(
        lastWatchPosition: positionInSeconds,
        lastWatchedAt: DateTime.now().millisecondsSinceEpoch,
        playCount: movie.safePlayCount + 1,
      );
      await updateMovie(updated);
    }
  }

  static Future<void> clearAllTranslations() async {
    final movies = getAllMovies();
    for (final movie in movies) {
      if (movie.translatedName != null || movie.translatedTags != null) {
        final updated = movie.copyWith(clearTranslated: true);
        await updateMovie(updated);
      }
    }
  }

  static Box<AppNotification> get notificationsBoxInstance =>
      Hive.box<AppNotification>(notificationsBox);

  static List<AppNotification> getAllNotifications() {
    final notifications = notificationsBoxInstance.values.toList();
    notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return notifications;
  }

  static List<AppNotification> getUnreadNotifications() {
    return getAllNotifications().where((n) => !n.isRead).toList();
  }

  static Future<void> addNotification(AppNotification notification) async {
    await notificationsBoxInstance.put(notification.id, notification);
  }

  static Future<void> markAsRead(String notificationId) async {
    final notification = notificationsBoxInstance.get(notificationId);
    if (notification != null) {
      final updated = notification.copyWith(isRead: true);
      await notificationsBoxInstance.put(notificationId, updated);
    }
  }

  static Future<void> markAllAsRead() async {
    final notifications = getAllNotifications();
    for (final notification in notifications) {
      if (!notification.isRead) {
        await markAsRead(notification.id);
      }
    }
  }

  static Future<void> deleteNotification(String notificationId) async {
    await notificationsBoxInstance.delete(notificationId);
  }

  static Future<void> clearAllNotifications() async {
    await notificationsBoxInstance.clear();
  }

  static Box<CustomMovieTag> get customMovieTagsBoxInstance =>
      Hive.box<CustomMovieTag>(customMovieTagsBox);

  static Box<MovieCustomTagLink> get movieCustomTagLinksBoxInstance =>
      Hive.box<MovieCustomTagLink>(movieCustomTagLinksBox);

  static Box<dynamic> get movieRelationsBoxInstance =>
      Hive.box<dynamic>(movieRelationsBox);

  static Box<AiTaggingResult> get aiTaggingResultsBoxInstance =>
      Hive.box<AiTaggingResult>(aiTaggingResultsBox);

  static List<String> getMovieRelatedIds(String movieId) {
    final raw = movieRelationsBoxInstance.get(movieId);
    if (raw is! List) {
      return const <String>[];
    }

    final normalized = <String>{};
    for (final item in raw) {
      if (item is String) {
        final id = item.trim();
        if (id.isNotEmpty) {
          normalized.add(id);
        }
      }
    }
    return normalized.toList(growable: false);
  }

  static Future<void> setMovieRelatedIds(
    String movieId,
    Iterable<String> relatedIds,
  ) async {
    final normalized = <String>{};
    for (final rawId in relatedIds) {
      final id = rawId.trim();
      if (id.isNotEmpty && id != movieId) {
        normalized.add(id);
      }
    }

    if (normalized.isEmpty) {
      await movieRelationsBoxInstance.delete(movieId);
      return;
    }

    await movieRelationsBoxInstance.put(
      movieId,
      normalized.toList(growable: false),
    );
  }

  static String _makeMovieTagLinkId(String movieId, String tagId) {
    return '$movieId::$tagId';
  }

  static List<CustomMovieTag> getAllCustomMovieTags() {
    final tags = customMovieTagsBoxInstance.values.toList();
    tags.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return tags;
  }

  static List<MovieCustomTagLink> getAllMovieCustomTagLinks() {
    return movieCustomTagLinksBoxInstance.values.toList();
  }

  static Future<CustomMovieTag> createCustomMovieTag(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Custom movie tag name is empty');
    }

    for (final tag in customMovieTagsBoxInstance.values) {
      if (tag.name == trimmedName) {
        return tag;
      }
    }

    final now = DateTime.now().microsecondsSinceEpoch;
    _customMovieTagSequence++;
    final tag = CustomMovieTag(
      id: 'tag_${now}_$_customMovieTagSequence',
      name: trimmedName,
      createdAt: now,
    );
    await customMovieTagsBoxInstance.put(tag.id, tag);
    return tag;
  }

  static Future<void> renameCustomMovieTag(String tagId, String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Custom movie tag name is empty');
    }

    final tag = customMovieTagsBoxInstance.get(tagId);
    if (tag == null) return;
    await customMovieTagsBoxInstance.put(
      tagId,
      tag.copyWith(name: trimmedName),
    );
  }

  static Future<void> deleteCustomMovieTag(String tagId) async {
    await customMovieTagsBoxInstance.delete(tagId);

    final linksToDelete = movieCustomTagLinksBoxInstance.values
        .where((link) => link.tagId == tagId)
        .toList();
    for (final link in linksToDelete) {
      await movieCustomTagLinksBoxInstance.delete(link.id);
    }
  }

  static Future<void> setMovieCustomTags(
    String movieId,
    Set<String> tagIds,
  ) async {
    final existingLinks = movieCustomTagLinksBoxInstance.values
        .where((link) => link.movieId == movieId)
        .toList();
    final existingTagIds = existingLinks.map((link) => link.tagId).toSet();

    for (final link in existingLinks) {
      if (!tagIds.contains(link.tagId)) {
        await movieCustomTagLinksBoxInstance.delete(link.id);
      }
    }

    final now = DateTime.now().microsecondsSinceEpoch;
    for (final tagId in tagIds) {
      if (existingTagIds.contains(tagId)) continue;
      if (!customMovieTagsBoxInstance.containsKey(tagId)) continue;

      final link = MovieCustomTagLink(
        id: _makeMovieTagLinkId(movieId, tagId),
        movieId: movieId,
        tagId: tagId,
        createdAt: now,
      );
      await movieCustomTagLinksBoxInstance.put(link.id, link);
    }
  }

  static Future<void> addMovieToCustomTag(String movieId, String tagId) async {
    if (!customMovieTagsBoxInstance.containsKey(tagId)) return;

    final linkId = _makeMovieTagLinkId(movieId, tagId);
    if (movieCustomTagLinksBoxInstance.containsKey(linkId)) return;

    final link = MovieCustomTagLink(
      id: linkId,
      movieId: movieId,
      tagId: tagId,
      createdAt: DateTime.now().microsecondsSinceEpoch,
    );
    await movieCustomTagLinksBoxInstance.put(link.id, link);
  }

  static Future<void> removeMovieFromCustomTag(
    String movieId,
    String tagId,
  ) async {
    await movieCustomTagLinksBoxInstance.delete(
      _makeMovieTagLinkId(movieId, tagId),
    );
  }

  static Set<String> getCustomTagIdsForMovie(String movieId) {
    return movieCustomTagLinksBoxInstance.values
        .where((link) => link.movieId == movieId)
        .map((link) => link.tagId)
        .toSet();
  }

  static List<CustomMovieTag> getCustomTagsForMovie(String movieId) {
    final tagIds = getCustomTagIdsForMovie(movieId);
    final tags = tagIds
        .map((tagId) => customMovieTagsBoxInstance.get(tagId))
        .whereType<CustomMovieTag>()
        .toList();
    tags.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return tags;
  }

  static List<Movie> getMoviesForCustomTag(String tagId) {
    final movies = movieCustomTagLinksBoxInstance.values
        .where((link) => link.tagId == tagId)
        .map((link) => movieBoxInstance.get(link.movieId))
        .whereType<Movie>()
        .toList();
    movies.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return movies;
  }

  static List<Movie> getMoviesWithAnyCustomTag() {
    final movieIds = movieCustomTagLinksBoxInstance.values
        .map((link) => link.movieId)
        .toSet();
    final movies = movieIds
        .map((movieId) => movieBoxInstance.get(movieId))
        .whereType<Movie>()
        .toList();
    movies.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return movies;
  }

  static Map<String, int> getCustomMovieTagCounts() {
    final counts = <String, int>{};
    for (final link in movieCustomTagLinksBoxInstance.values) {
      if (!movieBoxInstance.containsKey(link.movieId)) continue;
      counts[link.tagId] = (counts[link.tagId] ?? 0) + 1;
    }
    return counts;
  }

  // ==================== 数据导出/导入 ====================

  /// 导出所有数据到指定文件
  static Future<void> saveAiTaggingResult(AiTaggingResult result) async {
    await aiTaggingResultsBoxInstance.put(result.id, result);
  }

  static AiTaggingResult? getAiTaggingResult(String id) {
    return aiTaggingResultsBoxInstance.get(id);
  }

  static List<AiTaggingResult> getAllAiTaggingResults({String? status}) {
    final results = aiTaggingResultsBoxInstance.values.where((result) {
      return status == null || result.status == status;
    }).toList();
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return results;
  }

  static AiTaggingResult? getLatestAiTaggingResultForMovie(String movieId) {
    final results = aiTaggingResultsBoxInstance.values
        .where((result) => result.movieId == movieId)
        .toList();
    if (results.isEmpty) return null;
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return results.first;
  }

  static Future<void> updateAiTaggingResultStatus(
    String id,
    String status, {
    String? errorMessage,
  }) async {
    final result = aiTaggingResultsBoxInstance.get(id);
    if (result == null) return;
    await aiTaggingResultsBoxInstance.put(
      id,
      result.copyWith(
        status: status,
        errorMessage: errorMessage,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  static Future<void> exportData(
    String filePath, {
    bool includeSensitiveSettings = false,
  }) async {
    final exportData = <String, dynamic>{
      'version': 1,
      'exportTime': DateTime.now().millisecondsSinceEpoch,
      'movies': getAllMovies().map((m) => _movieToJson(m)).toList(),
      'settings': _settingsToJson(
        getSettings(),
        includeSensitiveSettings: includeSensitiveSettings,
      ),
      'sensitiveSettingsRedacted': !includeSensitiveSettings,
      'customMovieTags': getAllCustomMovieTags()
          .map((tag) => _customMovieTagToJson(tag))
          .toList(),
      'movieCustomTagLinks': getAllMovieCustomTagLinks()
          .map((link) => _movieCustomTagLinkToJson(link))
          .toList(),
      'aiTaggingResults': getAllAiTaggingResults()
          .map((taggingResult) => _aiTaggingResultToJson(taggingResult))
          .toList(),
    };

    final jsonString = jsonEncode(exportData);
    final file = File(filePath);
    await file.writeAsString(jsonString, encoding: utf8);
  }

  /// 从指定文件导入数据
  static Future<ImportResult> importData(String filePath) async {
    final result = ImportResult();

    try {
      final file = File(filePath);
      final jsonString = await file.readAsString(encoding: utf8);
      final importData = jsonDecode(jsonString) as Map<String, dynamic>;

      // 检查版本
      final version = importData['version'] as int? ?? 0;
      if (version > 1) {
        result.error = '不支持的数据格式版本';
        return result;
      }

      // 导入电影
      final moviesData = importData['movies'] as List<dynamic>?;
      if (moviesData != null) {
        for (final movieJson in moviesData) {
          try {
            final movie = _movieFromJson(movieJson as Map<String, dynamic>);
            await movieBoxInstance.put(movie.id, movie);
            result.importedMovies++;
          } catch (e) {
            result.failedMovies++;
            print('[DatabaseService] Failed to import movie: $e');
          }
        }
      }

      // 导入设置
      final sensitiveSettingsRedacted =
          importData['sensitiveSettingsRedacted'] as bool? ?? false;

      final settingsData = importData['settings'] as Map<String, dynamic>?;
      if (settingsData != null) {
        try {
          var settings = _settingsFromJson(settingsData);
          if (sensitiveSettingsRedacted) {
            settings = _preserveSensitiveSettings(
              imported: settings,
              current: getSettings(),
            );
          }
          await saveSettings(settings);
          result.importedSettings = true;
        } catch (e) {
          print('[DatabaseService] Failed to import settings: $e');
        }
      }

      final customMovieTagsData =
          importData['customMovieTags'] as List<dynamic>?;
      if (customMovieTagsData != null) {
        for (final tagJson in customMovieTagsData) {
          try {
            final tag =
                _customMovieTagFromJson(tagJson as Map<String, dynamic>);
            await customMovieTagsBoxInstance.put(tag.id, tag);
            result.importedCustomMovieTags++;
          } catch (e) {
            result.failedCustomMovieTags++;
            print('[DatabaseService] Failed to import custom movie tag: $e');
          }
        }
      }

      final movieCustomTagLinksData =
          importData['movieCustomTagLinks'] as List<dynamic>?;
      if (movieCustomTagLinksData != null) {
        for (final linkJson in movieCustomTagLinksData) {
          try {
            final link =
                _movieCustomTagLinkFromJson(linkJson as Map<String, dynamic>);
            if (!movieBoxInstance.containsKey(link.movieId) ||
                !customMovieTagsBoxInstance.containsKey(link.tagId)) {
              result.failedMovieCustomTagLinks++;
              continue;
            }
            await movieCustomTagLinksBoxInstance.put(link.id, link);
            result.importedMovieCustomTagLinks++;
          } catch (e) {
            result.failedMovieCustomTagLinks++;
            print(
                '[DatabaseService] Failed to import movie custom tag link: $e');
          }
        }
      }

      final aiTaggingResultsData =
          importData['aiTaggingResults'] as List<dynamic>?;
      if (aiTaggingResultsData != null) {
        for (final taggingResultJson in aiTaggingResultsData) {
          try {
            final taggingResult = _aiTaggingResultFromJson(
              taggingResultJson as Map<String, dynamic>,
            );
            if (!movieBoxInstance.containsKey(taggingResult.movieId)) {
              result.failedAiTaggingResults++;
              continue;
            }
            await aiTaggingResultsBoxInstance.put(
              taggingResult.id,
              taggingResult,
            );
            result.importedAiTaggingResults++;
          } catch (e) {
            result.failedAiTaggingResults++;
            print('[DatabaseService] Failed to import AI tagging result: $e');
          }
        }
      }

      result.success = true;
    } catch (e) {
      result.error = e.toString();
      print('[DatabaseService] Import failed: $e');
    }

    return result;
  }

  // 辅助方法：Movie <-> JSON
  static Map<String, dynamic> _movieToJson(Movie movie) {
    return {
      'id': movie.id,
      'name': movie.name,
      'path': movie.path,
      'size': movie.size,
      'createdAt': movie.createdAt,
      'cast': movie.cast.map((c) => _castToJson(c)).toList(),
      'tags': movie.tags?.map((t) => _namedItemToJson(t)).toList(),
      'coverUrl': movie.coverUrl,
      'originalCoverUrl': movie.originalCoverUrl,
      'isCoverCropped': movie.isCoverCropped,
      'backdropUrl': movie.backdropUrl,
      'code': movie.code,
      'releaseDate': movie.releaseDate,
      'length': movie.length,
      'videoFilePaths': movie.videoFilePaths,
      'subtitleFilePaths': movie.subtitleFilePaths,
      'isFavorite': movie.isFavorite,
      'lastWatchPosition': movie.lastWatchPosition,
      'lastWatchedAt': movie.lastWatchedAt,
      'playCount': movie.playCount,
      'translatedName': movie.translatedName,
      'translatedTags': movie.translatedTags,
      'translatedPlot': movie.translatedPlot,
      'samples': movie.samples?.map((s) => _sampleInfoToJson(s)).toList(),
      'magnets': movie.magnets?.map((m) => _magnetInfoToJson(m)).toList(),
      'director':
          movie.director != null ? _namedItemToJson(movie.director!) : null,
      'producer':
          movie.producer != null ? _namedItemToJson(movie.producer!) : null,
      'publisher':
          movie.publisher != null ? _namedItemToJson(movie.publisher!) : null,
      'series': movie.series != null ? _namedItemToJson(movie.series!) : null,
    };
  }

  static Movie _movieFromJson(Map<String, dynamic> json) {
    return Movie(
      id: json['id'] as String,
      name: json['name'] as String,
      path: json['path'] as String?,
      size: (json['size'] as num?)?.toDouble(),
      createdAt: json['createdAt'] as int,
      cast: (json['cast'] as List<dynamic>?)
              ?.map((e) => _castFromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      tags: (json['tags'] as List<dynamic>?)
          ?.map((e) => _namedItemFromJson(e as Map<String, dynamic>))
          .toList(),
      coverUrl: json['coverUrl'] as String?,
      originalCoverUrl: json['originalCoverUrl'] as String?,
      isCoverCropped: json['isCoverCropped'] as bool?,
      backdropUrl: json['backdropUrl'] as String?,
      code: json['code'] as String,
      releaseDate: json['releaseDate'] as String?,
      length: json['length'] as int?,
      videoFilePaths: (json['videoFilePaths'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      subtitleFilePaths: (json['subtitleFilePaths'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      isFavorite: json['isFavorite'] as bool?,
      lastWatchPosition: (json['lastWatchPosition'] as num?)?.toDouble(),
      lastWatchedAt: json['lastWatchedAt'] as int?,
      playCount: json['playCount'] as int?,
      translatedName: json['translatedName'] as String?,
      translatedTags: (json['translatedTags'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      translatedPlot: json['translatedPlot'] as String?,
      samples: (json['samples'] as List<dynamic>?)
          ?.map((e) => _sampleInfoFromJson(e as Map<String, dynamic>))
          .toList(),
      magnets: (json['magnets'] as List<dynamic>?)
          ?.map((e) => _magnetInfoFromJson(e as Map<String, dynamic>))
          .toList(),
      director: json['director'] != null
          ? _namedItemFromJson(json['director'] as Map<String, dynamic>)
          : null,
      producer: json['producer'] != null
          ? _namedItemFromJson(json['producer'] as Map<String, dynamic>)
          : null,
      publisher: json['publisher'] != null
          ? _namedItemFromJson(json['publisher'] as Map<String, dynamic>)
          : null,
      series: json['series'] != null
          ? _namedItemFromJson(json['series'] as Map<String, dynamic>)
          : null,
    );
  }

  static Map<String, dynamic> _castToJson(Cast cast) {
    return {
      'id': cast.id,
      'name': cast.name,
      'imageUrl': cast.imageUrl,
    };
  }

  static Cast _castFromJson(Map<String, dynamic> json) {
    return Cast(
      id: json['id'] as String,
      name: json['name'] as String,
      imageUrl: json['imageUrl'] as String?,
    );
  }

  static Map<String, dynamic> _namedItemToJson(NamedItem item) {
    return {
      'id': item.id,
      'name': item.name,
    };
  }

  static NamedItem _namedItemFromJson(Map<String, dynamic> json) {
    return NamedItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
    );
  }

  static Map<String, dynamic> _sampleInfoToJson(SampleInfo sample) {
    return {
      'id': sample.id,
      'src': sample.src,
      'thumbnail': sample.thumbnail,
      'alt': sample.alt,
    };
  }

  static SampleInfo _sampleInfoFromJson(Map<String, dynamic> json) {
    return SampleInfo(
      id: json['id'] as String? ?? '',
      src: json['src'] as String? ?? '',
      thumbnail: json['thumbnail'] as String? ?? '',
      alt: json['alt'] as String? ?? '',
    );
  }

  static Map<String, dynamic> _magnetInfoToJson(MagnetInfo magnet) {
    return {
      'id': magnet.id,
      'link': magnet.link,
      'isHD': magnet.isHD,
      'title': magnet.title,
      'size': magnet.size,
      'numberSize': magnet.numberSize,
      'shareDate': magnet.shareDate,
      'hasSubtitle': magnet.hasSubtitle,
    };
  }

  static MagnetInfo _magnetInfoFromJson(Map<String, dynamic> json) {
    return MagnetInfo(
      id: json['id'] as String? ?? '',
      link: json['link'] as String? ?? '',
      isHD: json['isHD'] as bool? ?? false,
      title: json['title'] as String? ?? '',
      size: json['size'] as String? ?? '',
      numberSize: json['numberSize'] as int? ?? 0,
      shareDate: json['shareDate'] as String? ?? '',
      hasSubtitle: json['hasSubtitle'] as bool? ?? false,
    );
  }

  static Map<String, dynamic> _customMovieTagToJson(CustomMovieTag tag) {
    return {
      'id': tag.id,
      'name': tag.name,
      'createdAt': tag.createdAt,
    };
  }

  static CustomMovieTag _customMovieTagFromJson(Map<String, dynamic> json) {
    return CustomMovieTag(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: json['createdAt'] as int,
    );
  }

  static Map<String, dynamic> _movieCustomTagLinkToJson(
    MovieCustomTagLink link,
  ) {
    return {
      'id': link.id,
      'movieId': link.movieId,
      'tagId': link.tagId,
      'createdAt': link.createdAt,
    };
  }

  static MovieCustomTagLink _movieCustomTagLinkFromJson(
    Map<String, dynamic> json,
  ) {
    return MovieCustomTagLink(
      id: json['id'] as String,
      movieId: json['movieId'] as String,
      tagId: json['tagId'] as String,
      createdAt: json['createdAt'] as int,
    );
  }

  static Map<String, dynamic> _aiTaggingResultToJson(
    AiTaggingResult taggingResult,
  ) {
    return {
      'id': taggingResult.id,
      'movieId': taggingResult.movieId,
      'modelId': taggingResult.modelId,
      'inputHash': taggingResult.inputHash,
      'titleSegmentsJson': taggingResult.titleSegmentsJson,
      'matchedTagsJson': taggingResult.matchedTagsJson,
      'status': taggingResult.status,
      'createdAt': taggingResult.createdAt,
      'updatedAt': taggingResult.updatedAt,
      'rawOutput': taggingResult.rawOutput,
      'errorMessage': taggingResult.errorMessage,
    };
  }

  static AiTaggingResult _aiTaggingResultFromJson(
    Map<String, dynamic> json,
  ) {
    return AiTaggingResult(
      id: json['id'] as String,
      movieId: json['movieId'] as String,
      modelId: json['modelId'] as String,
      inputHash: json['inputHash'] as String,
      titleSegmentsJson: json['titleSegmentsJson'] as String,
      matchedTagsJson: json['matchedTagsJson'] as String,
      status: json['status'] as String,
      createdAt: json['createdAt'] as int,
      updatedAt: json['updatedAt'] as int,
      rawOutput: json['rawOutput'] as String? ?? '',
      errorMessage: json['errorMessage'] as String?,
    );
  }

  static Map<String, dynamic> _settingsToJson(
    AppSettings settings, {
    bool includeSensitiveSettings = false,
  }) {
    return {
      'videoFolders': settings.videoFolders,
      'playbackSpeed': settings.playbackSpeed,
      'autoResumePlayback': settings.autoResumePlayback,
      'showSubtitlesByDefault': settings.showSubtitlesByDefault,
      'subtitleFontSize': settings.subtitleFontSize,
      'localAssetManagerPath': settings.localAssetManagerPath,
      'aiTranslationEnabled': settings.aiTranslationEnabled,
      'selectedModelId': settings.selectedModelId,
      'customModelsPath': settings.customModelsPath,
      'aiThreadCount': settings.aiThreadCount,
      'fallbackToOriginal': settings.fallbackToOriginal,
      'unloadModelAfterAiTagging': settings.unloadModelAfterAiTagging,
      'dataStoragePath': settings.dataStoragePath,
      'castTags': settings.castTags,
      'apiBaseUrl': settings.apiBaseUrl,
      'proxyEnabled': settings.proxyEnabled,
      'proxyType': settings.proxyType,
      'proxyHost': settings.proxyHost,
      'proxyPort': settings.proxyPort,
      'proxyUsername': includeSensitiveSettings ? settings.proxyUsername : null,
      'proxyPassword': includeSensitiveSettings ? settings.proxyPassword : null,
      'cacheEnabled': settings.cacheEnabled,
      'cachePath': settings.cachePath,
      'maxCacheSizeMB': settings.maxCacheSizeMB,
      'maxCacheFiles': settings.maxCacheFiles,
      'useAria2ForDownloads': settings.useAria2ForDownloads,
      'aria2RpcPort': settings.aria2RpcPort,
      'aria2RpcSecret':
          includeSensitiveSettings ? settings.aria2RpcSecret : null,
      'aria2MaxConcurrentDownloads': settings.aria2MaxConcurrentDownloads,
      'aria2MaxConnectionPerServer': settings.aria2MaxConnectionPerServer,
      'aria2DownloadSpeedLimitKB': settings.aria2DownloadSpeedLimitKB,
      'aria2UploadSpeedLimitKB': settings.aria2UploadSpeedLimitKB,
      'autoStartAria2': settings.autoStartAria2,
      'aria2TrackersList': settings.aria2TrackersList,
      'autoUpdateTrackers': settings.autoUpdateTrackers,
      'lastTrackersUpdateTime': settings.lastTrackersUpdateTime,
      'trackersSourceUrls': settings.trackersSourceUrls,
    };
  }

  static AppSettings _settingsFromJson(Map<String, dynamic> json) {
    return AppSettings(
      videoFolders: (json['videoFolders'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      playbackSpeed: (json['playbackSpeed'] as num?)?.toDouble() ?? 1.0,
      autoResumePlayback: json['autoResumePlayback'] as bool? ?? true,
      showSubtitlesByDefault: json['showSubtitlesByDefault'] as bool? ?? true,
      subtitleFontSize: json['subtitleFontSize'] as String? ?? 'medium',
      localAssetManagerPath: json['localAssetManagerPath'] as String?,
      aiTranslationEnabled: json['aiTranslationEnabled'] as bool? ?? false,
      selectedModelId: json['selectedModelId'] as String?,
      customModelsPath: json['customModelsPath'] as String?,
      aiThreadCount: json['aiThreadCount'] as int? ?? 4,
      fallbackToOriginal: json['fallbackToOriginal'] as bool? ?? true,
      unloadModelAfterAiTagging:
          json['unloadModelAfterAiTagging'] as bool? ?? false,
      dataStoragePath: json['dataStoragePath'] as String?,
      castTags: (json['castTags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      apiBaseUrl: json['apiBaseUrl'] as String?,
      proxyEnabled: json['proxyEnabled'] as bool? ?? false,
      proxyType: json['proxyType'] as String? ?? 'http',
      proxyHost: json['proxyHost'] as String?,
      proxyPort: json['proxyPort'] as int?,
      proxyUsername: json['proxyUsername'] as String?,
      proxyPassword: json['proxyPassword'] as String?,
      cacheEnabled: json['cacheEnabled'] as bool? ?? true,
      cachePath: json['cachePath'] as String?,
      maxCacheSizeMB: json['maxCacheSizeMB'] as int? ?? 50,
      maxCacheFiles: json['maxCacheFiles'] as int? ?? 200,
      useAria2ForDownloads: json['useAria2ForDownloads'] as bool? ?? false,
      aria2RpcPort: json['aria2RpcPort'] as int? ?? 6800,
      aria2RpcSecret: json['aria2RpcSecret'] as String?,
      aria2MaxConcurrentDownloads:
          json['aria2MaxConcurrentDownloads'] as int? ?? 5,
      aria2MaxConnectionPerServer:
          json['aria2MaxConnectionPerServer'] as int? ?? 16,
      aria2DownloadSpeedLimitKB: json['aria2DownloadSpeedLimitKB'] as int? ?? 0,
      aria2UploadSpeedLimitKB: json['aria2UploadSpeedLimitKB'] as int? ?? 0,
      autoStartAria2: json['autoStartAria2'] as bool? ?? true,
      aria2TrackersList: json['aria2TrackersList'] as String?,
      autoUpdateTrackers: json['autoUpdateTrackers'] as bool? ?? false,
      lastTrackersUpdateTime: json['lastTrackersUpdateTime'] as int?,
      trackersSourceUrls: json['trackersSourceUrls'] as String?,
    );
  }

  static AppSettings _preserveSensitiveSettings({
    required AppSettings imported,
    required AppSettings current,
  }) {
    return imported.copyWith(
      proxyUsername: current.proxyUsername,
      proxyPassword: current.proxyPassword,
      aria2RpcSecret: current.aria2RpcSecret,
      clearProxyUsername: current.proxyUsername == null,
      clearProxyPassword: current.proxyPassword == null,
      clearAria2RpcSecret: current.aria2RpcSecret == null,
    );
  }
}

/// 导入结果
class ImportResult {
  bool success = false;
  String? error;
  int importedMovies = 0;
  int failedMovies = 0;
  bool importedSettings = false;
  int importedCustomMovieTags = 0;
  int failedCustomMovieTags = 0;
  int importedMovieCustomTagLinks = 0;
  int failedMovieCustomTagLinks = 0;
  int importedAiTaggingResults = 0;
  int failedAiTaggingResults = 0;

  String getSummary() {
    if (!success) {
      return '导入失败: $error';
    }
    final buffer = StringBuffer('导入成功!\n');
    buffer.writeln('电影: $importedMovies 个');
    if (failedMovies > 0) {
      buffer.writeln('失败: $failedMovies 个');
    }
    buffer.writeln('设置: ${importedSettings ? "已导入" : "未导入"}');
    buffer.writeln('自定义标签: $importedCustomMovieTags 个');
    if (failedCustomMovieTags > 0) {
      buffer.writeln('自定义标签失败: $failedCustomMovieTags 个');
    }
    buffer.writeln('影片标签关联: $importedMovieCustomTagLinks 个');
    if (failedMovieCustomTagLinks > 0) {
      buffer.writeln('影片标签关联失败: $failedMovieCustomTagLinks 个');
    }
    buffer.writeln('AI tagging results: $importedAiTaggingResults');
    if (failedAiTaggingResults > 0) {
      buffer.writeln('AI tagging result failures: $failedAiTaggingResults');
    }
    return buffer.toString();
  }
}
