import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../shared/drive_image.dart';

class FollowingPage extends StatefulWidget {
  const FollowingPage({super.key});

  @override
  State<FollowingPage> createState() => _FollowingPageState();
}

class _FollowingPageState extends State<FollowingPage> {
  // Key để force rebuild FutureBuilder khi refresh
  int _refreshKey = 0;

  Future<List<CloudComic>> _getFollowedComics(List<String> followedIds) async {
    final allComics = await DriveService.instance.getComics(
      forceRefresh: false,
    );
    return allComics.where((c) => followedIds.contains(c.id)).toList();
  }

  Future<void> _handleRefresh() async {
    await DriveService.instance.getComics(forceRefresh: true);
    if (mounted) {
      setState(() {
        _refreshKey++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        body: Center(
          child: Text(
            'Vui lòng đăng nhập để xem danh sách theo dõi',
            style: TextStyle(fontSize: 16, color: Colors.white),
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      );
    }

    final followingRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('following');

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

        final followedIds = docs.map((d) => d.id).toList();

        return FutureBuilder<List<CloudComic>>(
          key: ValueKey(_refreshKey), // Đánh dấu rebuild khi key thay đổi
          future: _getFollowedComics(followedIds),
          builder: (context, comicSnapshot) {
            // Hiển thị dữ liệu cũ nếu có để tránh giật lag, hoặc hiện loading
            if (comicSnapshot.connectionState == ConnectionState.waiting &&
                !comicSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final comics = comicSnapshot.data ?? [];

            if (comics.isEmpty &&
                comicSnapshot.connectionState == ConnectionState.done) {
              // ...
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
                itemCount: comics.length,
                itemBuilder: (context, index) {
                  final comic = comics[index];

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
                          fileId: comic.coverFileId,
                          width: 60,
                          height: 80,
                          fit: BoxFit.cover,
                        ),
                      ),
                      title: Text(
                        comic.title,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        'Tác giả: ${comic.author}',
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: Theme.of(context).iconTheme.color,
                      ),
                      onTap: () => context.push('/detail/${comic.id}'),
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
