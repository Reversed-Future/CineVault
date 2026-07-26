// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'custom_movie_tag.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CustomMovieTagAdapter extends TypeAdapter<CustomMovieTag> {
  @override
  final int typeId = 10;

  @override
  CustomMovieTag read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CustomMovieTag(
      id: fields[0] as String,
      name: fields[1] as String,
      createdAt: fields[2] as int,
    );
  }

  @override
  void write(BinaryWriter writer, CustomMovieTag obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomMovieTagAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class MovieCustomTagLinkAdapter extends TypeAdapter<MovieCustomTagLink> {
  @override
  final int typeId = 11;

  @override
  MovieCustomTagLink read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MovieCustomTagLink(
      id: fields[0] as String,
      movieId: fields[1] as String,
      tagId: fields[2] as String,
      createdAt: fields[3] as int,
    );
  }

  @override
  void write(BinaryWriter writer, MovieCustomTagLink obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.movieId)
      ..writeByte(2)
      ..write(obj.tagId)
      ..writeByte(3)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovieCustomTagLinkAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
