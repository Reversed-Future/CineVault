import 'package:hive/hive.dart';

part 'notification.g.dart';

@HiveType(typeId: 5)
enum AppNotificationType {
  @HiveField(0)
  info,
  @HiveField(1)
  success,
  @HiveField(2)
  warning,
  @HiveField(3)
  error,
}

@HiveType(typeId: 4)
class AppNotification extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String message;

  @HiveField(3)
  final AppNotificationType type;

  @HiveField(4)
  final bool isRead;

  @HiveField(5)
  final int createdAt; // milliseconds since epoch

  @HiveField(6)
  final int? progress; // 0-100，null 表示没有进度

  @HiveField(7)
  final bool isProgressing; // 是否正在进行中

  @HiveField(8)
  final bool isCancelled; // 是否已被取消

  @HiveField(9)
  final String? taskType; // 任务类型，用于标识可以取消的任务（如 batch_update）

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    this.type = AppNotificationType.info,
    this.isRead = false,
    required this.createdAt,
    this.progress,
    this.isProgressing = false,
    this.isCancelled = false,
    this.taskType,
  });

  AppNotification copyWith({
    String? id,
    String? title,
    String? message,
    AppNotificationType? type,
    bool? isRead,
    int? createdAt,
    int? progress,
    bool? isProgressing,
    bool? isCancelled,
    String? taskType,
  }) {
    return AppNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      type: type ?? this.type,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      progress: progress ?? this.progress,
      isProgressing: isProgressing ?? this.isProgressing,
      isCancelled: isCancelled ?? this.isCancelled,
      taskType: taskType ?? this.taskType,
    );
  }

  DateTime get createdAtDateTime =>
      DateTime.fromMillisecondsSinceEpoch(createdAt);

  static String generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
}
