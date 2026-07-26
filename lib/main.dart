import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart';
import 'screens/home_screen.dart';
import 'theme/theme.dart';
import 'services/database_service.dart';
import 'services/aria2_initializer.dart';
import 'services/data_storage_path_service.dart';
import 'services/image_cache_service.dart';
import 'services/remote/remote_cine_vault_server.dart';
import 'providers/app_lifecycle_provider.dart';
import 'providers/movie_providers.dart';

Future<void> _initHive() async {
  final dataPath = await DataStoragePathService.resolveInitialDataPath();
  await DatabaseService.init(customPath: dataPath);
  try {
    await DataStoragePathService.consumePendingImport(
      storagePath: dataPath,
      importData: (filePath) async {
        final result = await DatabaseService.importData(filePath);
        if (!result.success) {
          throw StateError(result.error ?? result.getSummary());
        }
      },
    );
  } catch (e) {
    debugPrint('[main] Failed to import pending data snapshot: $e');
  }

  final settings = DatabaseService.getSettings();
  ImageCacheService.configure(
    enabled: settings.cacheEnabled,
    cachePath: settings.cachePath,
    maxCacheSizeMB: settings.maxCacheSizeMB,
    maxCacheFiles: settings.maxCacheFiles,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  MediaKit.ensureInitialized();

  await _initHive();
  try {
    await remoteCineVaultServer.startFromSettings();
  } catch (error) {
    debugPrint('[main] Failed to start remote server: $error');
  }

  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1400, 900),
    minimumSize: Size(1200, 700),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();
    // 初始化应用生命周期监听
    ref.read(appLifecycleInitProvider);
    // 初始化代理配置
    ref.read(initProxyConfigProvider);
    // 初始化 aria2
    ref.read(aria2InitProvider);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CineVault',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      themeMode: ThemeMode.light,
      home: const HomeScreen(),
    );
  }
}
