import 'dart:async';
import 'package:flutter/material.dart';
import '../models/notification.dart';

class ToastNotification extends StatefulWidget {
  final AppNotification notification;
  final VoidCallback onDismissed;
  final Duration duration;

  const ToastNotification({
    super.key,
    required this.notification,
    required this.onDismissed,
    this.duration = const Duration(seconds: 4),
  });

  @override
  State<ToastNotification> createState() => _ToastNotificationState();
}

class _ToastNotificationState extends State<ToastNotification>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward();

    _timer = Timer(widget.duration, () {
      _dismiss();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _dismiss() {
    _timer?.cancel();
    _controller.reverse().then((_) {
      widget.onDismissed();
    });
  }

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
  Widget build(BuildContext context) {
    return Positioned(
      top: 20,
      left: 20,
      right: 20,
      child: SlideTransition(
        position: _offsetAnimation,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _getTypeColor(widget.notification.type),
                width: 2,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _getTypeIcon(widget.notification.type),
                  color: _getTypeColor(widget.notification.type),
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.notification.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.notification.message,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _dismiss,
                  child: Icon(
                    Icons.close,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
