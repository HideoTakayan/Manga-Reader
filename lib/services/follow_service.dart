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
    if (uid == null) return Stream.value(false);
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
    final mangaRef = _db.collection('comics').doc(mangaId);

    await _db.runTransaction((transaction) async {
      final doc = await transaction.get(ref);
      if (doc.exists) return;

      transaction.set(ref, {
        'mangaId': mangaId,
        'title': title,
        'coverUrl': coverUrl,
        'followedAt': Timestamp.now(),
      });
      transaction.set(mangaRef, {
        'likeCount': FieldValue.increment(1),
      }, SetOptions(merge: true));
    });
  }

  Future<void> unfollowManga(String mangaId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Chưa đăng nhập');
    final ref = _db
        .collection('users')
        .doc(uid)
        .collection('following')
        .doc(mangaId);
    final mangaRef = _db.collection('comics').doc(mangaId);

    await _db.runTransaction((transaction) async {
      final doc = await transaction.get(ref);
      if (!doc.exists) return;

      final mangaDoc = await transaction.get(mangaRef);
      final likeCount = (mangaDoc.data()?['likeCount'] as num?)?.toInt() ?? 0;

      transaction.delete(ref);
      if (likeCount > 0) {
        transaction.set(mangaRef, {
          'likeCount': FieldValue.increment(-1),
        }, SetOptions(merge: true));
      }
    });
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
    final mangaRef = _db.collection('comics').doc(mangaId);

    final doc = await ref.get();
    if (!doc.exists && (title == null || coverUrl == null)) {
      throw Exception('Thiếu thông tin để theo dõi');
    }

    if (doc.exists) {
      await _db.runTransaction((transaction) async {
        final followDoc = await transaction.get(ref);
        if (!followDoc.exists) return;

        final mangaDoc = await transaction.get(mangaRef);
        final likeCount = (mangaDoc.data()?['likeCount'] as num?)?.toInt() ?? 0;

        transaction.delete(ref);
        if (likeCount > 0) {
          transaction.set(mangaRef, {
            'likeCount': FieldValue.increment(-1),
          }, SetOptions(merge: true));
        }
      });
    } else {
      await _db.runTransaction((transaction) async {
        final followDoc = await transaction.get(ref);
        if (followDoc.exists) return;

        transaction.set(ref, {
          'mangaId': mangaId,
          'title': title,
          'coverUrl': coverUrl,
          'followedAt': Timestamp.now(),
        });
        transaction.set(mangaRef, {
          'likeCount': FieldValue.increment(1),
        }, SetOptions(merge: true));
      });
    }
  }
}
