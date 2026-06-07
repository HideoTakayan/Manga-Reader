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
  final VoidCallback? onReport;
  final VoidCallback? onReply;
  final bool isFirstInSequence;
  final bool isLastInSequence;

  const ChatMessageBubble({
    super.key,
    required this.message,
    this.onDelete,
    this.onMute,
    this.onUnmute,
    this.onReport,
    this.onReply,
    this.isFirstInSequence = true,
    this.isLastInSequence = true,
  });

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isMe = message.authorId == currentUserId;
    final currentUserIsAdmin = AdminConfig.isAdmin(FirebaseAuth.instance.currentUser?.email);

    return GestureDetector(
      onLongPress: !message.isDeleted ? () => _showOptionsMenu(context, currentUserIsAdmin, isMe) : null,
      child: Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          top: isFirstInSequence ? 12 : 2,
          bottom: isLastInSequence ? 12 : 2,
        ),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            SizedBox(
              width: 32,
              child: isLastInSequence
                  ? CircleAvatar(
                      radius: 16,
                      backgroundImage: message.authorAvatar.isNotEmpty
                          ? NetworkImage(message.authorAvatar)
                          : null,
                      child: message.authorAvatar.isEmpty
                          ? const Icon(Icons.person, size: 20)
                          : null,
                    )
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
                if ((!isMe && isFirstInSequence) || message.authorIsAdmin)
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
                if (message.replyToMessageId != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Column(
                      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.reply, size: 12, color: Theme.of(context).textTheme.bodySmall?.color),
                            const SizedBox(width: 4),
                            Text(
                              isMe
                                  ? 'Bạn đã trả lời ${message.replyToAuthorName ?? 'ai đó'}'
                                  : '${message.authorName} đã trả lời ${message.replyToAuthorName ?? 'ai đó'}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(context).textTheme.bodySmall?.color,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isMe 
                                ? Theme.of(context).primaryColor.withValues(alpha: 0.4) 
                                : Theme.of(context).dividerColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          constraints: const BoxConstraints(maxWidth: 200),
                          child: Text(
                            message.replyToBody ?? 'Hình ảnh/GIF',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isMe 
                                  ? Colors.white.withValues(alpha: 0.8) 
                                  : Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
                            ),
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
                      topLeft: Radius.circular(message.replyToMessageId != null && !isMe ? 4 : (isMe || isFirstInSequence ? 18 : 4)),
                      topRight: Radius.circular(message.replyToMessageId != null && isMe ? 4 : (!isMe || isFirstInSequence ? 18 : 4)),
                      bottomLeft: Radius.circular(isMe || isLastInSequence ? 18 : 4),
                      bottomRight: Radius.circular(!isMe || isLastInSequence ? 18 : 4),
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
                      if (message.imageUrl != null && !message.isDeleted)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: (message.body.isNotEmpty || message.gifUrl != null) ? 8.0 : 0,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: message.imageUrl!,
                              width: 200,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                height: 150,
                                width: 200,
                                color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                              errorWidget: (context, url, error) =>
                                  const Icon(Icons.error),
                            ),
                          ),
                        ),
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
                if (isLastInSequence)
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

  void _showOptionsMenu(BuildContext context, bool isAdmin, bool isMe) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Trả lời tin nhắn này'),
                onTap: () {
                  Navigator.pop(context);
                  onReply?.call();
                },
              ),
              if (!isMe)
                ListTile(
                  leading: const Icon(Icons.report, color: Colors.orange),
                  title: const Text('Báo cáo vi phạm'),
                  onTap: () {
                    Navigator.pop(context);
                    onReport?.call();
                  },
                ),
              if (isAdmin || isMe) ...[
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Xóa tin nhắn này', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    onDelete?.call();
                  },
                ),
              ],
              if (isAdmin && !isMe) ...[
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
            ],
          ),
        );
      },
    );
  }
}
