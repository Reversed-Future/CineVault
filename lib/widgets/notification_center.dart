import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification.dart';
import '../providers/notification_provider.dart';
import '../providers/unregistered_movies_provider.dart';
import 'unregistered_movies_dialog.dart';

class NotificationCenter extends ConsumerWidget {
  const NotificationCenter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationProvider);
    final notifications = state.notifications;
    final pendingCount = ref.watch(effectiveUnregisteredMoviesProvider).length;

    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          width: 450,
          constraints: const BoxConstraints(maxHeight: 600),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.notifications,
                      color: Theme.of(context).colorScheme.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '通知中心',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    if (state.unreadNotifications.isNotEmpty) ...[
                      TextButton(
                        onPressed: () {
                          ref
                              .read(notificationProvider.notifier)
                              .markAllAsRead();
                        },
                        child: const Text('全部已读'),
                      ),
                      const SizedBox(width: 8),
                    ],
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // 待审核影片快捷入口
              if (pendingCount > 0)
                Material(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  child: InkWell(
                    onTap: () {
                      ref
                          .read(unregisteredMoviesProvider.notifier)
                          .restoreFromLastScan();
                      // 关闭通知中心
                      Navigator.of(context).pop();
                      // 延迟一帧后弹 dialog（使用 root navigator 避免被通知中心遮挡）
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        showDialog(
                          context: context,
                          useRootNavigator: true,
                          builder: (_) => Consumer(
                            builder: (context, ref, _) {
                              return const UnregisteredMoviesDialog
                                  .fromProvider();
                            },
                          ),
                        );
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.movie_filter_outlined,
                            color: Theme.of(context)
                                .colorScheme
                                .onTertiaryContainer,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '有 $pendingCount 个待审核的影片',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onTertiaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '前往审核 →',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onTertiaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const Divider(height: 1),
              if (notifications.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 64,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '暂无通知',
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: notifications.length,
                    itemBuilder: (context, index) {
                      return _NotificationItem(
                        notification: notifications[index],
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationItem extends ConsumerWidget {
  final AppNotification notification;

  const _NotificationItem({
    required this.notification,
  });

  Color _getTypeColor(AppNotificationType type) {
    switch (type) {
      case AppNotificationType.success:
        return Colors.green;
      case AppNotificationType.warning:
        return Colors.orange;
      case AppNotificationType.error:
        return Colors.red;
      case AppNotificationType.info:
      default:
        return Colors.blue;
    }
  }

  IconData _getTypeIcon(AppNotificationType type) {
    switch (type) {
      case AppNotificationType.success:
        return Icons.check_circle;
      case AppNotificationType.warning:
        return Icons.warning;
      case AppNotificationType.error:
        return Icons.error;
      case AppNotificationType.info:
      default:
        return Icons.info;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasProgress = notification.progress != null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: notification.isRead
            ? Colors.transparent
            : Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (!notification.isRead) {
              ref
                  .read(notificationProvider.notifier)
                  .markAsRead(notification.id);
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color:
                        _getTypeColor(notification.type).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getTypeIcon(notification.type),
                    color: _getTypeColor(notification.type),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: TextStyle(
                                fontWeight: notification.isRead
                                    ? FontWeight.normal
                                    : FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (hasProgress)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _getTypeColor(notification.type)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${notification.progress!.clamp(0, 100)}%',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _getTypeColor(notification.type),
                                ),
                              ),
                            ),
                          const SizedBox(width: 8),
                          Text(
                            _formatTime(notification.createdAtDateTime),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notification.message,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (hasProgress)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: ((notification.progress!.clamp(0, 100)) /
                                      100.0)
                                  .clamp(0.0, 1.0),
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _getTypeColor(notification.type),
                              ),
                              minHeight: 6,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 暂停/取消按钮
                if (notification.isProgressing &&
                    notification.taskType == 'batch_update' &&
                    !notification.isCancelled)
                  IconButton(
                    icon: const Icon(Icons.pause, size: 18),
                    onPressed: () {
                      ref
                          .read(notificationProvider.notifier)
                          .cancelNotification(notification.id);
                    },
                    visualDensity: VisualDensity.compact,
                    tooltip: '暂停更新',
                    color: Colors.orange,
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () {
                    ref
                        .read(notificationProvider.notifier)
                        .deleteNotification(notification.id);
                  },
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}天前';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}小时前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }
}
