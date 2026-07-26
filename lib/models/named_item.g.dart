// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'named_item.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class NamedItemAdapter extends TypeAdapter<NamedItem> {
  @override
  final int typeId = 8;

  @override
  NamedItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return NamedItem(
      id: fields[0] as String,
      name: fields[1] as String,
    );
  }

  @override
  void write(BinaryWriter writer, NamedItem obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NamedItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
