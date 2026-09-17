import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/notification_service.dart';

// Trang danh sách thông báo — StatefulWidget với TabBar lọc theo nguồn.
// Thông báo nhóm theo ngày: Hôm nay / Hôm qua / Tuần này / Cũ hơn.
class NotificationListPage extends StatefulWidget {
  const NotificationListPage({super.key});

  @override
  State<NotificationListPage> createState() => _NotificationListPageState();
}

class _NotificationListPageState extends State<NotificationListPage>
    with SingleTickerProviderStateMixin {
  late final Stream<List<AppNotification>> _stream;
  late final TabController _tabController;
  bool _isMarkingAll = false;

  // Tab config: source == null nghĩa là "Tất cả"
  static const _tabDefs = [
    (label: 'Tất cả', source: null as String?),
    (label: 'Manga', source: 'manga'),
    (label: 'Diễn đàn', source: 'forum'),
    (label: 'Hệ thống', source: 'system'),
  ];

  @override
  void initState() {
    super.initState();
    _stream = NotificationService.instance.streamUserNotifications();
    _tabController = TabController(length: _tabDefs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _markAllAsRead(List<AppNotification> notifications) async {
    if (_isMarkingAll) return;
    setState(() => _isMarkingAll = true);
    try {
      await NotificationService.instance.markAllNotificationsAsRead(notifications);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã đánh dấu tất cả là đã đọc'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể đánh dấu tất cả: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
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
        backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Dọn dẹp thông báo?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(ctx).colorScheme.onSurface,
          ),
        ),
        content: Text(
          'Bạn có muốn xóa ${readNotes.length} thông báo đã đọc khỏi hòm thư?',
          style: TextStyle(
            color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.75),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Xóa', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await NotificationService.instance.clearReadNotifications(notifications);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã dọn dẹp ${readNotes.length} thông báo đã đọc'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi dọn dẹp thông báo: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Trả về nhãn nhóm ngày để tạo section headers trong danh sách.
  String _dateGroup(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(date).inDays;
    if (diff == 0) return 'Hôm nay';
    if (diff == 1) return 'Hôm qua';
    if (diff <= 7) return 'Tuần này';
    return 'Cũ hơn';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<List<AppNotification>>(
      stream: _stream,
      initialData: const [],
      builder: (context, snapshot) {
        final allNotifications = snapshot.data ?? [];
        final hasRead = allNotifications.any((note) => note.isRead);

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
                  onPressed: () => _clearReadNotifications(allNotifications),
                ),
            ],
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: const EdgeInsets.only(left: 8),
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: Colors.white54,
              indicatorColor: theme.colorScheme.primary,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              tabs: _tabDefs.map((t) {
                final tabNotes = t.source == null
                    ? allNotifications
                    : allNotifications.where((n) => n.source == t.source).toList();
                final unread = tabNotes.where((n) => !n.isRead).length;
                return Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(t.label),
                      if (unread > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$unread',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: _tabDefs.map((tab) {
              final notifications = tab.source == null
                  ? allNotifications
                  : allNotifications.where((n) => n.source == tab.source).toList();

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.notifications_off_outlined,
                            size: 56,
                            color: Colors.redAccent,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Không thể tải thông báo',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              if (notifications.isEmpty) {
                final primary = Theme.of(context).colorScheme.primary;
                final onPrimary = Theme.of(context).colorScheme.onPrimary;
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.notifications_none_rounded,
                            size: 56,
                            color: primary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Hòm thư thông báo trống',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Bạn sẽ nhận được thông báo khi các bộ truyện đang theo dõi có chương mới hoặc có cập nhật quan trọng.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () => context.go('/'),
                          icon: const Icon(Icons.explore_rounded, size: 18),
                          label: const Text(
                            'Khám phá truyện',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: onPrimary,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Xây dựng list kết hợp giữa header ngày và notification items
              final List<dynamic> listItems = [];
              String? currentGroup;
              for (final note in notifications) {
                final group = _dateGroup(note.createdAt);
                if (group != currentGroup) {
                  listItems.add(group);
                  currentGroup = group;
                }
                listItems.add(note);
              }

              final hasUnread = notifications.any((note) => !note.isRead);

              return Column(
                children: [
                  if (hasUnread)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
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
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      itemCount: listItems.length,
                      itemBuilder: (context, index) {
                        final item = listItems[index];

                        // Header ngày
                        if (item is String) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
                            child: Row(
                              children: [
                                Text(
                                  item,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Divider(
                                    color: theme.colorScheme.primary.withValues(alpha: 0.25),
                                    height: 1,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        // Notification item
                        final note = item as AppNotification;
                        final isRead = note.isRead;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Dismissible(
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
                            confirmDismiss: (direction) async {
                              try {
                                await NotificationService.instance.deleteNotification(note);
                                return true;
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Không thể xóa: $e'),
                                      backgroundColor: Colors.redAccent,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                                return false; // Ngăn Dismissible gỡ Widget nếu lỗi
                              }
                            },
                            onDismissed: (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
                                    context.push(route);
                                    return;
                                  }
                                  final targetId = note.targetId;
                                  if (targetId != null && targetId.isNotEmpty) {
                                    if (note.source == 'forum' ||
                                        note.type.contains('forum')) {
                                      context.push('/forum/detail/$targetId');
                                    } else {
                                      context.push('/detail/$targetId');
                                    }
                                  }
                                }
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isRead
                                      ? Colors.transparent
                                      : theme.colorScheme.primary.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isRead
                                        ? theme.dividerColor.withValues(alpha: 0.15)
                                        : theme.colorScheme.primary.withValues(alpha: 0.15),
                                  ),
                                ),
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
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        );
      },
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'Vừa xong';
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
