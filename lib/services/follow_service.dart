import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FollowService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<bool> isFollowing(String comicId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _db
        .collection('users')
        .doc(uid)
        .collection('following')
        .doc(comicId)
        .snapshots()
        .map((snap) => snap.exists);
  }

  Future<void> followComic({
    required String comicId,
    required String title,
    required String coverUrl,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Chưa đăng nhập');
    final ref = _db
        .collection('users')
        .doc(uid)
        .collection('following')
        .doc(comicId);
    await ref.set({
      'comicId': comicId,
      'title': title,
      'coverUrl': coverUrl,
      'followedAt': FieldValue.serverTimestamp(),
    });

    // Tăng lượt yêu thích toàn cục
    await _db.collection('comics').doc(comicId).set({
      'likeCount': FieldValue.increment(1),
    }, SetOptions(merge: true));
  }

  Future<void> unfollowComic(String comicId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Chưa đăng nhập');
    final ref = _db
        .collection('users')
        .doc(uid)
        .collection('following')
        .doc(comicId);
    await ref.delete();

    // Giảm lượt yêu thích toàn cục
    await _db.collection('comics').doc(comicId).set({
      'likeCount': FieldValue.increment(-1),
    }, SetOptions(merge: true));
  }

  Future<void> toggleFollow(
    String comicId, {
    String? title,
    String? coverUrl,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Chưa đăng nhập');

    final ref = _db
        .collection('users')
        .doc(uid)
        .collection('following')
        .doc(comicId);
    final doc = await ref.get();

    if (doc.exists) {
      await ref.delete();
      // Giảm lượt yêu thích toàn cục
      await _db.collection('comics').doc(comicId).set({
        'likeCount': FieldValue.increment(-1),
      }, SetOptions(merge: true));
    } else {
      if (title == null || coverUrl == null) {
        throw Exception('Missing info for follow');
      }
      await ref.set({
        'comicId': comicId,
        'title': title,
        'coverUrl': coverUrl,
        'followedAt': FieldValue.serverTimestamp(),
      });
      // Tăng lượt yêu thích toàn cục
      await _db.collection('comics').doc(comicId).set({
        'likeCount': FieldValue.increment(1),
      }, SetOptions(merge: true));
    }
  }
}
