import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/tmdb_provider.dart';
import '../providers/movie_providers.dart';
import '../services/tmdb_api_service.dart';

class TmdbConfigScreen extends ConsumerStatefulWidget {
  const TmdbConfigScreen({super.key});

  @override
  ConsumerState<TmdbConfigScreen> createState() => _TmdbConfigScreenState();
}

class _TmdbConfigScreenState extends ConsumerState<TmdbConfigScreen> {
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _readAccessTokenController =
      TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _languageController = TextEditingController();
  final TextEditingController _regionController = TextEditingController();
  bool _isTesting = false;
  bool _testSuccess = false;
  String? _testMessage;

  @override
  void initState() {
    super.initState();
    final config = ref.read(tmdbConfigProvider);
    _baseUrlController.text = config.baseUrl;
    _readAccessTokenController.text = config.readAccessToken;
    _apiKeyController.text = config.apiKey;
    _languageController.text = config.language;
    _regionController.text = config.region;
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _readAccessTokenController.dispose();
    _apiKeyController.dispose();
    _languageController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testSuccess = false;
      _testMessage = null;
    });

    final service = TmdbApiService();
    try {
      service.configure(
        baseUrl: _baseUrlController.text,
        readAccessToken: _readAccessTokenController.text,
        apiKey: _apiKeyController.text,
        language: _languageController.text,
        region: _regionController.text,
      );
      final proxySettings = ref.read(proxyConfigProvider);
      service.configureProxy(
        enabled: proxySettings.proxyEnabled,
        type: proxySettings.proxyType,
        host: proxySettings.proxyHost,
        port: proxySettings.proxyPort,
        username: proxySettings.proxyUsername,
        password: proxySettings.proxyPassword,
      );
      await service.testConnection();
      setState(() {
        _testSuccess = true;
        _testMessage = '连接成功';
      });
    } on TmdbException catch (error) {
      setState(() {
        _testMessage = error.message;
      });
    } catch (error) {
      setState(() {
        _testMessage = error.toString();
      });
    } finally {
      service.close();
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  Future<void> _saveConfig() async {
    final baseUrl = _baseUrlController.text.trim();
    final readAccessToken = _readAccessTokenController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    final language = _languageController.text.trim();
    final region = _regionController.text.trim();

    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.isAbsolute) {
      _showSnack('请输入有效的 TMDB API URL');
      return;
    }
    if (readAccessToken.isEmpty && apiKey.isEmpty) {
      _showSnack('请填写 TMDB Read Access Token 或 API Key');
      return;
    }
    if (language.isEmpty) {
      _showSnack('请填写语言代码');
      return;
    }

    await ref.read(tmdbConfigProvider.notifier).saveConfig(
          baseUrl: baseUrl,
          readAccessToken: readAccessToken,
          apiKey: apiKey,
          language: language,
          region: region,
        );

    if (!mounted) return;
    _showSnack('配置已保存');
    Navigator.pop(context);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TMDB 配置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              labelText: 'API URL',
              hintText: TmdbApiService.defaultBaseUrl,
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _readAccessTokenController,
            decoration: const InputDecoration(
              labelText: 'Read Access Token',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.key),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKeyController,
            decoration: const InputDecoration(
              labelText: 'API Key',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.vpn_key),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _languageController,
                  decoration: const InputDecoration(
                    labelText: '语言',
                    hintText: 'zh-CN',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.language),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _regionController,
                  decoration: const InputDecoration(
                    labelText: '地区',
                    hintText: '可留空',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.public),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _isTesting ? null : _testConnection,
            icon: _isTesting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: const Text('测试连接'),
          ),
          if (_testMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _testMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _testSuccess
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saveConfig,
            icon: const Icon(Icons.save),
            label: const Text('保存配置'),
          ),
        ],
      ),
    );
  }
}
