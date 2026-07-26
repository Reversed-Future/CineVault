import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'translation_provider.dart';
import '../ai/local_translator.dart';

class AppLifecycleProvider extends WidgetsBindingObserver {
  final Ref _ref;

  AppLifecycleProvider(this._ref) {
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.detached:
        _cleanupOnClose();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.resumed:
        break;
    }
  }

  void _cleanupOnClose() {
    try {
      _ref.read(backgroundTranslationProvider.notifier).stopTranslation();
      debugPrint('AppLifecycleProvider: 翻译任务已终止');

      Future.delayed(const Duration(milliseconds: 100), () {
        try {
          LocalTranslator().unloadModel();
          debugPrint('AppLifecycleProvider: 模型已卸载');
        } catch (e) {
          debugPrint('AppLifecycleProvider: 卸载模型时出错: $e');
        }
      });
    } catch (e) {
      debugPrint('AppLifecycleProvider: 终止翻译时出错: $e');
    }
  }
}

// 这是一个用于启动生命周期监听的 Provider
final appLifecycleInitProvider = Provider<void>((ref) {
  final lifecycle = AppLifecycleProvider(ref);
  ref.onDispose(() {
    lifecycle.dispose();
  });
});
