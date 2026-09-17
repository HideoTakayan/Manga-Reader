import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'services/firebase_forum_repository.dart';
import 'models/forum_comment.dart';
import 'models/forum_post.dart';
import 'widgets/forum_comment_tile.dart';
import 'widgets/forum_post_card.dart';

class CommentNode {
  final ForumComment comment;
  final int depth;

  CommentNode({required this.comment, required this.depth});
}

class ForumPostDetailPage extends StatefulWidget {
  final String postId;

  const ForumPostDetailPage({super.key, required this.postId});

  @override
  State<ForumPostDetailPage> createState() => _ForumPostDetailPageState();
}

class _ForumPostDetailPageState extends State<ForumPostDetailPage> {
  final _repository = FirebaseForumRepository();
  final _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();

  ForumPost? _post;
  List<ForumComment> _comments = [];
  List<CommentNode> _commentTree = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  ForumComment? _replyingTo;
  Stream<DocumentSnapshot>? _userSnapshotStream;

  @override
  void initState() {
    super.initState();
    _initUserStream();
    _loadComments();
  }

  void _initUserStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _userSnapshotStream = FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots();
    } else {
      _userSnapshotStream = const Stream.empty();
    }
  }

  static final Set<String> _viewedPostIdsInSession = {};

  Future<void> _incrementViewCount() async {
    if (_viewedPostIdsInSession.contains(widget.postId)) return;
    _viewedPostIdsInSession.add(widget.postId);
    try {
      await _repository.incrementViewCount(widget.postId);
    } catch (e) {
      // Ignore view count errors quietly
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadComments({bool showLoading = true}) async {
    if (showLoading && _post == null) {
      setState(() => _isLoading = true);
    }
    try {
      final post = await _repository.fetchPost(widget.postId);

      if (post != null) {
        final comments = await _repository.fetchComments(widget.postId);

        // Nếu load lần đầu mới tăng view
        if (_post == null) {
          _incrementViewCount();
        }

        if (!mounted) return;

        setState(() {
          _post = post;
          _comments = comments;
          _commentTree = _buildCommentTree(comments);
          _isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _post = null;
          _comments = [];
          _commentTree = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi tải comment: $e')));
      }
    }
  }

  Future<void> _submitComment() async {
    final body = _commentController.text.trim();
    if (body.isEmpty) return;

    if (body.length > 2000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bình luận không được vượt quá 2000 ký tự'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vui lòng đăng nhập')));
      return;
    }

    setState(() => _isSubmitting = true);

    final authorName = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : 'Người dùng';

    final replyingToComment = _replyingTo;

    // Optimistic UI update: thêm comment vào cây ngay lập tức
    final optimisticComment = ForumComment(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      authorId: user.uid,
      authorName: authorName,
      authorAvatar: user.photoURL ?? '',
      body: body,
      replyToCommentId: replyingToComment?.id,
      replyToAuthorName: replyingToComment?.authorName,
      replyToUserId: replyingToComment?.authorId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final updatedComments = List<ForumComment>.from(_comments)..add(optimisticComment);
    final updatedTree = _buildCommentTree(updatedComments);

    _commentController.clear();
    setState(() {
      _replyingTo = null;
      _comments = updatedComments;
      _commentTree = updatedTree;
      if (_post != null) {
        _post = _post!.copyWith(commentCount: _post!.commentCount + 1);
      }
    });

    try {
      await _repository.createComment(
        postId: widget.postId,
        uid: user.uid,
        authorName: authorName,
        authorAvatar: user.photoURL ?? '',
        body: body,
        replyToCommentId: replyingToComment?.id,
        replyToAuthorName: replyingToComment?.authorName,
        replyToUserId: replyingToComment?.authorId,
      );

      // Đồng bộ ngầm để cập nhật ID thật từ server
      unawaited(_loadComments(showLoading: false));
    } catch (e) {
      // Rollback nếu gửi lỗi
      if (mounted) {
        setState(() {
          _comments.removeWhere((c) => c.id == optimisticComment.id);
          _commentTree = _buildCommentTree(_comments);
          if (_post != null && _post!.commentCount > 0) {
            _post = _post!.copyWith(commentCount: _post!.commentCount - 1);
          }
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  List<CommentNode> _buildCommentTree(List<ForumComment> comments) {
    final Map<String, List<ForumComment>> childrenMap = {};
    final List<ForumComment> roots = [];
    final allIds = comments.map((c) => c.id).toSet();

    for (final c in comments) {
      if (c.replyToCommentId == null || !allIds.contains(c.replyToCommentId)) {
        roots.add(c);
      } else {
        childrenMap.putIfAbsent(c.replyToCommentId!, () => []).add(c);
      }
    }

    final List<CommentNode> result = [];
    void traverse(ForumComment comment, int depth) {
      result.add(CommentNode(comment: comment, depth: depth));
      final children = childrenMap[comment.id] ?? [];
      // Sắp xếp các phản hồi theo thời gian cũ -> mới
      children.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (final child in children) {
        // Giới hạn thụt lề 1 cấp duy nhất (như Facebook) để không bị tràn màn hình
        traverse(child, 1);
      }
    }

    roots.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final root in roots) {
      traverse(root, 0);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết bài viết')),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _post == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.article_outlined,
                              size: 48,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Không tìm thấy bài viết',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Bài viết có thể đã bị tác giả xóa hoặc đã bị ẩn do vi phạm tiêu chuẩn cộng đồng.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () {
                              if (context.canPop()) {
                                context.pop();
                              } else {
                                context.go('/forum');
                              }
                            },
                            icon: const Icon(Icons.forum_outlined, size: 18),
                            label: const Text(
                              'Quay lại Diễn đàn',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => _loadComments(showLoading: false),
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: _commentTree.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return ForumPostCard(
                            post: _post!,
                            onDeleted: () {
                              if (mounted) context.pop(true);
                            },
                            onTap: () {}, // Already in detail page
                          );
                        }
                        final node = _commentTree[index - 1];
                        return Padding(
                          padding: EdgeInsets.only(left: (node.depth.clamp(0, 3)) * 20.0),
                          child: ForumCommentTile(
                            postId: widget.postId,
                            comment: node.comment,
                            onDeleted: () {
                              setState(() {
                                _comments.removeWhere(
                                  (item) => item.id == node.comment.id,
                                );
                                _commentTree = _buildCommentTree(_comments);
                                if (_post != null && _post!.commentCount > 0) {
                                  _post = _post!.copyWith(
                                    commentCount: _post!.commentCount - 1,
                                  );
                                }
                              });
                              unawaited(_loadComments(showLoading: false));
                            },
                            onReply: (comment) {
                              setState(() {
                                _replyingTo = comment;
                              });
                              _commentFocusNode.requestFocus();
                            },
                          ),
                        );
                      },
                    ),
                  ),
          ),

          // Sticky Comment Input Bar (chỉ hiện khi bài viết tồn tại)
          if (_post != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                ),
              ),
            ),
            child: SafeArea(
              child: StreamBuilder<DocumentSnapshot>(
                stream: _userSnapshotStream,
                builder: (context, snapshot) {
                  bool isBanned = false;
                  bool isMuted = false;
                  DateTime? mutedUntil;

                  if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
                    final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
                    if (data['isBanned'] == true) {
                      isBanned = true;
                    }
                    if (data['mutedUntil'] != null) {
                      mutedUntil = (data['mutedUntil'] as Timestamp).toDate();
                      if (mutedUntil.isAfter(DateTime.now())) {
                        isMuted = true;
                      }
                    }
                  }

                  if (isBanned) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        'Bạn đã bị cấm bình luận.',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  if (isMuted) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        'Bạn đang bị cấm ngôn (Tới ${mutedUntil != null ? "${mutedUntil.day}/${mutedUntil.month}" : "Không rõ"}).',
                        style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  return Column(
                    children: [
                      if (_replyingTo != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
                          child: Row(
                            children: [
                              Icon(
                                Icons.reply_rounded,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Đang phản hồi @${_replyingTo!.authorName}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  setState(() => _replyingTo = null);
                                },
                              ),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _commentController,
                              focusNode: _commentFocusNode,
                              textCapitalization: TextCapitalization.sentences,
                              maxLines: null,
                              decoration: const InputDecoration(
                                hintText: 'Viết bình luận...',
                                border: InputBorder.none,
                              ),
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) {
                                if (_commentController.text.trim().isNotEmpty && !_isSubmitting) {
                                  _submitComment();
                                }
                              },
                            ),
                          ),
                          // Bộ đếm ký tự — chỉ hiện khi > 80% giới hạn
                          if (_commentController.text.length > 1600) ...[  
                            Text(
                              '${_commentController.text.length}/2000',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _commentController.text.length > 2000
                                    ? Colors.redAccent
                                    : Colors.orangeAccent,
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          IconButton(
                            icon: _isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send),
                            color: _commentController.text.trim().isEmpty || _isSubmitting
                                ? Colors.grey
                                : Theme.of(context).colorScheme.primary,
                            onPressed: _commentController.text.trim().isEmpty || _isSubmitting
                                ? null
                                : _submitComment,
                          ),
                        ],
                      ),
                    ],
                  );
                }
              ),
            ),
          ),
        ],
      ),
    );
  }
}
