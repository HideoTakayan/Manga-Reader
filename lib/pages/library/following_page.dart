import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../data/mock_catalog.dart';
import '../../data/models.dart';

class FollowingPage extends StatelessWidget {
  const FollowingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    // Nếu chưa đăng nhập
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

    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      appBar: AppBar(
        title: const Text('Truyện đang theo dõi'),
        backgroundColor: const Color(0xFF1C1C1E),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () {
            context.go('/'); // ← ĐÚNG: về trang chủ (root)
          },
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
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

          final followedComics = docs
              .map((d) => MockCatalog.comicById(d.id))
              .where((c) => c != null)
              .cast<Comic>()
              .toList();

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: followedComics.length,
            itemBuilder: (context,  index) {
              final comic = followedComics[index];
              return Card(
                color: const Color(0xFF2C2C2E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: comic.coverUrl,
                      width: 60,
                      height: 80,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Colors.grey[800],
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: Colors.grey[800],
                        child: const Icon(Icons.error, color: Colors.red),
                      ),
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
                  trailing:
                  const Icon(Icons.chevron_right, color: Colors.white),
                  onTap: () => context.push('/detail/${comic.id}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}