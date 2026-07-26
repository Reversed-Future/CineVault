import 'package:flutter_test/flutter_test.dart';
import 'package:cine_vault/models/app_settings.dart';
import 'package:cine_vault/screens/ai_settings_screen.dart';

void main() {
  test('AI settings update preserves unrelated settings', () {
    final existing = AppSettings(
      videoFolders: const ['D:\\videos'],
      playbackSpeed: 1.25,
      autoResumePlayback: false,
      showSubtitlesByDefault: false,
      subtitleFontSize: 'large',
      localAssetManagerPath: 'D:\\assets',
      dataStoragePath: 'D:\\data',
      castTags: const ['tag-a'],
      apiBaseUrl: 'http://127.0.0.1:3000',
      proxyEnabled: true,
      proxyType: 'socks5',
      proxyHost: '127.0.0.1',
      proxyPort: 1080,
      proxyUsername: 'user',
      proxyPassword: 'pass',
      cacheEnabled: false,
      cachePath: 'D:\\cache',
      maxCacheSizeMB: 512,
      maxCacheFiles: 1000,
      useAria2ForDownloads: true,
      aria2RpcPort: 16800,
      aria2RpcSecret: 'secret',
      aria2MaxConcurrentDownloads: 9,
      aria2MaxConnectionPerServer: 12,
      aria2DownloadSpeedLimitKB: 2048,
      aria2UploadSpeedLimitKB: 1024,
      autoStartAria2: false,
      aria2TrackersList: 'udp://tracker.example:80',
      autoUpdateTrackers: true,
      lastTrackersUpdateTime: 123456,
      trackersSourceUrls: 'https://trackers.example/list.txt',
      fontFamily: 'Arial',
      fontSize: 18,
      unloadModelAfterAiTagging: true,
    );

    final updated = buildAiSettingsUpdate(
      existing,
      aiTranslationEnabled: true,
      selectedModelId: 'qwen2.5-1.5b-q4km',
      customModelsPath: 'D:\\models',
      aiThreadCount: 8,
      fallbackToOriginal: false,
      unloadModelAfterAiTagging: false,
    );

    expect(updated.aiTranslationEnabled, isTrue);
    expect(updated.selectedModelId, 'qwen2.5-1.5b-q4km');
    expect(updated.customModelsPath, 'D:\\models');
    expect(updated.aiThreadCount, 8);
    expect(updated.fallbackToOriginal, isFalse);
    expect(updated.unloadModelAfterAiTagging, isFalse);

    expect(updated.videoFolders, existing.videoFolders);
    expect(updated.playbackSpeed, existing.playbackSpeed);
    expect(updated.autoResumePlayback, existing.autoResumePlayback);
    expect(updated.showSubtitlesByDefault, existing.showSubtitlesByDefault);
    expect(updated.subtitleFontSize, existing.subtitleFontSize);
    expect(updated.localAssetManagerPath, existing.localAssetManagerPath);
    expect(updated.dataStoragePath, existing.dataStoragePath);
    expect(updated.castTags, existing.castTags);
    expect(updated.apiBaseUrl, existing.apiBaseUrl);
    expect(updated.proxyEnabled, existing.proxyEnabled);
    expect(updated.proxyType, existing.proxyType);
    expect(updated.proxyHost, existing.proxyHost);
    expect(updated.proxyPort, existing.proxyPort);
    expect(updated.proxyUsername, existing.proxyUsername);
    expect(updated.proxyPassword, existing.proxyPassword);
    expect(updated.cacheEnabled, existing.cacheEnabled);
    expect(updated.cachePath, existing.cachePath);
    expect(updated.maxCacheSizeMB, existing.maxCacheSizeMB);
    expect(updated.maxCacheFiles, existing.maxCacheFiles);
    expect(updated.useAria2ForDownloads, existing.useAria2ForDownloads);
    expect(updated.aria2RpcPort, existing.aria2RpcPort);
    expect(updated.aria2RpcSecret, existing.aria2RpcSecret);
    expect(
      updated.aria2MaxConcurrentDownloads,
      existing.aria2MaxConcurrentDownloads,
    );
    expect(
      updated.aria2MaxConnectionPerServer,
      existing.aria2MaxConnectionPerServer,
    );
    expect(
      updated.aria2DownloadSpeedLimitKB,
      existing.aria2DownloadSpeedLimitKB,
    );
    expect(
      updated.aria2UploadSpeedLimitKB,
      existing.aria2UploadSpeedLimitKB,
    );
    expect(updated.autoStartAria2, existing.autoStartAria2);
    expect(updated.aria2TrackersList, existing.aria2TrackersList);
    expect(updated.autoUpdateTrackers, existing.autoUpdateTrackers);
    expect(updated.lastTrackersUpdateTime, existing.lastTrackersUpdateTime);
    expect(updated.trackersSourceUrls, existing.trackersSourceUrls);
    expect(updated.fontFamily, existing.fontFamily);
    expect(updated.fontSize, existing.fontSize);
  });
}
