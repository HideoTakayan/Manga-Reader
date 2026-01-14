import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/models.dart';

class HistoryService {
  static final HistoryService instance = HistoryService._();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  HistoryService._();

  /// Lưu tiến độ đọc truyện (lịch sử) của người dùng hiện tại lên Cloud Firestore
  /// Dữ liệu sẽ được lưu trong subcollection 'history' của user đó
  Future<void> saveHistory(ReadingHistory history) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('history')
          .doc(history.comicId)
          .set({...history.toMap(), 'updatedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      print('Lỗi khi lưu lịch sử lên cloud: $e');
    }
  }

  /// Truy xuất lịch sử đọc của một bộ truyện cụ thể
  /// Giúp người dùng tiếp tục đọc từ chương đang dang dở
  Future<ReadingHistory?> getHistoryForComic(String comicId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;

    try {
      final doc = await _db
          .collection('users')
          .doc(uid)
          .collection('history')
          .doc(comicId)
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        // Chuyển đổi Timestamp của Firestore về dạng mili-giây
        if (data['updatedAt'] is Timestamp) {
          data['updatedAt'] =
              (data['updatedAt'] as Timestamp).millisecondsSinceEpoch;
        }
        return ReadingHistory.fromMap(data);
      }
    } catch (e) {
      print('Lỗi khi lấy lịch sử truyện từ cloud: $e');
    }
    return null;
  }

  /// Lấy toàn bộ danh sách lịch sử đọc của người dùng
  /// Sắp xếp giảm dần theo thời gian cập nhật (mới đọc nhất lên đầu)
  Future<List<ReadingHistory>> getAllHistory() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return [];

    try {
      final snapshot = await _db
          .collection('users')
          .doc(uid)
          .collection('history')
          .orderBy('updatedAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        if (data['updatedAt'] is Timestamp) {
          data['updatedAt'] =
              (data['updatedAt'] as Timestamp).millisecondsSinceEpoch;
        }
        return ReadingHistory.fromMap(data);
      }).toList();
    } catch (e) {
      print('Lỗi khi tải toàn bộ lịch sử từ cloud: $e');
      return [];
    }
  }

  /// Xoá lịch sử đọc của một bộ truyện cụ thể khỏi danh sách
  Future<void> deleteHistory(String comicId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('history')
          .doc(comicId)
          .delete();
    } catch (e) {
      print('Lỗi khi xoá lịch sử truyện: $e');
    }
  }

  /// Xoá sạch toàn bộ lịch sử đọc của người dùng hiện tại
  /// Sử dụng Batch Write để thực hiện xoá hàng loạt document cùng lúc
  Future<void> clearAllHistory() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      final collection = _db.collection('users').doc(uid).collection('history');
      final snapshot = await collection.get();

      final batch = _db.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      print('Lỗi khi xoá toàn bộ lịch sử: $e');
    }
  }
}
