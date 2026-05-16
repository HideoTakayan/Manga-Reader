import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../data/models.dart';

// HistoryService: lưu và đồng bộ lịch sử đọc lên Firestore.
// Mỗi truyện có 1 document trong users/{uid}/history/{mangaId}
// → ghi đè toàn bộ khi đọc chapter mới (không append)
class HistoryService {
  static final HistoryService instance = HistoryService._();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  HistoryService._();

  /// Lưu tiến độ đọc lên Firestore — set() ghi đè toàn document nên không cần merge
  Future<void> saveHistory(ReadingHistory history) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      final data = history.toMap()..remove('comicId');
      await _db
          .collection('users')
          .doc(uid)
          .collection('history')
          .doc(history.mangaId)
          .set({...data, 'updatedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      debugPrint('Lỗi khi lưu lịch sử lên cloud: $e');
    }
  }

  Future<ReadingHistory?> getHistoryForManga(String mangaId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;

    try {
      final doc = await _db
          .collection('users')
          .doc(uid)
          .collection('history')
          .doc(mangaId)
          .get();
      if (doc.exists && doc.data() != null) {
        return _historyFromFirestore(doc.id, doc.data()!);
      }
    } catch (e) {
      debugPrint('Lỗi khi lấy lịch sử truyện từ cloud: $e');
    }
    return null;
  }

  /// Lấy toàn bộ lịch sử — orderBy updatedAt để hiện mới nhất trước
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
        return _historyFromFirestore(doc.id, doc.data());
      }).toList();
    } catch (e) {
      debugPrint('Lỗi khi tải toàn bộ lịch sử từ cloud: $e');
      return [];
    }
  }

  Future<void> deleteHistory(String mangaId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('history')
          .doc(mangaId)
          .delete();
    } catch (e) {
      debugPrint('Lỗi khi xoá lịch sử truyện: $e');
    }
  }

  /// Xóa toàn bộ history — dùng Batch Write để xóa nhiều document trong 1 request
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
      debugPrint('Lỗi khi xoá toàn bộ lịch sử: $e');
    }
  }

  ReadingHistory _historyFromFirestore(
    String docId,
    Map<String, dynamic> rawData,
  ) {
    final data = Map<String, dynamic>.from(rawData);
    data['mangaId'] ??= docId;
    if (data['updatedAt'] is Timestamp) {
      data['updatedAt'] =
          (data['updatedAt'] as Timestamp).millisecondsSinceEpoch;
    }
    data['updatedAt'] ??= 0;
    return ReadingHistory.fromMap(data);
  }
}
