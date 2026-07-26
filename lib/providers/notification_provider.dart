import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification.dart';
import '../services/database_service.dart';

class NotificationState {
  final List<AppNotification> notifications;
  final List<AppNotification> unreadNotifications;
  final AppNotification? latestNotification;

  NotificationState({
    required this.notifications,
    required this.unreadNotifications,
    this.latestNotification,
  });

  NotificationState copyWith({
    List<AppNotification>? notifications,
    List<AppNotification>? unreadNotifications,
    AppNotification? latestNotification,
  }) {
    return NotificationState(
      notifications: notifications ?? this.notifications,
      unreadNotifications: unreadNotifications ?? this.unreadNotifications,
      latestNotification: latestNotification ?? this.latestNotification,
    );
  }
}

class NotificationNotifier extends Notifier<NotificationState> {
  @override
  NotificationState build() {
    return NotificationState(
      notifications: DatabaseService.getAllNotifications(),
      unreadNotifications: DatabaseService.getUnreadNotifications(),
    );
  }

  void _refreshState() {
    state = NotificationState(
      notifications: DatabaseService.getAllNotifications(),
      unreadNotifications: DatabaseService.getUnreadNotifications(),
    );
  }

  /// 添加普通通知
  Future<void> addNotification({
    required String title,
    required String message,
    AppNotificationType type = AppNotificationType.info,
  }) async {
    final notification = AppNotification(
      id: AppNotification.generateId(),
      title: title,
      message: message,
      type: type,
      isRead: false,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    await DatabaseService.addNotification(notification);
    
    state = state.copyWith(
      latestNotification: notification,
    );
    
    _refreshState();
  }
  
  /// 添加进度通知（返回通知ID，用于后续更新）
  Future<String> addProgressNotification({
    required String title,
    required String message,
    AppNotificationType type = AppNotificationType.info,
    int initialProgress = 0,
    String? taskType,
  }) async {
    final notificationId = AppNotification.generateId();
    final notification = AppNotification(
      id: notificationId,
      title: title,
      message: message,
      type: type,
      isRead: false,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      progress: initialProgress,
      isProgressing: true,
      isCancelled: false,
      taskType: taskType,
    );

    await DatabaseService.addNotification(notification);
    
    state = state.copyWith(
      latestNotification: notification,
    );
    
    _refreshState();
    return notificationId;
  }
  
  /// 更新现有通知（特别是进度通知）
  Future<void> updateNotification({
    required String notificationId,
    String? title,
    String? message,
    AppNotificationType? type,
    int? progress,
    bool? isProgressing,
  }) async {
    // 查找现有通知
    final existingIndex = state.notifications.indexWhere((n) => n.id == notificationId);
    if (existingIndex == -1) return;
    
    final existing = state.notifications[existingIndex];
    final updated = existing.copyWith(
      title: title,
      message: message,
      type: type,
      progress: progress,
      isProgressing: isProgressing,
    );
    
    await DatabaseService.addNotification(updated);
    
    // 更新最新通知
    state = state.copyWith(
      latestNotification: updated,
    );
    
    _refreshState();
  }

  Future<void> markAsRead(String notificationId) async {
    await DatabaseService.markAsRead(notificationId);
    _refreshState();
  }

  Future<void> markAllAsRead() async {
    await DatabaseService.markAllAsRead();
    _refreshState();
  }

  Future<void> deleteNotification(String notificationId) async {
    await DatabaseService.deleteNotification(notificationId);
    _refreshState();
  }

  Future<void> clearAllNotifications() async {
    await DatabaseService.clearAllNotifications();
    _refreshState();
  }

  void clearLatestNotification() {
    state = state.copyWith(latestNotification: null);
  }
  
  /// 取消任务通知（标记为已取消）
  Future<void> cancelNotification(String notificationId) async {
    final existingIndex = state.notifications.indexWhere((n) => n.id == notificationId);
    if (existingIndex == -1) return;
    
    final existing = state.notifications[existingIndex];
    final updated = existing.copyWith(
      isCancelled: true,
      isProgressing: false,
    );
    
    await DatabaseService.addNotification(updated);
    _refreshState();
  }
  
  /// 检查通知是否被取消
  Future<bool> isNotificationCancelled(String notificationId) async {
    // 从数据库重新获取最新状态
    final notifications = DatabaseService.getAllNotifications();
    final notification = notifications.firstWhere(
      (n) => n.id == notificationId,
      orElse: () => AppNotification(
        id: notificationId,
        title: '',
        message: '',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        isCancelled: false,
      ),
    );
    return notification.isCancelled;
  }
}

final notificationProvider = NotifierProvider<NotificationNotifier, NotificationState>(() {
  return NotificationNotifier();
});
