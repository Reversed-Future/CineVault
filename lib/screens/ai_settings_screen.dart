import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../ai/model_manifest.dart';
import '../ai/model_manager.dart';
import '../ai/local_translator.dart';
import '../services/database_service.dart';
import '../models/app_settings.dart';
import '../models/movie.dart';
import 'translation_list_screen.dart';

AppSettings buildAiSettingsUpdate(
  AppSettings current, {
  required bool aiTranslationEnabled,
  required String? selectedModelId,
  required String? customModelsPath,
  required int aiThreadCount,
  required bool fallbackToOriginal,
  required bool unloadModelAfterAiTagging,
}) {
  return current.copyWith(
    aiTranslationEnabled: aiTranslationEnabled,
    selectedModelId: selectedModelId,
    clearSelectedModelId: selectedModelId == null,
    customModelsPath: customModelsPath,
    clearCustomModelsPath: customModelsPath == null || customModelsPath.isEmpty,
    aiThreadCount: aiThreadCount,
    fallbackToOriginal: fallbackToOriginal,
    unloadModelAfterAiTagging: unloadModelAfterAiTagging,
  );
}

class AISettingsScreen extends ConsumerStatefulWidget {
  const AISettingsScreen({super.key});

  @override
  ConsumerState<AISettingsScreen> createState() => _AISettingsScreenState();
}

class _AISettingsScreenState extends ConsumerState<AISettingsScreen> {
  final ModelManager _modelManager = ModelManager();
  final LocalTranslator _translator = LocalTranslator();
  Map<String, bool> _downloadedModels = {};
  List<ModelInfo> _allModels = [];
  bool _isLoading = true;
  String? _downloadingModelId;
  double _downloadProgress = 0.0;
  String? _customModelsPath;
  String? _currentModelsPath;
  bool _aiEnabled = false;
  String? _selectedModelId;
  int _threadCount = 4;
  bool _fallbackToOriginal = true;
  bool _unloadModelAfterAiTagging = false;

  @override
  void initState() {
    super.initState();
    _initializeAndLoadModels();
  }

  Future<void> _initializeAndLoadModels() async {
    final defaultPath = await _modelManager.getDefaultModelsPath();

    final settings = DatabaseService.getSettings();

    setState(() {
      _currentModelsPath = defaultPath;
      _customModelsPath = settings.customModelsPath;
      if (_customModelsPath != null && _customModelsPath!.isNotEmpty) {
        _currentModelsPath = _customModelsPath;
      }
      _aiEnabled = settings.aiTranslationEnabled;
      _selectedModelId = settings.selectedModelId;
      _threadCount = settings.aiThreadCount;
      _fallbackToOriginal = settings.fallbackToOriginal;
      _unloadModelAfterAiTagging = settings.unloadModelAfterAiTagging;
    });

    await _modelManager.setCustomModelsPath(_customModelsPath);
    await _loadModels();
  }

  Future<void> _loadModels() async {
    if (!mounted) return;

    try {
      final downloaded = await _modelManager.getDownloadedModels();
      final allModels = await _modelManager.getAllAvailableModels();

      for (final model in allModels) {
        if (!downloaded.containsKey(model.id)) {
          downloaded[model.id] = await _modelManager.isModelDownloaded(model);
        }
      }

      if (!mounted) return;
      setState(() {
        _downloadedModels = downloaded;
        _allModels = allModels;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    final current = DatabaseService.getSettings();
    final settings = buildAiSettingsUpdate(
      current,
      aiTranslationEnabled: _aiEnabled,
      selectedModelId: _selectedModelId,
      customModelsPath: _customModelsPath,
      aiThreadCount: _threadCount,
      fallbackToOriginal: _fallbackToOriginal,
      unloadModelAfterAiTagging: _unloadModelAfterAiTagging,
    );
    try {
      await DatabaseService.saveSettings(settings);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('AI设置保存失败: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _toggleAIEnabled(bool value) async {
    setState(() {
      _aiEnabled = value;
    });
    await _saveSettings();
  }

  Future<void> _selectModel(ModelInfo model) async {
    setState(() {
      _selectedModelId = model.id;
    });
    await _saveSettings();
  }

  Future<void> _downloadModel(ModelInfo model) async {
    if (!mounted) return;

    setState(() {
      _downloadingModelId = model.id;
      _downloadProgress = 0.0;
    });

    await _modelManager.downloadModel(
      model: model,
      onProgress: (received, total) {
        if (!mounted) return;
        if (total > 0) {
          setState(() {
            _downloadProgress = received / total;
          });
        }
      },
      onDone: () async {
        if (!mounted) return;
        setState(() {
          _downloadingModelId = null;
          _downloadProgress = 0.0;
        });
        await _loadModels();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('模型 ${model.name} 下载完成')),
        );
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _downloadingModelId = null;
          _downloadProgress = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $error')),
        );
      },
    );
  }

  Future<void> _deleteModel(ModelInfo model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除模型 ${model.name} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _modelManager.deleteModel(model);
      await _loadModels();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('模型 ${model.name} 已删除')),
      );
    }
  }

  Future<void> _selectCustomPath() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null) {
      setState(() {
        _customModelsPath = path;
        _currentModelsPath = path;
      });
      await _modelManager.setCustomModelsPath(path);
      await _saveSettings();
      await _loadModels();
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _translateAllMovies() async {
    if (!_aiEnabled || _selectedModelId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先启用AI翻译并选择模型')),
      );
      return;
    }

    final movies = DatabaseService.getAllMovies();
    final moviesWithoutTranslation = movies
        .where(
          (m) => m.translatedName == null || m.translatedName!.isEmpty,
        )
        .toList();

    if (moviesWithoutTranslation.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所有影片都已有翻译')),
      );
      return;
    }

    final currentContext = context;
    showDialog(
      context: currentContext,
      barrierDismissible: false,
      builder: (context) => _TranslationProgressDialog(
        movies: moviesWithoutTranslation,
        modelId: _selectedModelId!,
        threadCount: _threadCount,
      ),
    );
  }

  Widget _buildAIEnabledSection() {
    return Card(
      child: SwitchListTile(
        title: const Text('启用AI翻译'),
        subtitle: const Text('使用本地AI模型进行翻译'),
        value: _aiEnabled,
        onChanged: _toggleAIEnabled,
      ),
    );
  }

  Widget _buildCustomPathSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '模型存储位置',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentModelsPath ?? '未设置',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  if (_customModelsPath != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '自定义位置',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _selectCustomPath,
              icon: const Icon(Icons.folder_open),
              label: Text(_customModelsPath == null ? '选择位置' : '更改位置'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '高级设置',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('AI分类完成后卸载模型'),
              subtitle: const Text('释放 llama.cpp server 占用的显存和内存'),
              value: _unloadModelAfterAiTagging,
              onChanged: (value) {
                setState(() {
                  _unloadModelAfterAiTagging = value;
                });
                _saveSettings();
              },
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('线程数'),
              subtitle: Text('当前: $_threadCount'),
              trailing: DropdownButton<int>(
                value: _threadCount,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1')),
                  DropdownMenuItem(value: 2, child: Text('2')),
                  DropdownMenuItem(value: 4, child: Text('4')),
                  DropdownMenuItem(value: 6, child: Text('6')),
                  DropdownMenuItem(value: 8, child: Text('8')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _threadCount = value;
                    });
                    _saveSettings();
                  }
                },
              ),
            ),
            SwitchListTile(
              title: const Text('失败时回退原文'),
              subtitle: const Text('当翻译失败时显示原始文本'),
              value: _fallbackToOriginal,
              onChanged: (value) {
                setState(() {
                  _fallbackToOriginal = value;
                });
                _saveSettings();
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _translateAllMovies,
              icon: const Icon(Icons.translate),
              label: const Text('翻译现有内容'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '自动翻译所有影片的日语标题为中文',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _clearAllTranslations,
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              label: const Text('清除所有翻译', style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '清除所有影片的翻译内容',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _viewTranslationList,
              icon: const Icon(Icons.list, color: Colors.blue),
              label: const Text('查看翻译列表', style: TextStyle(color: Colors.blue)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.blue),
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '查看所有已翻译的影片列表',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _viewTranslationList() async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) {
          return const TranslationListScreen();
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;

          var tween =
              Tween(begin: begin, end: end).chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  Future<void> _clearAllTranslations() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清除'),
        content: const Text('确定要清除所有影片的翻译内容吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DatabaseService.clearAllTranslations();
      await _translator.clearCache();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清除所有翻译')),
      );
    }
  }

  Widget _buildModelsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.model_training,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '翻译模型',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ..._allModels.map((model) {
              final isDownloaded = _downloadedModels[model.id] ?? false;
              final isDownloading = _downloadingModelId == model.id;
              final isSelected = _selectedModelId == model.id;

              return _buildModelCard(
                model,
                isDownloaded,
                isDownloading,
                isSelected,
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildModelCard(
    ModelInfo model,
    bool isDownloaded,
    bool isDownloading,
    bool isSelected,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSelected
            ? Theme.of(context).colorScheme.primaryContainer.withAlpha(30)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: model.tier == 'lite'
                      ? Colors.green.withAlpha(20)
                      : model.tier == 'custom'
                          ? Colors.purple.withAlpha(20)
                          : Colors.blue.withAlpha(20),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  model.tier == 'lite'
                      ? '轻量'
                      : model.tier == 'custom'
                          ? '自定义'
                          : '高质量',
                  style: TextStyle(
                    color: model.tier == 'lite'
                        ? Colors.green
                        : model.tier == 'custom'
                            ? Colors.purple
                            : Colors.blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  model.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              if (isDownloaded)
                const Icon(
                  Icons.check_circle,
                  color: Colors.green,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            model.description,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '大小: ${_formatFileSize(model.fileSizeBytes)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 16),
              Text(
                '内存: ${model.estimatedRamMb} MB',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          if (isDownloading) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _downloadProgress),
            const SizedBox(height: 8),
            Text(
              '下载中... ${(_downloadProgress * 100).toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => _modelManager.cancelDownload(),
              icon: const Icon(Icons.cancel),
              label: const Text('取消'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ] else if (isDownloaded) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (!isSelected)
                  ElevatedButton.icon(
                    onPressed: () => _selectModel(model),
                    icon: const Icon(Icons.check),
                    label: const Text('使用此模型'),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green),
                        SizedBox(width: 8),
                        Text(
                          '当前使用中',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () => _deleteModel(model),
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text('删除', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _downloadModel(model),
              icon: const Icon(Icons.download),
              label: const Text('下载'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI翻译设置'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildAIEnabledSection(),
                const SizedBox(height: 16),
                _buildCustomPathSection(),
                const SizedBox(height: 16),
                _buildModelsSection(),
                const SizedBox(height: 16),
                _buildAdvancedSettings(),
              ],
            ),
    );
  }
}

class _TranslationProgressDialog extends StatefulWidget {
  final List<Movie> movies;
  final String modelId;
  final int threadCount;

  const _TranslationProgressDialog({
    required this.movies,
    required this.modelId,
    required this.threadCount,
  });

  @override
  State<_TranslationProgressDialog> createState() =>
      _TranslationProgressDialogState();
}

class _TranslationProgressDialogState
    extends State<_TranslationProgressDialog> {
  final LocalTranslator _translator = LocalTranslator();
  int _currentIndex = 0;
  String _currentOriginal = '';
  String _currentTranslation = '';
  bool _isCompleted = false;
  int _successCount = 0;
  int _failedCount = 0;

  @override
  void initState() {
    super.initState();
    _startTranslation();
  }

  Future<void> _startTranslation() async {
    // 在开始翻译前，先确保服务已启动
    try {
      await _translator.ensureServiceStarted(modelId: widget.modelId);
    } catch (e) {
      debugPrint('启动翻译服务失败: $e');
    }

    for (int i = 0; i < widget.movies.length; i++) {
      final movie = widget.movies[i];

      setState(() {
        _currentIndex = i + 1;
        _currentOriginal = movie.name;
        _currentTranslation = '翻译中...';
      });

      try {
        final translatedResult = await _translator.translateText(
          text: movie.name,
          fieldHint: 'title',
          modelId: widget.modelId,
        );

        setState(() {
          _currentTranslation = translatedResult.parsedOutput;
        });

        // 只有当翻译结果不等于原文时才保存到数据库
        if (translatedResult.parsedOutput != movie.name) {
          await DatabaseService.updateMovieWithLatest(
            movie.id,
            (latestMovie) => latestMovie.copyWith(
              translatedName: translatedResult.parsedOutput,
            ),
          );
          _successCount++;
        } else {
          _failedCount++;
        }

        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        setState(() {
          _currentTranslation = '翻译失败';
        });
        _failedCount++;
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    setState(() {
      _isCompleted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        widget.movies.isNotEmpty ? _currentIndex / widget.movies.length : 0.0;

    return AlertDialog(
      title: const Text('批量翻译'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isCompleted) ...[
              Text(
                '正在翻译 $_currentIndex/${widget.movies.length}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '日语原文:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _currentOriginal,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '翻译后中文:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _currentTranslation,
                      style: TextStyle(
                        fontSize: 16,
                        color: _currentTranslation == '翻译失败'
                            ? Colors.red
                            : _currentTranslation == '翻译中...'
                                ? Colors.blue
                                : const Color.fromRGBO(102, 102, 102, 1.0),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 64,
              ),
              const SizedBox(height: 16),
              const Text(
                '翻译完成',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '成功: $_successCount',
                      style: const TextStyle(color: Colors.green),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '失败: $_failedCount',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: _isCompleted
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ]
          : [],
    );
  }
}
