import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/notification_service.dart';

// Trang danh sách thông báo — StatelessWidget vì toàn bộ state đến từ Stream Firestore.
// Thông báo do Admin ghi vào Firestore khi có chapter mới, hiển thị cho tất cả user.
class NotificationListPage extends StatefulWidget {
  const NotificationListPage({super.key});

  @override
  State<NotificationListPage> createState() => _NotificationListPageState();
}

class _NotificationListPageState extends State<NotificationListPage> {
  late final Stream<List<AppNotification>> _stream;
  bool _isMarkingAll = false;

  @override
  void initState() {
    super.initState();
    _stream = NotificationService.instance.streamUserNotifications();
  }

  Future<void> _markAllAsRead(List<AppNotification> notifications) async {
    if (_isMarkingAll) return;

    setState(() => _isMarkingAll = true);
    try {
      await NotificationService.instance.markAllNotificationsAsRead(
        notifications,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã đánh dấu tất cả là đã đọc')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể đánh dấu tất cả: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isMarkingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Thông báo'),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: _stream,
        initialData: const [],
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Lỗi tải thông báo:\n${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final notifications = snapshot.data ?? [];
          final hasUnread = notifications.any((note) => !note.isRead);
          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_off_outlined,
                    size: 64,
                    color: theme.disabledColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Chưa có thông báo nào',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.disabledColor,
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              if (hasUnread)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _isMarkingAll
                          ? null
                          : () => _markAllAsRead(notifications),
                      icon: _isMarkingAll
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.done_all),
                      label: const Text('Đánh dấu tất cả đã đọc'),
                    ),
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: notifications.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 24),
                  itemBuilder: (context, index) {
                    final note = notifications[index];
                    final isRead = note.isRead;

                    return InkWell(
                      onTap: () async {
                        if (!isRead) {
                          await NotificationService.instance
                              .markNotificationAsRead(note);
                        }
                        if (context.mounted) {
                          final route = note.route;
                          if (route != null && route.isNotEmpty) {
                            context.go(route);
                            return;
                          }
                        }
                      },
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 4, right: 12),
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _iconFor(note.source),
                              size: 17,
                              color: isRead
                                  ? theme.disabledColor
                                  : theme.colorScheme.primary,
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  note.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: isRead
                                        ? FontWeight.normal
                                        : FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  note.body,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: isRead
                                        ? theme.disabledColor
                                        : theme.textTheme.bodyMedium?.color,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Text(
                                      _formatTimestamp(note.createdAt),
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    Text(
                                      ' · ${_labelFor(note.source)}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    if (!isRead) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration: const BoxDecoration(
                                          color: Colors.redAccent,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  IconData _iconFor(String source) {
    return switch (source) {
      'manga' => Icons.menu_book_outlined,
      'forum' => Icons.forum_outlined,
      'system' => Icons.notifications_outlined,
      'download' => Icons.download_outlined,
      _ => Icons.notifications_outlined,
    };
  }

  String _labelFor(String source) {
    return switch (source) {
      'manga' => 'Truyện',
      'forum' => 'Diễn đàn',
      'system' => 'Hệ thống',
      'download' => 'Tải xuống',
      _ => 'Thông báo',
    };
  }
}
