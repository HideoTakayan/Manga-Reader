import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/forum_comment.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firebase_forum_repository.dart';
import '../../../config/admin_config.dart';
import 'report_dialog.dart';

class ForumCommentTile extends StatelessWidget {
  final String postId;
  final ForumComment comment;
  final VoidCallback? onDeleted;
  final ValueChanged<ForumComment>? onReply;

  const ForumCommentTile({
    super.key,
    required this.postId,
    required this.comment,
    this.onDeleted,
    this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onLongPress: () => _showOptions(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundImage: comment.authorAvatar.isNotEmpty
                  ? CachedNetworkImageProvider(comment.authorAvatar)
                  : null,
              child: comment.authorAvatar.isEmpty
                  ? const Icon(Icons.person, size: 16)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          comment.authorName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          timeago.format(comment.createdAt, locale: 'vi'),
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodySmall?.color,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (comment.replyToAuthorName != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        child: Text(
                          'Phản hồi @${comment.replyToAuthorName}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.primary,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    Text(comment.body, style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildLikeButton(context),
                        const SizedBox(width: 16),
                        _buildAction(
                          context,
                          Icons.reply_rounded,
                          'Phản hồi',
                          onTap: () {
                            onReply?.call(comment);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showOptions(BuildContext pageContext) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isOwner = currentUser?.uid == comment.authorId;
    final isAdmin = AdminConfig.isAdmin(currentUser?.email);

    showModalBottomSheet(
      context: pageContext,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Báo cáo bình luận'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showDialog(
                    context: pageContext,
                    builder: (_) => ReportDialog(
                      targetType: 'comment',
                      targetId: comment.id,
                      postId: postId,
                    ),
                  );
                },
              ),
              if (isOwner || isAdmin)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'Xóa bình luận',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final confirm = await showDialog<bool>(
                      context: pageContext,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Xác nhận xóa'),
                        content: const Text(
                          'Bạn có chắc muốn xóa bình luận này?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: const Text('Hủy'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: const Text(
                              'Xóa',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true && pageContext.mounted) {
                      try {
                        await FirebaseForumRepository().softDeleteComment(
                          postId,
                          comment.id,
                        );
                        if (pageContext.mounted) {
                          ScaffoldMessenger.of(pageContext).showSnackBar(
                            const SnackBar(content: Text('Đã xóa bình luận')),
                          );
                          onDeleted?.call();
                        }
                      } catch (e) {
                        if (pageContext.mounted) {
                          ScaffoldMessenger.of(
                            pageContext,
                          ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                        }
                      }
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLikeButton(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return _buildAction(
        context,
        Icons.thumb_up_outlined,
        comment.likeCount.toString(),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vui lòng đăng nhập để thích')),
          );
        },
      );
    }

    return StreamBuilder<bool>(
      stream: FirebaseForumRepository().hasLikedComment(
        postId,
        comment.id,
        uid,
      ),
      builder: (context, snapshot) {
        final isLiked = snapshot.data ?? false;
        return _buildAction(
          context,
          isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
          comment.likeCount.toString(),
          color: isLiked
              ? const Color(0xFFFF5252)
              : _inactiveActionColor(context),
          onTap: () async {
            try {
              await FirebaseForumRepository().toggleLikeComment(
                postId,
                comment.id,
                uid,
              );
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
              }
            }
          },
        );
      },
    );
  }

  Widget _buildAction(
    BuildContext context,
    IconData icon,
    String label, {
    Color? color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color ?? _inactiveActionColor(context)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color ?? _inactiveActionColor(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _inactiveActionColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFBDBDBD)
        : const Color(0xFF5F6368);
  }
}
