import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  bool _isLoading = true;
  bool _isSubmitting = false;
  ForumComment? _replyingTo;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _incrementViewCount() async {
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

  Future<void> _loadComments() async {
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
          _isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _post = null;
          _comments = [];
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

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vui lòng đăng nhập')));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _repository.createComment(
        postId: widget.postId,
        uid: user.uid,
        authorName: user.displayName ?? 'Người dùng',
        authorAvatar: user.photoURL ?? '',
        body: body,
        replyToCommentId: _replyingTo?.id,
        replyToAuthorName: _replyingTo?.authorName,
        replyToUserId: _replyingTo?.authorId,
      );

      _commentController.clear();
      setState(() => _replyingTo = null);
      await _loadComments(); // Tải lại danh sách comment
    } catch (e) {
      if (mounted) {
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

  List<CommentNode> _buildCommentTree() {
    final Map<String, List<ForumComment>> childrenMap = {};
    final List<ForumComment> roots = [];
    final allIds = _comments.map((c) => c.id).toSet();

    for (final c in _comments) {
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

    for (final root in roots) {
      traverse(root, 0);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final commentTree = _buildCommentTree();

    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết bài viết')),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _post == null
                ? const Center(child: Text('Không tìm thấy bài viết'))
                  : ListView.builder(
                    itemCount: commentTree.length + 1,
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
                      final node = commentTree[index - 1];
                      return Padding(
                        padding: EdgeInsets.only(left: node.depth * 44.0),
                        child: ForumCommentTile(
                          postId: widget.postId,
                          comment: node.comment,
                          onDeleted: () {
                            setState(
                              () => _comments.removeWhere(
                                (item) => item.id == node.comment.id,
                              ),
                            );
                            unawaited(_loadComments());
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

          // Sticky Comment Input Bar
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
              child: Column(
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
                          decoration: const InputDecoration(
                            hintText: 'Viết bình luận...',
                            border: InputBorder.none,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
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
                        color: const Color(0xFFFF5252),
                        onPressed: _isSubmitting ? null : _submitComment,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
