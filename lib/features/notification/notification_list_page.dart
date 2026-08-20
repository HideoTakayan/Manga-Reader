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

  Future<void> _clearReadNotifications(List<AppNotification> notifications) async {
    final readNotes = notifications.where((n) => n.isRead).toList();
    if (readNotes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có thông báo đã đọc nào để xóa')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: const Text('Dọn dẹp thông báo?'),
        content: Text('Bạn có muốn xóa ${readNotes.length} thông báo đã đọc khỏi hòm thư?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await NotificationService.instance.clearReadNotifications(notifications);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã dọn dẹp ${readNotes.length} thông báo đã đọc')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi dọn dẹp thông báo: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<List<AppNotification>>(
      stream: _stream,
      initialData: const [],
      builder: (context, snapshot) {
        final notifications = snapshot.data ?? [];
        final hasRead = notifications.any((note) => note.isRead);

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            title: const Text('Thông báo'),
            backgroundColor: theme.scaffoldBackgroundColor,
            elevation: 0,
            actions: [
              if (hasRead)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white70),
                  tooltip: 'Xóa thông báo đã đọc',
                  onPressed: () => _clearReadNotifications(notifications),
                ),
            ],
          ),
          body: () {
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

                      return Dismissible(
                        key: ValueKey(note.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Xóa',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              SizedBox(width: 6),
                              Icon(Icons.delete_outline, color: Colors.white, size: 20),
                            ],
                          ),
                        ),
                        onDismissed: (_) async {
                          await NotificationService.instance.deleteNotification(note);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Đã xóa thông báo'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        child: InkWell(
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
                                          '${_formatTimestamp(note.createdAt)} • ${_labelFor(note.source)}',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.disabledColor,
                                          ),
                                        ),
                                        if (!isRead) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.primary,
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
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          }(),
        );
      },
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
