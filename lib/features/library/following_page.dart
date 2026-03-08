import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../shared/drive_image.dart';

// Trang danh sách truyện đang theo dõi.
// Dữ liệu follow lưu trong Firestore: users/{uid}/following/{mangaId}
class FollowingPage extends StatefulWidget {
  const FollowingPage({super.key});

  @override
  State<FollowingPage> createState() => _FollowingPageState();
}

class _FollowingPageState extends State<FollowingPage> {
  // _refreshKey: tăng lên khi pull-to-refresh → FutureBuilder tạo Future mới
  int _refreshKey = 0;

  // Lọc từ toàn bộ catalog Drive chỉ lấy các manga user đang theo dõi
  Future<List<CloudManga>> _getFollowedMangas(List<String> followedIds) async {
    final allMangas = await DriveService.instance.getMangas(
      forceRefresh: false,
    );
    return allMangas.where((c) => followedIds.contains(c.id)).toList();
  }

  Future<void> _handleRefresh() async {
    await DriveService.instance.getMangas(forceRefresh: true);
    if (mounted) setState(() => _refreshKey++);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    // Guard: chưa đăng nhập → hiện thông báo, không query Firestore
    if (user == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(
          child: Text(
            'Vui lòng đăng nhập để xem danh sách theo dõi',
            style: TextStyle(fontSize: 16, color: Colors.white),
          ),
        ),
      );
    }

    // Đường dẫn Firestore: users/{uid}/following — mỗi doc là 1 mangaId đang theo dõi
    final followingRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('following');

    // StreamBuilder ngoài: lắng nghe danh sách mangaId realtime từ Firestore
    // Khi user follow/unfollow ở màn hình khác → stream phát → list tự cập nhật
    return StreamBuilder<QuerySnapshot>(
      stream: followingRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'Bạn chưa theo dõi truyện nào.',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          );
        }

        // doc.id chính là mangaId — không cần đọc thêm field nào
        final followedIds = docs.map((d) => d.id).toList();

        // FutureBuilder trong: tải chi tiết từng truyện từ Drive bằng danh sách id vừa lấy
        // ValueKey(_refreshKey) → đổi key = ép Flutter tạo lại FutureBuilder hoàn toàn mới
        return FutureBuilder<List<CloudManga>>(
          key: ValueKey(_refreshKey),
          future: _getFollowedMangas(followedIds),
          builder: (context, mangaSnapshot) {
            if (mangaSnapshot.connectionState == ConnectionState.waiting &&
                !mangaSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final mangas = mangaSnapshot.data ?? [];

            // Edge case: followedIds có nhưng Drive không tìm thấy truyện nào
            // (truyện đã bị xóa khỏi catalog, nhưng id vẫn còn trong Firestore)
            if (mangas.isEmpty &&
                mangaSnapshot.connectionState == ConnectionState.done) {
              return RefreshIndicator(
                onRefresh: _handleRefresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 200),
                    Center(
                      child: Text(
                        'Không tìm thấy dữ liệu truyện theo dõi',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: _handleRefresh,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                itemCount: mangas.length,
                itemBuilder: (context, index) {
                  final manga = mangas[index];
                  return Card(
                    color: Theme.of(context).cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: DriveImage(
                          fileId: manga.coverFileId,
                          width: 60,
                          height: 80,
                          fit: BoxFit.cover,
                        ),
                      ),
                      title: Text(
                        manga.title,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        'Tác giả: ${manga.author}',
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: Theme.of(context).iconTheme.color,
                      ),
                      onTap: () => context.push('/detail/${manga.id}'),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
