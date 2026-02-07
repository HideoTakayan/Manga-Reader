import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FollowService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<bool> isFollowing(String mangaId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
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
      'comicId': mangaId, // Backward compatibility
      'title': title,
      'coverUrl': coverUrl,
      'followedAt': FieldValue.serverTimestamp(),
    });

    // Tăng lượt yêu thích toàn cục (vẫn dùng collection 'comics')
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

    // Giảm lượt yêu thích toàn cục
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
      // Giảm lượt yêu thích toàn cục
      await _db.collection('comics').doc(mangaId).set({
        'likeCount': FieldValue.increment(-1),
      }, SetOptions(merge: true));
    } else {
      if (title == null || coverUrl == null) {
        throw Exception('Missing info for follow');
      }
      await ref.set({
        'mangaId': mangaId,
        'comicId': mangaId, // Backward compatibility
        'title': title,
        'coverUrl': coverUrl,
        'followedAt': FieldValue.serverTimestamp(),
      });
      // Tăng lượt yêu thích toàn cục
      await _db.collection('comics').doc(mangaId).set({
        'likeCount': FieldValue.increment(1),
      }, SetOptions(merge: true));
    }
  }
}
