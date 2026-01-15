import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  /// Kiểm tra xem người dùng đã bật chuông cho truyện này chưa
  Stream<bool> streamSubscriptionStatus(String comicId) {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return Stream.value(false);

    return _db
        .collection('users')
        .doc(userId)
        .collection('comic_subscriptions')
        .doc(comicId)
        .snapshots()
        .map((doc) => doc.exists);
  }

  /// Bật/Tắt nhận thông báo (Bấm chuông)
  Future<void> toggleSubscription(String comicId) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    final docRef = _db
        .collection('users')
        .doc(userId)
        .collection('comic_subscriptions')
        .doc(comicId);

    final doc = await docRef.get();

    // Sử dụng Batch để cập nhật cả user sub và tổng số sub của truyện
    final batch = _db.batch();
    final comicRef = _db.collection('comics').doc(comicId);

    // Reference đến danh sách những người đăng ký của truyện này
    final subscriberRef = _db
        .collection('comics')
        .doc(comicId)
        .collection('subscribers')
        .doc(userId);

    if (doc.exists) {
      // Unsubscribe
      batch.delete(docRef);
      batch.delete(subscriberRef);
      batch.set(comicRef, {
        'notificationCount': FieldValue.increment(-1),
      }, SetOptions(merge: true));
    } else {
      // Subscribe
      batch.set(docRef, {'subscribedAt': FieldValue.serverTimestamp()});
      batch.set(subscriberRef, {
        'subscribedAt': FieldValue.serverTimestamp(),
        'userId': userId,
      });
      batch.set(comicRef, {
        'notificationCount': FieldValue.increment(1),
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  /// Gửi thông báo đến tất cả người đăng ký của một truyện
  Future<void> notifySubscribers({
    required String comicId,
    required String title,
    required String body,
  }) async {
    try {
      final snapshot = await _db
          .collection('comics')
          .doc(comicId)
          .collection('subscribers')
          .get();

      if (snapshot.docs.isEmpty) return;

      final batch = _db.batch();
      final timestamp = FieldValue.serverTimestamp();

      for (var doc in snapshot.docs) {
        final userId = doc.id;
        final notifRef = _db
            .collection('users')
            .doc(userId)
            .collection('notifications')
            .doc();

        batch.set(notifRef, {
          'comicId': comicId,
          'title': title,
          'body': body,
          'isRead': false,
          'timestamp': timestamp,
          'type': 'comic_update',
        });
      }

      await batch.commit();
      print('Đã gửi thông báo cho ${snapshot.docs.length} người đăng ký.');
    } catch (e) {
      print('Lỗi khi gửi thông báo: $e');
    }
  }

  /// Lấy tổng số người bật chuông của một truyện
  Stream<int> streamComicNotificationCount(String comicId) {
    return _db
        .collection('comics')
        .doc(comicId)
        .snapshots()
        .map((doc) => (doc.data()?['notificationCount'] as num?)?.toInt() ?? 0);
  }

  /// Lấy danh sách thông báo của người dùng
  Stream<List<Map<String, dynamic>>> streamUserNotifications() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return Stream.value([]);

    return _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => {...doc.data(), 'id': doc.id})
              .toList(),
        );
  }

  /// Đánh dấu đã đọc thông báo
  Future<void> markAsRead(String notificationId) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    await _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .doc(notificationId)
        .update({'isRead': true});
  }
}
