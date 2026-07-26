// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'movie.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MovieAdapter extends TypeAdapter<Movie> {
  @override
  final int typeId = 0;

  @override
  Movie read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Movie(
      id: fields[0] as String,
      name: fields[1] as String,
      path: fields[2] as String?,
      size: fields[3] as double?,
      createdAt: fields[4] as int,
      cast: (fields[5] as List).cast<Cast>(),
      tags: (fields[6] as List?)?.cast<NamedItem>(),
      coverUrl: fields[7] as String?,
      originalCoverUrl: fields[21] as String?,
      isCoverCropped: fields[22] as bool?,
      backdropUrl: fields[28] as String?,
      code: fields[8] as String,
      releaseDate: fields[9] as String?,
      length: fields[10] as int?,
      videoFilePaths: (fields[11] as List?)?.cast<String>(),
      isFavorite: fields[12] as bool?,
      lastWatchPosition: fields[13] as double?,
      lastWatchedAt: fields[14] as int?,
      playCount: fields[15] as int?,
      translatedName: fields[16] as String?,
      translatedTags: (fields[17] as List?)?.cast<String>(),
      translatedPlot: fields[18] as String?,
      samples: (fields[19] as List?)?.cast<SampleInfo>(),
      magnets: (fields[20] as List?)?.cast<MagnetInfo>(),
      director: fields[23] as NamedItem?,
      producer: fields[24] as NamedItem?,
      publisher: fields[25] as NamedItem?,
      series: fields[26] as NamedItem?,
      subtitleFilePaths: (fields[27] as List?)?.cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, Movie obj) {
    writer
      ..writeByte(29)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.path)
      ..writeByte(3)
      ..write(obj.size)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write(obj.cast)
      ..writeByte(6)
      ..write(obj.tags)
      ..writeByte(7)
      ..write(obj.coverUrl)
      ..writeByte(21)
      ..write(obj.originalCoverUrl)
      ..writeByte(22)
      ..write(obj.isCoverCropped)
      ..writeByte(28)
      ..write(obj.backdropUrl)
      ..writeByte(8)
      ..write(obj.code)
      ..writeByte(9)
      ..write(obj.releaseDate)
      ..writeByte(10)
      ..write(obj.length)
      ..writeByte(11)
      ..write(obj.videoFilePaths)
      ..writeByte(12)
      ..write(obj.isFavorite)
      ..writeByte(13)
      ..write(obj.lastWatchPosition)
      ..writeByte(14)
      ..write(obj.lastWatchedAt)
      ..writeByte(15)
      ..write(obj.playCount)
      ..writeByte(16)
      ..write(obj.translatedName)
      ..writeByte(17)
      ..write(obj.translatedTags)
      ..writeByte(18)
      ..write(obj.translatedPlot)
      ..writeByte(19)
      ..write(obj.samples)
      ..writeByte(20)
      ..write(obj.magnets)
      ..writeByte(23)
      ..write(obj.director)
      ..writeByte(24)
      ..write(obj.producer)
      ..writeByte(25)
      ..write(obj.publisher)
      ..writeByte(26)
      ..write(obj.series)
      ..writeByte(27)
      ..write(obj.subtitleFilePaths);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovieAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SampleInfoAdapter extends TypeAdapter<SampleInfo> {
  @override
  final int typeId = 6;

  @override
  SampleInfo read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SampleInfo(
      id: fields[0] as String,
      src: fields[1] as String,
      thumbnail: fields[2] as String,
      alt: fields[3] as String,
    );
  }

  @override
  void write(BinaryWriter writer, SampleInfo obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.src)
      ..writeByte(2)
      ..write(obj.thumbnail)
      ..writeByte(3)
      ..write(obj.alt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SampleInfoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class MagnetInfoAdapter extends TypeAdapter<MagnetInfo> {
  @override
  final int typeId = 7;

  @override
  MagnetInfo read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MagnetInfo(
      id: fields[0] as String,
      link: fields[1] as String,
      isHD: fields[2] as bool,
      title: fields[3] as String,
      size: fields[4] as String,
      numberSize: fields[5] as int,
      shareDate: fields[6] as String,
      hasSubtitle: fields[7] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, MagnetInfo obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.link)
      ..writeByte(2)
      ..write(obj.isHD)
      ..writeByte(3)
      ..write(obj.title)
      ..writeByte(4)
      ..write(obj.size)
      ..writeByte(5)
      ..write(obj.numberSize)
      ..writeByte(6)
      ..write(obj.shareDate)
      ..writeByte(7)
      ..write(obj.hasSubtitle);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MagnetInfoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
