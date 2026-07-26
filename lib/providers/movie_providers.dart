import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import '../models/app_settings.dart';
import '../models/custom_movie_tag.dart';
import '../services/database_service.dart';

// 刷新信号提供者，用于触发 moviesProvider 的刷新
final moviesRefreshSignal = StateProvider<int>((ref) => 0);

// 图片刷新信号，用于强制 SmartImage 重新加载图片
final imageRefreshSignal = StateProvider<int>((ref) => 0);

final customMovieTagsRefreshSignal = StateProvider<int>((ref) => 0);

// 增加刷新信号
final moviesRefreshProvider = Provider<void>((ref) {
  ref.listen(moviesRefreshSignal, (_, __) {});
});

final moviesProvider = FutureProvider<List<Movie>>((ref) async {
  // 监听刷新信号，当信号改变时重新获取数据
  ref.watch(moviesRefreshSignal);
  return DatabaseService.getAllMovies();
});

// 刷新 moviesProvider 的方法
void refreshMovies(WidgetRef ref) {
  ref.read(moviesRefreshSignal.notifier).state++;
}

void refreshCustomMovieTags(WidgetRef ref) {
  ref.read(customMovieTagsRefreshSignal.notifier).state++;
}

final customMovieTagsProvider =
    FutureProvider<List<CustomMovieTag>>((ref) async {
  ref.watch(customMovieTagsRefreshSignal);
  return DatabaseService.getAllCustomMovieTags();
});

final movieCustomTagLinksProvider =
    FutureProvider<List<MovieCustomTagLink>>((ref) async {
  ref.watch(customMovieTagsRefreshSignal);
  return DatabaseService.getAllMovieCustomTagLinks();
});

final settingsProvider = FutureProvider<AppSettings>((ref) async {
  return DatabaseService.getSettingsAsync();
});

// 代理配置状态管理
class ProxyConfigNotifier extends StateNotifier<AppSettings> {
  ProxyConfigNotifier() : super(AppSettings());

  Future<void> loadSettings() async {
    final settings = await DatabaseService.getSettingsAsync();
    state = settings;
  }

  void updateSettings(AppSettings newSettings) {
    state = newSettings;
  }
}

final proxyConfigProvider =
    StateNotifierProvider<ProxyConfigNotifier, AppSettings>((ref) {
  return ProxyConfigNotifier();
});

// 初始化代理配置
final initProxyConfigProvider = FutureProvider<void>((ref) async {
  await ref.read(proxyConfigProvider.notifier).loadSettings();
});

final favoriteMoviesProvider = Provider<List<Movie>>((ref) {
  final movies = ref.watch(moviesProvider);
  return movies.when(
    data: (data) => data.where((m) => m.safeIsFavorite).toList(),
    loading: () => [],
    error: (_, __) => [],
  );
});

final recentMoviesProvider = Provider<List<Movie>>((ref) {
  final movies = ref.watch(moviesProvider);
  return movies.when(
    data: (data) {
      final sorted = List<Movie>.from(data)
        ..sort((a, b) {
          final aDate =
              a.safeLastWatchedAt > 0 ? a.safeLastWatchedAt : a.createdAt;
          final bDate =
              b.safeLastWatchedAt > 0 ? b.safeLastWatchedAt : b.createdAt;
          return bDate.compareTo(aDate);
        });
      return sorted.take(20).toList();
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

/// 最新保存的影片provider
/// 按创建时间倒序排列，最新保存的在最上面
final newestMoviesProvider = Provider<List<Movie>>((ref) {
  final movies = ref.watch(moviesProvider);
  return movies.when(
    data: (data) {
      final sorted = List<Movie>.from(data)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return sorted;
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

final searchQueryProvider = StateProvider<String>((ref) => '');

final filteredMoviesProvider = Provider<List<Movie>>((ref) {
  final query = ref.watch(searchQueryProvider).toLowerCase();
  final movies = ref.watch(moviesProvider);

  return movies.when(
    data: (data) {
      if (query.isEmpty) return data;
      return data.where((movie) {
        return movie.name.toLowerCase().contains(query) ||
            movie.code.toLowerCase().contains(query) ||
            (movie.tags?.any((tag) => tag.name.toLowerCase().contains(query)) ??
                false) ||
            movie.cast.any((cast) => cast.name.toLowerCase().contains(query));
      }).toList();
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

/// 有本地视频文件的影片 provider
/// 筛选出 videoFilePaths 不为空且有内容的影片
final localMoviesProvider = Provider<List<Movie>>((ref) {
  final movies = ref.watch(moviesProvider);
  return movies.when(
    data: (data) {
      return data.where((movie) {
        return movie.videoFilePaths != null && movie.videoFilePaths!.isNotEmpty;
      }).toList();
    },
    loading: () => [],
    error: (_, __) => [],
  );
});
