import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../shared/drive_image.dart';

class FollowingPage extends StatelessWidget {
  const FollowingPage({super.key});

  Future<List<CloudComic>> _getFollowedComics(List<String> followedIds) async {
    final allComics = await DriveService.instance.getComics();
    return allComics.where((c) => followedIds.contains(c.id)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Vui lòng đăng nhập để xem danh sách theo dõi',
            style: TextStyle(fontSize: 16, color: Colors.white),
          ),
        ),
        backgroundColor: Color(0xFF1C1C1E),
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
          future: _getFollowedComics(followedIds),
          builder: (context, comicSnapshot) {
            if (comicSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final comics = comicSnapshot.data ?? [];

            if (comics.isEmpty) {
              // Should technically not happen if IDs match, but possible if Drive data is out of sync
              return const Center(
                child: Text(
                  'Không tìm thấy dữ liệu truyện theo dõi',
                  style: TextStyle(color: Colors.white70),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: comics.length,
              itemBuilder: (context, index) {
                final comic = comics[index];

                return Card(
                  color: const Color(0xFF2C2C2E),
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      'Tác giả: ${comic.author}',
                      style: const TextStyle(color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.white,
                    ),
                    onTap: () => context.push('/detail/${comic.id}'),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
