import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

/// aria2 任务状态
class Aria2TaskStatus {
  final String gid;
  final String status;
  final int totalLength;
  final int completedLength;
  final int downloadSpeed;
  final int uploadSpeed;
  final String? errorCode;
  final String? errorMessage;
  final List<String> files;
  final String? dir;
  final bool isBitTorrent;

  Aria2TaskStatus({
    required this.gid,
    required this.status,
    this.totalLength = 0,
    this.completedLength = 0,
    this.downloadSpeed = 0,
    this.uploadSpeed = 0,
    this.errorCode,
    this.errorMessage,
    this.files = const [],
    this.dir,
    this.isBitTorrent = false,
  });

  /// 进度（0.0-1.0）
  double get progress {
    if (totalLength <= 0) return 0;
    return (completedLength / totalLength).clamp(0.0, 1.0);
  }

  bool get isComplete => status == 'complete';
  bool get isActive => status == 'active';
  bool get isPaused => status == 'paused';
  bool get isError => status == 'error';
  bool get isWaiting => status == 'waiting';
  bool get isRemoved => status == 'removed';

  factory Aria2TaskStatus.fromMap(Map<String, dynamic> map) {
    return Aria2TaskStatus(
      gid: map['gid'] as String? ?? '',
      status: map['status'] as String? ?? 'unknown',
      totalLength: int.tryParse(map['totalLength']?.toString() ?? '0') ?? 0,
      completedLength:
          int.tryParse(map['completedLength']?.toString() ?? '0') ?? 0,
      downloadSpeed:
          int.tryParse(map['downloadSpeed']?.toString() ?? '0') ?? 0,
      uploadSpeed: int.tryParse(map['uploadSpeed']?.toString() ?? '0') ?? 0,
      errorCode: map['errorCode'] as String?,
      errorMessage: map['errorMessage'] as String?,
      files: (map['files'] as List<dynamic>?)
              ?.map((f) => (f as Map<String, dynamic>)['path'] as String? ?? '')
              .toList() ??
          [],
      dir: map['dir'] as String?,
      isBitTorrent: map['bittorrent'] != null,
    );
  }
}

/// aria2 文件信息（来自 getFiles 接口）
class Aria2FileInfo {
  final int index; // 文件索引（1-based）
  final String path; // 完整路径
  final int length; // 文件大小（字节）
  final int completedLength; // 已完成大小
  final bool selected; // 是否被选中
  final List<String> uris; // 文件 URI 列表

  Aria2FileInfo({
    required this.index,
    required this.path,
    this.length = 0,
    this.completedLength = 0,
    this.selected = true,
    this.uris = const [],
  });

  /// 文件名（不含路径）
  String get name {
    final sep = path.contains('\\') ? '\\' : '/';
    final lastSep = path.lastIndexOf(sep);
    if (lastSep < 0) return path;
    return path.substring(lastSep + 1);
  }

  /// 父目录
  String? get parentDir {
    final sep = path.contains('\\') ? '\\' : '/';
    final lastSep = path.lastIndexOf(sep);
    if (lastSep < 0) return null;
    return path.substring(0, lastSep);
  }

  /// 相对路径（相对于根目录）
  String? relativePath(String? rootDir) {
    if (rootDir == null || rootDir.isEmpty) return null;
    final sep = path.contains('\\') ? '\\' : '/';
    if (!path.startsWith(rootDir)) return name;
    String rel = path.substring(rootDir.length);
    if (rel.startsWith(sep)) rel = rel.substring(1);
    return rel;
  }

  factory Aria2FileInfo.fromMap(Map<String, dynamic> map) {
    return Aria2FileInfo(
      // aria2c 数字字段可能是 String 也可能是 int，统一用 tryParse
      index: int.tryParse(map['index']?.toString() ?? '0') ?? 0,
      path: map['path'] as String? ?? '',
      length: int.tryParse(map['length']?.toString() ?? '0') ?? 0,
      completedLength:
          int.tryParse(map['completedLength']?.toString() ?? '0') ?? 0,
      // aria2c 的 selected 字段可能是 bool、String、int 等多种类型
      // 统一转为 bool："true"/"1"/1 → true；其他 → false
      selected: _parseBool(map['selected'], defaultValue: true),
      uris: (map['uris'] as List<dynamic>?)
              ?.map((u) {
                if (u is Map) {
                  // uri 字段也可能是 String
                  return u['uri']?.toString() ?? '';
                }
                return u.toString();
              })
              .where((s) => s.isNotEmpty)
              .toList() ??
          [],
    );
  }

  /// 通用 bool 解析
  static bool _parseBool(dynamic value, {bool defaultValue = false}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) {
      final s = value.toLowerCase().trim();
      return s == 'true' || s == '1' || s == 'yes';
    }
    return defaultValue;
  }
}

/// aria2 全局选项
class Aria2GlobalOptions {
  /// 最大并发下载数
  final int maxConcurrentDownloads;

  /// 每个服务器最大连接数
  final int maxConnectionPerServer;

  /// 全局下载限速（字节/秒，0=不限）
  final int maxOverallDownloadLimit;

  /// 全局上传限速（字节/秒，0=不限）
  final int maxOverallUploadLimit;

  /// 单文件分片数
  final int split;

  /// 最小分片大小（字节）
  final int minSplitSize;

  /// BT trackers
  final String? btTracker;

  /// 是否启用 mmap
  final bool enableMmap;

  Aria2GlobalOptions({
    this.maxConcurrentDownloads = 5,
    this.maxConnectionPerServer = 16,
    this.maxOverallDownloadLimit = 0,
    this.maxOverallUploadLimit = 0,
    this.split = 16,
    this.minSplitSize = 1024 * 1024,
    this.btTracker,
    this.enableMmap = true,
  });

  Map<String, dynamic> toAria2Map() {
    final map = <String, dynamic>{
      'max-concurrent-downloads': maxConcurrentDownloads.toString(),
      'max-connection-per-server': maxConnectionPerServer.toString(),
      'max-overall-download-limit': maxOverallDownloadLimit.toString(),
      'max-overall-upload-limit': maxOverallUploadLimit.toString(),
      'split': split.toString(),
      'min-split-size': minSplitSize.toString(),
      'enable-mmap': enableMmap,
    };
    if (btTracker != null && btTracker!.isNotEmpty) {
      map['bt-tracker'] = btTracker;
    }
    return map;
  }

  factory Aria2GlobalOptions.fromAria2Map(Map<String, dynamic> map) {
    return Aria2GlobalOptions(
      maxConcurrentDownloads:
          int.tryParse(map['max-concurrent-downloads']?.toString() ?? '5') ??
              5,
      maxConnectionPerServer:
          int.tryParse(map['max-connection-per-server']?.toString() ?? '16') ??
              16,
      maxOverallDownloadLimit:
          int.tryParse(map['max-overall-download-limit']?.toString() ?? '0') ??
              0,
      maxOverallUploadLimit:
          int.tryParse(map['max-overall-upload-limit']?.toString() ?? '0') ??
              0,
      split: int.tryParse(map['split']?.toString() ?? '16') ?? 16,
      minSplitSize:
          int.tryParse(map['min-split-size']?.toString() ?? '1048576') ??
              1048576,
      btTracker: map['bt-tracker'] as String?,
      enableMmap: map['enable-mmap'] == true,
    );
  }

  Aria2GlobalOptions copyWith({
    int? maxConcurrentDownloads,
    int? maxConnectionPerServer,
    int? maxOverallDownloadLimit,
    int? maxOverallUploadLimit,
    int? split,
    int? minSplitSize,
    String? btTracker,
    bool? enableMmap,
  }) {
    return Aria2GlobalOptions(
      maxConcurrentDownloads:
          maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      maxConnectionPerServer:
          maxConnectionPerServer ?? this.maxConnectionPerServer,
      maxOverallDownloadLimit:
          maxOverallDownloadLimit ?? this.maxOverallDownloadLimit,
      maxOverallUploadLimit:
          maxOverallUploadLimit ?? this.maxOverallUploadLimit,
      split: split ?? this.split,
      minSplitSize: minSplitSize ?? this.minSplitSize,
      btTracker: btTracker ?? this.btTracker,
      enableMmap: enableMmap ?? this.enableMmap,
    );
  }
}

/// aria2 JSON-RPC 异常
class Aria2Exception implements Exception {
  final int code;
  final String message;
  Aria2Exception({required this.code, required this.message});

  @override
  String toString() => 'Aria2Exception($code): $message';
}

/// aria2 JSON-RPC 客户端
///
/// 封装 aria2c 的 JSON-RPC 接口调用，支持以下功能：
/// - HTTP/FTP/磁力链接/种子/Metalink 下载
/// - 任务管理（添加/暂停/恢复/移除/查询）
/// - 全局选项配置（限速、并发数、trackers等）
class Aria2Service {
  /// 默认 RPC 地址
  static const String defaultRpcHost = '127.0.0.1';
  static const int defaultRpcPort = 6800;

  /// 单例
  static final Aria2Service _instance = Aria2Service._internal();
  factory Aria2Service() => _instance;
  Aria2Service._internal();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 10),
    responseType: ResponseType.json,
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
  ));

  String _rpcHost = defaultRpcHost;
  int _rpcPort = defaultRpcPort;
  String? _rpcSecret;
  int _requestId = 0;

  /// 当前 RPC 地址
  String get rpcUrl => 'http://$_rpcHost:$_rpcPort/jsonrpc';

  /// 当前 RPC 端口
  int get rpcPort => _rpcPort;

  /// 当前 RPC 主机
  String get rpcHost => _rpcHost;

  /// 配置 RPC 连接
  void configure({
    String host = defaultRpcHost,
    int port = defaultRpcPort,
    String? secret,
  }) {
    _rpcHost = host;
    _rpcPort = port;
    _rpcSecret = secret;
  }

  /// 检查 aria2 是否可用
  Future<bool> isAvailable() async {
    try {
      await getVersion();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 获取 aria2 版本信息
  Future<Map<String, dynamic>> getVersion() async {
    final result = await _call('aria2.getVersion', []);
    return result as Map<String, dynamic>;
  }

  /// 添加 HTTP/FTP 下载任务
  ///
  /// [uris] 下载链接列表（aria2 支持多源下载以加速）
  /// [dir] 保存目录
  /// [filename] 保存的文件名
  /// [maxConnectionPerServer] 每个服务器连接数
  /// [split] 分片数
  /// 返回任务 GID
  Future<String> addUri(
    List<String> uris, {
    String? dir,
    String? filename,
    int? maxConnectionPerServer,
    int? split,
  }) async {
    final options = <String, dynamic>{};
    if (dir != null) options['dir'] = dir;
    if (filename != null) options['out'] = filename;
    if (maxConnectionPerServer != null) {
      options['max-connection-per-server'] = maxConnectionPerServer;
    }
    if (split != null) options['split'] = split;

    final result = await _call('aria2.addUri', [uris, options]);
    return result as String;
  }

  /// 添加磁力链接下载任务
  Future<String> addMagnet(
    String magnet, {
    String? dir,
    List<String>? trackers,
  }) async {
    final options = <String, dynamic>{};
    if (dir != null) options['dir'] = dir;
    if (trackers != null && trackers.isNotEmpty) {
      // trackers 用逗号或换行分隔
      options['bt-tracker'] = trackers.join(',');
    }

    final result = await _call('aria2.addUri', [[magnet], options]);
    return result as String;
  }

  /// 添加种子文件下载任务
  Future<String> addTorrent(
    String torrentPath, {
    String? dir,
    List<String>? trackers,
  }) async {
    final options = <String, dynamic>{};
    if (dir != null) options['dir'] = dir;
    if (trackers != null && trackers.isNotEmpty) {
      options['bt-tracker'] = trackers.join(',');
    }

    // 读取种子文件并 base64 编码
    final torrentFile = File(torrentPath);
    final torrentBytes = await torrentFile.readAsBytes();
    final torrentBase64 = base64Encode(torrentBytes);

    final result =
        await _call('aria2.addTorrent', [torrentBase64, [], options]);
    return result as String;
  }

  /// 添加 Metalink 下载
  Future<String> addMetalink(
    String metalinkPath, {
    String? dir,
  }) async {
    final options = <String, dynamic>{};
    if (dir != null) options['dir'] = dir;

    final metalinkFile = File(metalinkPath);
    final metalinkBytes = await metalinkFile.readAsBytes();
    final metalinkBase64 = base64Encode(metalinkBytes);

    final result = await _call('aria2.addMetalink', [metalinkBase64, options]);
    return result as String;
  }

  /// 移除任务
  Future<void> remove(String gid) async {
    await _call('aria2.remove', [gid]);
  }

  /// 强制移除任务
  Future<void> forceRemove(String gid) async {
    await _call('aria2.forceRemove', [gid]);
  }

  /// 暂停任务
  Future<void> pause(String gid) async {
    await _call('aria2.pause', [gid]);
  }

  /// 强制暂停任务
  Future<void> forcePause(String gid) async {
    await _call('aria2.forcePause', [gid]);
  }

  /// 恢复暂停的任务
  Future<void> unpause(String gid) async {
    await _call('aria2.unpause', [gid]);
  }

  /// 查询任务状态
  Future<Aria2TaskStatus> tellStatus(String gid) async {
    final result = await _call('aria2.tellStatus', [gid]);
    return Aria2TaskStatus.fromMap(result as Map<String, dynamic>);
  }

  /// 获取任务的文件列表（包含每个文件的路径、大小、是否选中）
  ///
  /// [gid] 任务 GID
  /// 返回文件列表
  Future<List<Aria2FileInfo>> getFiles(String gid) async {
    final result = await _call('aria2.getFiles', [gid]);
    return (result as List<dynamic>)
        .map((e) => Aria2FileInfo.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取活动任务列表
  Future<List<Aria2TaskStatus>> tellActive() async {
    final result = await _call('aria2.tellActive', []);
    return (result as List<dynamic>)
        .map((e) => Aria2TaskStatus.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取等待中的任务列表
  Future<List<Aria2TaskStatus>> tellWaiting({int offset = 0, int num = 100}) async {
    final result = await _call('aria2.tellWaiting', [offset, num]);
    return (result as List<dynamic>)
        .map((e) => Aria2TaskStatus.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取已停止的任务列表
  Future<List<Aria2TaskStatus>> tellStopped({int offset = 0, int num = 100}) async {
    final result = await _call('aria2.tellStopped', [offset, num]);
    return (result as List<dynamic>)
        .map((e) => Aria2TaskStatus.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取全局选项
  Future<Aria2GlobalOptions> getGlobalOption() async {
    final result = await _call('aria2.getGlobalOption', []);
    return Aria2GlobalOptions.fromAria2Map(result as Map<String, dynamic>);
  }

  /// 修改全局选项
  Future<void> changeGlobalOption(Aria2GlobalOptions options) async {
    await _call('aria2.changeGlobalOption', [options.toAria2Map()]);
  }

  /// 修改单个任务的选项
  Future<void> changeOption(String gid, Map<String, dynamic> options) async {
    await _call('aria2.changeOption', [gid, options]);
  }

  /// 获取全局统计信息
  Future<Map<String, dynamic>> getGlobalStat() async {
    final result = await _call('aria2.getGlobalStat', []);
    return result as Map<String, dynamic>;
  }

  /// 暂停所有活动任务
  Future<void> pauseAll() async {
    await _call('aria2.pauseAll', []);
  }

  /// 强制暂停所有任务
  Future<void> forcePauseAll() async {
    await _call('aria2.forcePauseAll', []);
  }

  /// 恢复所有暂停的任务
  Future<void> unpauseAll() async {
    await _call('aria2.unpauseAll', []);
  }

  /// 清理已完成/错误/已移除的任务结果
  Future<void> purgeDownloadResult() async {
    await _call('aria2.purgeDownloadResult', []);
  }

  /// 移除单个下载结果记录
  Future<void> removeDownloadResult(String gid) async {
    await _call('aria2.removeDownloadResult', [gid]);
  }

  /// 保存会话（将任务保存到 session 文件）
  Future<String> saveSession() async {
    final result = await _call('aria2.saveSession', []);
    return result as String;
  }

  /// 关闭 aria2
  Future<void> shutdown() async {
    await _call('aria2.shutdown', []);
  }

  /// 强制关闭 aria2
  Future<void> forceShutdown() async {
    await _call('aria2.forceShutdown', []);
  }

  /// 底层 JSON-RPC 调用
  Future<dynamic> _call(String method, [List<dynamic>? params]) async {
    _requestId++;
    final requestBody = {
      'jsonrpc': '2.0',
      'id': '$_requestId',
      'method': method,
      'params': params ?? [],
    };

    // 如果有密钥，添加为第一个参数
    if (_rpcSecret != null && _rpcSecret!.isNotEmpty) {
      requestBody['params'] = ['token:$_rpcSecret', ...?params];
    }

    try {
      final response = await _dio.post(
        rpcUrl,
        data: jsonEncode(requestBody),
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
          // 接受 200 和 4xx，aria2 RPC 在协议错误时返回 400
          // 真正的错误信息在 JSON 响应体的 error 字段
          validateStatus: (status) =>
              status != null && status >= 200 && status < 500,
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        Map<String, dynamic>? jsonData;
        if (data is Map<String, dynamic>) {
          jsonData = data;
        } else if (data is Map) {
          jsonData = Map<String, dynamic>.from(data);
        } else if (data is String) {
          // 尝试解析字符串为 JSON
          try {
            final parsed = jsonDecode(data);
            if (parsed is Map) {
              jsonData = Map<String, dynamic>.from(parsed);
            }
          } catch (_) {}
        }

        if (jsonData != null) {
          if (jsonData.containsKey('error')) {
            final error = jsonData['error'];
            String message = 'Unknown error';
            int code = -1;
            if (error is Map) {
              message = error['message']?.toString() ?? message;
              code = error['code'] as int? ?? code;
            } else {
              message = error.toString();
            }
            throw Aria2Exception(code: code, message: message);
          }
          return jsonData['result'];
        }
      }
      // 4xx 错误（aria2 在 JSON-RPC 协议错误时返回 400）
      // 错误信息应该在响应体的 error 字段
      final data = response.data;
      if (data is Map) {
        final error = data['error'];
        if (error != null) {
          String message = error.toString();
          int code = -1;
          if (error is Map) {
            message = error['message']?.toString() ?? message;
            code = error['code'] as int? ?? code;
          }
          throw Aria2Exception(code: code, message: message);
        }
      }
      throw Aria2Exception(
        code: response.statusCode ?? -1,
        message: 'HTTP error: ${response.statusCode}',
      );
    } on DioException catch (e) {
      throw Aria2Exception(
        code: -1,
        message: 'Network error: ${e.message}',
      );
    }
  }
}
