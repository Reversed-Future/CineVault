import '../models/movie.dart';
import '../models/notification.dart';
import 'database_service.dart';
import 'movie_sync_adapter.dart';
import 'tmdb_api_service.dart';

class MovieBatchUpdater {
  static Future<MovieUpdateResult> updateSingleMovie(
    String movieId, {
    String? movieCode,
    required TmdbApiService apiService,
  }) async {
    try {
      final lookupId =
          (movieCode != null && movieCode.trim().isNotEmpty) ? movieCode : movieId;
      final detail = await apiService.getMovieDetail(lookupId);
      final updatedMovie = MovieSyncAdapter.convertAndMerge(detail);
      await DatabaseService.updateMovie(updatedMovie);

      return MovieUpdateResult(
        movieId: movieId,
        success: true,
        updatedMovie: updatedMovie,
      );
    } catch (error) {
      print('[MovieBatchUpdater] Failed to update $movieId: $error');
      return MovieUpdateResult(
        movieId: movieId,
        success: false,
        errorMessage: error.toString(),
      );
    }
  }

  static Future<BatchUpdateResult> updateAllMovies({
    required List<Movie> movies,
    required dynamic notificationNotifier,
    required TmdbApiService apiService,
    int concurrency = 3,
  }) async {
    final stopwatch = Stopwatch()..start();
    final totalMovies = movies.length;
    String? notificationId;

    try {
      notificationId = await _sendProgressNotification(
        notifier: notificationNotifier,
        title: '批量更新电影资料',
        message: '共 $totalMovies 部电影，准备更新...',
        type: AppNotificationType.info,
        progress: 0,
        taskType: 'batch_update',
      );
    } catch (error) {
      print('[MovieBatchUpdater] Failed to send progress notification: $error');
    }

    if (movies.isEmpty) {
      await _finishNotification(
        notificationNotifier,
        notificationId,
        title: '批量更新完成',
        message: '片库为空，无可更新内容',
        type: AppNotificationType.warning,
      );
      return BatchUpdateResult(
        totalCount: 0,
        successCount: 0,
        failedCount: 0,
        failedMovies: const [],
        durationMs: 0,
      );
    }

    final results = <MovieUpdateResult>[];
    final workerCount = concurrency < 1 ? 1 : concurrency;

    for (var i = 0; i < movies.length; i += workerCount) {
      if (notificationId != null) {
        final isCancelled = await _checkNotificationCancelled(
          notifier: notificationNotifier,
          notificationId: notificationId,
        );
        if (isCancelled) break;
      }

      final end = i + workerCount > movies.length ? movies.length : i + workerCount;
      final batch = movies.sublist(i, end);
      final batchResults = await Future.wait(
        batch.map((movie) => updateSingleMovie(
              movie.id,
              movieCode: movie.code,
              apiService: apiService,
            )),
      );
      results.addAll(batchResults);

      if (notificationId != null) {
        final processed = results.length;
        final successCount = results.where((result) => result.success).length;
        final failedCount = processed - successCount;
        await _updateProgressNotification(
          notifier: notificationNotifier,
          notificationId: notificationId,
          title: '批量更新电影资料',
          message: '进度 $processed/$totalMovies，成功 $successCount，失败 $failedCount',
          type: AppNotificationType.info,
          progress: ((processed / totalMovies * 100).round()).clamp(0, 100),
          isProgressing: processed < totalMovies,
        );
      }
    }

    stopwatch.stop();
    final successCount = results.where((result) => result.success).length;
    final failedMovies = results.where((result) => !result.success).toList();
    final failedCount = failedMovies.length;
    final seconds = (stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1);

    await _finishNotification(
      notificationNotifier,
      notificationId,
      title: '批量更新完成',
      message: failedCount == 0
          ? '耗时 ${seconds}s，成功更新 $successCount 部电影'
          : '耗时 ${seconds}s，成功 $successCount 部，失败 $failedCount 部',
      type: failedCount == 0
          ? AppNotificationType.success
          : AppNotificationType.warning,
    );

    return BatchUpdateResult(
      totalCount: totalMovies,
      successCount: successCount,
      failedCount: failedCount,
      failedMovies: failedMovies,
      durationMs: stopwatch.elapsedMilliseconds,
    );
  }

  static Future<void> _finishNotification(
    dynamic notifier,
    String? notificationId, {
    required String title,
    required String message,
    required AppNotificationType type,
  }) async {
    if (notificationId == null) {
      await _sendNotification(
        notifier: notifier,
        title: title,
        message: message,
        type: type,
      );
      return;
    }
    await _updateProgressNotification(
      notifier: notifier,
      notificationId: notificationId,
      title: title,
      message: message,
      type: type,
      progress: 100,
      isProgressing: false,
    );
  }

  static Future<void> _sendNotification({
    required dynamic notifier,
    required String title,
    required String message,
    AppNotificationType type = AppNotificationType.info,
  }) async {
    try {
      await notifier.addNotification(
        title: title,
        message: message,
        type: type,
      );
    } catch (error) {
      print('[MovieBatchUpdater] Failed to send notification: $error');
    }
  }

  static Future<String> _sendProgressNotification({
    required dynamic notifier,
    required String title,
    required String message,
    AppNotificationType type = AppNotificationType.info,
    int progress = 0,
    String? taskType,
  }) async {
    return notifier.addProgressNotification(
      title: title,
      message: message,
      type: type,
      initialProgress: progress,
      taskType: taskType,
    );
  }

  static Future<void> _updateProgressNotification({
    required dynamic notifier,
    required String notificationId,
    String? title,
    String? message,
    AppNotificationType? type,
    int? progress,
    bool isProgressing = true,
  }) async {
    try {
      await notifier.updateNotification(
        notificationId: notificationId,
        title: title,
        message: message,
        type: type,
        progress: progress,
        isProgressing: isProgressing,
      );
    } catch (error) {
      print('[MovieBatchUpdater] Failed to update notification: $error');
    }
  }

  static Future<bool> _checkNotificationCancelled({
    required dynamic notifier,
    required String notificationId,
  }) async {
    try {
      return await notifier.isNotificationCancelled(notificationId);
    } catch (_) {
      return false;
    }
  }
}

class MovieUpdateResult {
  final String movieId;
  final bool success;
  final Movie? updatedMovie;
  final String? errorMessage;

  MovieUpdateResult({
    required this.movieId,
    required this.success,
    this.updatedMovie,
    this.errorMessage,
  });
}

class BatchUpdateResult {
  final int totalCount;
  final int successCount;
  final int failedCount;
  final List<MovieUpdateResult> failedMovies;
  final int durationMs;

  BatchUpdateResult({
    required this.totalCount,
    required this.successCount,
    required this.failedCount,
    required this.failedMovies,
    required this.durationMs,
  });
}
