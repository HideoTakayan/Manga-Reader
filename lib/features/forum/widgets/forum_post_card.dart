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

class ForumPostCard extends StatefulWidget {
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
  State<ForumPostCard> createState() => _ForumPostCardState();
}

class _ForumPostCardState extends State<ForumPostCard> {
  late int _likeCount;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.post.likeCount;
  }

  @override
  void didUpdateWidget(ForumPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.post.id != oldWidget.post.id || widget.post.likeCount != oldWidget.post.likeCount) {
      _likeCount = widget.post.likeCount;
    }
  }

  ForumPost get post => widget.post;
  VoidCallback get onTap => widget.onTap;
  VoidCallback? get onDeleted => widget.onDeleted;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Thick divider between posts like Facebook
        Container(
          height: 8,
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        ),
        Container(
          color: Theme.of(context).cardColor,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: Avatar, Name, Time
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
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
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
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
                        icon: const Icon(Icons.more_horiz, size: 20),
                        onPressed: () => _showOptions(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                
                // Body text
                if (post.body.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      post.body,
                      style: const TextStyle(fontSize: 15, height: 1.3),
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (post.body.isNotEmpty) const SizedBox(height: 12),

                // Image or GIF (Full width, no padding, no border radius)
                if (post.imageUrl != null)
                  CachedNetworkImage(
                    imageUrl: post.imageUrl!,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      height: 200,
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (context, url, error) => const Icon(Icons.error),
                  )
                else if (post.gifUrl != null)
                  CachedNetworkImage(
                    imageUrl: post.gifUrl!,
                    width: double.infinity,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => Container(
                      height: 200,
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (context, url, error) => const Icon(Icons.error),
                  ),

                // Shared Manga Card
                if (post.sharedMangaId != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: SharedMangaCard(
                      mangaId: post.sharedMangaId!,
                      title: post.sharedMangaTitle ?? 'Truyện không tên',
                      coverUrl: post.sharedMangaCoverUrl ?? '',
                      author: post.sharedMangaAuthor,
                      onTap: () {
                        context.push('/detail/${post.sharedMangaId}');
                      },
                    ),
                  ),

                // Post Stats (Optional: typically Facebook shows number of likes/comments above the buttons)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFF1877F2), // Facebook Blue
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.thumb_up, size: 10, color: Colors.white),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _likeCount.toString(),
                            style: TextStyle(
                              color: Theme.of(context).textTheme.bodySmall?.color,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${post.commentCount} bình luận • ${post.viewCount} lượt xem',
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),

                // Actions: Like, Comment
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(child: _buildLikeButton(context)),
                      Expanded(
                        child: _buildAction(
                          context,
                          Icons.chat_bubble_outline,
                          'Bình luận',
                          color: _inactiveActionColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLikeButton(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return _buildAction(
        context,
        Icons.thumb_up_outlined,
        _likeCount.toString(),
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
          _likeCount.toString(),
          color: isLiked
              ? const Color(0xFFFF5252)
              : _inactiveActionColor(context),
          onTap: () async {
            setState(() {
              if (isLiked) {
                _likeCount = (_likeCount > 0) ? _likeCount - 1 : 0;
              } else {
                _likeCount++;
              }
            });
            try {
              await FirebaseForumRepository().toggleLikePost(post.id, uid);
            } catch (e) {
              if (context.mounted) {
                setState(() {
                  if (isLiked) {
                    _likeCount++;
                  } else {
                    _likeCount = (_likeCount > 0) ? _likeCount - 1 : 0;
                  }
                });
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
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
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color ?? _inactiveActionColor(context)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color ?? _inactiveActionColor(context),
                fontSize: 14,
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
