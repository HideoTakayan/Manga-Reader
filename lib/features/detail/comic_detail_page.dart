import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/mock_catalog.dart';
import '../../data/models.dart';
import '../../services/follow_service.dart';

class ComicDetailPage extends StatefulWidget {
  final String comicId;
  const ComicDetailPage({super.key, required this.comicId});

  @override
  State<ComicDetailPage> createState() => _ComicDetailPageState();
}

class _ComicDetailPageState extends State<ComicDetailPage> {
  bool showAll = false;

  // Thay 'late' bằng khởi tạo rỗng
  List<Comment> comments = [];

  final TextEditingController _commentController = TextEditingController();
  final GlobalKey _commentSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  void _loadComments() {
    setState(() {
      // Copy danh sách comment từ MockCatalog
      comments = List.from(MockCatalog.commentsOf(widget.comicId));
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Comic? comic = MockCatalog.comicById(widget.comicId);
    if (comic == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Không tìm thấy truyện')),
        body: const Center(child: Text('Comic not found')),
      );
    }

    final chapters = List<Chapter>.from(MockCatalog.chaptersOf(comic.id))
      ..sort((a, b) => b.number.compareTo(a.number));

    final followService = FollowService();
    final displayChapters = showAll ? chapters : chapters.take(5).toList();
    final views = MockCatalog.viewsOf(comic.id);

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E10),
      body: CustomScrollView(
        slivers: [
          // === Ảnh bìa ===
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: Colors.black,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                comic.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                      imageUrl: comic.coverUrl, fit: BoxFit.cover),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent.withOpacity(0.9),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                      onPressed: () {
                        if (chapters.isNotEmpty) {
                          context.push('/reader/${chapters.first.id}');
                        }
                      },
                      icon: const Icon(Icons.play_arrow, color: Colors.white),
                      label: const Text(
                        'Đọc ngay',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // === Thông tin truyện ===
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comic.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text('Tác giả: ${comic.author}',
                      style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.visibility,
                          color: Colors.white54, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        '${_formatNumber(views)} lượt xem',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    comic.description,
                    style: const TextStyle(color: Colors.white70, height: 1.4),
                  ),
                  const SizedBox(height: 20),

                  // === Nút theo dõi ===
                  StreamBuilder<bool>(
                    stream: followService.isFollowing(comic.id),
                    builder: (context, snapshot) {
                      final isFollowing = snapshot.data == true;
                      return ElevatedButton.icon(
                        onPressed: () async {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Vui lòng đăng nhập để theo dõi')),
                            );
                            context.push('/login');
                            return;
                          }

                          try {
                            if (isFollowing) {
                              await followService.unfollowComic(comic.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Đã bỏ theo dõi')),
                              );
                            } else {
                              await followService.followComic(
                                comicId: comic.id,
                                title: comic.title,
                                coverUrl: comic.coverUrl,
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Đã theo dõi')),
                              );
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Lỗi: $e')),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white12,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: Icon(
                          isFollowing ? Icons.favorite : Icons.favorite_border,
                          color: isFollowing ? Colors.red : Colors.white70,
                        ),
                        label: Text(
                          isFollowing ? 'Đang theo dõi' : 'Theo dõi',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // === Danh sách chương ===
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Danh sách chương',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                  if (chapters.length > 5)
                    TextButton(
                      onPressed: () => setState(() => showAll = !showAll),
                      child: Text(
                        showAll ? 'Thu gọn' : 'Xem tất cả',
                        style: const TextStyle(color: Colors.lightBlueAccent),
                      ),
                    ),
                ],
              ),
            ),
          ),

          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final ch = displayChapters[index];
                return Card(
                  color: const Color(0xFF1A1A1D),
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: ListTile(
                    title: Text(ch.name,
                        style: const TextStyle(color: Colors.white)),
                    trailing:
                        const Icon(Icons.chevron_right, color: Colors.white54),
                    onTap: () => context.push('/reader/${ch.id}'),
                  ),
                );
              },
              childCount: displayChapters.length,
            ),
          ),

          // === PHẦN BÌNH LUẬN ===
          SliverToBoxAdapter(
            key: _commentSectionKey,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Bình luận',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      Text('${comments.length} bình luận',
                          style: const TextStyle(color: Colors.white54)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildCommentInput(comic.id),
                  const SizedBox(height: 16),
                  ...comments.map(_buildCommentTile).toList(),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  // === Input bình luận ===
  Widget _buildCommentInput(String comicId) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Viết bình luận...',
                hintStyle: TextStyle(color: Colors.white54),
                border: InputBorder.none,
              ),
              maxLines: null,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send, color: Colors.redAccent),
            onPressed: _handleSendComment,
          ),
        ],
      ),
    );
  }

  void _handleSendComment() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng đăng nhập để bình luận')),
      );
      context.push('/login');
      return;
    }

    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final newComment = Comment(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      comicId: widget.comicId,
      userId: user.uid,
      userName: user.displayName ?? 'Người dùng',
      userAvatar: user.photoURL ?? 'https://i.pravatar.cc/40?u=${user.uid}',
      content: text,
      likes: 0,
      createdAt: DateTime.now(),
      isLiked: false,
    );

    MockCatalog.addComment(newComment);

    setState(() {
      comments.insert(0, newComment);
      _commentController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã gửi bình luận!')),
    );
  }

  // === Hiển thị 1 bình luận ===
  Widget _buildCommentTile(Comment comment) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
              radius: 18, backgroundImage: NetworkImage(comment.userAvatar)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(comment.userName,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                    Text(_formatTimeAgo(comment.createdAt),
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(comment.content,
                    style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () {
                    final isLiked = !comment.isLiked;
                    MockCatalog.updateCommentLike(comment.id, isLiked);
                    setState(() {
                      final index = comments.indexOf(comment);
                      comments[index] = comment.copyWith(
                          isLiked: isLiked,
                          likes:
                              isLiked ? comment.likes + 1 : comment.likes - 1);
                    });
                  },
                  child: Row(
                    children: [
                      Icon(
                        comment.isLiked
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color:
                            comment.isLiked ? Colors.redAccent : Colors.white54,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text('${comment.likes}',
                          style: const TextStyle(color: Colors.white54)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000) return '${(number / 1000).toStringAsFixed(1)}K';
    return number.toString();
  }

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inHours < 1) return '${diff.inMinutes} phút trước';
    if (diff.inDays < 1) return '${diff.inHours} giờ trước';
    return '${diff.inDays} ngày trước';
  }
}
