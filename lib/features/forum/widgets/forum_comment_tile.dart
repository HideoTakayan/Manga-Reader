import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/forum_comment.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firebase_forum_repository.dart';
import '../../../config/admin_config.dart';
import '../../../widgets/level_badge.dart';
import '../../../widgets/vip_leaderboard_flair.dart';
import '../services/leaderboard_service.dart';
import 'report_dialog.dart';

class ForumCommentTile extends StatefulWidget {
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
  State<ForumCommentTile> createState() => _ForumCommentTileState();
}

class _ForumCommentTileState extends State<ForumCommentTile> {
  Stream<bool>? _likeStream;

  @override
  void initState() {
    super.initState();
    _initLikeStream();
  }

  @override
  void didUpdateWidget(covariant ForumCommentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId != widget.postId || oldWidget.comment.id != widget.comment.id) {
      _initLikeStream();
    }
  }

  void _initLikeStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _likeStream = FirebaseForumRepository().hasLikedComment(
        widget.postId,
        widget.comment.id,
        uid,
      );
    } else {
      _likeStream = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final comment = widget.comment;
    final authorRank = LeaderboardService.instance.getCachedRank(comment.authorId);

    return InkWell(
      onLongPress: () => _showOptions(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VipAvatarFrame(
              rank: authorRank,
              radius: 16,
              child: CircleAvatar(
                radius: 16,
                backgroundImage: comment.authorAvatar.isNotEmpty
                    ? CachedNetworkImageProvider(comment.authorAvatar)
                    : null,
                child: comment.authorAvatar.isEmpty
                    ? const Icon(Icons.person, size: 16)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: authorRank == 1
                      ? const Color(0xFF2C2216).withValues(alpha: 0.8)
                      : authorRank == 2
                          ? const Color(0xFF21282D).withValues(alpha: 0.8)
                          : authorRank == 3
                              ? const Color(0xFF2B1C17).withValues(alpha: 0.8)
                              : Theme.of(context).cardColor.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: authorRank == 1
                      ? Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 1.2)
                      : authorRank == 2
                          ? Border.all(color: Colors.blueGrey.withValues(alpha: 0.4), width: 1.1)
                          : authorRank == 3
                              ? Border.all(color: Colors.deepOrange.withValues(alpha: 0.4), width: 1.1)
                              : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              comment.authorName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: comment.authorId == FirebaseAuth.instance.currentUser?.uid
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 6),
                            LevelBadge(level: comment.authorLevel, fontSize: 9.5),
                            if (authorRank > 0 && authorRank <= 10) ...[
                              const SizedBox(width: 6),
                              VipRankBadge(rank: authorRank, fontSize: 8.5),
                            ],
                          ],
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
                            widget.onReply?.call(comment);
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
    final isOwner = currentUser?.uid == widget.comment.authorId;
    final isAdmin = AdminConfig.isAdmin(currentUser?.email);

    showModalBottomSheet(
      context: pageContext,
      backgroundColor: Theme.of(pageContext).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
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
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Sao chép nội dung'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Clipboard.setData(ClipboardData(text: widget.comment.body));
                  ScaffoldMessenger.of(pageContext).hideCurrentSnackBar();
                  ScaffoldMessenger.of(pageContext).showSnackBar(
                    const SnackBar(
                      content: Text('Đã sao chép bình luận'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Báo cáo bình luận'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showDialog(
                    context: pageContext,
                    builder: (_) => ReportDialog(
                      targetType: 'comment',
                      targetId: widget.comment.id,
                      postId: widget.postId,
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
                      builder: (dialogContext) {
                        final onSurface = Theme.of(dialogContext).colorScheme.onSurface;
                        return AlertDialog(
                          backgroundColor: Theme.of(dialogContext).dialogTheme.backgroundColor ?? Theme.of(dialogContext).cardColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          title: Text('Xác nhận xóa', style: TextStyle(color: onSurface, fontWeight: FontWeight.bold)),
                          content: Text(
                            'Bạn có chắc muốn xóa bình luận này?',
                            style: TextStyle(color: onSurface.withValues(alpha: 0.7)),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => Navigator.pop(dialogContext, true),
                              child: const Text('Xóa', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        );
                      },
                    );

                    if (confirm == true && pageContext.mounted) {
                      try {
                        await FirebaseForumRepository().softDeleteComment(
                          widget.postId,
                          widget.comment.id,
                        );
                        if (pageContext.mounted) {
                          ScaffoldMessenger.of(pageContext).hideCurrentSnackBar();
                          ScaffoldMessenger.of(pageContext).showSnackBar(
                            const SnackBar(
                              content: Text('Đã xóa bình luận'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          widget.onDeleted?.call();
                        }
                      } catch (e) {
                        if (pageContext.mounted) {
                          ScaffoldMessenger.of(pageContext).hideCurrentSnackBar();
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
        widget.comment.likeCount.toString(),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vui lòng đăng nhập để thích')),
          );
        },
      );
    }

    return StreamBuilder<bool>(
      stream: _likeStream,
      builder: (context, snapshot) {
        final isLiked = snapshot.data ?? false;
        return _buildAction(
          context,
          isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
          widget.comment.likeCount.toString(),
          color: isLiked
              ? const Color(0xFFFF5252)
              : _inactiveActionColor(context),
          onTap: () async {
            try {
              await FirebaseForumRepository().toggleLikeComment(
                widget.postId,
                widget.comment.id,
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
      onTap: onTap != null
          ? () {
              HapticFeedback.selectionClick();
              onTap();
            }
          : null,
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
