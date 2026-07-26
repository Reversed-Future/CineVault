import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import '../models/notification.dart';
import '../ai/local_translator.dart';
import '../ai/model_manager.dart';
import '../ai/model_manifest.dart';
import '../services/database_service.dart';
import 'notification_provider.dart';
import 'movie_providers.dart';

class FullTranslationResult {
  final String rawOutput;
  final String parsedOutput;

  FullTranslationResult({required this.rawOutput, required this.parsedOutput});
}

class StreamOutputState {
  final String sourceText;
  final String currentOutput;
  final List<StreamToken> tokens;
  final bool isComplete;

  const StreamOutputState({
    this.sourceText = '',
    this.currentOutput = '',
    this.tokens = const [],
    this.isComplete = false,
  });

  StreamOutputState copyWith({
    String? sourceText,
    String? currentOutput,
    List<StreamToken>? tokens,
    bool? isComplete,
  }) {
    return StreamOutputState(
      sourceText: sourceText ?? this.sourceText,
      currentOutput: currentOutput ?? this.currentOutput,
      tokens: tokens ?? this.tokens,
      isComplete: isComplete ?? this.isComplete,
    );
  }
}

class StreamToken {
  final String text;
  final int index;
  final int timestamp;

  StreamToken({
    required this.text,
    required this.index,
    required this.timestamp,
  });
}

// 后台翻译状态
class BackgroundTranslationState {
  final bool isTranslating;
  final bool isPaused;
  final int totalMovies;
  final int completedMovies;
  final String? currentMovie;
  final StreamOutputState streamOutput;

  BackgroundTranslationState({
    this.isTranslating = false,
    this.isPaused = false,
    this.totalMovies = 0,
    this.completedMovies = 0,
    this.currentMovie,
    this.streamOutput = const StreamOutputState(),
  });

  BackgroundTranslationState copyWith({
    bool? isTranslating,
    bool? isPaused,
    int? totalMovies,
    int? completedMovies,
    String? currentMovie,
    StreamOutputState? streamOutput,
  }) {
    return BackgroundTranslationState(
      isTranslating: isTranslating ?? this.isTranslating,
      isPaused: isPaused ?? this.isPaused,
      totalMovies: totalMovies ?? this.totalMovies,
      completedMovies: completedMovies ?? this.completedMovies,
      currentMovie: currentMovie ?? this.currentMovie,
      streamOutput: streamOutput ?? this.streamOutput,
    );
  }
}

// 后台翻译 Provider
class BackgroundTranslationNotifier
    extends Notifier<BackgroundTranslationState> {
  @override
  BackgroundTranslationState build() {
    return BackgroundTranslationState();
  }

  void pauseTranslation() {
    if (state.isTranslating && !state.isPaused) {
      state = state.copyWith(isPaused: true);
      debugPrint('BackgroundTranslation: 翻译已暂停');
    }
  }

  void resumeTranslation() {
    if (state.isTranslating && state.isPaused) {
      state = state.copyWith(isPaused: false);
      debugPrint('BackgroundTranslation: 翻译已继续');
    }
  }

  void stopTranslation() {
    if (state.isTranslating) {
      debugPrint('BackgroundTranslation: 正在停止翻译...');

      // 取消当前正在进行的翻译
      LocalTranslator().cancelTranslation();

      state = state.copyWith(
        isTranslating: false,
        isPaused: false,
        currentMovie: null,
      );
      debugPrint('BackgroundTranslation: 翻译已停止');
    }
  }

  Future<void> startBackgroundTranslation() async {
    if (state.isTranslating) return;

    // 重置取消标志
    LocalTranslator().resetCancelFlag();

    // 获取所有需要翻译的影片（未翻译过标题或标签的影片）
    final allMovies = DatabaseService.getAllMovies();
    final moviesToTranslate = allMovies.where((movie) {
      final needsNameTranslation =
          movie.translatedName == null || movie.translatedName!.isEmpty;
      final needsTagsTranslation =
          movie.translatedTags == null || movie.translatedTags!.isEmpty;
      return needsNameTranslation || needsTagsTranslation;
    }).toList();

    if (moviesToTranslate.isEmpty) {
      // 没有需要翻译的影片
      await ref.read(notificationProvider.notifier).addNotification(
            title: '翻译完成',
            message: '没有需要翻译的影片',
            type: AppNotificationType.info,
          );
      return;
    }

    // 开始后台翻译
    state = state.copyWith(
      isTranslating: true,
      totalMovies: moviesToTranslate.length,
      completedMovies: 0,
      currentMovie: null,
    );

    // 初始化翻译服务
    final translationService = ref.read(translationServiceProvider);

    // 多次尝试初始化，最多等待 30 秒
    bool initialized = false;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        initialized = await translationService.initialize();
        if (initialized) {
          debugPrint('BackgroundTranslation: 翻译服务初始化成功');
          break;
        }
      } catch (e) {
        debugPrint('BackgroundTranslation: 初始化尝试 $attempt 失败: $e');
        if (attempt < 3) {
          await Future.delayed(Duration(seconds: attempt * 5));
        }
      }
    }

    if (!initialized) {
      state = state.copyWith(isTranslating: false);
      await ref.read(notificationProvider.notifier).addNotification(
            title: '翻译失败',
            message: '翻译服务初始化失败，请检查AI设置',
            type: AppNotificationType.error,
          );
      return;
    }

    int successCount = 0;
    int failCount = 0;
    bool wasStopped = false;

    for (int i = 0; i < moviesToTranslate.length; i++) {
      // 检查是否被停止
      if (!state.isTranslating) {
        wasStopped = true;
        break;
      }

      // 检查是否暂停，如果暂停则等待
      while (state.isPaused) {
        await Future.delayed(const Duration(milliseconds: 100));
        // 再次检查是否被停止
        if (!state.isTranslating) {
          wasStopped = true;
          break;
        }
      }

      if (wasStopped) {
        break;
      }

      final movie = moviesToTranslate[i];

      // 更新当前翻译状态
      state = state.copyWith(
        completedMovies: i,
        currentMovie: movie.name,
        streamOutput: StreamOutputState(
          sourceText: movie.name,
          currentOutput: '',
          tokens: [],
          isComplete: false,
        ),
      );

      try {
        final translatedMovie = await translationService.translateMovie(
          movie,
          onToken: (token, index) {
            final currentState = state;
            if (!currentState.isTranslating) return;

            final newTokens =
                List<StreamToken>.from(currentState.streamOutput.tokens)
                  ..add(StreamToken(
                    text: token,
                    index: index,
                    timestamp: DateTime.now().millisecondsSinceEpoch,
                  ));

            final newOutput = currentState.streamOutput.currentOutput + token;

            state = BackgroundTranslationState(
              isTranslating: currentState.isTranslating,
              isPaused: currentState.isPaused,
              totalMovies: currentState.totalMovies,
              completedMovies: currentState.completedMovies,
              currentMovie: currentState.currentMovie,
              streamOutput: StreamOutputState(
                sourceText: currentState.streamOutput.sourceText,
                currentOutput: newOutput,
                tokens: newTokens,
                isComplete: currentState.streamOutput.isComplete,
              ),
            );
          },
        );

        await DatabaseService.updateMovieWithLatest(
          movie.id,
          (latestMovie) => latestMovie.copyWith(
            translatedName: translatedMovie.translatedName,
            translatedTags: translatedMovie.translatedTags,
            translatedPlot: translatedMovie.translatedPlot,
          ),
        );
        successCount++;

        // 更新流式输出状态为完成
        state = state.copyWith(
          streamOutput: state.streamOutput.copyWith(
            isComplete: true,
          ),
        );
      } catch (e) {
        debugPrint('翻译影片失败: $e');
        failCount++;
      }

      // 每翻译完一个影片后，稍作等待，避免连续请求导致 llama-server 负载过高
      if (i < moviesToTranslate.length - 1) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    // 翻译完成或停止
    state = state.copyWith(
      isTranslating: false,
      isPaused: false,
      currentMovie: null,
    );

    // 刷新影片列表
    ref.refresh(moviesProvider);

    // 发送通知
    if (wasStopped) {
      final remaining = moviesToTranslate.length - successCount - failCount;
      await ref.read(notificationProvider.notifier).addNotification(
            title: '翻译已停止',
            message: '已翻译 $successCount 部影片，剩余 $remaining 部未翻译',
            type: AppNotificationType.info,
          );
    } else {
      final message =
          '成功翻译 $successCount 部影片${failCount > 0 ? '，失败 $failCount 部' : ''}';
      await ref.read(notificationProvider.notifier).addNotification(
            title: '翻译完成',
            message: message,
            type: failCount > 0
                ? AppNotificationType.warning
                : AppNotificationType.success,
          );
    }
  }
}

final backgroundTranslationProvider =
    NotifierProvider<BackgroundTranslationNotifier, BackgroundTranslationState>(
  () => BackgroundTranslationNotifier(),
);

final translationServiceProvider = Provider<TranslationService>(
  (ref) => TranslationService(),
);

class TranslationService {
  final LocalTranslator _translator = LocalTranslator();

  bool get hasLoadedModel => _translator.isLoaded;
  String? get loadedModelName => _translator.loadedModelInfo?.name;

  Future<bool> initialize() async {
    try {
      print('TranslationService: 开始初始化...');

      final settings = DatabaseService.getSettings();
      final modelId = settings.selectedModelId;
      final aiEnabled = settings.aiTranslationEnabled;

      print('TranslationService: AI启用状态: $aiEnabled');
      print('TranslationService: 选择的模型ID: $modelId');

      if (!aiEnabled) {
        print('TranslationService: AI翻译未启用');
        return false;
      }

      if (modelId == null) {
        print('TranslationService: 未选择模型');
        return false;
      }

      final modelManager = ModelManager();

      print('TranslationService: 获取所有可用模型...');
      final allModels = await modelManager.getAllAvailableModels();

      print('TranslationService: 查找模型信息...');
      ModelInfo? modelInfo;
      try {
        modelInfo = allModels.firstWhere(
          (m) => m.id == modelId,
        );
        print('TranslationService: 找到模型: ${modelInfo.name}');
      } catch (e) {
        print('TranslationService: 找不到模型ID: $modelId');
        return false;
      }

      print('TranslationService: 检查模型是否已下载...');
      final isDownloaded = await modelManager.isModelDownloaded(modelInfo);
      if (!isDownloaded) {
        print('TranslationService: 模型未下载');
        return false;
      }

      print('TranslationService: 获取模型文件...');
      final modelFile = await modelManager.getModelFile(modelInfo);
      print('TranslationService: 模型文件路径: ${modelFile.path}');

      print('TranslationService: 加载模型...');
      await _translator.loadModel(modelFile.path, modelInfo);

      print('TranslationService: 模型加载成功!');
      return true;
    } catch (e, stackTrace) {
      print('TranslationService: 初始化失败: $e');
      print('TranslationService: StackTrace: $stackTrace');
      return false;
    }
  }

  Future<String> translate({
    required String text,
    required String fieldHint,
    String? modelId,
    bool skipCache = false,
  }) async {
    // 如果没有提供 modelId，从设置中获取
    final targetModelId =
        modelId ?? DatabaseService.getSettings().selectedModelId;

    final result = await _translator.translateText(
      text: text,
      fieldHint: fieldHint,
      modelId: targetModelId,
      skipCache: skipCache,
    );

    return result.parsedOutput;
  }

  Future<FullTranslationResult> translateWithRawOutput({
    required String text,
    required String fieldHint,
    String? modelId,
    bool skipCache = false,
  }) async {
    // 如果没有提供 modelId，从设置中获取
    final targetModelId =
        modelId ?? DatabaseService.getSettings().selectedModelId;

    final result = await _translator.translateText(
      text: text,
      fieldHint: fieldHint,
      modelId: targetModelId,
      skipCache: skipCache,
    );

    return FullTranslationResult(
      rawOutput: result.rawOutput,
      parsedOutput: result.parsedOutput,
    );
  }

  Future<Movie> translateMovie(Movie movie,
      {String? modelId,
      int maxRetries = 3,
      void Function(String, int)? onToken,
      bool forceTranslate = false}) async {
    final targetModelId =
        modelId ?? DatabaseService.getSettings().selectedModelId;

    // 如果没有选择模型，直接返回
    if (targetModelId == null) {
      return movie;
    }

    String? translatedName = movie.translatedName;

    // 只翻译标题（除非 forceTranslate 为 true，强制重新翻译）
    final shouldTranslate = forceTranslate ||
        (movie.name.isNotEmpty &&
            (translatedName == null || translatedName.isEmpty));

    if (shouldTranslate) {
      for (int retry = 0; retry < maxRetries; retry++) {
        try {
          final result = await _translator.translateText(
            text: movie.name,
            fieldHint: 'title',
            modelId: targetModelId,
            onToken: onToken,
            skipCache: forceTranslate, // 强制翻译时跳过缓存
          );
          translatedName = result.parsedOutput;
          break;
        } on TranslationLoopException catch (e) {
          print('检测到AI输出循环重复 (尝试 ${retry + 1}/$maxRetries): ${e.message}');
          if (retry < maxRetries - 1) {
            print('将在1秒后重试...');
            await Future.delayed(const Duration(seconds: 1));
          }
        } on TranslationTimeoutException catch (e) {
          print('AI响应超时 (尝试 ${retry + 1}/$maxRetries): ${e.message}');
          if (retry < maxRetries - 1) {
            print('将在1秒后重试...');
            await Future.delayed(const Duration(seconds: 1));
          }
        } catch (e) {
          print('翻译标题失败 (尝试 ${retry + 1}/$maxRetries): $e');
          if (retry < maxRetries - 1) {
            await Future.delayed(Duration(seconds: retry + 1));
          }
        }
      }
    }

    return movie.copyWith(
      translatedName: translatedName,
    );
  }

  Future<List<Movie>> translateMovies(List<Movie> movies,
      {String? modelId}) async {
    final results = <Movie>[];
    for (final movie in movies) {
      final translated = await translateMovie(movie, modelId: modelId);
      results.add(translated);
    }
    return results;
  }
}
