import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/forum_post.dart';
import '../services/firebase_forum_repository.dart';
import '../../../config/admin_config.dart';
import 'shared_manga_card.dart';
import 'report_dialog.dart';

class ForumPostCard extends StatelessWidget {
  final ForumPost post;
  final VoidCallback onTap;
  final VoidCallback? onDeleted;

  const ForumPostCard({
    super.key,
    required this.post,
    required this.onTap,
    this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      color: Theme.of(context).cardColor.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Avatar, Name, Time
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: post.authorAvatar.isNotEmpty
                        ? CachedNetworkImageProvider(post.authorAvatar)
                        : null,
                    child: post.authorAvatar.isEmpty
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.authorName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          timeago.format(post.createdAt, locale: 'vi'),
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodySmall?.color,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onPressed: () => _showOptions(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Body text
              if (post.body.isNotEmpty) ...[
                Text(
                  post.body,
                  style: const TextStyle(fontSize: 15),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
              ],

              // Image or GIF
              if (post.imageUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: post.imageUrl!,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      height: 200,
                      color: Theme.of(
                        context,
                      ).dividerColor.withValues(alpha: 0.1),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (context, url, error) =>
                        const Icon(Icons.error),
                  ),
                ),
                const SizedBox(height: 12),
              ] else if (post.gifUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: post.gifUrl!,
                    width: double.infinity,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => Container(
                      height: 200,
                      color: Theme.of(
                        context,
                      ).dividerColor.withValues(alpha: 0.1),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (context, url, error) =>
                        const Icon(Icons.error),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Shared Manga Card
              if (post.sharedMangaId != null) ...[
                SharedMangaCard(
                  mangaId: post.sharedMangaId!,
                  title: post.sharedMangaTitle ?? 'Truyện không tên',
                  coverUrl: post.sharedMangaCoverUrl ?? '',
                  author: post.sharedMangaAuthor,
                  onTap: () {
                    context.push('/detail/${post.sharedMangaId}');
                  },
                ),
                const SizedBox(height: 12),
              ],

              // Actions: Like, Comment, View
              Row(
                children: [
                  _buildLikeButton(context),
                  const SizedBox(width: 16),
                  _buildAction(
                    context,
                    Icons.comment_outlined,
                    post.commentCount.toString(),
                    color: _inactiveActionColor(context),
                  ),
                  const Spacer(),
                  _buildAction(
                    context,
                    Icons.remove_red_eye_outlined,
                    post.viewCount.toString(),
                    color: _inactiveActionColor(
                      context,
                    ).withValues(alpha: 0.85),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLikeButton(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return _buildAction(
        context,
        Icons.thumb_up_outlined,
        post.likeCount.toString(),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vui lòng đăng nhập để thích')),
          );
        },
      );
    }

    return StreamBuilder<bool>(
      stream: FirebaseForumRepository().hasLikedPost(post.id, uid),
      builder: (context, snapshot) {
        final isLiked = snapshot.data ?? false;
        return _buildAction(
          context,
          isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
          post.likeCount.toString(),
          color: isLiked
              ? const Color(0xFFFF5252)
              : _inactiveActionColor(context),
          onTap: () async {
            try {
              await FirebaseForumRepository().toggleLikePost(post.id, uid);
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
          children: [
            Icon(icon, size: 18, color: color ?? _inactiveActionColor(context)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color ?? _inactiveActionColor(context),
                fontSize: 13,
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

  void _showOptions(BuildContext pageContext) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isOwner = currentUser?.uid == post.authorId;
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
                title: const Text('Báo cáo bài viết'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showDialog(
                    context: pageContext,
                    builder: (_) => ReportDialog(
                      targetType: 'post',
                      targetId: post.id,
                      postId: post.id,
                    ),
                  );
                },
              ),
              if (isOwner || isAdmin)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'Xóa bài viết',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final confirm = await showDialog<bool>(
                      context: pageContext,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Xác nhận xóa'),
                        content: const Text(
                          'Bạn có chắc muốn xóa bài viết này?',
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
                        await FirebaseForumRepository().softDeletePost(post.id);
                        if (pageContext.mounted) {
                          ScaffoldMessenger.of(pageContext).showSnackBar(
                            const SnackBar(content: Text('Đã xóa bài viết')),
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
}
