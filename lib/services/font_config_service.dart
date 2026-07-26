import 'package:flutter/material.dart';
import '../models/app_settings.dart';

/// 字体配置服务
/// 
/// 管理应用字体设置，提供字体列表、字体预览和主题生成
class FontConfigService {
  /// 可用字体列表
  static const List<FontOption> availableFonts = [
    FontOption(
      id: 'system',
      displayName: '系统默认',
      fontFamily: null,
      sampleText: '这是系统默认字体的预览效果',
    ),
    FontOption(
      id: 'microsoft-yahei',
      displayName: '微软雅黑',
      fontFamily: 'Microsoft YaHei',
      sampleText: '这是微软雅黑字体的预览效果',
    ),
    FontOption(
      id: 'songti',
      displayName: '宋体',
      fontFamily: 'SimSun',
      sampleText: '这是宋体字体的预览效果',
    ),
    FontOption(
      id: 'heiti',
      displayName: '黑体',
      fontFamily: 'SimHei',
      sampleText: '这是黑体字体的预览效果',
    ),
    FontOption(
      id: 'arial',
      displayName: 'Arial',
      fontFamily: 'Arial',
      sampleText: 'Arial font preview effect',
    ),
    FontOption(
      id: 'custom',
      displayName: '自定义',
      fontFamily: null,
      sampleText: '选择自定义字体文件',
    ),
  ];

  /// 获取字体选项
  static FontOption? getFontOption(String? fontId) {
    if (fontId == null || fontId.isEmpty) {
      return availableFonts[0]; // 返回系统默认
    }
    return availableFonts.firstWhere(
      (font) => font.id == fontId,
      orElse: () => availableFonts[0],
    );
  }

  /// 根据设置生成主题文本样式
  static TextTheme generateTextTheme(AppSettings settings) {
    final fontOption = getFontOption(settings.fontFamily);
    final fontSize = settings.fontSize.clamp(12, 24);
    
    final baseTextTheme = ThemeData.light().textTheme;
    
    return baseTextTheme.apply(
      fontFamily: fontOption?.fontFamily,
      bodyColor: null,
      displayColor: null,
    ).copyWith(
      // 调整字体大小
      displayLarge: baseTextTheme.displayLarge?.copyWith(
        fontSize: fontSize * 2.2,
        fontFamily: fontOption?.fontFamily,
      ),
      displayMedium: baseTextTheme.displayMedium?.copyWith(
        fontSize: fontSize * 1.8,
        fontFamily: fontOption?.fontFamily,
      ),
      displaySmall: baseTextTheme.displaySmall?.copyWith(
        fontSize: fontSize * 1.6,
        fontFamily: fontOption?.fontFamily,
      ),
      headlineLarge: baseTextTheme.headlineLarge?.copyWith(
        fontSize: fontSize * 1.5,
        fontFamily: fontOption?.fontFamily,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        fontSize: fontSize * 1.4,
        fontFamily: fontOption?.fontFamily,
      ),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        fontSize: fontSize * 1.3,
        fontFamily: fontOption?.fontFamily,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontSize: fontSize * 1.2,
        fontFamily: fontOption?.fontFamily,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontSize: fontSize * 1.1,
        fontFamily: fontOption?.fontFamily,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
        fontSize: fontSize * 1.05,
        fontFamily: fontOption?.fontFamily,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        fontSize: fontSize.toDouble(),
        fontFamily: fontOption?.fontFamily,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        fontSize: fontSize.toDouble(),
        fontFamily: fontOption?.fontFamily,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
        fontSize: fontSize * 0.9,
        fontFamily: fontOption?.fontFamily,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontSize: fontSize * 0.95,
        fontFamily: fontOption?.fontFamily,
      ),
      labelMedium: baseTextTheme.labelMedium?.copyWith(
        fontSize: fontSize * 0.9,
        fontFamily: fontOption?.fontFamily,
      ),
      labelSmall: baseTextTheme.labelSmall?.copyWith(
        fontSize: fontSize * 0.85,
        fontFamily: fontOption?.fontFamily,
      ),
    );
  }

  /// 根据设置生成主题
  static ThemeData generateTheme(AppSettings settings) {
    final textTheme = generateTextTheme(settings);
    return ThemeData(
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      fontFamily: getFontOption(settings.fontFamily)?.fontFamily,
    );
  }

  /// 格式化字体大小显示
  static String formatFontSize(int size) {
    return '${size}px';
  }
}

/// 字体选项
class FontOption {
  final String id;
  final String displayName;
  final String? fontFamily;
  final String sampleText;

  const FontOption({
    required this.id,
    required this.displayName,
    this.fontFamily,
    required this.sampleText,
  });
}