import 'package:dio/dio.dart';

/// Tracker 更新服务
///
/// 用于自动从公开 trackers 源下载最新 BT trackers 列表
class TrackerUpdater {
  static final TrackerUpdater _instance = TrackerUpdater._internal();
  factory TrackerUpdater() => _instance;
  TrackerUpdater._internal();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    responseType: ResponseType.plain,
  ));

  /// 默认 trackers 源列表
  ///
  /// 这些都是公开的、常用的 BT trackers 列表源：
  /// - ngosang/trackerslist：最流行的 trackers 列表（best=精选 / all=全部 / http=仅 HTTP）
  /// - DeSireFire/freeNodeTracker：另一个流行的中文友好源
  /// - xditzou/superior-tracker-list：高质量的精选列表
  /// - XIU2/TrackersListCollection：国内常用
  /// - newtrackon.com：实时验证的 trackers
  /// - trackerslist.codeberg.page：另一个常用源
  static const List<String> defaultTrackerSources = [
    // ngosang/trackerslist - 最流行
    'https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_best.txt',
    'https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_all.txt',
    'https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_all_udp.txt',
    'https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_all_http.txt',
    'https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_all_https.txt',
    'https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_all_ws.txt',

    // DeSireFire/freeNodeTracker - 中文友好
    'https://raw.githubusercontent.com/DeSireFire/freeNodeTracker/master/best.txt',
    'https://raw.githubusercontent.com/DeSireFire/freeNodeTracker/master/all.txt',

    // XIU2/TrackersListCollection - 国内常用
    'https://raw.githubusercontent.com/XIU2/TrackersListCollection/master/best.txt',
    'https://raw.githubusercontent.com/XIU2/TrackersListCollection/master/all.txt',
    'https://raw.githubusercontent.com/XIU2/TrackersListCollection/master/http.txt',

    // xditzou/superior-tracker-list
    'https://raw.githubusercontent.com/xditzou/superior-tracker-list/master/trackers.txt',

    // 4everSky/TrackerList
    'https://raw.githubusercontent.com/4everSky/TrackerList/master/trackerlist.txt',

    // anacrolix/tracker-list
    'https://raw.githubusercontent.com/anacrolix/tracker-list/master/trackers.txt',

    // 其他补充源
    'https://newtrackon.com/api/stable',
  ];

  /// 从所有源更新 trackers
  ///
  /// 返回合并后的 trackers 列表（已去重）
  /// [sources] 自定义源列表，传入 null 则使用默认源
  /// [onProgress] 进度回调（0.0-1.0）
  Future<List<String>> updateTrackers({
    List<String>? sources,
    void Function(double progress)? onProgress,
  }) async {
    final sourceList = sources ?? defaultTrackerSources;
    final allTrackers = <String>{};
    var completed = 0;

    for (final source in sourceList) {
      try {
        onProgress?.call(completed / sourceList.length);
        final trackers = await _fetchFromSource(source);
        allTrackers.addAll(trackers);
      } catch (e) {
        print('[TrackerUpdater] Failed to fetch from $source: $e');
      }
      completed++;
    }

    onProgress?.call(1.0);

    // 返回排序后的列表（去重后）
    final list = allTrackers.toList();
    list.sort();
    return list;
  }

  /// 从单个源获取 trackers
  Future<List<String>> _fetchFromSource(String url) async {
    try {
      final response = await _dio.get(url);

      if (response.statusCode == 200 && response.data != null) {
        final content = response.data.toString();
        return _parseTrackers(content);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// 解析 trackers 内容
  ///
  /// 支持格式：
  /// - 每行一个 tracker URL
  /// - JSON 格式：["udp://...", "wss://..."]
  List<String> _parseTrackers(String content) {
    final trackers = <String>{};

    // 尝试解析 JSON
    if (content.trim().startsWith('[')) {
      try {
        // 简单提取
        final matches = RegExp(r'"(udp|wss|https?|http)://[^"]+"')
            .allMatches(content);
        for (final match in matches) {
          final url = match.group(0)?.replaceAll('"', '');
          if (url != null && _isValidTracker(url)) {
            trackers.add(url);
          }
        }
        return trackers.toList();
      } catch (_) {
        // 继续用文本解析
      }
    }

    // 按行解析
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (_isValidTracker(trimmed)) {
        trackers.add(trimmed);
      }
    }

    return trackers.toList();
  }

  /// 验证是否是有效的 tracker URL
  bool _isValidTracker(String url) {
    if (url.isEmpty) return false;
    if (url.startsWith('#')) return false; // 注释
    return url.startsWith('udp://') ||
        url.startsWith('http://') ||
        url.startsWith('https://') ||
        url.startsWith('wss://') ||
        url.startsWith('ws://');
  }

  /// 测试源是否可用
  Future<bool> testSource(String url) async {
    try {
      final response = await _dio.head(
        url,
        options: Options(
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
