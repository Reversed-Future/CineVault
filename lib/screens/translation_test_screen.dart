import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ai/model_manager.dart';
import '../providers/translation_provider.dart';

class TranslationTestScreen extends ConsumerStatefulWidget {
  const TranslationTestScreen({super.key});

  @override
  ConsumerState<TranslationTestScreen> createState() =>
      _TranslationTestScreenState();
}

class _TranslationTestScreenState extends ConsumerState<TranslationTestScreen> {
  final TextEditingController _inputController = TextEditingController();
  String _result = '';
  String _rawOutput = ''; // 新增：存储原始输出
  bool _isTranslating = false;
  bool _isLoadingModel = false;
  bool _isModelLoaded = false;
  String? _loadedModelName;
  String _selectedHint = 'title';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkModelStatus();
  }

  Future<void> _checkModelStatus() async {
    final service = ref.read(translationServiceProvider);
    if (mounted) {
      setState(() {
        _isModelLoaded = service.hasLoadedModel;
        _loadedModelName = service.loadedModelName;
      });
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _loadModel() async {
    setState(() {
      _isLoadingModel = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(translationServiceProvider);
      final loaded = await service.initialize();

      if (!mounted) return;

      setState(() {
        _isModelLoaded = loaded;
        _loadedModelName = service.loadedModelName;
      });

      if (loaded) {
        final modelName = service.loadedModelName ?? '未知模型';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 模型加载成功: $modelName'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ 模型加载失败'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('加载出错: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingModel = false;
        });
      }
    }
  }

  Future<void> _translate() async {
    if (_inputController.text.trim().isEmpty) return;

    setState(() {
      _isTranslating = true;
      _result = '';
      _rawOutput = ''; // 重置原始输出
      _errorMessage = null;
    });

    try {
      final service = ref.read(translationServiceProvider);
      final fullResult = await service.translateWithRawOutput(
        text: _inputController.text,
        fieldHint: _selectedHint,
        skipCache: true, // 翻译测试时跳过缓存
      );

      if (!mounted) return;

      setState(() {
        _rawOutput = fullResult.rawOutput; // 保存原始输出
        _result = fullResult.parsedOutput;
        _isModelLoaded = service.hasLoadedModel;
        _loadedModelName = service.loadedModelName;
      });

      if (fullResult.parsedOutput == _inputController.text) {
        setState(() {
          _errorMessage = '返回原文';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ 返回原文，可能是模型未加载'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('翻译出错: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTranslating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final modelManager = ModelManager();

    return Scaffold(
      appBar: AppBar(
        title: const Text('翻译测试'),
        actions: [
          IconButton(
            icon: _isLoadingModel
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _isModelLoaded ? Icons.check_circle : Icons.refresh,
                    color: _isModelLoaded ? Colors.green : null,
                  ),
            onPressed: _isLoadingModel ? null : _loadModel,
            tooltip: '加载模型',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            '使用说明',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('1. 先在"设置 → AI翻译设置"中下载模型'),
                    const Text('2. 选择要使用的模型并启用AI翻译'),
                    const Text('3. 点击右上角刷新按钮加载模型'),
                    const Text('4. 在下方输入日语文本进行测试'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('模型状态: '),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _isModelLoaded
                                ? Colors.green.withOpacity(0.2)
                                : Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _isModelLoaded ? '已加载' : '未加载',
                            style: TextStyle(
                              color:
                                  _isModelLoaded ? Colors.green : Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '模型数量: ${modelManager.manifest.models.length}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    if (_isModelLoaded && _loadedModelName != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('当前模型: '),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _loadedModelName!,
                                style: const TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '⚠️ $_errorMessage',
                              style: const TextStyle(color: Colors.red),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '提示：检查模型是否已下载并选择',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (!_isModelLoaded && !_isLoadingModel) ...[
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _loadModel,
                        icon: const Icon(Icons.download),
                        label: const Text('加载模型'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor:
                              Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedHint,
              decoration: const InputDecoration(
                labelText: '翻译类型',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'title', child: Text('标题')),
                DropdownMenuItem(value: 'plot', child: Text('剧情')),
                DropdownMenuItem(value: 'tags', child: Text('标签')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedHint = value;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _inputController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '输入日语文本',
                hintText: '请输入要翻译的日语文本...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isTranslating ? null : _translate,
              icon: _isTranslating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.translate),
              label: Text(_isTranslating ? '翻译中...' : '翻译'),
            ),
            if (_result.isNotEmpty || _rawOutput.isNotEmpty) ...[
              const Divider(height: 32),

              // 原始输出（新增）
              if (_rawOutput.isNotEmpty) ...[
                const Text(
                  '模型原始输出:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    _rawOutput,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 解析后的结果
              if (_result.isNotEmpty) ...[
                const Text(
                  '解析后的翻译结果:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    _result,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
