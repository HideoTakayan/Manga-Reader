import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/firebase_forum_repository.dart';
import 'models/forum_comment.dart';
import 'models/forum_post.dart';
import 'widgets/forum_comment_tile.dart';
import 'widgets/forum_post_card.dart';

class ForumPostDetailPage extends StatefulWidget {
  final String postId;

  const ForumPostDetailPage({super.key, required this.postId});

  @override
  State<ForumPostDetailPage> createState() => _ForumPostDetailPageState();
}

class _ForumPostDetailPageState extends State<ForumPostDetailPage> {
  final _repository = FirebaseForumRepository();
  final _commentController = TextEditingController();

  ForumPost? _post;
  List<ForumComment> _comments = [];
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
    _incrementViewCount();
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
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final post = await _repository.fetchPost(widget.postId);
      final comments = await _repository.fetchComments(widget.postId);

      if (!mounted) return;

      setState(() {
        _post = post;
        _comments = comments;
        _isLoading = false;
      });
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
      );

      _commentController.clear();
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
                ? const Center(child: Text('Không tìm thấy bài viết'))
                : ListView.builder(
                    itemCount: _comments.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return ForumPostCard(
                          post: _post!,
                          onTap: () {}, // Already in detail page
                        );
                      }
                      return ForumCommentTile(
                        postId: widget.postId,
                        comment: _comments[index - 1],
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
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
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
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    color: Theme.of(context).colorScheme.primary,
                    onPressed:
                        _isSubmitting || _commentController.text.trim().isEmpty
                        ? null
                        : _submitComment,
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
