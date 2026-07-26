import 'package:hive/hive.dart';

part 'app_settings.g.dart';

@HiveType(typeId: 2)
class AppSettings extends HiveObject {
  @HiveField(0)
  final List<String> videoFolders;

  @HiveField(1)
  final double playbackSpeed;

  @HiveField(2)
  final bool autoResumePlayback;

  @HiveField(3)
  final bool showSubtitlesByDefault;

  @HiveField(4)
  final String? subtitleFontSize;

  @HiveField(5)
  final String? localAssetManagerPath;

  @HiveField(6)
  final bool aiTranslationEnabled;

  @HiveField(7)
  final String? selectedModelId;

  @HiveField(8)
  final String? customModelsPath;

  @HiveField(9)
  final int aiThreadCount;

  @HiveField(10)
  final bool fallbackToOriginal;

  @HiveField(11)
  final String? dataStoragePath;

  @HiveField(12)
  final List<String> castTags;

  @HiveField(13)
  String? apiBaseUrl;

  @HiveField(14)
  bool proxyEnabled;

  @HiveField(15)
  String? proxyType;

  @HiveField(16)
  String? proxyHost;

  @HiveField(17)
  int? proxyPort;

  @HiveField(18)
  String? proxyUsername;

  @HiveField(19)
  String? proxyPassword;

  @HiveField(20)
  bool cacheEnabled;

  @HiveField(21)
  String? cachePath;

  @HiveField(22)
  int maxCacheSizeMB;

  @HiveField(23)
  int maxCacheFiles;

  // ==================== Aria2 下载设置 ====================

  /// 是否使用 aria2 进行下载
  @HiveField(24)
  bool useAria2ForDownloads;

  /// aria2 RPC 端口
  @HiveField(25)
  int aria2RpcPort;

  /// aria2 RPC 密钥（可选）
  @HiveField(26)
  String? aria2RpcSecret;

  /// aria2 最大并发下载数
  @HiveField(27)
  int aria2MaxConcurrentDownloads;

  /// aria2 每个服务器最大连接数
  @HiveField(28)
  int aria2MaxConnectionPerServer;

  /// aria2 全局下载限速（KB/s，0=不限速）
  @HiveField(29)
  int aria2DownloadSpeedLimitKB;

  /// aria2 全局上传限速（KB/s，0=不限速）
  @HiveField(30)
  int aria2UploadSpeedLimitKB;

  /// 是否自动启动 aria2
  @HiveField(31)
  bool autoStartAria2;

  /// BT trackers 列表（用换行或逗号分隔）
  @HiveField(32)
  String? aria2TrackersList;

  /// 是否启用自动更新 trackers
  @HiveField(33)
  bool autoUpdateTrackers;

  /// 上次更新 trackers 的时间
  @HiveField(34)
  int? lastTrackersUpdateTime;

  /// trackers 源 URL（多个用换行分隔）
  @HiveField(35)
  String? trackersSourceUrls;

  /// 字体名称（系统默认、微软雅黑、宋体、黑体、Arial 等）
  @HiveField(36)
  String? fontFamily;

  /// 字体大小（像素，范围 12-24）
  @HiveField(37)
  int fontSize;

  @HiveField(38)
  final bool unloadModelAfterAiTagging;

  AppSettings({
    this.videoFolders = const [],
    this.playbackSpeed = 1.0,
    this.autoResumePlayback = true,
    this.showSubtitlesByDefault = true,
    this.subtitleFontSize = 'medium',
    this.localAssetManagerPath,
    this.aiTranslationEnabled = false,
    this.selectedModelId,
    this.customModelsPath,
    this.aiThreadCount = 4,
    this.fallbackToOriginal = true,
    this.dataStoragePath,
    this.castTags = const [],
    String? apiBaseUrl,
    bool? proxyEnabled,
    String? proxyType,
    this.proxyHost,
    this.proxyPort,
    this.proxyUsername,
    this.proxyPassword,
    bool? cacheEnabled,
    this.cachePath,
    int? maxCacheSizeMB,
    int? maxCacheFiles,
    bool? useAria2ForDownloads,
    int? aria2RpcPort,
    this.aria2RpcSecret,
    int? aria2MaxConcurrentDownloads,
    int? aria2MaxConnectionPerServer,
    int? aria2DownloadSpeedLimitKB,
    int? aria2UploadSpeedLimitKB,
    bool? autoStartAria2,
    this.aria2TrackersList,
    bool? autoUpdateTrackers,
    this.lastTrackersUpdateTime,
    this.trackersSourceUrls,
    this.fontFamily,
    int? fontSize,
    this.unloadModelAfterAiTagging = false,
  })  : apiBaseUrl = apiBaseUrl,
        proxyEnabled = proxyEnabled ?? false,
        proxyType = proxyType ?? 'http',
        cacheEnabled = cacheEnabled ?? true,
        maxCacheSizeMB = maxCacheSizeMB ?? 512,
        maxCacheFiles = maxCacheFiles ?? 5000,
        useAria2ForDownloads = useAria2ForDownloads ?? false,
        aria2RpcPort = aria2RpcPort ?? 6800,
        aria2MaxConcurrentDownloads = aria2MaxConcurrentDownloads ?? 5,
        aria2MaxConnectionPerServer = aria2MaxConnectionPerServer ?? 16,
        aria2DownloadSpeedLimitKB = aria2DownloadSpeedLimitKB ?? 0,
        aria2UploadSpeedLimitKB = aria2UploadSpeedLimitKB ?? 0,
        autoStartAria2 = autoStartAria2 ?? true,
        autoUpdateTrackers = autoUpdateTrackers ?? false,
        fontSize = fontSize ?? 14;

  AppSettings copyWith({
    List<String>? videoFolders,
    double? playbackSpeed,
    bool? autoResumePlayback,
    bool? showSubtitlesByDefault,
    String? subtitleFontSize,
    String? localAssetManagerPath,
    bool? aiTranslationEnabled,
    String? selectedModelId,
    String? customModelsPath,
    int? aiThreadCount,
    bool? fallbackToOriginal,
    String? dataStoragePath,
    List<String>? castTags,
    String? apiBaseUrl,
    bool? proxyEnabled,
    String? proxyType,
    String? proxyHost,
    int? proxyPort,
    String? proxyUsername,
    String? proxyPassword,
    bool? cacheEnabled,
    String? cachePath,
    int? maxCacheSizeMB,
    int? maxCacheFiles,
    bool? useAria2ForDownloads,
    int? aria2RpcPort,
    String? aria2RpcSecret,
    int? aria2MaxConcurrentDownloads,
    int? aria2MaxConnectionPerServer,
    int? aria2DownloadSpeedLimitKB,
    int? aria2UploadSpeedLimitKB,
    bool? autoStartAria2,
    String? aria2TrackersList,
    bool? autoUpdateTrackers,
    int? lastTrackersUpdateTime,
    String? trackersSourceUrls,
    String? fontFamily,
    int? fontSize,
    bool? unloadModelAfterAiTagging,
    bool clearSelectedModelId = false,
    bool clearCustomModelsPath = false,
    bool clearProxyUsername = false,
    bool clearProxyPassword = false,
    bool clearAria2RpcSecret = false,
  }) {
    return AppSettings(
      videoFolders: videoFolders ?? this.videoFolders,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      autoResumePlayback: autoResumePlayback ?? this.autoResumePlayback,
      showSubtitlesByDefault:
          showSubtitlesByDefault ?? this.showSubtitlesByDefault,
      subtitleFontSize: subtitleFontSize ?? this.subtitleFontSize,
      localAssetManagerPath:
          localAssetManagerPath ?? this.localAssetManagerPath,
      aiTranslationEnabled: aiTranslationEnabled ?? this.aiTranslationEnabled,
      selectedModelId: clearSelectedModelId
          ? null
          : (selectedModelId ?? this.selectedModelId),
      customModelsPath: clearCustomModelsPath
          ? null
          : (customModelsPath ?? this.customModelsPath),
      aiThreadCount: aiThreadCount ?? this.aiThreadCount,
      fallbackToOriginal: fallbackToOriginal ?? this.fallbackToOriginal,
      dataStoragePath: dataStoragePath ?? this.dataStoragePath,
      castTags: castTags ?? this.castTags,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      proxyEnabled: proxyEnabled ?? this.proxyEnabled,
      proxyType: proxyType ?? this.proxyType,
      proxyHost: proxyHost ?? this.proxyHost,
      proxyPort: proxyPort ?? this.proxyPort,
      proxyUsername:
          clearProxyUsername ? null : (proxyUsername ?? this.proxyUsername),
      proxyPassword:
          clearProxyPassword ? null : (proxyPassword ?? this.proxyPassword),
      cacheEnabled: cacheEnabled ?? this.cacheEnabled,
      cachePath: cachePath ?? this.cachePath,
      maxCacheSizeMB: maxCacheSizeMB ?? this.maxCacheSizeMB,
      maxCacheFiles: maxCacheFiles ?? this.maxCacheFiles,
      useAria2ForDownloads: useAria2ForDownloads ?? this.useAria2ForDownloads,
      aria2RpcPort: aria2RpcPort ?? this.aria2RpcPort,
      aria2RpcSecret:
          clearAria2RpcSecret ? null : (aria2RpcSecret ?? this.aria2RpcSecret),
      aria2MaxConcurrentDownloads:
          aria2MaxConcurrentDownloads ?? this.aria2MaxConcurrentDownloads,
      aria2MaxConnectionPerServer:
          aria2MaxConnectionPerServer ?? this.aria2MaxConnectionPerServer,
      aria2DownloadSpeedLimitKB:
          aria2DownloadSpeedLimitKB ?? this.aria2DownloadSpeedLimitKB,
      aria2UploadSpeedLimitKB:
          aria2UploadSpeedLimitKB ?? this.aria2UploadSpeedLimitKB,
      autoStartAria2: autoStartAria2 ?? this.autoStartAria2,
      aria2TrackersList: aria2TrackersList ?? this.aria2TrackersList,
      autoUpdateTrackers: autoUpdateTrackers ?? this.autoUpdateTrackers,
      lastTrackersUpdateTime:
          lastTrackersUpdateTime ?? this.lastTrackersUpdateTime,
      trackersSourceUrls: trackersSourceUrls ?? this.trackersSourceUrls,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      unloadModelAfterAiTagging:
          unloadModelAfterAiTagging ?? this.unloadModelAfterAiTagging,
    );
  }
}
