import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// FollowService: quản lý trạng thái theo dõi (follow/unfollow) từng truyện.
// Dữ liệu lưu ở subcollection users/{uid}/following/{mangaId}
// và đồng thời cập nhật likeCount trong collection 'comics'.
class FollowService {
  static final FollowService instance = FollowService._internal();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  FollowService._internal();
  factory FollowService() => instance;

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
      if (doc.exists) {
        transaction.update(ref, {
          'followedAt': Timestamp.now(),
        });
        return;
      }

      transaction.set(ref, {
        'mangaId': mangaId,
        'title': title,
        'coverUrl': coverUrl,
        'followedAt': Timestamp.now(),
        'notifyEnabled': true,
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
      final currentLikes = (mangaDoc.data()?['likeCount'] as num?)?.toInt() ?? 0;

      transaction.delete(ref);
      transaction.set(mangaRef, {
        'likeCount': currentLikes > 0 ? currentLikes - 1 : 0,
      }, SetOptions(merge: true));
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
        final currentLikes = (mangaDoc.data()?['likeCount'] as num?)?.toInt() ?? 0;

        transaction.delete(ref);
        transaction.set(mangaRef, {
          'likeCount': currentLikes > 0 ? currentLikes - 1 : 0,
        }, SetOptions(merge: true));
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
          'notifyEnabled': true,
        });
        transaction.set(mangaRef, {
          'likeCount': FieldValue.increment(1),
        }, SetOptions(merge: true));
      });
    }
  }

  /// Lắng nghe trạng thái bật/tắt thông báo cho bộ truyện (Mặc định là true nếu theo dõi)
  Stream<bool> isNotificationEnabled(String mangaId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(false);
    return _db
        .collection('users')
        .doc(uid)
        .collection('following')
        .doc(mangaId)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return false;
      final data = snap.data();
      return data?['notifyEnabled'] is bool ? data!['notifyEnabled'] as bool : true;
    });
  }

  /// Bật/Tắt chuông thông báo chương mới cho bộ truyện
  Future<bool> toggleNotification(String mangaId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Chưa đăng nhập');

    final ref = _db
        .collection('users')
        .doc(uid)
        .collection('following')
        .doc(mangaId);

    final doc = await ref.get();
    if (!doc.exists) return false;

    final current = doc.data()?['notifyEnabled'] is bool
        ? doc.data()!['notifyEnabled'] as bool
        : true;
    final next = !current;

    await ref.update({'notifyEnabled': next});
    return next;
  }
}

