import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../services/aria2_downloader.dart';
import '../services/database_service.dart';
import 'model_manifest.dart';

typedef VoidCallback = void Function();

class ModelFileInfo {
  final String name;
  final int size;
  final String url;
  final String? sha256;
  double? progress;
  bool isDownloading;
  bool isDownloaded;

  ModelFileInfo({
    required this.name,
    required this.size,
    required this.url,
    this.sha256,
    this.progress,
    this.isDownloading = false,
    this.isDownloaded = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'size': size,
      'url': url,
      'sha256': sha256,
      'progress': progress,
      'isDownloading': isDownloading,
      'isDownloaded': isDownloaded,
    };
  }
}

class DownloadTask {
  final String id;
  final String repositoryUrl;
  final String modelName;
  final List<ModelFileInfo> files;
  final DateTime createdAt;
  bool isCompleted;
  String? errorMessage;

  DownloadTask({
    required this.id,
    required this.repositoryUrl,
    required this.modelName,
    required this.files,
    required this.createdAt,
    this.isCompleted = false,
    this.errorMessage,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'repositoryUrl': repositoryUrl,
      'modelName': modelName,
      'files': files.map((f) => f.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'isCompleted': isCompleted,
      'errorMessage': errorMessage,
    };
  }
}

class ModelManager {
  static final ModelManager _instance = ModelManager._internal();
  factory ModelManager() => _instance;
  ModelManager._internal();

  final Dio _dio = Dio()
    ..options.connectTimeout = const Duration(seconds: 15)
    ..options.receiveTimeout = const Duration(seconds: 30);
  final ModelManifest _manifest = ModelManifest.defaultManifest();
  String? _customModelsPath;
  String? _previousModelsPath;
  final Map<String, CancelToken> _downloadCancelTokens = {};
  final List<DownloadTask> _downloadTasks = [];
  CancelToken? _downloadCancelToken; // 保留单个下载令牌支持
  bool _isDownloading = false;
  String? _downloadingModelId;

  ModelManifest get manifest => _manifest;

  bool get isDownloading => _isDownloading;
  String? get downloadingModelId => _downloadingModelId;

  Future<String> getModelsDirectory() async {
    if (_customModelsPath != null && _customModelsPath!.isNotEmpty) {
      final dir = Directory(_customModelsPath!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return _customModelsPath!;
    }
    return await getDefaultModelsPath();
  }

  Future<String> getDefaultModelsPath() async {
    try {
      String? exePath;
      if (Platform.isWindows) {
        exePath = Platform.resolvedExecutable;
        final exeDir = Directory(path.dirname(exePath));
        final modelsDir = Directory(path.join(exeDir.path, 'models'));
        if (!await modelsDir.exists()) {
          await modelsDir.create(recursive: true);
        }
        return modelsDir.path;
      }
    } catch (e) {
      print('获取程序根目录失败: $e');
    }

    final appDir = await getApplicationSupportDirectory();
    final modelsDir = Directory(path.join(appDir.path, 'models'));
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return modelsDir.path;
  }

  Future<void> setCustomModelsPath(String? pathStr) async {
    if (pathStr == _customModelsPath) return;

    _previousModelsPath = _customModelsPath;
    _customModelsPath = pathStr;

    if (_previousModelsPath != null && pathStr != null) {
      await _migrateModels(_previousModelsPath!, pathStr);
    }
  }

  Future<void> _migrateModels(String fromPath, String toPath) async {
    try {
      final fromDir = Directory(fromPath);
      if (!await fromDir.exists()) return;

      final toDir = Directory(toPath);
      if (!await toDir.exists()) {
        await toDir.create(recursive: true);
      }

      await for (final entity in fromDir.list()) {
        if (entity is Directory) {
          final destDir =
              Directory(path.join(toPath, path.basename(entity.path)));
          if (!await destDir.exists()) {
            await entity.rename(destDir.path);
          }
        } else if (entity is File) {
          final destFile = File(path.join(toPath, path.basename(entity.path)));
          if (!await destFile.exists()) {
            await entity.rename(destFile.path);
          }
        }
      }
    } catch (e) {
      print('模型迁移失败: $e');
    }
  }

  Future<File> getModelFile(ModelInfo model) async {
    return _getSafeModelDownloadFile(
      modelName: model.id,
      fileName: model.fileName,
    );
  }

  Future<bool> isModelDownloaded(ModelInfo model) async {
    try {
      final file = await getModelFile(model);
      if (!await file.exists()) return false;

      final stat = await file.stat();
      return stat.size > 1024 * 1024;
    } catch (e) {
      return false;
    }
  }

  Future<int?> getDownloadedModelSize(ModelInfo model) async {
    try {
      final file = await getModelFile(model);
      if (!await file.exists()) return null;
      final stat = await file.stat();
      return stat.size;
    } catch (e) {
      return null;
    }
  }

  Future<void> downloadModel({
    required ModelInfo model,
    required void Function(int received, int total) onProgress,
    required VoidCallback onDone,
    required Function(Object error) onError,
  }) async {
    if (_isDownloading) {
      onError(Exception('已有下载正在进行'));
      return;
    }

    _isDownloading = true;
    _downloadingModelId = model.id;
    _downloadCancelToken = CancelToken();

    // 创建 DownloadTask 以便在下载中心显示
    final modelFile = ModelFileInfo(
      name: model.fileName,
      size: model.fileSizeBytes,
      url: model.ggufUrl,
      sha256: model.sha256,
    );
    final task = DownloadTask(
      id: 'model-${model.id}-${DateTime.now().millisecondsSinceEpoch}',
      repositoryUrl: 'model-market://${model.id}',
      modelName: model.name,
      files: [modelFile],
      createdAt: DateTime.now(),
    );
    _downloadTasks.insert(0, task);
    modelFile.isDownloading = true;

    try {
      final file = await getModelFile(model);
      final directory = file.parent;

      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      // 检查是否启用 aria2
      final useAria2 = await _shouldUseAria2();
      if (useAria2) {
        // 在任务上标记使用 aria2
        modelFile.isDownloading = true;
        final downloader = Aria2Downloader();
        final result = await downloader.downloadFile(
          url: model.ggufUrl,
          savePath: file.path,
          onProgress: (received, total) {
            if (total <= 0) {
              modelFile.progress = received / model.fileSizeBytes;
              onProgress(received, model.fileSizeBytes);
            } else {
              modelFile.progress = received / total;
              onProgress(received, total);
            }
          },
        );
        if (result.success) {
          await _ensureDownloadedFileExists(file);
          await _verifyDownloadedFile(file, model.sha256);
          modelFile.isDownloading = false;
          modelFile.isDownloaded = true;
          modelFile.progress = 1.0;
          task.isCompleted = true;
          onDone();
          return;
        }
        // aria2 失败时回退到 dio
        print(
            '[ModelManager] aria2 download failed: ${result.errorMessage}, falling back to dio');
        task.errorMessage = 'aria2 失败，已回退到 dio: ${result.errorMessage}';
      }

      await _dio.download(
        model.ggufUrl,
        file.path,
        cancelToken: _downloadCancelToken,
        onReceiveProgress: (received, total) {
          if (total == -1) {
            modelFile.progress = received / model.fileSizeBytes;
            onProgress(received, model.fileSizeBytes);
          } else {
            modelFile.progress = received / total;
            onProgress(received, total);
          }
        },
        deleteOnError: true,
      );

      if (await file.exists()) {
        final stat = await file.stat();
        if (stat.size > 1024) {
          await _verifyDownloadedFile(file, model.sha256);
          modelFile.isDownloading = false;
          modelFile.isDownloaded = true;
          modelFile.progress = 1.0;
          task.isCompleted = true;
          onDone();
          return;
        }
      }

      task.errorMessage = '下载文件无效';
      onError(Exception('下载文件无效'));
    } catch (e) {
      if (_downloadCancelToken != null && !_downloadCancelToken!.isCancelled) {
        task.errorMessage = e.toString();
        onError(e);
      }
    } finally {
      _isDownloading = false;
      _downloadingModelId = null;
      _downloadCancelToken = null;
      modelFile.isDownloading = false;
    }
  }

  /// 检查是否应该使用 aria2
  Future<bool> _shouldUseAria2() async {
    try {
      final settings = DatabaseService.getSettings();
      if (settings == null || !settings.useAria2ForDownloads) return false;
      return await Aria2Downloader().isAvailable();
    } catch (e) {
      return false;
    }
  }

  void cancelDownload() {
    _downloadCancelTokens.values.forEach((token) {
      if (!token.isCancelled) {
        token.cancel('用户取消下载');
      }
    });
  }

  Future<void> deleteModel(ModelInfo model) async {
    final file = await getModelFile(model);
    if (await file.exists()) {
      await file.delete();
      final dir = file.parent;
      if (await dir.exists()) {
        await dir.delete();
      }
    }
  }

  Future<Map<String, bool>> getDownloadedModels() async {
    final result = <String, bool>{};
    for (final model in _manifest.models) {
      result[model.id] = await isModelDownloaded(model);
    }
    return result;
  }

  List<DownloadTask> get downloadTasks => List.unmodifiable(_downloadTasks);

  Future<List<ModelInfo>> getAllAvailableModels() async {
    final allModels = <ModelInfo>[..._manifest.models];

    final customModels = await _scanCustomModels();
    for (final customModel in customModels) {
      if (!allModels.any((m) => m.id == customModel.id)) {
        allModels.add(customModel);
      }
    }

    return allModels;
  }

  Future<List<ModelInfo>> _scanCustomModels() async {
    final models = <ModelInfo>[];
    try {
      final modelsDir = await getModelsDirectory();
      final dir = Directory(modelsDir);

      if (!await dir.exists()) {
        return models;
      }

      await for (final entity in dir.list()) {
        if (entity is Directory) {
          final modelDir = entity;
          final modelId = path.basename(modelDir.path);

          if (_manifest.models.any((m) => m.id == modelId)) {
            continue;
          }

          final files = <File>[];
          await for (final entity in modelDir.list()) {
            if (entity is File) {
              files.add(entity);
            }
          }
          final ggufFiles =
              files.where((f) => f.path.endsWith('.gguf')).toList();

          if (ggufFiles.isNotEmpty) {
            final ggufFile = ggufFiles.first;
            final fileName = path.basename(ggufFile.path);
            final stat = await ggufFile.stat();

            // 使用文件名（去掉扩展名）作为模型名称
            final baseName = path.basenameWithoutExtension(fileName);

            models.add(ModelInfo(
              id: modelId,
              name: baseName,
              description: '自定义下载的模型',
              tier: 'custom',
              ggufUrl: '',
              fileName: fileName,
              fileSizeBytes: stat.size,
              sha256: null,
              minFreeStorageMb: (stat.size / (1024 * 1024)).ceil(),
              estimatedRamMb: ((stat.size / (1024 * 1024)) * 1.5).ceil(),
              defaultCtx: 2048,
              defaultThreads: 4,
              nGpuLayers: -1,
            ));
          }
        }
      }
    } catch (e) {
      print('扫描自定义模型失败: $e');
    }

    return models;
  }

  Future<List<ModelFileInfo>> parseHuggingFaceRepo(String url,
      {int retries = 3, bool preferMirror = false}) async {
    Uri uri;
    try {
      uri = Uri.parse(url);
    } catch (e) {
      throw Exception('无效的URL格式');
    }

    String? repoOwner;
    String? repoName;
    String? repoRef;

    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length >= 2) {
      repoOwner = segments[0];
      repoName = segments[1];
    }

    if (segments.length >= 4 && segments[2] == 'tree') {
      repoRef = segments[3];
    }

    if (repoOwner == null || repoName == null) {
      throw Exception('无法解析仓库链接，请确保URL格式正确');
    }

    final baseUrls = preferMirror
        ? [
            'https://hf-mirror.com',
            'https://huggingface.co',
          ]
        : [
            'https://huggingface.co',
            'https://hf-mirror.com',
          ];

    for (final baseUrl in baseUrls) {
      for (int attempt = 1; attempt <= retries; attempt++) {
        try {
          final apiUrl = '$baseUrl/api/models/$repoOwner/$repoName';

          final options = Options(
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Accept': 'application/json',
            },
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
          );

          final response = await _dio.get(apiUrl, options: options);

          if (response.statusCode != 200) {
            throw Exception('HTTP错误: ${response.statusCode}');
          }

          final data = response.data as Map<String, dynamic>;
          final files = <ModelFileInfo>[];

          final siblings = data['siblings'] as List<dynamic>? ?? [];
          for (final sibling in siblings) {
            final fileInfo = sibling as Map<String, dynamic>;
            final fileName = fileInfo['rfilename'] as String?;
            if (fileName != null &&
                (fileName.endsWith('.gguf') ||
                    fileName.endsWith('.safetensors') ||
                    fileName.endsWith('.model') ||
                    fileName.endsWith('.bin') ||
                    fileName.endsWith('.pt') ||
                    fileName.endsWith('.pth'))) {
              final fileUrl =
                  '$baseUrl/$repoOwner/$repoName/resolve/${repoRef ?? 'main'}/$fileName';

              files.add(ModelFileInfo(
                name: fileName,
                size: (fileInfo['size'] as int?) ?? 0,
                url: fileUrl,
                sha256: fileInfo['sha256'] as String?,
              ));
            }
          }

          if (files.isEmpty) {
            throw Exception('仓库中未找到可下载的模型文件');
          }

          return files;
        } catch (e) {
          if (attempt < retries) {
            await Future.delayed(Duration(seconds: attempt * 2));
            continue;
          }

          if (baseUrl == baseUrls.last) {
            String errorMessage = '解析仓库失败';
            if (e.toString().contains('timeout') ||
                e.toString().contains('信号灯')) {
              errorMessage = '网络连接超时，请检查网络连接';
            } else if (e.toString().contains('connection error')) {
              errorMessage = '无法连接到镜像站点，请检查网络连接';
            } else {
              errorMessage = '解析仓库失败: $e';
            }
            throw Exception(errorMessage);
          }
        }
      }
    }

    throw Exception('解析仓库失败');
  }

  Future<DownloadTask> createDownloadTask({
    required String repositoryUrl,
    required String modelName,
    required List<ModelFileInfo> files,
  }) async {
    final task = DownloadTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      repositoryUrl: repositoryUrl,
      modelName: modelName,
      files: files,
      createdAt: DateTime.now(),
    );

    _downloadTasks.insert(0, task);
    return task;
  }

  Future<void> downloadFiles({
    required String taskId,
    required List<ModelFileInfo> filesToDownload,
    required String modelName,
    required Function(ModelFileInfo, int received, int total) onProgress,
    required VoidCallback onDone,
    required Function(Object error) onError,
  }) async {
    if (_downloadTasks.any((t) => t.id == taskId)) {
      final task = _downloadTasks.firstWhere((t) => t.id == taskId);

      // 检查是否启用 aria2
      final useAria2 = await _shouldUseAria2();

      for (final file in filesToDownload) {
        final cancelToken = CancelToken();
        _downloadCancelTokens['$taskId-${file.name}'] = cancelToken;

        try {
          file.isDownloading = true;

          final localFile = await _getSafeModelDownloadFile(
            modelName: modelName,
            fileName: file.name,
          );

          // 尝试使用 aria2
          if (useAria2) {
            final downloader = Aria2Downloader();
            final result = await downloader.downloadFile(
              url: file.url,
              savePath: localFile.path,
              onProgress: (received, total) {
                if (total > 0) {
                  file.progress = received / total;
                }
                onProgress(file, received, total);
              },
            );
            if (result.success) {
              await _ensureDownloadedFileExists(localFile);
              await _verifyDownloadedFile(localFile, file.sha256);
              file.isDownloading = false;
              file.isDownloaded = true;
              continue;
            }
            print(
                '[ModelManager] aria2 download failed for ${file.name}: ${result.errorMessage}, falling back to dio');
          }

          await _dio.download(
            file.url,
            localFile.path,
            cancelToken: cancelToken,
            onReceiveProgress: (received, total) {
              if (total > 0) {
                file.progress = received / total;
              }
              onProgress(file, received, total);
            },
            deleteOnError: true,
          );

          await _ensureDownloadedFileExists(localFile);
          await _verifyDownloadedFile(localFile, file.sha256);
          file.isDownloading = false;
          file.isDownloaded = true;
        } catch (e) {
          if (!cancelToken.isCancelled) {
            file.isDownloading = false;
            onError(e);
            task.errorMessage = e.toString();
            return;
          }
        }
      }

      task.isCompleted = true;
      onDone();
    }
  }

  void cancelFileDownload(String taskId, String fileName) {
    final token = _downloadCancelTokens['$taskId-$fileName'];
    if (token != null && !token.isCancelled) {
      token.cancel('用户取消下载');
    }
  }

  Future<File> _getSafeModelDownloadFile({
    required String modelName,
    required String fileName,
  }) async {
    final safeModelName = _safePathSegment(modelName, 'modelName');
    final safeFileName = _safePathSegment(fileName, 'fileName');
    final modelsDir = Directory(
      path.normalize(path.absolute(await getModelsDirectory())),
    );
    final modelDir = Directory(path.join(modelsDir.path, safeModelName));
    final localFile = File(path.join(modelDir.path, safeFileName));

    final modelDirPath =
        _normalizedDirectoryPath(path.normalize(path.absolute(modelDir.path)));
    final localFilePath = path.normalize(path.absolute(localFile.path));
    if (!localFilePath.startsWith(modelDirPath)) {
      throw StateError('Model download path is outside the model directory');
    }

    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    return localFile;
  }

  String _safePathSegment(String value, String label) {
    final segment = value.trim();
    if (segment.isEmpty) {
      throw ArgumentError.value(value, label, 'Path segment is empty');
    }
    if (segment == '.' ||
        segment == '..' ||
        segment.contains('..') ||
        segment.contains('/') ||
        segment.contains('\\') ||
        path.basename(segment) != segment) {
      throw ArgumentError.value(value, label, 'Invalid path segment');
    }
    return segment;
  }

  String _normalizedDirectoryPath(String directoryPath) {
    return directoryPath.endsWith(path.separator)
        ? directoryPath
        : '$directoryPath${path.separator}';
  }

  Future<void> _ensureDownloadedFileExists(File file) async {
    if (!await file.exists()) {
      throw StateError('Downloaded model file does not exist');
    }
    final stat = await file.stat();
    if (stat.size <= 1024) {
      throw StateError('Downloaded model file is invalid');
    }
  }

  Future<void> _verifyDownloadedFile(
    File file,
    String? expectedSha256,
  ) async {
    final expectedHash = expectedSha256?.trim().toLowerCase();
    if (expectedHash == null || expectedHash.isEmpty) {
      return;
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedHash)) {
      throw StateError('Model SHA256 format is invalid');
    }

    final actualHash = (await sha256.bind(file.openRead()).first).toString();
    if (actualHash.toLowerCase() == expectedHash) {
      return;
    }

    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
    throw StateError('Model SHA256 verification failed');
  }
}
