// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_tagging_result.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AiTaggingResultAdapter extends TypeAdapter<AiTaggingResult> {
  @override
  final int typeId = 12;

  @override
  AiTaggingResult read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AiTaggingResult(
      id: fields[0] as String,
      movieId: fields[1] as String,
      modelId: fields[2] as String,
      inputHash: fields[3] as String,
      titleSegmentsJson: fields[4] as String,
      matchedTagsJson: fields[5] as String,
      status: fields[6] as String,
      createdAt: fields[7] as int,
      updatedAt: fields[8] as int,
      rawOutput: fields[9] as String,
      errorMessage: fields[10] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, AiTaggingResult obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.movieId)
      ..writeByte(2)
      ..write(obj.modelId)
      ..writeByte(3)
      ..write(obj.inputHash)
      ..writeByte(4)
      ..write(obj.titleSegmentsJson)
      ..writeByte(5)
      ..write(obj.matchedTagsJson)
      ..writeByte(6)
      ..write(obj.status)
      ..writeByte(7)
      ..write(obj.createdAt)
      ..writeByte(8)
      ..write(obj.updatedAt)
      ..writeByte(9)
      ..write(obj.rawOutput)
      ..writeByte(10)
      ..write(obj.errorMessage);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiTaggingResultAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
