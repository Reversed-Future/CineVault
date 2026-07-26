import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as path;
import '../models/app_settings.dart';
import '../services/database_service.dart';
import '../services/data_storage_path_service.dart';
import '../providers/movie_providers.dart';
import '../providers/translation_provider.dart';
import '../providers/tmdb_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/unregistered_movies_provider.dart';
import '../services/tmdb_api_service.dart';
import '../services/image_cache_service.dart';
import '../services/local_movie_scanner.dart';
import '../services/movie_batch_updater.dart';
import '../services/font_config_service.dart';
import '../services/remote/remote_cine_vault_server.dart';
import '../services/remote/remote_server_settings.dart';
import '../widgets/stream_output_dialog.dart';
import '../widgets/unregistered_movies_dialog.dart';
import 'ai_settings_screen.dart';
import 'translation_test_screen.dart';
import 'download_center_screen.dart';
import 'download_settings_page.dart';
import 'url_download_dialog.dart';

enum SettingsCategory {
  general('通用设置', Icons.settings),
  videoFolders('视频文件夹', Icons.folder),
  storage('数据存储', Icons.folder_special),
  downloads('下载中心', Icons.download),
  assetManager('本地资源管理器', Icons.storage),
  playback('播放设置', Icons.play_circle_outline),
  remoteAccess('远程访问', Icons.phone_android),
  api('API配置', Icons.api),
  proxy('代理配置', Icons.router),
  cache('缓存管理', Icons.storage),
  ai('AI翻译', Icons.translate);

  final String label;
  final IconData icon;
  const SettingsCategory(this.label, this.icon);
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  AppSettings? _settings;
  RemoteServerSettings? _remoteSettings;
  bool _isLoading = true;
  SettingsCategory _selectedCategory = SettingsCategory.general;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await DatabaseService.init();
    final settings = await DatabaseService.getSettingsAsync();
    final remoteSettings = await remoteCineVaultServer.loadSettings();
    setState(() {
      _settings = settings;
      _remoteSettings = remoteSettings;
      _isLoading = false;
    });
    if (mounted) {
      ref.read(proxyConfigProvider.notifier).updateSettings(settings);
    }
  }

  Future<void> _saveSettings() async {
    if (_settings != null) {
      try {
        await DatabaseService.saveSettings(_settings!);
        ImageCacheService.configure(
          enabled: _settings!.cacheEnabled,
          cachePath: _settings!.cachePath ?? '',
          maxCacheSizeMB: _settings!.maxCacheSizeMB,
          maxCacheFiles: _settings!.maxCacheFiles,
        );
        if (mounted) {
          ref.refresh(settingsProvider);
          ref.read(proxyConfigProvider.notifier).updateSettings(_settings!);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('设置已保存')),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('设置保存失败: $error'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _addVideoFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();

    if (result != null && _settings != null) {
      final folders = List<String>.from(_settings!.videoFolders);
      if (!folders.contains(result)) {
        folders.add(result);
        setState(() {
          _settings = _settings!.copyWith(videoFolders: folders);
        });
        await _saveSettings();

        // 触发本地影片扫描（异步执行，不阻塞UI）
        _triggerLocalScan(folders);
      }
    }
  }

  /// 触发本地影片扫描（添加文件夹时自动触发）
  void _triggerLocalScan(List<String> folders) {
    final notifier = ref.read(notificationProvider.notifier);
    // 异步执行，不等待完成
    LocalMovieScanner.startScan(
      videoFolders: folders,
      notificationNotifier: notifier,
      // 扫描完成后保存到 provider（检查 mounted 状态）
      onCompleted: (result) {
        if (mounted) {
          ref
              .read(unregisteredMoviesProvider.notifier)
              .set(result.notInLibrary);
        }
      },
    ).then((result) {
      // 扫描完成后，弹出未注册影片对话框（如果当前在视频文件夹页面）
      if (mounted &&
          result.notInLibrary.isNotEmpty &&
          _selectedCategory == SettingsCategory.videoFolders) {
        showDialog(
          context: context,
          builder: (_) =>
              UnregisteredMoviesDialog(entries: result.notInLibrary),
        );
      }
    }).catchError((e, st) {
      print('[SettingsScreen] Local scan error: $e\n$st');
    });
  }

  /// 手动触发扫描（用户点击"扫描本地影片"按钮）
  void _manualScan() {
    if (_settings == null || _settings!.videoFolders.isEmpty) return;
    // 弹个 SnackBar 提示开始
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('开始扫描本地影片...'),
        duration: Duration(seconds: 2),
      ),
    );
    _triggerLocalScan(_settings!.videoFolders);
  }

  /// 手动批量更新所有影片数据（用户点击"更新所有影片数据"按钮）
  Future<void> _manualUpdateAllMovies() async {
    if (_settings == null) return;

    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量更新影片数据'),
        content: const Text(
          '将从 TMDB API 拉取所有影片的最新元数据并覆盖现有数据。\n'
          '此操作可能需要较长时间（取决于影片数量和网络速度）。\n\n'
          '是否继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('开始更新'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // 立即 SnackBar 提示开始
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('开始批量更新影片数据...'),
        duration: Duration(seconds: 2),
      ),
    );

    final notifier = ref.read(notificationProvider.notifier);
    final movies = DatabaseService.getAllMovies();

    if (movies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('影片库为空，无可更新内容'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // 手动创建并配置 API 服务（避免依赖 provider 的异步加载）
    print(
        '[SettingsScreen] Manually creating API service with config from Hive');
    final apiService = TmdbApiService();

    // 加载 Tmdb 配置
    try {
      final configBox = await Hive.openBox('tmdb_config');
      final baseUrl = configBox.get('base_url', defaultValue: '') as String;
      final readAccessToken =
          configBox.get('read_access_token', defaultValue: '') as String;
      final apiKey = configBox.get('api_key', defaultValue: '') as String;

      print(
          '[SettingsScreen] Loaded TMDB config - baseUrl: $baseUrl, hasToken: ${readAccessToken.isNotEmpty}, hasApiKey: ${apiKey.isNotEmpty}');
      if (baseUrl.isNotEmpty) {
        apiService.configure(
          baseUrl: baseUrl,
          readAccessToken: readAccessToken,
          apiKey: apiKey,
        );
      }
    } catch (e) {
      print('[SettingsScreen] Failed to load TMDB config: $e');
    }

    // 加载代理配置
    try {
      final settings = DatabaseService.getSettings();
      print(
          '[SettingsScreen] Loaded settings - proxyEnabled: ${settings.proxyEnabled}');
      apiService.configureProxy(
        enabled: settings.proxyEnabled,
        type: settings.proxyType,
        host: settings.proxyHost,
        port: settings.proxyPort,
        username: settings.proxyUsername,
        password: settings.proxyPassword,
      );
    } catch (e) {
      print('[SettingsScreen] Failed to load proxy config: $e');
    }

    print('[SettingsScreen] Starting batch update with configured API service');
    print('[SettingsScreen]  API base URL: ${apiService.baseUrl}');
    print(
        '[SettingsScreen]  Has auth: ${apiService.authToken != null && apiService.authToken!.isNotEmpty}');

    // 打印完整调试信息
    apiService.printDebugInfo();

    // 异步执行
    MovieBatchUpdater.updateAllMovies(
      movies: movies,
      notificationNotifier: notifier,
      apiService: apiService,
    ).then((result) {
      // 完成后 SnackBar 反馈
      if (!mounted) return;

      // 刷新 UI
      print('[SettingsScreen] Batch update complete, refreshing UI');
      refreshMovies(ref);

      final seconds = (result.durationMs / 1000).toStringAsFixed(1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '更新完成（${seconds}s）：成功 ${result.successCount}/${result.totalCount}'
            '${result.failedCount > 0 ? '，失败 ${result.failedCount}' : ''}',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }).catchError((e, st) {
      print('[SettingsScreen] Batch update error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('批量更新失败: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    });
  }

  /// 批量更新占位影片数据（仅有资料 ID 的影片）
  Future<void> _manualUpdatePlaceholderMovies() async {
    // 获取所有影片
    final allMovies = DatabaseService.getAllMovies();

    // 筛选占位影片（只有资料 ID，没有详细数据）
    final placeholderMovies = allMovies.where((movie) {
      // 判断标准：封面为空 或 名称等于资料 ID（说明是自动生成的占位）
      return (movie.coverUrl == null || movie.coverUrl!.isEmpty) ||
          (movie.name == movie.code);
    }).toList();

    if (placeholderMovies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('没有占位影片需要更新'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量更新占位影片数据'),
        content: Text(
          '检测到 ${placeholderMovies.length} 个占位影片（仅有资料 ID），将从 TMDB API 拉取完整数据。\n\n'
          '是否继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('开始更新'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // 立即 SnackBar 提示开始
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('开始更新 ${placeholderMovies.length} 个占位影片数据...'),
        duration: const Duration(seconds: 2),
      ),
    );

    final notifier = ref.read(notificationProvider.notifier);

    // 手动创建并配置 API 服务
    final apiService = TmdbApiService();

    // 加载 Tmdb 配置
    try {
      final configBox = await Hive.openBox('tmdb_config');
      final baseUrl = configBox.get('base_url', defaultValue: '') as String;
      final readAccessToken =
          configBox.get('read_access_token', defaultValue: '') as String;
      final apiKey = configBox.get('api_key', defaultValue: '') as String;

      if (baseUrl.isNotEmpty) {
        apiService.configure(
          baseUrl: baseUrl,
          readAccessToken: readAccessToken,
          apiKey: apiKey,
        );
      }
    } catch (e) {
      print('[SettingsScreen] Failed to load TMDB config: $e');
    }

    // 加载代理配置
    try {
      final settings = DatabaseService.getSettings();
      apiService.configureProxy(
        enabled: settings.proxyEnabled,
        type: settings.proxyType,
        host: settings.proxyHost,
        port: settings.proxyPort,
        username: settings.proxyUsername,
        password: settings.proxyPassword,
      );
    } catch (e) {
      print('[SettingsScreen] Failed to load proxy config: $e');
    }

    // 异步执行批量更新（只更新占位影片）
    MovieBatchUpdater.updateAllMovies(
      movies: placeholderMovies,
      notificationNotifier: notifier,
      apiService: apiService,
    ).then((result) {
      if (!mounted) return;

      // 刷新 UI
      print(
          '[SettingsScreen] Placeholder batch update complete, refreshing UI');
      refreshMovies(ref);

      final seconds = (result.durationMs / 1000).toStringAsFixed(1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '更新完成（${seconds}s）：成功 ${result.successCount}/${result.totalCount}'
            '${result.failedCount > 0 ? '，失败 ${result.failedCount}' : ''}',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }).catchError((e, st) {
      print('[SettingsScreen] Placeholder batch update error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('批量更新失败: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    });
  }

  Future<void> _removeVideoFolder(String folder) async {
    if (_settings != null) {
      final folders = List<String>.from(_settings!.videoFolders)
        ..remove(folder);
      setState(() {
        _settings = _settings!.copyWith(videoFolders: folders);
      });
      await _saveSettings();
      final updatedMovies =
          await LocalMovieScanner.removeVideoPathsUnderFolder(folder);
      if (updatedMovies > 0) {
        refreshMovies(ref);
      }
    }
  }

  Future<void> _setLocalAssetManagerPath() async {
    final result = await FilePicker.platform.getDirectoryPath();

    if (result != null && _settings != null) {
      setState(() {
        _settings = _settings!.copyWith(localAssetManagerPath: result);
      });
      await _saveSettings();
    }
  }

  Future<void> _setDataStoragePath() async {
    final result = await FilePicker.platform.getDirectoryPath();

    if (result != null && _settings != null) {
      final previousSettings = _settings!;
      final updatedSettings = _settings!.copyWith(dataStoragePath: result);
      setState(() {
        _settings = updatedSettings;
      });

      try {
        await DatabaseService.saveSettings(updatedSettings);
        final pathChange = await DataStoragePathService.prepareDataPathChange(
          newPath: result,
          exportData: (filePath) => DatabaseService.exportData(
            filePath,
            includeSensitiveSettings: true,
          ),
        );

        if (mounted) {
          ref.refresh(settingsProvider);
          ref
              .read(proxyConfigProvider.notifier)
              .updateSettings(updatedSettings);
          final message = pathChange.migrationSnapshotCreated
              ? '数据存储路径已修改，当前数据会在重启后导入新目录'
              : '数据存储路径已修改，重启应用后生效';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        }
      } catch (e) {
        try {
          await DatabaseService.saveSettings(previousSettings);
        } catch (rollbackError) {
          debugPrint('Failed to restore previous settings: $rollbackError');
        }
        if (mounted) {
          setState(() {
            _settings = previousSettings;
          });
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('数据存储路径修改失败: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  void _openAISettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AISettingsScreen(),
      ),
    );
  }

  void _openTranslationTest() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const TranslationTestScreen(),
      ),
    );
  }

  void _openDownloadSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const DownloadSettingsPage(),
      ),
    );
  }

  Future<void> _exportData() async {
    try {
      final now = DateTime.now();
      final timestamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';

      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '选择导出位置',
        fileName: 'cinevault_backup_$timestamp.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (outputPath == null) return;

      // 显示加载对话框
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      await DatabaseService.exportData(outputPath);

      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭加载对话框

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('数据已成功导出到: $outputPath（敏感配置未导出）'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // 关闭加载对话框
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导出失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _importData() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        dialogTitle: '选择要导入的备份文件',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.single.path == null) return;

      final filePath = result.files.single.path!;

      // 确认对话框
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认导入'),
          content: const Text(
            '导入会合并备份数据；同 ID 的数据会被覆盖，备份中不存在的现有数据会保留。是否继续？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('合并导入'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // 显示加载对话框
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final importResult = await DatabaseService.importData(filePath);

      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭加载对话框

      // 显示结果
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(importResult.success ? '导入完成' : '导入失败'),
          content: Text(importResult.getSummary()),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (importResult.success) {
                  // 刷新设置
                  _loadSettings();
                  // 刷新电影列表（通过刷新 provider）
                  ref.read(moviesRefreshSignal.notifier).state++;
                }
              },
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // 关闭加载对话框
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导入失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('设置'),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWideScreen = constraints.maxWidth >= 900;

                if (isWideScreen) {
                  return Row(
                    children: [
                      _buildSidebar(),
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      Expanded(
                        child: _buildContentArea(),
                      ),
                    ],
                  );
                } else {
                  return Row(
                    children: [
                      SizedBox(
                        width: 80,
                        child: _buildCompactSidebar(),
                      ),
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      Expanded(
                        child: _buildContentArea(),
                      ),
                    ],
                  );
                }
              },
            ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 280,
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Icon(
                  Icons.settings,
                  size: 28,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  '设置',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          Divider(
              height: 1,
              color: Theme.of(context).colorScheme.surfaceContainerHighest),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: SettingsCategory.values.length,
              itemBuilder: (context, index) {
                final category = SettingsCategory.values[index];
                final isSelected = category == _selectedCategory;

                return _SettingsSidebarItem(
                  icon: category.icon,
                  label: category.label,
                  isSelected: isSelected,
                  onTap: () {
                    setState(() {
                      _selectedCategory = category;
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactSidebar() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: SettingsCategory.values.length,
              itemBuilder: (context, index) {
                final category = SettingsCategory.values[index];
                final isSelected = category == _selectedCategory;

                return Tooltip(
                  message: category.label,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedCategory = category;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        category.icon,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentArea() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: SingleChildScrollView(
        key: ValueKey(_selectedCategory),
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: _buildCurrentSection(),
        ),
      ),
    );
  }

  Widget _buildCurrentSection() {
    switch (_selectedCategory) {
      case SettingsCategory.general:
        return _buildGeneralSection();
      case SettingsCategory.videoFolders:
        return _buildVideoFoldersSection();
      case SettingsCategory.storage:
        return _buildStorageSection();
      case SettingsCategory.downloads:
        return _buildDownloadsSection();
      case SettingsCategory.assetManager:
        return _buildAssetManagerSection();
      case SettingsCategory.playback:
        return _buildPlaybackSection();
      case SettingsCategory.remoteAccess:
        return _buildRemoteAccessSection();
      case SettingsCategory.api:
        return _buildApiSection();
      case SettingsCategory.proxy:
        return _buildProxySection();
      case SettingsCategory.cache:
        return _buildCacheSection();
      case SettingsCategory.ai:
        return _buildAISection();
    }
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 16),
          Divider(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.settings,
          title: '通用设置',
          subtitle: '配置应用的基本行为',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '欢迎使用 CineVault',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'CineVault 是一款面向个人电影库的桌面影片管理与播放工具。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '版本 1.0.0',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildFontSettings(),
      ],
    );
  }

  Widget _buildFontSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.font_download,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '字体设置',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 字体选择
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '字体',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Column(
                  children: FontConfigService.availableFonts.map((font) {
                    return RadioListTile<String>(
                      title: Text(font.displayName),
                      subtitle: _buildFontPreview(font),
                      value: font.id,
                      groupValue: _settings?.fontFamily,
                      onChanged: (value) {
                        if (value != null && _settings != null) {
                          setState(() {
                            _settings = _settings!.copyWith(fontFamily: value);
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // 字体大小
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '字体大小',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Text(
                      '${_settings?.fontSize ?? 14}px',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Slider(
                  min: 12,
                  max: 24,
                  value: (_settings?.fontSize ?? 14).toDouble(),
                  divisions: 12,
                  label: '${_settings?.fontSize ?? 14}px',
                  onChanged: (value) {
                    if (_settings != null) {
                      setState(() {
                        _settings =
                            _settings!.copyWith(fontSize: value.toInt());
                      });
                    }
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '12px',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        '24px',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 预览区域
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '预览效果',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '这是标题文字 (Headline)',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontFamily: FontConfigService.getFontOption(
                                          _settings?.fontFamily)
                                      ?.fontFamily,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '这是正文文字 (Body)。字体大小: ${_settings?.fontSize ?? 14}px',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontFamily: FontConfigService.getFontOption(
                                          _settings?.fontFamily)
                                      ?.fontFamily,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              ElevatedButton(
                                onPressed: () {},
                                child: const Text('按钮'),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () {},
                                child: const Text('文字按钮'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 保存按钮
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saveFontSettings,
                    child: const Text('应用字体设置'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFontPreview(FontOption font) {
    return Text(
      font.sampleText,
      style: TextStyle(
        fontFamily: font.fontFamily,
        fontSize: (_settings?.fontSize ?? 14).toDouble() * 0.9,
      ),
    );
  }

  Future<void> _saveFontSettings() async {
    if (_settings != null) {
      try {
        await DatabaseService.saveSettings(_settings!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('字体设置已保存，重启应用后生效'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('字体设置保存失败: $error'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  Widget _buildVideoFoldersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.folder,
          title: '视频文件夹',
          subtitle: '添加包含视频的文件夹以便自动匹配',
          trailing: ElevatedButton.icon(
            onPressed: _addVideoFolder,
            icon: const Icon(Icons.add),
            label: const Text('添加'),
          ),
        ),
        // 待审核影片横幅
        _buildUnregisteredMoviesBanner(),
        // 手动操作按钮组
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _settings?.videoFolders.isEmpty ?? true
                    ? null
                    : _manualScan,
                icon: const Icon(Icons.search),
                label: const Text('扫描本地影片'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _manualUpdateAllMovies,
                icon: const Icon(Icons.refresh),
                label: const Text('更新所有影片数据'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _manualUpdatePlaceholderMovies,
          icon: const Icon(Icons.download),
          label: const Text('更新占位影片数据'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: _settings?.videoFolders.isEmpty ?? true
              ? Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.folder_open,
                        size: 64,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '未添加视频文件夹',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '点击上方按钮添加包含视频的文件夹',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(8),
                  itemCount: _settings!.videoFolders.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final folder = _settings!.videoFolders[index];
                    return ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.folder,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      title: Text(path.basename(folder)),
                      subtitle: Text(
                        folder,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removeVideoFolder(folder),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// 待审核影片横幅
  /// 显示在视频文件夹页面顶部，如果有未审核的影片则提供快捷入口
  Widget _buildUnregisteredMoviesBanner() {
    final pending = ref.watch(effectiveUnregisteredMoviesProvider);
    if (pending.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        color: theme.colorScheme.tertiaryContainer,
        child: InkWell(
          onTap: () => UnregisteredMoviesDialog.showFromProvider(context, ref),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.movie_filter_outlined,
                  color: theme.colorScheme.onTertiaryContainer,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '有 ${pending.length} 个待审核的影片',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '扫描到但未在库中，点击审核并选择保存为占位',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer
                              .withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStorageSection() {
    final currentPath = DatabaseService.currentPath ?? '未设置';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.folder_special,
          title: '数据存储',
          subtitle: '配置影片信息和设置的存储位置',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前存储位置',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder,
                        color: Theme.of(context).colorScheme.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          currentPath,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontFamily: 'monospace',
                                  ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _setDataStoragePath,
                    icon: const Icon(Icons.edit),
                    label: const Text('修改存储位置'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .tertiaryContainer
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color:
                            Theme.of(context).colorScheme.onTertiaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '修改后需要重启应用才能生效',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onTertiaryContainer,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '数据备份与恢复',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '导出或导入您的所有数据（影片信息、设置、自定义标签等）',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _exportData,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('导出数据'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _importData,
                        icon: const Icon(Icons.download),
                        label: const Text('导入数据'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.download,
          title: '下载中心',
          subtitle: '管理模型和视频的下载任务',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const DownloadCenterScreen(),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.download_done,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '下载管理',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '查看和管理所有下载任务',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(),
                InkWell(
                  onTap: () => showDialog(
                    context: context,
                    builder: (context) => const UrlDownloadDialog(),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .secondaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.link,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '从URL下载模型',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '从Hugging Face等仓库下载模型文件',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(),
                InkWell(
                  onTap: _openDownloadSettings,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.tune,
                            color: Theme.of(context).colorScheme.tertiary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '下载设置',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '配置 aria2、限速、trackers等',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAssetManagerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.storage,
          title: '本地资源管理器',
          subtitle: '配置本地刮削源路径',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '资源路径',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                if (_settings?.localAssetManagerPath != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder,
                          color: Theme.of(context).colorScheme.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                path.basename(
                                    _settings!.localAssetManagerPath!),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500),
                              ),
                              Text(
                                _settings!.localAssetManagerPath!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      fontFamily: 'monospace',
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _setLocalAssetManagerPath,
                    icon: const Icon(Icons.folder_open),
                    label: Text(
                      _settings?.localAssetManagerPath == null
                          ? '选择文件夹'
                          : '更换文件夹',
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaybackSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.play_circle_outline,
          title: '播放设置',
          subtitle: '配置播放器的行为',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自动恢复播放进度'),
                  subtitle: const Text('下次播放时从上次停止位置继续'),
                  value: _settings?.autoResumePlayback ?? true,
                  onChanged: (value) {
                    setState(() {
                      _settings =
                          _settings!.copyWith(autoResumePlayback: value);
                    });
                    _saveSettings();
                  },
                ),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('默认显示字幕'),
                  subtitle: const Text('播放时自动加载字幕'),
                  value: _settings?.showSubtitlesByDefault ?? true,
                  onChanged: (value) {
                    setState(() {
                      _settings =
                          _settings!.copyWith(showSubtitlesByDefault: value);
                    });
                    _saveSettings();
                  },
                ),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  '字幕字体大小',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'small', label: Text('小')),
                    ButtonSegment(value: 'medium', label: Text('中')),
                    ButtonSegment(value: 'large', label: Text('大')),
                  ],
                  selected: {_settings?.subtitleFontSize ?? 'medium'},
                  onSelectionChanged: (Set<String> newSelection) {
                    setState(() {
                      _settings = _settings!.copyWith(
                        subtitleFontSize: newSelection.first,
                      );
                    });
                    _saveSettings();
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRemoteAccessSection() {
    final settings = _remoteSettings ??
        const RemoteServerSettings(
          enabled: true,
          port: RemoteServerSettingsService.defaultPort,
          token: '',
        );
    final enabled = ValueNotifier<bool>(settings.enabled);
    final portController =
        TextEditingController(text: settings.port.toString());
    final tokenController = TextEditingController(text: settings.token);
    final isSaving = ValueNotifier<bool>(false);

    Future<void> saveRemoteSettings() async {
      final port = int.tryParse(portController.text.trim());
      final token = tokenController.text.trim();
      if (port == null || port < 1 || port > 65535) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入 1-65535 范围内的端口')),
        );
        return;
      }
      if (token.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('访问令牌不能为空')),
        );
        return;
      }

      isSaving.value = true;
      try {
        final updated = RemoteServerSettings(
          enabled: enabled.value,
          port: port,
          token: token,
        );
        await remoteCineVaultServer.restart(updated);
        if (mounted) {
          setState(() {
            _remoteSettings = updated;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('远程访问设置已保存')),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('远程服务启动失败: $error'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      } finally {
        isSaving.value = false;
      }
    }

    Future<void> regenerateToken() async {
      isSaving.value = true;
      try {
        final updated = await remoteCineVaultServer.regenerateTokenAndRestart();
        tokenController.text = updated.token;
        if (mounted) {
          setState(() {
            _remoteSettings = updated;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('访问令牌已重新生成')),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('令牌生成失败: $error'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      } finally {
        isSaving.value = false;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.phone_android,
          title: '远程访问',
          subtitle: '供 CineVault 客户端在局域网内连接本机片库',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: enabled,
                  builder: (context, value, child) {
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用远程服务'),
                      subtitle: const Text('默认监听 0.0.0.0:53287'),
                      value: value,
                      onChanged: (newValue) {
                        enabled.value = newValue;
                      },
                    );
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: portController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '服务端口',
                    helperText: '手机端默认扫描 53287，后期可改为自定义端口',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: tokenController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '访问令牌',
                    helperText: '手机端连接时填写此 token',
                  ),
                  obscureText: false,
                ),
                const SizedBox(height: 16),
                Text(
                  remoteCineVaultServer.isRunning ? '当前状态：运行中' : '当前状态：未运行',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                ValueListenableBuilder<bool>(
                  valueListenable: isSaving,
                  builder: (context, saving, child) {
                    return Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: saving ? null : saveRemoteSettings,
                            icon: const Icon(Icons.save),
                            label: Text(saving ? '保存中...' : '保存并重启服务'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: saving ? null : regenerateToken,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重新生成令牌'),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildApiSection() {
    return Consumer(
      builder: (context, ref, child) {
        final config = ref.watch(tmdbConfigProvider);
        final proxySettings = ref.watch(proxyConfigProvider);
        final apiUrlController = TextEditingController(text: config.baseUrl);
        final readAccessTokenController =
            TextEditingController(text: config.readAccessToken);
        final apiKeyController = TextEditingController(text: config.apiKey);
        final isTesting = ValueNotifier(false);
        final testSuccess = ValueNotifier(false);
        final testMessage = ValueNotifier<String?>(null);

        Future<void> testConnection() async {
          isTesting.value = true;
          testSuccess.value = false;
          testMessage.value = null;

          final service = TmdbApiService();
          try {
            service.configure(
              baseUrl: apiUrlController.text.trim(),
              readAccessToken: readAccessTokenController.text.trim(),
              apiKey: apiKeyController.text.trim(),
            );
            service.configureProxy(
              enabled: proxySettings.proxyEnabled,
              type: proxySettings.proxyType,
              host: proxySettings.proxyHost,
              port: proxySettings.proxyPort,
              username: proxySettings.proxyUsername,
              password: proxySettings.proxyPassword,
            );

            await service.testConnection();
            testSuccess.value = true;
            testMessage.value = '连接成功';
          } on TmdbConnectionException catch (e) {
            testMessage.value = '连接失败: ${e.message}';
          } on TmdbAuthException catch (e) {
            testMessage.value = '认证失败: ${e.message}';
          } on TmdbApiException catch (e) {
            testMessage.value = 'API 错误: ${e.message}';
          } catch (e) {
            testMessage.value = '未知错误: ${e.toString()}';
          } finally {
            service.close();
            isTesting.value = false;
          }
        }

        Future<void> saveConfig() async {
          final baseUrl = apiUrlController.text.trim();
          final readAccessToken = readAccessTokenController.text.trim();
          final apiKey = apiKeyController.text.trim();

          final uri = Uri.tryParse(baseUrl);
          if (baseUrl.isEmpty || uri == null || !uri.isAbsolute) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('请输入有效的 TMDB API 地址')),
            );
            return;
          }

          if (readAccessToken.isEmpty && apiKey.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('请填写 Read Access Token 或 API Key')),
            );
            return;
          }

          try {
            await ref.read(tmdbConfigProvider.notifier).saveConfig(
                  baseUrl: baseUrl,
                  readAccessToken: readAccessToken,
                  apiKey: apiKey,
                  language: config.language,
                  region: config.region,
                );

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('配置保存成功')),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('保存失败: ${e.toString()}')),
            );
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              icon: Icons.api,
              title: 'TMDB 配置',
              subtitle: '配置 TMDB v3 电影数据源',
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: apiUrlController,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: 'API 地址',
                        hintText: 'https://api.themoviedb.org/3',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: apiUrlController.clear,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: readAccessTokenController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Read Access Token',
                        hintText: 'eyJhbGciOiJIUzI1NiJ9...',
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: apiKeyController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'API Key',
                        hintText: '可选，v3 API key',
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .tertiaryContainer
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: Theme.of(context)
                                .colorScheme
                                .onTertiaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '使用 TMDB 官方 API。优先使用 Read Access Token；未填写时使用 API Key。',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onTertiaryContainer,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    ValueListenableBuilder(
                      valueListenable: isTesting,
                      builder: (context, testing, child) {
                        return ElevatedButton(
                          onPressed: testing ? null : testConnection,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                          child: testing
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text('测试连接中...'),
                                  ],
                                )
                              : const Text('测试连接'),
                        );
                      },
                    ),
                    ValueListenableBuilder(
                      valueListenable: testMessage,
                      builder: (context, message, child) {
                        if (message == null) return const SizedBox();
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            message,
                            style: TextStyle(
                              color:
                                  testSuccess.value ? Colors.green : Colors.red,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: saveConfig,
                        child: const Text('保存设置'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProxySection() {
    final hostController =
        TextEditingController(text: _settings?.proxyHost ?? '');
    final portController =
        TextEditingController(text: _settings?.proxyPort?.toString() ?? '');
    final usernameController =
        TextEditingController(text: _settings?.proxyUsername ?? '');
    final passwordController =
        TextEditingController(text: _settings?.proxyPassword ?? '');
    final proxyEnabled = ValueNotifier(_settings?.proxyEnabled ?? false);
    final proxyType = ValueNotifier(_settings?.proxyType ?? 'http');

    void saveConfig() {
      setState(() {
        _settings = _settings!.copyWith(
          proxyEnabled: proxyEnabled.value,
          proxyType: proxyType.value,
          proxyHost: hostController.text,
          proxyPort: int.tryParse(portController.text),
          proxyUsername: usernameController.text,
          proxyPassword: passwordController.text,
        );
      });
      _saveSettings();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.router,
          title: '代理配置',
          subtitle: '配置网络代理服务器',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ValueListenableBuilder(
                  valueListenable: proxyEnabled,
                  builder: (context, enabled, child) {
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用代理'),
                      subtitle: const Text('通过代理服务器访问网络'),
                      value: enabled,
                      onChanged: (value) {
                        proxyEnabled.value = value;
                      },
                    );
                  },
                ),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  '代理协议',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder(
                  valueListenable: proxyType,
                  builder: (context, type, child) {
                    return SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'http', label: Text('HTTP')),
                        ButtonSegment(value: 'https', label: Text('HTTPS')),
                        ButtonSegment(value: 'socks5', label: Text('SOCKS5')),
                      ],
                      selected: {type},
                      onSelectionChanged: (Set<String> newSelection) {
                        proxyType.value = newSelection.first;
                      },
                    );
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  '代理服务器',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: hostController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '代理服务器地址',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: portController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '端口号',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 20),
                Text(
                  '认证信息（可选）',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '用户名',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '密码',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: saveConfig,
                    child: const Text('保存设置'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCacheSection() {
    final cachePathController =
        TextEditingController(text: _settings?.cachePath ?? '');
    final effectiveMaxCacheSizeMB = ImageCacheService.effectiveMaxCacheSizeMB(
      _settings?.maxCacheSizeMB ?? ImageCacheService.defaultMaxCacheSizeMB,
    );
    final effectiveMaxCacheFiles = ImageCacheService.effectiveMaxCacheFiles(
      _settings?.maxCacheFiles ?? ImageCacheService.defaultMaxCacheFiles,
    );
    final maxCacheSizeController = TextEditingController(
      text: effectiveMaxCacheSizeMB.toString(),
    );
    final maxCacheFilesController = TextEditingController(
      text: effectiveMaxCacheFiles.toString(),
    );
    final cacheEnabled = ValueNotifier(_settings?.cacheEnabled ?? true);

    Future<void> clearAllCache() async {
      await ImageCacheService.clearAllCache();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('全部缓存已清理')),
        );
      }
    }

    Future<void> clearCacheByCategory(CacheCategory category) async {
      await ImageCacheService.clearCacheByCategory(category);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${category.displayName}缓存已清理')),
        );
      }
    }

    Future<Map<CacheCategory, int>> getAllCacheSizes() async {
      return ImageCacheService.getAllCacheSizes();
    }

    Future<String> getCachePath() async {
      return await ImageCacheService.getCacheDirectoryPath() ?? '未设置';
    }

    String formatSize(int bytes) {
      if (bytes < 1024) {
        return '$bytes B';
      } else if (bytes < 1024 * 1024) {
        return '${(bytes / 1024).toStringAsFixed(1)} KB';
      } else if (bytes < 1024 * 1024 * 1024) {
        return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      } else {
        return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
      }
    }

    void saveConfig() {
      setState(() {
        _settings = _settings!.copyWith(
          cacheEnabled: cacheEnabled.value,
          cachePath: cachePathController.text.isNotEmpty
              ? cachePathController.text
              : null,
          maxCacheSizeMB: int.tryParse(maxCacheSizeController.text) ??
              ImageCacheService.defaultMaxCacheSizeMB,
          maxCacheFiles: int.tryParse(maxCacheFilesController.text) ??
              ImageCacheService.defaultMaxCacheFiles,
        );
      });
      _saveSettings();
    }

    void selectCachePath() async {
      final result = await FilePicker.platform.getDirectoryPath();
      if (result != null) {
        cachePathController.text = result;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.storage,
          title: '缓存管理',
          subtitle: '管理图片缓存和存储设置',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ValueListenableBuilder(
                  valueListenable: cacheEnabled,
                  builder: (context, enabled, child) {
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用缓存'),
                      subtitle: const Text('启用后图片将被缓存到本地'),
                      value: enabled,
                      onChanged: (value) {
                        cacheEnabled.value = value;
                      },
                    );
                  },
                ),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  '缓存存储路径',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: FutureBuilder<String>(
                    future: getCachePath(),
                    builder: (context, snapshot) {
                      return Row(
                        children: [
                          Icon(
                            Icons.folder,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              snapshot.data ?? '加载中...',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '缓存限制设置',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: maxCacheSizeController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '512',
                    labelText: '最大缓存大小 (MB)',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: maxCacheFilesController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '5000',
                    labelText: '最大缓存文件数',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 20),
                Text(
                  '分类缓存管理',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                FutureBuilder<Map<CacheCategory, int>>(
                  future: getAllCacheSizes(),
                  builder: (context, snapshot) {
                    final sizes = snapshot.data ?? {};
                    return Column(
                      children: CacheCategory.values.map((category) {
                        final size = sizes[category] ?? 0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _getCategoryIcon(category),
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(category.displayName),
                                const Spacer(),
                                Text(
                                  formatSize(size),
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                TextButton(
                                  onPressed: () =>
                                      clearCacheByCategory(category),
                                  style: TextButton.styleFrom(
                                    foregroundColor:
                                        Theme.of(context).colorScheme.error,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text('清除'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('当前总缓存大小'),
                        FutureBuilder<int>(
                          future: ImageCacheService.getCacheSize(),
                          builder: (context, snapshot) {
                            return Text(
                              formatSize(snapshot.data ?? 0),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: clearAllCache,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('清空全部缓存'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: saveConfig,
                        child: const Text('保存设置'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  IconData _getCategoryIcon(CacheCategory category) {
    switch (category) {
      case CacheCategory.covers:
        return Icons.image;
      case CacheCategory.actors:
        return Icons.person;
      case CacheCategory.samples:
        return Icons.photo_library;
      case CacheCategory.search:
        return Icons.search;
    }
  }

  Widget _buildAISection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.translate,
          title: 'AI翻译',
          subtitle: '配置本地AI翻译模型',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                InkWell(
                  onTap: _openAISettings,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.settings,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'AI翻译设置',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '下载和管理翻译模型',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(),
                InkWell(
                  onTap: _openTranslationTest,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .secondaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.translate,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '翻译测试',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '输入日语文本测试翻译效果',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(),
                Consumer(
                  builder: (context, ref, child) {
                    final translationState =
                        ref.watch(backgroundTranslationProvider);
                    return Column(
                      children: [
                        InkWell(
                          onTap: translationState.isTranslating
                              ? null
                              : () {
                                  ref
                                      .read(backgroundTranslationProvider
                                          .notifier)
                                      .startBackgroundTranslation();
                                },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: translationState.isTranslating
                                        ? Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest
                                        : Theme.of(context)
                                            .colorScheme
                                            .tertiaryContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: translationState.isTranslating
                                      ? SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Icon(
                                          Icons.translate,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .tertiary,
                                        ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        translationState.isTranslating
                                            ? '正在翻译...'
                                            : '翻译现有内容',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color:
                                                  translationState.isTranslating
                                                      ? Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant
                                                      : null,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      if (translationState.isTranslating)
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${translationState.completedMovies}/${translationState.totalMovies}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                            if (translationState.currentMovie !=
                                                null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 4),
                                                child: Text(
                                                  translationState
                                                      .currentMovie!,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                          ],
                                        )
                                      else
                                        Text(
                                          '后台翻译所有未翻译的影片',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (!translationState.isTranslating)
                                  Icon(
                                    Icons.chevron_right,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                if (translationState.isTranslating)
                                  IconButton(
                                    icon: Icon(
                                      Icons.visibility,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        builder: (context) =>
                                            StreamOutputDialog(),
                                      );
                                    },
                                    tooltip: '查看流式输出',
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (translationState.isTranslating)
                          Padding(
                            padding: const EdgeInsets.only(
                                top: 16, left: 16, right: 16),
                            child: LinearProgressIndicator(
                              value: translationState.totalMovies > 0
                                  ? translationState.completedMovies /
                                      translationState.totalMovies
                                  : 0,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsSidebarItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SettingsSidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_SettingsSidebarItem> createState() => _SettingsSidebarItemState();
}

class _SettingsSidebarItemState extends State<_SettingsSidebarItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : (_isHovered
                      ? Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.5)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    widget.icon,
                    size: 22,
                    color: widget.isSelected
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : (_isHovered
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontWeight: widget.isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: widget.isSelected
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : (_isHovered
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    child: Text(widget.label),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
