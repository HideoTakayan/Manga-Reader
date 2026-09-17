import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:cached_network_image/cached_network_image.dart';
import '../models/forum_message.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../config/admin_config.dart';
import '../../../widgets/vip_leaderboard_flair.dart';
import '../services/leaderboard_service.dart';

class ChatMessageBubble extends StatelessWidget {
  final ForumMessage message;
  final VoidCallback? onDelete;
  final void Function(Duration)? onMute;
  final VoidCallback? onUnmute;
  final VoidCallback? onReport;
  final VoidCallback? onReply;
  final VoidCallback? onMention;
  final void Function(String emoji)? onReact;
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
    this.onMention,
    this.onReact,
    this.isFirstInSequence = true,
    this.isLastInSequence = true,
  });

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isMe = message.authorId == currentUserId;
    final currentUserIsAdmin = AdminConfig.isAdmin(FirebaseAuth.instance.currentUser?.email);
    final authorRank = LeaderboardService.instance.getCachedRank(message.authorId);

    return GestureDetector(
      onLongPress: !message.isDeleted ? () => _showOptionsMenu(context, currentUserIsAdmin, isMe, currentUserId) : null,
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
              width: 34,
              child: isLastInSequence
                  ? VipAvatarFrame(
                      rank: authorRank,
                      radius: 16,
                      child: CircleAvatar(
                        radius: 16,
                        backgroundImage: message.authorAvatar.isNotEmpty
                            ? CachedNetworkImageProvider(message.authorAvatar)
                            : null,
                        child: message.authorAvatar.isEmpty
                            ? const Icon(Icons.person, size: 20)
                            : null,
                      ),
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
                if ((!isMe && isFirstInSequence) || message.authorIsAdmin || (authorRank > 0 && authorRank <= 10))
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
                          Flexible(
                            child: Text(
                              message.authorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (authorRank > 0 && authorRank <= 10) ...[
                          const SizedBox(width: 4),
                          VipRankBadge(rank: authorRank, fontSize: 8.5),
                        ],
                        if (message.authorIsAdmin)
                          Container(
                            margin: const EdgeInsets.only(left: 4),
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
                            Flexible(
                              child: Text(
                                isMe
                                    ? 'Bạn đã trả lời ${message.replyToAuthorName ?? 'ai đó'}'
                                    : '${message.authorName} đã trả lời ${message.replyToAuthorName ?? 'ai đó'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context).textTheme.bodySmall?.color,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isMe 
                                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.4) 
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
                    color: authorRank == 1
                        ? (isMe ? const Color(0xFF5D4037) : const Color(0xFF2C2216))
                        : authorRank == 2
                            ? (isMe ? const Color(0xFF37474F) : const Color(0xFF21282D))
                            : authorRank == 3
                                ? (isMe ? const Color(0xFF4E2618) : const Color(0xFF2B1C17))
                                : (isMe
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).cardColor),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(message.replyToMessageId != null && !isMe ? 4 : (isMe || isFirstInSequence ? 18 : 4)),
                      topRight: Radius.circular(message.replyToMessageId != null && isMe ? 4 : (!isMe || isFirstInSequence ? 18 : 4)),
                      bottomLeft: Radius.circular(isMe || isLastInSequence ? 18 : 4),
                      bottomRight: Radius.circular(!isMe || isLastInSequence ? 18 : 4),
                    ),
                    border: authorRank == 1
                        ? Border.all(color: const Color(0xFFFFD700), width: 1.4)
                        : authorRank == 2
                            ? Border.all(color: const Color(0xFFCFD8DC), width: 1.2)
                            : authorRank == 3
                                ? Border.all(color: const Color(0xFFFF8A65), width: 1.2)
                                : (isMe
                                    ? null
                                    : Border.all(
                                        color: Theme.of(
                                          context,
                                        ).dividerColor.withValues(alpha: 0.1),
                                      )),
                    boxShadow: authorRank == 1
                        ? [
                            BoxShadow(
                              color: Colors.amber.withValues(alpha: 0.25),
                              blurRadius: 8,
                              spreadRadius: 0.5,
                            ),
                          ]
                        : (authorRank > 1 && authorRank <= 3
                            ? [
                                BoxShadow(
                                  color: (authorRank == 2 ? Colors.blueGrey : Colors.deepOrange).withValues(alpha: 0.2),
                                  blurRadius: 6,
                                ),
                              ]
                            : null),
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
                            child: _isGifUrl(message.imageUrl!)
                                // GIF từ máy: dùng Image.network để giữ animation
                                ? Image.network(
                                    message.imageUrl!,
                                    width: 200,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                    loadingBuilder: (context, child, progress) {
                                      if (progress == null) return child;
                                      return Container(
                                        height: 150,
                                        width: 200,
                                        color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                                        child: const Center(child: CircularProgressIndicator()),
                                      );
                                    },
                                    errorBuilder: (context, error, _) =>
                                        const Icon(Icons.gif, size: 40, color: Colors.grey),
                                  )
                                // Ảnh tĩnh: dùng CachedNetworkImage
                                : CachedNetworkImage(
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
                            child: Image.network(
                              message.gifUrl!,
                              width: 180,
                              fit: BoxFit.contain,
                              gaplessPlayback: true, // Giữ ảnh cũ khi reload
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Container(
                                  height: 120,
                                  width: 180,
                                  color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                                  child: const Center(child: CircularProgressIndicator()),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.gif, size: 40, color: Colors.grey),
                            ),
                          ),
                        ),
                      if (message.body.isNotEmpty || message.isDeleted)
                        _buildMessageText(context, isMe),
                    ],
                  ),
                ),
                // Badges hiển thị reaction
                if (message.reactions.isNotEmpty && !message.isDeleted)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _buildReactionBadges(context, currentUserId),
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
            ),
        ],
      ),
      ),
    );
  }

  Widget _buildReactionBadges(BuildContext context, String? currentUserId) {
    // Gom nhóm reaction theo emoji
    final counts = <String, int>{};
    for (final emoji in message.reactions.values) {
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: counts.entries.map((entry) {
        final emoji = entry.key;
        final count = entry.value;
        final hasMyReaction = currentUserId != null &&
            message.reactions[currentUserId] == emoji;

        return InkWell(
          onTap: () => onReact?.call(emoji),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: hasMyReaction
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasMyReaction
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 12)),
                if (count > 1) ...[
                  const SizedBox(width: 3),
                  Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: hasMyReaction ? Theme.of(context).colorScheme.primary : Colors.white70,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMessageText(BuildContext context, bool isMe) {
    if (message.isDeleted) {
      return Text(
        'Tin nhắn đã bị xóa',
        style: TextStyle(
          color: isMe
              ? Colors.white.withValues(alpha: 0.7)
              : Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
          fontStyle: FontStyle.italic,
        ),
      );
    }

    final defaultStyle = TextStyle(
      color: isMe
          ? Colors.white
          : Theme.of(context).textTheme.bodyMedium?.color,
      fontSize: 14,
      height: 1.3,
    );

    final mentionStyle = TextStyle(
      color: isMe ? const Color(0xFFFFE082) : const Color(0xFF00B0FF),
      fontWeight: FontWeight.bold,
      fontSize: 14,
      height: 1.3,
    );

    final text = message.body;
    final regex = RegExp(r'(@[^\s@]+)');
    final matches = regex.allMatches(text);

    if (matches.isEmpty) {
      return Text(
        text,
        style: defaultStyle,
      );
    }

    final spans = <TextSpan>[];
    int lastIndex = 0;

    for (final match in matches) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: text.substring(lastIndex, match.start),
          style: defaultStyle,
        ));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: mentionStyle,
      ));
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastIndex),
        style: defaultStyle,
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }

  void _showOptionsMenu(BuildContext context, bool isAdmin, bool isMe, String? currentUserId) {
    const quickEmojis = ['❤️', '👍', '😂', '🔥', '😮', '😢', '🎉'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Thanh thả cảm xúc nhanh (Quick reaction bar)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).cardColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Theme.of(ctx).dividerColor.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: quickEmojis.map((emoji) {
                    final isSelected = currentUserId != null &&
                        message.reactions[currentUserId] == emoji;

                    return InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        HapticFeedback.lightImpact();
                        onReact?.call(emoji);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: isSelected
                            ? BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
                                shape: BoxShape.circle,
                              )
                            : null,
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: Text(message.body.isNotEmpty ? 'Sao chép nội dung' : 'Sao chép link ảnh/GIF'),
                onTap: () {
                  Navigator.pop(ctx);
                  final textToCopy = message.body.isNotEmpty
                      ? message.body
                      : (message.imageUrl ?? message.gifUrl ?? '');
                  if (textToCopy.isNotEmpty) {
                    Clipboard.setData(ClipboardData(text: textToCopy));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(message.body.isNotEmpty
                              ? 'Đã sao chép tin nhắn'
                              : 'Đã sao chép đường dẫn hình ảnh'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Trả lời tin nhắn này'),
                onTap: () {
                  Navigator.pop(ctx);
                  onReply?.call();
                },
              ),
              if (!isMe)
                ListTile(
                  leading: const Icon(Icons.alternate_email, color: Colors.blueAccent),
                  title: Text('Nhắc tên @${message.authorName}'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onMention?.call();
                  },
                ),
              if (!isMe)
                ListTile(
                  leading: const Icon(Icons.report, color: Colors.orange),
                  title: const Text('Báo cáo vi phạm'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onReport?.call();
                  },
                ),
              if (isAdmin || isMe) ...[
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Xóa tin nhắn này', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(ctx);
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
                    Navigator.pop(ctx);
                    onMute?.call(const Duration(minutes: 10));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.timer_off),
                  title: const Text('Cấm ngôn 1 giờ'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onMute?.call(const Duration(hours: 1));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.timer_off),
                  title: const Text('Cấm ngôn 24 giờ'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onMute?.call(const Duration(hours: 24));
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.volume_up),
                  title: const Text('Gỡ cấm ngôn'),
                  onTap: () {
                    Navigator.pop(ctx);
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

  /// Kiểm tra URL có phải là GIF không (theo extension)
  static bool _isGifUrl(String url) {
    final lower = url.toLowerCase().split('?').first; // Bỏ query params
    return lower.endsWith('.gif');
  }
}
