import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'model_manifest.dart';
import 'model_manager.dart';
import 'translate_cache.dart';

const String _systemPrompt = '''你是一个专业的影视元数据翻译工具。
你的唯一任务是：接收日语文本 → 输出中文翻译 → 结束。

请严格遵守以下规则：
1. 输出内容必须只有中文翻译结果，不要任何思考过程
2. 不要解释，不要添加任何前缀或后缀
3. 人名、作品名、编号等专有名词使用中文圈通用译法
4. 数字、年份、括号内的编号完全保持原样
5. 如果原文已是中文或英文，原样返回
6. 只输出翻译，不要其他内容！''';

const String _apiEndpoint = '/v1/chat/completions';

class TranslationResult {
  final String rawOutput;
  final String parsedOutput;

  TranslationResult({required this.rawOutput, required this.parsedOutput});
}

class TranslationLoopException implements Exception {
  final String message;
  final String partialOutput;

  TranslationLoopException(this.message, this.partialOutput);

  @override
  String toString() => 'TranslationLoopException: $message';
}

class TranslationTimeoutException implements Exception {
  final String message;
  final String partialOutput;

  TranslationTimeoutException(this.message, this.partialOutput);

  @override
  String toString() => 'TranslationTimeoutException: $message';
}

class TranslationCanceledException implements Exception {
  final String message;

  TranslationCanceledException(this.message);

  @override
  String toString() => 'TranslationCanceledException: $message';
}

class LocalTranslator {
  static final LocalTranslator _instance = LocalTranslator._internal();
  factory LocalTranslator() => _instance;
  LocalTranslator._internal();

  Process? _serverProcess;
  String? _loadedModelPath;
  ModelInfo? _loadedModelInfo;
  final TranslateCache _cache = TranslateCache();
  Future<void>? _modelLoadFuture;
  String? _modelLoadPath;
  final HttpClient _httpClient = HttpClient();
  bool _isServiceChecking = false;

  bool _isTranslationCanceled = false;
  Completer<void>? _translationCompleter;

  static const String _host = '127.0.0.1';
  static const int _port = 8080;

  bool get isLoaded => _loadedModelPath != null && _serverProcess != null;
  ModelInfo? get loadedModelInfo => _loadedModelInfo;

  bool get isTranslationCanceled => _isTranslationCanceled;

  void cancelTranslation() {
    _isTranslationCanceled = true;
    _translationCompleter?.complete();
    debugPrint('LocalTranslator: 翻译任务已取消');
  }

  void resetCancelFlag() {
    _isTranslationCanceled = false;
    _translationCompleter = null;
    debugPrint('LocalTranslator: 取消标志已重置');
  }

  Future<void> loadModel(String modelPath, ModelInfo modelInfo) async {
    if (_loadedModelPath == modelPath && _serverProcess != null) {
      final isHealthy = await checkServiceHealth();
      if (isHealthy) {
        debugPrint('LocalTranslator: 模型已加载，跳过');
        return;
      }
    }

    final activeLoad = _modelLoadFuture;
    if (activeLoad != null) {
      debugPrint('LocalTranslator: 正在初始化，等待当前加载完成');
      await activeLoad;
      if (_loadedModelPath == modelPath && _serverProcess != null) {
        final isHealthy = await checkServiceHealth();
        if (isHealthy) return;
      }
    }

    _modelLoadPath = modelPath;
    _modelLoadFuture = _loadModelInternal(modelPath, modelInfo);
    try {
      await _modelLoadFuture;
    } finally {
      if (_modelLoadPath == modelPath) {
        _modelLoadPath = null;
        _modelLoadFuture = null;
      }
    }
  }

  Future<void> _loadModelInternal(String modelPath, ModelInfo modelInfo) async {
    await unloadModel();

    try {
      debugPrint('LocalTranslator: 开始加载模型: $modelPath');

      final file = File(modelPath);
      if (!await file.exists()) {
        throw Exception('模型文件不存在: $modelPath');
      }

      final serverPath = await _findServerExecutable();
      if (serverPath == null) {
        throw Exception('找不到 llama-server.exe');
      }

      debugPrint('LocalTranslator: 启动 llama-server...');

      _serverProcess = await Process.start(
        serverPath,
        [
          '--model',
          modelPath,
          '--host',
          _host,
          '--port',
          _port.toString(),
          '-ngl',
          '99', // 使用 GPU
        ],
      );

      _serverProcess!.stdout.listen((data) {
        final output = utf8.decode(data);
        debugPrint('llama-server stdout: $output');

        // 检查是否成功加载
        if (output.contains('model loaded')) {
          debugPrint('LocalTranslator: 检测到模型加载完成');
        }
      });

      _serverProcess!.stderr.listen((data) {
        debugPrint('llama-server stderr: ${utf8.decode(data)}');
      });

      await _waitForServiceReady();

      _loadedModelPath = modelPath;
      _loadedModelInfo = modelInfo;
      debugPrint('LocalTranslator: 模型加载成功！');
    } catch (e, stackTrace) {
      debugPrint('LocalTranslator: 模型加载失败: $e');
      debugPrint('LocalTranslator: StackTrace: $stackTrace');
      await unloadModel();
      rethrow;
    }
  }

  Future<String?> _findServerExecutable() async {
    try {
      final exe = Platform.isWindows ? 'llama-server.exe' : 'llama-server';

      final possiblePaths = [
        path.join(path.dirname(Platform.resolvedExecutable), 'llama.cpp', exe),
        path.join(path.dirname(Platform.resolvedExecutable), exe),
      ];

      for (final serverPath in possiblePaths) {
        final file = File(serverPath);
        if (await file.exists()) {
          debugPrint('LocalTranslator: 找到 llama-server: $serverPath');
          return serverPath;
        }
      }
    } catch (e) {
      debugPrint('查找 llama-server 失败: $e');
    }
    return null;
  }

  Future<void> unloadModel() async {
    try {
      if (_serverProcess != null) {
        debugPrint('LocalTranslator: 停止 llama-server...');

        // 首先尝试正常终止
        _serverProcess!.kill(ProcessSignal.sigterm);

        // 等待进程退出，最多等待3秒
        final exitCode = await _serverProcess!.exitCode.timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            debugPrint('LocalTranslator: 进程未响应，强制终止...');
            // 如果进程没有正常退出，强制终止
            _serverProcess!.kill(ProcessSignal.sigkill);
            return -1;
          },
        );

        debugPrint('LocalTranslator: llama-server 已停止，退出码: $exitCode');
        _serverProcess = null;
      }
    } catch (e) {
      debugPrint('LocalTranslator: 停止服务失败: $e');
      // 即使失败，也将进程置为 null，以便后续可以重新启动
      _serverProcess = null;
    }

    _loadedModelPath = null;
    _loadedModelInfo = null;
  }

  Future<void> _waitForServiceReady() async {
    final stopwatch = Stopwatch()..start();
    const timeout = Duration(seconds: 90);
    while (stopwatch.elapsed < timeout) {
      if (_serverProcess == null) {
        throw StateError('Local AI service process is not running');
      }
      if (await checkServiceHealth()) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    throw TimeoutException('Local AI service startup timed out', timeout);
  }

  Future<TranslationResult> translateText({
    required String text,
    required String fieldHint,
    String? modelId,
    bool skipCache = false,
    void Function(String token, int index)? onToken,
  }) async {
    final stopwatch = Stopwatch()..start();
    debugPrint(
      'LocalTranslator.translateText: 开始翻译任务，文本: "$text"',
    );

    if (text.trim().isEmpty) {
      debugPrint('LocalTranslator.translateText: 文本为空，直接返回');
      return TranslationResult(rawOutput: text, parsedOutput: text);
    }

    // 如果提供了 modelId，确保服务已启动
    if (modelId != null) {
      debugPrint(
          'LocalTranslator.translateText: [${stopwatch.elapsedMilliseconds}ms] 检查服务状态...');
      try {
        await ensureServiceStarted(modelId: modelId);
        debugPrint(
            'LocalTranslator.translateText: [${stopwatch.elapsedMilliseconds}ms] 服务已就绪');
      } catch (e) {
        debugPrint(
            'LocalTranslator.translateText: [${stopwatch.elapsedMilliseconds}ms] 启动服务失败: $e');
        return TranslationResult(rawOutput: text, parsedOutput: text);
      }
    }

    // 再次检查服务是否真的启动了
    if (_serverProcess == null) {
      debugPrint(
          'LocalTranslator.translateText: [${stopwatch.elapsedMilliseconds}ms] 服务进程为null，返回原文');
      return TranslationResult(rawOutput: text, parsedOutput: text);
    }

    if (_loadedModelInfo != null && !skipCache) {
      debugPrint(
          'LocalTranslator.translateText: [${stopwatch.elapsedMilliseconds}ms] 检查缓存...');
      final cached = await _cache.get(_loadedModelInfo!.id, fieldHint, text);
      if (cached != null) {
        debugPrint(
            'LocalTranslator.translateText: [${stopwatch.elapsedMilliseconds}ms] 使用缓存结果');
        return TranslationResult(rawOutput: cached, parsedOutput: cached);
      }
      debugPrint(
          'LocalTranslator.translateText: [${stopwatch.elapsedMilliseconds}ms] 缓存未命中');
    }

    final prompt = _buildPrompt(text, fieldHint);
    debugPrint(
        'LocalTranslator.translateText: [${stopwatch.elapsedMilliseconds}ms] 开始调用 _translateViaServer...');

    String rawResult = text;
    bool isTranslationSuccessful = false;

    try {
      if (_isTranslationCanceled) {
        throw TranslationCanceledException('翻译已被取消');
      }

      rawResult = await _translateViaServer(prompt, onToken: onToken);
      isTranslationSuccessful = true;
      debugPrint(
          'LocalTranslator.translateText: [${stopwatch.elapsedMilliseconds}ms] 翻译成功');
    } catch (e, stackTrace) {
      debugPrint(
          'LocalTranslator.translateText: [${stopwatch.elapsedMilliseconds}ms] 翻译失败: $e');
      debugPrint('LocalTranslator.translateText: StackTrace: $stackTrace');
      rawResult = text;
      isTranslationSuccessful = false;
    }

    final parsedResult = _parseResult(rawResult, fallback: text);

    // 只有当翻译成功且结果不等于原文时才保存到缓存
    if (_loadedModelInfo != null &&
        isTranslationSuccessful &&
        parsedResult != text) {
      debugPrint(
          'LocalTranslator.translateText: [${stopwatch.elapsedMilliseconds}ms] 保存到缓存...');
      await _cache.put(_loadedModelInfo!.id, fieldHint, text, parsedResult);
    }

    debugPrint(
        'LocalTranslator.translateText: [${stopwatch.elapsedMilliseconds}ms] 任务完成!');
    return TranslationResult(rawOutput: rawResult, parsedOutput: parsedResult);
  }

  Future<String> _translateViaServer(String prompt,
      {void Function(String, int)? onToken}) async {
    final stopwatch = Stopwatch()..start();
    final StringBuffer fullContent = StringBuffer();
    int tokenCount = 0;

    // 循环检测相关
    final List<String> recentChunks = [];
    const int maxRecentChunks = 20;
    const int loopThreshold = 3;
    int loopCount = 0;

    // 超时控制：60秒
    const Duration timeout = Duration(seconds: 60);

    try {
      debugPrint(
          'LocalTranslator: [${stopwatch.elapsedMilliseconds}ms] 开始发送请求到 llama-server (流式模式)');

      final request = await _httpClient.post(_host, _port, _apiEndpoint);
      debugPrint(
          'LocalTranslator: [${stopwatch.elapsedMilliseconds}ms] 请求对象已创建，端点: $_apiEndpoint');

      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set('Accept', 'text/event-stream');

      final jsonBody = jsonEncode({
        'model': _loadedModelInfo?.id ?? 'default',
        'messages': [
          {
            'role': 'system',
            'content': _systemPrompt,
          },
          {
            'role': 'user',
            'content': prompt,
          },
        ],
        'temperature': 0.3,
        'stream': true,
        'max_tokens': 512,
        'chat_template_kwargs': {
          'enable_thinking': false,
        },
      });

      debugPrint(
          'LocalTranslator: [${stopwatch.elapsedMilliseconds}ms] 发送请求体...');
      request.write(jsonBody);

      debugPrint(
          'LocalTranslator: [${stopwatch.elapsedMilliseconds}ms] 等待响应...');
      final response = await request.close();
      debugPrint(
          'LocalTranslator: [${stopwatch.elapsedMilliseconds}ms] 收到响应，状态码: ${response.statusCode}');

      debugPrint(
          'LocalTranslator: [${stopwatch.elapsedMilliseconds}ms] 开始流式读取响应...');

      final completer = Completer<void>();

      response.transform(utf8.decoder).transform(const LineSplitter()).listen(
        (line) async {
          // 检查取消
          if (_isTranslationCanceled) {
            debugPrint(
                'LocalTranslator: [${stopwatch.elapsedMilliseconds}ms] 翻译被取消');
            completer.completeError(TranslationCanceledException('翻译已被用户取消'));
            return;
          }

          // 检查超时
          if (stopwatch.elapsed > timeout) {
            debugPrint(
                'LocalTranslator: [${stopwatch.elapsedMilliseconds}ms] 超时！已运行 ${stopwatch.elapsedMilliseconds}ms');
            completer.completeError(TranslationTimeoutException(
              'AI响应超时（${timeout.inSeconds}秒），内容已生成: ${fullContent.length} 字符',
              fullContent.toString(),
            ));
            return;
          }

          if (line.trim().isEmpty) return;

          if (line.startsWith('data: ')) {
            final jsonStr = line.substring(6).trim();
            if (jsonStr.isEmpty || jsonStr == '[DONE]') return;

            try {
              final json = jsonDecode(jsonStr) as Map<String, dynamic>;

              // 处理 /v1/chat/completions 格式
              String? content;
              final choices = json['choices'] as List?;
              if (choices != null && choices.isNotEmpty) {
                final choice = choices[0] as Map<String, dynamic>;
                final delta = choice['delta'] as Map<String, dynamic>?;
                content = delta?['content'] as String?;
              } else {
                // 兼容旧格式
                content = json['content'] as String?;
              }

              if (content != null && content.isNotEmpty) {
                fullContent.write(content);
                tokenCount++;

                // 循环检测
                if (content.length >= 5) {
                  recentChunks.add(content);
                  if (recentChunks.length > maxRecentChunks) {
                    recentChunks.removeAt(0);
                  }

                  // 检测重复模式
                  if (recentChunks.length >= loopThreshold * 2) {
                    final lastN = recentChunks
                        .sublist(recentChunks.length - loopThreshold);
                    final previousN = recentChunks.sublist(
                        recentChunks.length - loopThreshold * 2,
                        recentChunks.length - loopThreshold);

                    if (_isSimilarContent(lastN, previousN)) {
                      loopCount++;
                      if (loopCount >= 2) {
                        debugPrint(
                            'LocalTranslator: [${stopwatch.elapsedMilliseconds}ms] 检测到循环重复！触发重试');
                        completer.completeError(TranslationLoopException(
                          '检测到AI输出循环重复，已生成内容: ${fullContent.length} 字符',
                          fullContent.toString(),
                        ));
                        return;
                      }
                    } else {
                      loopCount = 0;
                    }
                  }
                }

                if (tokenCount <= 10 || tokenCount % 20 == 0) {
                  debugPrint(
                      'LocalTranslator: [${stopwatch.elapsedMilliseconds}ms] 收到 token #$tokenCount: "$content"');
                }

                onToken?.call(content, tokenCount);
              }
            } catch (e) {
              if (e is TranslationLoopException ||
                  e is TranslationTimeoutException) {
                return;
              }
              debugPrint('LocalTranslator: 解析流数据失败: $e, 数据: $jsonStr');
            }
          }
        },
        onError: (e) {
          debugPrint(
              'LocalTranslator: [${stopwatch.elapsedMilliseconds}ms] 流式读取错误: $e');
          completer.completeError(e);
        },
        onDone: () {
          debugPrint(
              'LocalTranslator: [${stopwatch.elapsedMilliseconds}ms] 流式读取完成');
          completer.complete();
        },
      );

      await completer.future;

      final result = fullContent.toString();
      debugPrint(
          'LocalTranslator: [${stopwatch.elapsedMilliseconds}ms] 流式读取完成，共 $tokenCount 个 tokens');

      if (result.length < 500) {
        debugPrint('llama-server 完整响应: $result');
      } else {
        debugPrint(
            'llama-server 完整响应: ${result.substring(0, 500)}...[截断，共 ${result.length} 字符]');
      }

      debugPrint('LocalTranslator: [${stopwatch.elapsedMilliseconds}ms] 翻译完成!');
      return result;
    } catch (e, stackTrace) {
      debugPrint(
          'LocalTranslator: [${stopwatch.elapsedMilliseconds}ms] 调用 llama-server 失败: $e');
      debugPrint('LocalTranslator: StackTrace: $stackTrace');
      rethrow;
    } finally {
      stopwatch.stop();
      debugPrint('LocalTranslator: 总耗时: ${stopwatch.elapsedMilliseconds}ms');
    }
  }

  Future<Map<String, String>> translateBatch(
    Map<String, String> fields,
  ) async {
    final result = <String, String>{};
    for (final entry in fields.entries) {
      final translationResult = await translateText(
        text: entry.value,
        fieldHint: entry.key,
      );
      result[entry.key] = translationResult.parsedOutput;
    }
    return result;
  }

  Future<String> completeText({
    required String modelId,
    required String systemPrompt,
    required String userPrompt,
    double temperature = 0.2,
    int maxTokens = 1024,
  }) async {
    await ensureServiceStarted(modelId: modelId);
    if (_serverProcess == null) {
      throw StateError('Local AI service is not running');
    }

    final request = await _httpClient.post(_host, _port, _apiEndpoint);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set('Accept', 'text/event-stream');
    request.write(jsonEncode({
      'model': _loadedModelInfo?.id ?? modelId,
      'messages': [
        {
          'role': 'system',
          'content': systemPrompt,
        },
        {
          'role': 'user',
          'content': userPrompt,
        },
      ],
      'temperature': temperature,
      'stream': true,
      'max_tokens': maxTokens,
      'chat_template_kwargs': {
        'enable_thinking': false,
      },
    }));

    final response = await request.close();
    if (response.statusCode != 200) {
      final body = await response.transform(utf8.decoder).join();
      throw HttpException(
        'Local AI request failed: ${response.statusCode} $body',
      );
    }

    final content = StringBuffer();
    await for (final line
        in response.transform(utf8.decoder).transform(const LineSplitter())) {
      final trimmedLine = line.trim();
      if (!trimmedLine.startsWith('data: ')) continue;
      final jsonText = trimmedLine.substring(6).trim();
      if (jsonText.isEmpty || jsonText == '[DONE]') continue;

      final data = jsonDecode(jsonText) as Map<String, dynamic>;
      final choices = data['choices'] as List?;
      if (choices != null && choices.isNotEmpty) {
        final choice = choices.first as Map<String, dynamic>;
        final delta = choice['delta'] as Map<String, dynamic>?;
        final token = delta?['content'] as String?;
        if (token != null) {
          content.write(token);
        }
      } else {
        final token = data['content'] as String?;
        if (token != null) {
          content.write(token);
        }
      }
    }

    return content.toString().trim();
  }

  String _buildPrompt(String text, String hint) {
    return hint == 'title'
        ? '翻译影片标题：$text'
        : hint == 'plot'
            ? '翻译剧情简介：$text'
            : '翻译以下内容：$text';
  }

  String _parseResult(String raw, {required String fallback}) {
    var s = raw.trim();
    debugPrint('LocalTranslator: 解析原始输出: $s');

    // 移除思考标签（包括 HTML/XML 风格）
    s = s.replaceAll(RegExp(r'<think>[\s\S]*?</think>', multiLine: true), '');
    s = s.replaceAll(RegExp(r'</?think>'), '');

    // 移除英文思考过程（包括 Thinking Process 等）
    s = s.replaceAll(
        RegExp(r'Thinking\s*Process:?[\s\S]*?(?=\n\n|$)',
            caseSensitive: false, multiLine: true),
        '');
    s = s.replaceAll(
        RegExp(r'Analyze\s*(the)?\s*(Request|Input)[\s\S]*?(?=\n\n|$)',
            caseSensitive: false, multiLine: true),
        '');

    // 移除编号列表格式的思考内容（1. 2. 3.）
    s = s.replaceAll(
        RegExp(r'^\s*\d+\.\s*[\s\S]*?(?=\n\n|$)',
            caseSensitive: false, multiLine: true),
        '');

    // 移除中文思考相关文字
    s = s.replaceAll(RegExp(r'分析过程:?|思考过程:?'), '');

    // 移除引号
    s = s.replaceAll(RegExp(r'^["「]+|["」]+$'), '');

    // 清除多余的空白和空行
    s = s.replaceAll(RegExp(r'\n\s*\n'), '\n');
    s = s.trim();

    if (s.contains('<src>')) {
      debugPrint('LocalTranslator: 解析结果包含特殊标记，使用原文');
      return fallback;
    }
    if (s.isEmpty) {
      debugPrint('LocalTranslator: 解析结果为空，使用原文');
      return fallback;
    }
    debugPrint('LocalTranslator: 返回解析结果: $s');
    return s;
  }

  Future<void> clearCache() async {
    await _cache.clear();
  }

  /// 检查服务是否健康运行
  Future<bool> checkServiceHealth() async {
    if (_isServiceChecking) return false;
    _isServiceChecking = true;
    try {
      if (_serverProcess == null) {
        debugPrint('LocalTranslator: 服务进程不存在');
        return false;
      }

      final request = await _httpClient.get(_host, _port, '/health');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close();
      final isHealthy = response.statusCode == 200;
      debugPrint('LocalTranslator: 服务健康检查结果: $isHealthy');
      return isHealthy;
    } catch (e) {
      debugPrint('LocalTranslator: 服务健康检查失败: $e');
      return false;
    } finally {
      _isServiceChecking = false;
    }
  }

  /// 确保服务已启动并加载模型
  Future<void> ensureServiceStarted({
    required String modelId,
  }) async {
    // 首先检查服务是否已加载且健康
    if (_serverProcess != null &&
        _loadedModelPath != null &&
        _loadedModelInfo?.id == modelId) {
      final isHealthy = await checkServiceHealth();
      if (isHealthy) {
        debugPrint('LocalTranslator: 服务已启动且健康，无需重新启动');
        return;
      }
      debugPrint('LocalTranslator: 服务不健康，需要重新启动');
    }

    // 获取模型信息 - 包括自定义下载的模型
    final modelManager = ModelManager();
    final allModels = await modelManager.getAllAvailableModels();
    final modelInfo = allModels.firstWhere(
      (m) => m.id == modelId,
      orElse: () => throw Exception('找不到模型: $modelId'),
    );

    // 检查模型是否已下载
    final isDownloaded = await modelManager.isModelDownloaded(modelInfo);
    if (!isDownloaded) {
      throw Exception('模型未下载: $modelId');
    }

    // 获取模型文件路径
    final modelFile = await modelManager.getModelFile(modelInfo);
    final modelPath = modelFile.path;

    debugPrint('LocalTranslator: 正在启动服务，模型: $modelPath');
    await loadModel(modelPath, modelInfo);
  }

  /// 检测两段内容是否相似（用于循环检测）
  bool _isSimilarContent(List<String> chunks1, List<String> chunks2) {
    if (chunks1.length != chunks2.length) return false;

    int matchCount = 0;
    for (int i = 0; i < chunks1.length; i++) {
      if (chunks1[i] == chunks2[i]) {
        matchCount++;
      }
    }

    // 如果超过60%的chunk相同，认为是重复模式
    return matchCount >= (chunks1.length * 0.6);
  }
}
