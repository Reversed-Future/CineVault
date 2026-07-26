// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AppNotificationAdapter extends TypeAdapter<AppNotification> {
  @override
  final int typeId = 4;

  @override
  AppNotification read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AppNotification(
      id: fields[0] as String,
      title: fields[1] as String,
      message: fields[2] as String,
      type: fields[3] as AppNotificationType,
      isRead: fields[4] as bool,
      createdAt: fields[5] as int,
      progress: fields[6] as int?,
      isProgressing: fields[7] as bool,
      isCancelled: fields[8] as bool,
      taskType: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, AppNotification obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.message)
      ..writeByte(3)
      ..write(obj.type)
      ..writeByte(4)
      ..write(obj.isRead)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.progress)
      ..writeByte(7)
      ..write(obj.isProgressing)
      ..writeByte(8)
      ..write(obj.isCancelled)
      ..writeByte(9)
      ..write(obj.taskType);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppNotificationAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AppNotificationTypeAdapter extends TypeAdapter<AppNotificationType> {
  @override
  final int typeId = 5;

  @override
  AppNotificationType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return AppNotificationType.info;
      case 1:
        return AppNotificationType.success;
      case 2:
        return AppNotificationType.warning;
      case 3:
        return AppNotificationType.error;
      default:
        return AppNotificationType.info;
    }
  }

  @override
  void write(BinaryWriter writer, AppNotificationType obj) {
    switch (obj) {
      case AppNotificationType.info:
        writer.writeByte(0);
        break;
      case AppNotificationType.success:
        writer.writeByte(1);
        break;
      case AppNotificationType.warning:
        writer.writeByte(2);
        break;
      case AppNotificationType.error:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppNotificationTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
