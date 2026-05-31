import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:cached_network_image/cached_network_image.dart';
import '../models/forum_message.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../config/admin_config.dart';

class ChatMessageBubble extends StatelessWidget {
  final ForumMessage message;
  final VoidCallback? onDelete;
  final void Function(Duration)? onMute;
  final VoidCallback? onUnmute;

  const ChatMessageBubble({
    super.key,
    required this.message,
    this.onDelete,
    this.onMute,
    this.onUnmute,
  });

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isMe = message.authorId == currentUserId;
    final currentUserIsAdmin = AdminConfig.isAdmin(FirebaseAuth.instance.currentUser?.email);

    return GestureDetector(
      onLongPress: currentUserIsAdmin && !isMe ? () => _showModerationMenu(context) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundImage: message.authorAvatar.isNotEmpty
                  ? NetworkImage(message.authorAvatar)
                  : null,
              child: message.authorAvatar.isEmpty
                  ? const Icon(Icons.person, size: 20)
                  : null,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isMe || message.authorIsAdmin)
                  Padding(
                    padding: EdgeInsets.only(
                      left: isMe ? 0 : 4,
                      right: isMe ? 4 : 0,
                      bottom: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isMe)
                          Text(
                            message.authorName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        if (message.authorIsAdmin)
                          Container(
                            margin: EdgeInsets.only(left: isMe ? 0 : 4),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.verified_user, size: 10, color: Colors.black),
                                SizedBox(width: 2),
                                Text('ADMIN', style: TextStyle(fontSize: 8, color: Colors.black, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isMe
                        ? Theme.of(context).primaryColor
                        : Theme.of(context).cardColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                    border: isMe
                        ? null
                        : Border.all(
                            color: Theme.of(
                              context,
                            ).dividerColor.withValues(alpha: 0.1),
                          ),
                  ),
                  child: Column(
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (message.gifUrl != null && !message.isDeleted)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: message.body.isNotEmpty ? 8.0 : 0,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: message.gifUrl!,
                              width: 150,
                              fit: BoxFit.contain,
                              placeholder: (context, url) => Container(
                                height: 100,
                                width: 150,
                                color: Theme.of(
                                  context,
                                ).dividerColor.withValues(alpha: 0.1),
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                              errorWidget: (context, url, error) =>
                                  const Icon(Icons.error),
                            ),
                          ),
                        ),
                      if (message.body.isNotEmpty || message.isDeleted)
                        Text(
                          message.isDeleted
                              ? 'Tin nhắn đã bị xóa'
                              : message.body,
                          style: TextStyle(
                            color: isMe
                                ? Colors.white
                                : Theme.of(context).textTheme.bodyMedium?.color,
                            fontStyle: message.isDeleted
                                ? FontStyle.italic
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 4, left: 4),
                  child: Text(
                    timeago.format(message.createdAt, locale: 'vi'),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
          if (isMe)
            const SizedBox(
              width: 24,
            ), // Placeholder for avatar if we want to show it for 'me' too, but usually we don't.
        ],
      ),
      ),
    );
  }

  void _showModerationMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Xóa tin nhắn này', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  onDelete?.call();
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.timer_off),
                title: const Text('Cấm ngôn 10 phút'),
                onTap: () {
                  Navigator.pop(context);
                  onMute?.call(const Duration(minutes: 10));
                },
              ),
              ListTile(
                leading: const Icon(Icons.timer_off),
                title: const Text('Cấm ngôn 1 giờ'),
                onTap: () {
                  Navigator.pop(context);
                  onMute?.call(const Duration(hours: 1));
                },
              ),
              ListTile(
                leading: const Icon(Icons.timer_off),
                title: const Text('Cấm ngôn 24 giờ'),
                onTap: () {
                  Navigator.pop(context);
                  onMute?.call(const Duration(hours: 24));
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.volume_up),
                title: const Text('Gỡ cấm ngôn'),
                onTap: () {
                  Navigator.pop(context);
                  onUnmute?.call();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
