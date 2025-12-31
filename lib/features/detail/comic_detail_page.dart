import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/models.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart'; // Import DriveService
import '../../services/follow_service.dart';
import '../shared/drive_image.dart'; // Import DriveImage

class ComicDetailPage extends StatefulWidget {
  final String comicId;
  const ComicDetailPage({super.key, required this.comicId});

  @override
  State<ComicDetailPage> createState() => _ComicDetailPageState();
}

class _ComicDetailPageState extends State<ComicDetailPage> {
  bool showAll = false;

  // Placeholder for comments until migrated
  List<Comment> comments = [];
  final TextEditingController _commentController = TextEditingController();

  Future<CloudComic?> _fetchComic() async {
    // Temporary: Fetch all and find by ID because DriveService stores all in catalog.json
    // Ideally DriveService should implement getComic(id)
    final comics = await DriveService.instance.getComics();
    try {
      return comics.firstWhere((c) => c.id == widget.comicId);
    } catch (e) {
      return null;
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. Fetch Comic Details
    return FutureBuilder<CloudComic?>(
      future: _fetchComic(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF0E0E10),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final comic = snapshot.data;
        if (comic == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Lỗi')),
            body: const Center(child: Text('Không tìm thấy truyện')),
          );
        }

        // 2. Fetch Chapters
        return FutureBuilder<List<CloudChapter>>(
          future: DriveService.instance.getChapters(widget.comicId),
          builder: (context, chapterSnapshot) {
            final chapters = chapterSnapshot.data ?? [];

            final displayChapters = showAll
                ? chapters
                : chapters.take(5).toList();
            final followService = FollowService();

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
                          DriveImage(
                            fileId: comic.coverFileId,
                            fit: BoxFit.cover,
                          ),
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
                                backgroundColor: Colors.redAccent.withOpacity(
                                  0.9,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              onPressed: () {
                                if (chapters.isNotEmpty) {
                                  context.push('/reader/${chapters.first.id}');
                                }
                              },
                              icon: const Icon(
                                Icons.play_arrow,
                                color: Colors.white,
                              ),
                              label: const Text(
                                'Đọc ngay',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
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
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tác giả: ${comic.author}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            comic.description,
                            style: const TextStyle(
                              color: Colors.white70,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // === Nút theo dõi ===
                          StreamBuilder<bool>(
                            stream: followService.isFollowing(comic.id),
                            builder: (context, snapshot) {
                              final isFollowing = snapshot.data == true;
                              return ElevatedButton.icon(
                                onPressed: () async {
                                  final user =
                                      FirebaseAuth.instance.currentUser;
                                  if (user == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Vui lòng đăng nhập để theo dõi',
                                        ),
                                      ),
                                    );
                                    context.push('/login');
                                    return;
                                  }

                                  try {
                                    if (isFollowing) {
                                      await followService.unfollowComic(
                                        comic.id,
                                      );
                                    } else {
                                      await followService.followComic(
                                        comicId: comic.id,
                                        title: comic.title,
                                        coverUrl: comic
                                            .coverFileId, // Using File ID as URL for now, FollowService might need update
                                      );
                                    }
                                  } catch (e) {
                                    // Handle error
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white12,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: Icon(
                                  isFollowing
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: isFollowing
                                      ? Colors.red
                                      : Colors.white70,
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Danh sách chương',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (chapters.length > 5)
                            TextButton(
                              onPressed: () =>
                                  setState(() => showAll = !showAll),
                              child: Text(
                                showAll ? 'Thu gọn' : 'Xem tất cả',
                                style: const TextStyle(
                                  color: Colors.lightBlueAccent,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final ch = displayChapters[index];
                      return Card(
                        color: const Color(0xFF1A1A1D),
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListTile(
                          title: Text(
                            ch.title,
                            style: const TextStyle(color: Colors.white),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: Colors.white54,
                          ),
                          onTap: () => context.push('/reader/${ch.id}'),
                        ),
                      );
                    }, childCount: displayChapters.length),
                  ),

                  // === PHẦN BÌNH LUẬN (DISABLED FOR MIGRATION) ===
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        "Bình luận đang bảo trì...",
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
