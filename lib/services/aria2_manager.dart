import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:archive/archive_io.dart';

import 'aria2_service.dart';

/// aria2 进程状态
enum Aria2ProcessStatus {
  /// 未安装（aria2c 不存在）
  notInstalled,

  /// 已停止
  stopped,

  /// 启动中
  starting,

  /// 运行中
  running,

  /// 错误
  error,
}

/// aria2 进程管理器
///
/// 负责：
/// - 检查 aria2c 是否存在
/// - 从 GitHub 自动下载 aria2c
/// - 启动/停止 aria2c 进程
/// - 监控进程状态并自动重启
class Aria2Manager {
  static final Aria2Manager _instance = Aria2Manager._internal();
  factory Aria2Manager() => _instance;
  Aria2Manager._internal();

  Process? _process;
  Aria2ProcessStatus _status = Aria2ProcessStatus.stopped;
  String? _errorMessage;
  String? _aria2Dir;
  String? _aria2cPath;
  String _rpcSecret = '';
  String _trackers = '';

  Timer? _watchdogTimer;
  String? _downloadedPath;
  int _downloadProgress = 0;
  bool _isDownloading = false;
  String? _downloadErrorMessage;

  /// 当前状态
  Aria2ProcessStatus get status => _status;

  /// 错误信息
  String? get errorMessage => _errorMessage;

  /// aria2 二进制所在目录
  String? get aria2Dir => _aria2Dir;

  /// aria2c 可执行文件路径
  String? get aria2cPath => _aria2cPath;

  /// RPC 密钥
  String get rpcSecret => _rpcSecret;

  /// 是否正在下载
  bool get isDownloading => _isDownloading;

  /// 下载进度（0-100）
  int get downloadProgress => _downloadProgress;

  /// 下载错误信息
  String? get downloadErrorMessage => _downloadErrorMessage;

  /// 配置
  void configure({
    String? rpcSecret,
    String? trackers,
  }) {
    if (rpcSecret != null) _rpcSecret = rpcSecret;
    if (trackers != null) _trackers = trackers;
  }

  /// 获取 aria2 工作目录
  Future<String> _getAria2Dir() async {
    if (_aria2Dir != null) return _aria2Dir!;
    try {
      final exePath = Platform.resolvedExecutable;
      final exeDir = Directory(path.dirname(exePath));
      final aria2Dir = Directory(path.join(exeDir.path, 'aria2'));
      if (!await aria2Dir.exists()) {
        await aria2Dir.create(recursive: true);
      }
      _aria2Dir = aria2Dir.path;
      return aria2Dir.path;
    } catch (e) {
      // 降级到临时目录
      final tempDir = Directory.systemTemp;
      final aria2Dir = Directory(path.join(tempDir.path, 'cine_vault_aria2'));
      if (!await aria2Dir.exists()) {
        await aria2Dir.create(recursive: true);
      }
      _aria2Dir = aria2Dir.path;
      return aria2Dir.path;
    }
  }

  /// 清理损坏的 DHT 路由表文件
  ///
  /// 当 dht.dat 与 aria2c 版本不兼容时会报错
  /// 解决：删除旧文件，让 aria2c 重新建立
  Future<bool> cleanDhTableIfNeeded() async {
    try {
      // 1. 我们自己的 aria2 工作目录
      final ourDir = await _getAria2Dir();
      final dhtFile = File(path.join(ourDir, 'dht.dat'));
      if (await dhtFile.exists()) {
        try {
          final stat = await dhtFile.stat();
          // dht.dat 通常是几 MB，0 字节或过大（>50MB）都算异常
          if (stat.size == 0 || stat.size > 50 * 1024 * 1024) {
            print(
                '[Aria2Manager] Deleting suspicious dht.dat: ${stat.size} bytes');
            await dhtFile.delete();
            return true;
          }
        } catch (e) {
          // 出错也尝试删除
          try {
            await dhtFile.delete();
            return true;
          } catch (_) {}
        }
      }

      // 2. 用户家目录下的 aria2 缓存（aria2c 默认位置）
      if (Platform.isWindows) {
        final userHome = Platform.environment['USERPROFILE'];
        if (userHome != null) {
          final cacheDht =
              File(path.join(userHome, '.cache', 'aria2', 'dht.dat'));
          if (await cacheDht.exists()) {
            try {
              final stat = await cacheDht.stat();
              if (stat.size == 0 || stat.size > 50 * 1024 * 1024) {
                print(
                    '[Aria2Manager] Deleting user cache dht.dat: ${stat.size} bytes');
                await cacheDht.delete();
                return true;
              }
            } catch (e) {
              // 权限不足等
            }
          }
        }
      }

      return false;
    } catch (e) {
      print('[Aria2Manager] cleanDhTableIfNeeded error: $e');
      return false;
    }
  }

  /// 获取 aria2c 可执行文件路径
  Future<String> _getAria2cPath() async {
    if (_aria2cPath != null) return _aria2cPath!;
    final dir = await _getAria2Dir();
    final exeName = Platform.isWindows
        ? 'aria2c.exe'
        : Platform.isMacOS
            ? 'aria2c'
            : 'aria2c';
    _aria2cPath = path.join(dir, exeName);
    return _aria2cPath!;
  }

  /// 检查 aria2c 是否已安装
  Future<bool> isAria2Installed() async {
    final exePath = await _getAria2cPath();
    final file = File(exePath);
    return await file.exists();
  }

  /// 获取下载 URL
  String _getDownloadUrl() {
    if (Platform.isWindows) {
      return 'https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip';
    } else if (Platform.isMacOS) {
      // 通用 macOS 二进制
      return 'https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-os-x2_64-build1.zip';
    } else {
      // Linux（仅提供源码，用户需自行编译）
      return 'https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0.tar.gz';
    }
  }

  /// 获取下载文件名
  String _getDownloadFilename() {
    final url = _getDownloadUrl();
    return url.split('/').last;
  }

  /// 下载并安装 aria2c
  Future<bool> downloadAndInstall({
    void Function(int progress)? onProgress,
  }) async {
    if (_isDownloading) return false;
    _isDownloading = true;
    _downloadProgress = 0;
    _downloadErrorMessage = null;

    try {
      final url = _getDownloadUrl();
      final filename = _getDownloadFilename();
      final aria2Dir = await _getAria2Dir();
      final downloadPath = path.join(aria2Dir, filename);

      // 使用 HTTP client 下载
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        httpClient.close();
        _downloadErrorMessage = '下载失败: HTTP ${response.statusCode}';
        _isDownloading = false;
        return false;
      }

      final totalBytes = response.contentLength;
      var receivedBytes = 0;
      final file = File(downloadPath);
      final sink = file.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          _downloadProgress = ((receivedBytes / totalBytes) * 50).toInt();
          onProgress?.call(_downloadProgress);
        }
      }
      await sink.flush();
      await sink.close();
      httpClient.close();

      _downloadProgress = 50;
      onProgress?.call(50);

      // 解压
      if (filename.endsWith('.zip')) {
        await _extractZip(downloadPath, aria2Dir, (p) {
          _downloadProgress = 50 + (p * 50 ~/ 100);
          onProgress?.call(_downloadProgress);
        });
      } else if (filename.endsWith('.tar.gz')) {
        await _extractTarGz(downloadPath, aria2Dir, (p) {
          _downloadProgress = 50 + (p * 50 ~/ 100);
          onProgress?.call(_downloadProgress);
        });
      }

      // 清理压缩包
      try {
        await file.delete();
      } catch (e) {
        // 忽略
      }

      _downloadProgress = 100;
      onProgress?.call(100);
      _downloadedPath = await _getAria2cPath();
      _isDownloading = false;
      return await isAria2Installed();
    } catch (e) {
      _downloadErrorMessage = '下载失败: $e';
      _isDownloading = false;
      return false;
    }
  }

  /// 解压 zip 文件
  Future<void> _extractZip(
    String zipPath,
    String destDir,
    void Function(int)? onProgress,
  ) async {
    // 读取整个 zip 文件为字节数组
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final total = archive.length;
    var processed = 0;

    for (final file in archive) {
      final fileName = file.name;
      // 跳过目录
      if (file.isFile) {
        // 只提取 aria2c 二进制
        if (path.basename(fileName) == 'aria2c' ||
            path.basename(fileName) == 'aria2c.exe') {
          final content = file.content;
          if (content is List<int>) {
            final outFile = File(path.join(destDir, path.basename(fileName)));
            await outFile.writeAsBytes(content);

            // 设置可执行权限（Unix）
            if (!Platform.isWindows) {
              await Process.run('chmod', ['+x', outFile.path]);
            }
          }
        }
      }
      processed++;
      onProgress?.call(((processed / total) * 100).toInt());
    }
  }

  /// 解压 tar.gz 文件
  Future<void> _extractTarGz(
    String tarPath,
    String destDir,
    void Function(int)? onProgress,
  ) async {
    // 读取整个文件为字节
    final bytes = await File(tarPath).readAsBytes();
    final gzDecoder = GZipDecoder();
    final decompressed = gzDecoder.decodeBytes(bytes);

    // 直接读取 tar 内容
    final tarArchive = TarDecoder().decodeBytes(decompressed);
    final total = tarArchive.length;
    var processed = 0;

    for (final file in tarArchive) {
      if (file.isFile) {
        if (path.basename(file.name) == 'aria2c' ||
            path.basename(file.name) == 'aria2c.exe') {
          final content = file.content;
          if (content is List<int>) {
            final outFile = File(path.join(destDir, path.basename(file.name)));
            await outFile.writeAsBytes(content);

            if (!Platform.isWindows) {
              await Process.run('chmod', ['+x', outFile.path]);
            }
          }
        }
      }
      processed++;
      onProgress?.call(((processed / total) * 100).toInt());
    }
  }

  /// 启动 aria2c
  Future<bool> start() async {
    if (_status == Aria2ProcessStatus.running ||
        _status == Aria2ProcessStatus.starting) {
      return true;
    }

    if (!await isAria2Installed()) {
      _status = Aria2ProcessStatus.notInstalled;
      _errorMessage = 'aria2c 未安装';
      return false;
    }

    _status = Aria2ProcessStatus.starting;
    _errorMessage = null;

    // 启动前清理损坏的 DHT 路由表（避免版本不兼容报错）
    await cleanDhTableIfNeeded();

    final exePath = await _getAria2cPath();
    final workDir = await _getAria2Dir();

    // 确保 session 文件存在（aria2c 要求 --input-file 必须存在）
    final sessionFile = File(path.join(workDir, 'aria2.session'));
    if (!await sessionFile.exists()) {
      await sessionFile.create();
    }

    final args = <String>[
      '--enable-rpc=true',
      '--rpc-listen-all=false',
      '--rpc-listen-port=${Aria2Service.defaultRpcPort}',
      if (_rpcSecret.isNotEmpty) '--rpc-secret=$_rpcSecret',
      '--dir=$workDir',
      '--log=$workDir/aria2.log',
      '--log-level=warn',
      '--console-log-level=warn',
      '--save-session=$workDir/aria2.session',
      '--input-file=$workDir/aria2.session',
      '--save-session-interval=30',
      '--max-connection-per-server=16',
      '--split=16',
      '--min-split-size=1M',
      '--max-concurrent-downloads=5',
      '--continue=true',
      '--auto-file-renaming=true',
      // 注意：不通过命令行传 --bt-tracker，避免 1000+ trackers 时
      // Windows 命令行参数长度超限（lpCommandLine max 32767 字符）
      // 改为启动后通过 RPC changeGlobalOption 设置
    ];

    try {
      _process = await Process.start(
        exePath,
        args,
        workingDirectory: workDir,
        mode: ProcessStartMode.normal,
      );

      // 监听进程输出
      _process!.stdout.listen((data) {
        print('[aria2c] ${String.fromCharCodes(data)}');
      });
      _process!.stderr.listen((data) {
        print('[aria2c:err] ${String.fromCharCodes(data)}');
      });

      // 监听进程退出
      _process!.exitCode.then((code) {
        print('[aria2c] Process exited with code: $code');
        if (_status == Aria2ProcessStatus.running) {
          // 异常退出，尝试自动重启
          _scheduleRestart();
        } else {
          _status = Aria2ProcessStatus.stopped;
        }
      });

      // 等待 RPC 服务启动
      try {
        await _waitForRpcReady();
      } on TimeoutException {
        // 如果 RPC 连接超时，检查是否进程仍在运行 + 端口是否在监听
        if (_process != null && await _isPortListening()) {
          print('[Aria2Manager] RPC 响应超时但端口在监听，视为启动成功');
        } else {
          rethrow;
        }
      }

      // 启动后通过 RPC 设置全局 trackers（避免命令行参数长度超限）
      if (_trackers.isNotEmpty) {
        await _applyTrackersViaRpc();
      }

      _status = Aria2ProcessStatus.running;
      _startWatchdog();
      return true;
    } catch (e) {
      _errorMessage = '启动失败: $e';
      _status = Aria2ProcessStatus.error;
      return false;
    }
  }

  /// 启动后通过 RPC 设置全局 trackers
  ///
  /// 避免在命令行传 1000+ trackers 时超过 Windows lpCommandLine 32767 字符限制
  /// 同时避免 RPC 端 bt-tracker 超过 aria2 64KB 限制
  Future<void> _applyTrackersViaRpc() async {
    try {
      // 配置 RPC 客户端使用正确的密钥
      final service = Aria2Service();
      service.configure(
        host: '127.0.0.1',
        port: Aria2Service.defaultRpcPort,
        secret: _rpcSecret.isNotEmpty ? _rpcSecret : null,
      );

      // aria2 的 bt-tracker 字段有 64KB 大小限制
      // 如果超出，需要分批设置（每次设置不同的 trackers）
      // 或者直接截断到安全长度
      const maxLength = 60 * 1024; // 60KB，预留 4KB 余量
      var trackersToSet = _trackers;

      if (trackersToSet.length > maxLength) {
        print(
            '[Aria2Manager] Trackers string too long (${trackersToSet.length} bytes), truncating to $maxLength bytes');
        // 截断到安全长度，按逗号切分避免切断 URL
        final allTrackers = trackersToSet.split(',');
        final kept = <String>[];
        var currentLength = 0;
        for (final t in allTrackers) {
          if (currentLength + t.length + 1 > maxLength) break;
          kept.add(t);
          currentLength += t.length + 1;
        }
        trackersToSet = kept.join(',');
        print(
            '[Aria2Manager] Truncated to ${kept.length}/${allTrackers.length} trackers');
      }

      // 通过 RPC 设置全局 bt-tracker
      await service.changeGlobalOption(Aria2GlobalOptions(
        btTracker: trackersToSet,
      ));
      print(
          '[Aria2Manager] Applied ${trackersToSet.split(',').length} trackers via RPC (${trackersToSet.length} bytes)');
    } catch (e) {
      // 设置失败不应该导致整个启动失败
      print('[Aria2Manager] Failed to apply trackers via RPC: $e');
    }
  }

  /// 检查 RPC 端口是否在监听
  Future<bool> _isPortListening() async {
    try {
      final socket = await Socket.connect(
        '127.0.0.1',
        Aria2Service.defaultRpcPort,
        timeout: const Duration(seconds: 2),
      );
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 等待 RPC 服务就绪
  Future<void> _waitForRpcReady(
      {Duration timeout = const Duration(seconds: 10)}) async {
    final service = Aria2Service();
    final start = DateTime.now();
    while (DateTime.now().difference(start) < timeout) {
      if (await service.isAvailable()) return;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    throw TimeoutException('aria2c RPC 服务启动超时');
  }

  /// 安排重启
  void _scheduleRestart() {
    if (_watchdogTimer != null) return;
    _watchdogTimer = Timer(const Duration(seconds: 3), () {
      _watchdogTimer = null;
      if (_status == Aria2ProcessStatus.running) {
        start();
      }
    });
  }

  /// 启动看门狗（定期检查进程）
  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (_status != Aria2ProcessStatus.running) return;

      // 先检查进程是否还在运行
      if (_process != null && _process!.pid != 0) {
        // Windows 上用 tasklist 检查进程是否还在
        bool processAlive = true;
        if (Platform.isWindows) {
          try {
            final result = await Process.run(
              'tasklist',
              ['/FI', 'PID eq ${_process!.pid}'],
            );
            processAlive =
                result.stdout.toString().contains('${_process!.pid}');
          } catch (e) {
            // 检查失败时假设进程还活着
          }
        } else {
          processAlive = _process != null;
        }

        if (!processAlive) {
          print('[Aria2Manager] aria2 进程已退出，尝试重启...');
          _status = Aria2ProcessStatus.stopped;
          _scheduleRestart();
          return;
        }
      }

      // 检查 RPC 服务是否可用
      final service = Aria2Service();
      if (!await service.isAvailable()) {
        print('[Aria2Manager] RPC 服务不可用，尝试重启...');
        _scheduleRestart();
      }
    });
  }

  /// 停止 aria2c
  Future<void> stop() async {
    _status = Aria2ProcessStatus.stopped;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;

    if (_process != null) {
      try {
        _process!.kill();
        await _process!.exitCode.timeout(const Duration(seconds: 3));
      } catch (e) {
        try {
          _process!.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }
      _process = null;
    }
  }

  /// 释放资源
  void dispose() {
    _watchdogTimer?.cancel();
    _process?.kill();
    _process = null;
  }
}
