import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// FollowService: quản lý trạng thái theo dõi (follow/unfollow) từng truyện.
// Dữ liệu lưu ở subcollection users/{uid}/following/{mangaId}
// và đồng thời cập nhật likeCount trong collection 'comics'.
class FollowService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<bool> isFollowing(String mangaId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null)
      return const Stream.empty(); // C
    return _db
        .collection('users')
        .doc(uid)
        .collection('following')
        .doc(mangaId)
        .snapshots()
        .map((snap) => snap.exists);
  }

  Future<void> followManga({
    required String mangaId,
    required String title,
    required String coverUrl,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Chưa đăng nhập');
    final ref = _db
        .collection('users')
        .doc(uid)
        .collection('following')
        .doc(mangaId);
    await ref.set({
      'mangaId': mangaId,
      'comicId':
          mangaId,
      'title': title,
      'coverUrl': coverUrl,
      'followedAt': FieldValue.serverTimestamp(),
    });
    await _db.collection('comics').doc(mangaId).set({
      'likeCount': FieldValue.increment(1),
    }, SetOptions(merge: true)); 
  }

  Future<void> unfollowManga(String mangaId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Chưa đăng nhập');
    final ref = _db
        .collection('users')
        .doc(uid)
        .collection('following')
        .doc(mangaId);
    await ref.delete();
    await _db.collection('comics').doc(mangaId).set({
      'likeCount': FieldValue.increment(-1),
    }, SetOptions(merge: true));
  }

  Future<void> toggleFollow(
    String mangaId, {
    String? title,
    String? coverUrl,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Chưa đăng nhập');

    final ref = _db
        .collection('users')
        .doc(uid)
        .collection('following')
        .doc(mangaId);
    final doc = await ref.get();

    if (doc.exists) {
      await ref.delete();
      await _db.collection('comics').doc(mangaId).set({
        'likeCount': FieldValue.increment(-1),
      }, SetOptions(merge: true));
    } else {
      // Chưa theo dõi → theo dõi (title + coverUrl bắt buộc vì cần lưu metadata)
      if (title == null || coverUrl == null)
        throw Exception('Thiếu thông tin để theo dõi');
      await ref.set({
        'mangaId': mangaId,
        'comicId': mangaId,
        'title': title,
        'coverUrl': coverUrl,
        'followedAt': FieldValue.serverTimestamp(),
      });
      await _db.collection('comics').doc(mangaId).set({
        'likeCount': FieldValue.increment(1),
      }, SetOptions(merge: true));
    }
  }
}
