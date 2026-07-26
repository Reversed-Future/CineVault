// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_settings.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AppSettingsAdapter extends TypeAdapter<AppSettings> {
  @override
  final int typeId = 2;

  @override
  AppSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AppSettings(
      videoFolders: (fields[0] as List).cast<String>(),
      playbackSpeed: fields[1] as double,
      autoResumePlayback: fields[2] as bool,
      showSubtitlesByDefault: fields[3] as bool,
      subtitleFontSize: fields[4] as String?,
      localAssetManagerPath: fields[5] as String?,
      aiTranslationEnabled: fields[6] as bool,
      selectedModelId: fields[7] as String?,
      customModelsPath: fields[8] as String?,
      aiThreadCount: fields[9] as int,
      fallbackToOriginal: fields[10] as bool,
      dataStoragePath: fields[11] as String?,
      castTags: (fields[12] as List).cast<String>(),
      apiBaseUrl: fields[13] as String?,
      proxyEnabled: fields[14] as bool?,
      proxyType: fields[15] as String?,
      proxyHost: fields[16] as String?,
      proxyPort: fields[17] as int?,
      proxyUsername: fields[18] as String?,
      proxyPassword: fields[19] as String?,
      cacheEnabled: fields[20] as bool?,
      cachePath: fields[21] as String?,
      maxCacheSizeMB: fields[22] as int?,
      maxCacheFiles: fields[23] as int?,
      useAria2ForDownloads: fields[24] as bool?,
      aria2RpcPort: fields[25] as int?,
      aria2RpcSecret: fields[26] as String?,
      aria2MaxConcurrentDownloads: fields[27] as int?,
      aria2MaxConnectionPerServer: fields[28] as int?,
      aria2DownloadSpeedLimitKB: fields[29] as int?,
      aria2UploadSpeedLimitKB: fields[30] as int?,
      autoStartAria2: fields[31] as bool?,
      aria2TrackersList: fields[32] as String?,
      autoUpdateTrackers: fields[33] as bool?,
      lastTrackersUpdateTime: fields[34] as int?,
      trackersSourceUrls: fields[35] as String?,
      fontFamily: fields[36] as String?,
      fontSize: fields[37] as int?,
      unloadModelAfterAiTagging: fields[38] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, AppSettings obj) {
    writer
      ..writeByte(39)
      ..writeByte(0)
      ..write(obj.videoFolders)
      ..writeByte(1)
      ..write(obj.playbackSpeed)
      ..writeByte(2)
      ..write(obj.autoResumePlayback)
      ..writeByte(3)
      ..write(obj.showSubtitlesByDefault)
      ..writeByte(4)
      ..write(obj.subtitleFontSize)
      ..writeByte(5)
      ..write(obj.localAssetManagerPath)
      ..writeByte(6)
      ..write(obj.aiTranslationEnabled)
      ..writeByte(7)
      ..write(obj.selectedModelId)
      ..writeByte(8)
      ..write(obj.customModelsPath)
      ..writeByte(9)
      ..write(obj.aiThreadCount)
      ..writeByte(10)
      ..write(obj.fallbackToOriginal)
      ..writeByte(11)
      ..write(obj.dataStoragePath)
      ..writeByte(12)
      ..write(obj.castTags)
      ..writeByte(13)
      ..write(obj.apiBaseUrl)
      ..writeByte(14)
      ..write(obj.proxyEnabled)
      ..writeByte(15)
      ..write(obj.proxyType)
      ..writeByte(16)
      ..write(obj.proxyHost)
      ..writeByte(17)
      ..write(obj.proxyPort)
      ..writeByte(18)
      ..write(obj.proxyUsername)
      ..writeByte(19)
      ..write(obj.proxyPassword)
      ..writeByte(20)
      ..write(obj.cacheEnabled)
      ..writeByte(21)
      ..write(obj.cachePath)
      ..writeByte(22)
      ..write(obj.maxCacheSizeMB)
      ..writeByte(23)
      ..write(obj.maxCacheFiles)
      ..writeByte(24)
      ..write(obj.useAria2ForDownloads)
      ..writeByte(25)
      ..write(obj.aria2RpcPort)
      ..writeByte(26)
      ..write(obj.aria2RpcSecret)
      ..writeByte(27)
      ..write(obj.aria2MaxConcurrentDownloads)
      ..writeByte(28)
      ..write(obj.aria2MaxConnectionPerServer)
      ..writeByte(29)
      ..write(obj.aria2DownloadSpeedLimitKB)
      ..writeByte(30)
      ..write(obj.aria2UploadSpeedLimitKB)
      ..writeByte(31)
      ..write(obj.autoStartAria2)
      ..writeByte(32)
      ..write(obj.aria2TrackersList)
      ..writeByte(33)
      ..write(obj.autoUpdateTrackers)
      ..writeByte(34)
      ..write(obj.lastTrackersUpdateTime)
      ..writeByte(35)
      ..write(obj.trackersSourceUrls)
      ..writeByte(36)
      ..write(obj.fontFamily)
      ..writeByte(37)
      ..write(obj.fontSize)
      ..writeByte(38)
      ..write(obj.unloadModelAfterAiTagging);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
