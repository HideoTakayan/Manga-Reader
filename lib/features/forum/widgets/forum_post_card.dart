import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/forum_post.dart';
import '../services/firebase_forum_repository.dart';
import '../../../config/admin_config.dart';
import '../../../widgets/level_badge.dart';
import '../../../widgets/vip_leaderboard_flair.dart';
import '../services/leaderboard_service.dart';
import 'shared_manga_card.dart';
import 'report_dialog.dart';
import 'forum_poll_widget.dart';

class ForumPostCard extends StatefulWidget {
  final ForumPost post;
  final VoidCallback onTap;
  final VoidCallback? onDeleted;
  final ValueChanged<String>? onTagTap;

  const ForumPostCard({
    super.key,
    required this.post,
    required this.onTap,
    this.onDeleted,
    this.onTagTap,
  });

  @override
  State<ForumPostCard> createState() => _ForumPostCardState();
}

class _ForumPostCardState extends State<ForumPostCard> {
  ForumPost get post => widget.post;
  VoidCallback get onTap => widget.onTap;
  VoidCallback? get onDeleted => widget.onDeleted;

  late int _likeCount;
  Stream<bool>? _likeStream;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.post.likeCount;
    _initLikeStream();
  }

  void _initLikeStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _likeStream = FirebaseForumRepository().hasLikedPost(widget.post.id, uid);
    } else {
      _likeStream = null;
    }
  }

  @override
  void didUpdateWidget(covariant ForumPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.likeCount != widget.post.likeCount) {
      _likeCount = widget.post.likeCount;
    }
    if (oldWidget.post.id != widget.post.id) {
      _initLikeStream();
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final authorRank = LeaderboardService.instance.getCachedRank(post.authorId);

    return Column(
      children: [
        // Thick divider between posts like Facebook
        Container(
          height: 8,
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: authorRank == 1
                ? Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 1.2)
                : authorRank == 2
                    ? Border.all(color: Colors.blueGrey.withValues(alpha: 0.4), width: 1.2)
                    : authorRank == 3
                        ? Border.all(color: Colors.deepOrange.withValues(alpha: 0.4), width: 1.2)
                        : null,
            boxShadow: authorRank == 1
                ? [
                    BoxShadow(
                      color: Colors.amber.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: InkWell(
            onTap: widget.onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pinned Post Ribbon
                if (post.isPinned)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.amber.shade900.withValues(alpha: 0.6),
                          Colors.orangeAccent.withValues(alpha: 0.3),
                        ],
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.push_pin_rounded, size: 13, color: Colors.amberAccent),
                        SizedBox(width: 6),
                        Text(
                          'Bài viết được Ghim nổi bật',
                          style: TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Top 10 VIP Ribbon
                if (authorRank > 0 && authorRank <= 10)
                  VipPostRibbon(rank: authorRank),

                // Header: Avatar, Name, Time
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      VipAvatarFrame(
                        rank: authorRank,
                        radius: 20,
                        child: CircleAvatar(
                          radius: 20,
                          backgroundImage: post.authorAvatar.isNotEmpty
                              ? CachedNetworkImageProvider(post.authorAvatar)
                              : null,
                          child: post.authorAvatar.isEmpty
                              ? const Icon(Icons.person)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    post.authorName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                LevelBadge(level: post.authorLevel, fontSize: 10),
                                if (authorRank > 0 && authorRank <= 10) ...[
                                  const SizedBox(width: 6),
                                  VipRankBadge(rank: authorRank, fontSize: 8.5),
                                ],
                              ],
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
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const style = TextStyle(fontSize: 15, height: 1.3);
                        final textPainter = TextPainter(
                          text: TextSpan(text: post.body, style: style),
                          maxLines: 5,
                          textDirection: TextDirection.ltr,
                        )..layout(maxWidth: constraints.maxWidth);
                        final isOverflowing = textPainter.didExceedMaxLines;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              post.body,
                              style: style,
                              maxLines: 5,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (isOverflowing)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'Xem thêm',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                if (post.body.isNotEmpty) const SizedBox(height: 12),

                // Interactive Poll
                if (post.poll != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ForumPollWidget(
                      postId: post.id,
                      poll: post.poll!,
                    ),
                  ),

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

                // Hashtags Chip Wrap (#skibidi, #review, #anime, etc.)
                if (post.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: post.tags.map((tag) {
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            widget.onTagTap?.call(tag);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              '#$tag',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
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
                      Flexible(
                        child: Text(
                          '${post.commentCount} bình luận • ${post.viewCount} lượt xem',
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodySmall?.color,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                          onTap: onTap,
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
      stream: _likeStream,
      builder: (context, snapshot) {
        final isLiked = snapshot.data ?? false;
        return _buildAction(
          context,
          isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
          _likeCount.toString(),
          color: isLiked
              ? const Color(0xFF1877F2)
              : _inactiveActionColor(context),
          onTap: () async {
            HapticFeedback.selectionClick();
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
      onTap: onTap != null
          ? () {
              HapticFeedback.selectionClick();
              onTap();
            }
          : null,
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
                    color: Theme.of(sheetContext).colorScheme.onSurface.withValues(alpha: 0.2),
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
                  Clipboard.setData(ClipboardData(text: post.body));
                  ScaffoldMessenger.of(pageContext).showSnackBar(
                    const SnackBar(
                      content: Text('Đã sao chép nội dung bài viết'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
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
                        backgroundColor: Theme.of(dialogContext).dialogTheme.backgroundColor ?? Theme.of(dialogContext).cardColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        title: Text(
                          'Xác nhận xóa',
                          style: TextStyle(
                            color: Theme.of(dialogContext).colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        content: Text(
                          'Bạn có chắc muốn xóa bài viết này?',
                          style: TextStyle(
                            color: Theme.of(dialogContext).colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
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
