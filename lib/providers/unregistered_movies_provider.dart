import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_movie_scanner.dart';

/// 待审核影片（扫描到但未在库中）的全局状态
///
/// 为什么需要这个：
/// 1. 扫描是异步的，扫描时用户可能离开了扫描触发页面
/// 2. 弹 dialog 会被遮挡或被遗忘
/// 3. 用户需要从多个入口（通知中心、设置页面）都能访问待审核列表
class UnregisteredMoviesNotifier
    extends StateNotifier<List<ScannedMovieEntry>> {
  UnregisteredMoviesNotifier() : super(const []);

  /// 设置待审核列表（扫描完成后调用）
  void set(List<ScannedMovieEntry> entries) {
    if (entries.isEmpty) {
      LocalMovieScanner.clearPendingEntries();
    }
    state = List.unmodifiable(entries);
  }

  /// 添加新的待审核条目
  void addAll(List<ScannedMovieEntry> entries) {
    state = List.unmodifiable([...state, ...entries]);
  }

  /// 移除已审核（保存为占位）的条目
  void removeByCodes(Set<String> codes) {
    LocalMovieScanner.removePendingCodes(codes);
    state = List.unmodifiable(
      state.where((e) => !codes.contains(e.movieCode)),
    );
  }

  /// 清空全部
  void clear() {
    LocalMovieScanner.clearPendingEntries();
    state = const [];
  }

  /// 从最近一次本地扫描结果恢复待审核列表
  void restoreFromLastScan() {
    if (state.isNotEmpty) return;
    final entries = LocalMovieScanner.lastResult?.notInLibrary ?? const [];
    if (entries.isEmpty) return;
    state = List.unmodifiable(entries);
  }

  /// 数量
  int get count => state.length;
  bool get isEmpty => state.isEmpty;
}

final unregisteredMoviesProvider =
    StateNotifierProvider<UnregisteredMoviesNotifier, List<ScannedMovieEntry>>(
  (ref) => UnregisteredMoviesNotifier(),
);

final effectiveUnregisteredMoviesProvider =
    Provider.autoDispose<List<ScannedMovieEntry>>((ref) {
  final entries = ref.watch(unregisteredMoviesProvider);
  if (entries.isNotEmpty) return entries;
  return LocalMovieScanner.lastResult?.notInLibrary ?? const [];
});
