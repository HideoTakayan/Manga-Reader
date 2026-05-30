import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:cached_network_image/cached_network_image.dart';
import '../models/forum_message.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatMessageBubble extends StatelessWidget {
  final ForumMessage message;

  const ChatMessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isMe = message.authorId == currentUserId;

    return Padding(
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
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      message.authorName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
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
    );
  }
}
