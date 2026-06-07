import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/content_type.dart';
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
    final mangaById = {
      for (final manga in allMangas)
        if (followedIds.contains(manga.id)) manga.id: manga,
    };
    return [
      for (final id in followedIds)
        if (mangaById[id] != null) mangaById[id]!,
    ];
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

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Lỗi kết nối:\n${snapshot.error}',
              style: const TextStyle(color: Colors.redAccent),
              textAlign: TextAlign.center,
            ),
          );
        }

        final docs = [...?snapshot.data?.docs]
          ..sort((a, b) {
            final aData = a.data() as Map<String, dynamic>?;
            final bData = b.data() as Map<String, dynamic>?;
            final aTime = aData?['followedAt'];
            final bTime = bData?['followedAt'];
            final aMillis = aTime is Timestamp
                ? aTime.millisecondsSinceEpoch
                : 0;
            final bMillis = bTime is Timestamp
                ? bTime.millisecondsSinceEpoch
                : 0;
            return bMillis.compareTo(aMillis);
          });
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

            if (mangaSnapshot.hasError) {
              return Center(
                child: Text(
                  'Lỗi tải truyện:\n${mangaSnapshot.error}',
                  style: const TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              );
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
                  return Container(
                    height: 120,
                    margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => context.push('/detail/${manga.id}'),
                      child: Row(
                        children: [
                          DriveImage(
                            fileId: manga.coverFileId,
                            width: 85,
                            height: 120,
                            fit: BoxFit.cover,
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    manga.title,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tác giả: ${manga.author}',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const Spacer(),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      _ContentTypeBadge(type: manga.contentType),
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent.withValues(alpha: 0.15),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.play_arrow_rounded,
                                          color: Colors.redAccent,
                                          size: 20,
                                        ),
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
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _ContentTypeBadge extends StatelessWidget {
  final MangaContentType type;
  const _ContentTypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        type.label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
      ),
    );
  }
}
