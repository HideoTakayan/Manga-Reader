import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

// InteractionService: quản lý lượt xem (viewCount) và lượt thích (likeCount).
// Dữ liệu lưu trong collection 'comics' (tên collection cũ, giữ lại để tương thích).
// Singleton để tránh tạo nhiều instance truy cập Firestore.
class InteractionService {
  static final InteractionService instance = InteractionService._();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  InteractionService._();

  Future<void> incrementMangaView(String mangaId) async {
    try {
      final ref = _db.collection('comics').doc(mangaId);
      await ref.set({
        'viewCount': FieldValue.increment(1),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Lỗi khi tăng lượt xem truyện: $e');
    }
  }

  /// Tăng viewCount cho cả chapter lẫn manga (cascade)
  Future<void> incrementChapterView(String mangaId, String chapterId) async {
    try {
      // 1. Tăng view chapter trong subcollection
      final chapterRef = _db
          .collection('comics')
          .doc(mangaId)
          .collection('chapters')
          .doc(chapterId);
      await chapterRef.set({
        'viewCount': FieldValue.increment(1),
      }, SetOptions(merge: true));
      // 2. Cascade lên manga tổng
      await incrementMangaView(mangaId);
    } catch (e) {
      debugPrint('Lỗi khi tăng lượt xem chapter: $e');
    }
  }

  /// Lấy tất cả chapter views của 1 manga — trả về `Map<chapterId, viewCount>`.
  /// Dùng để hiển thị số lượt xem bên cạnh tên chapter
  Future<Map<String, int>> getChapterViews(String mangaId) async {
    try {
      final snapshot = await _db
          .collection('comics')
          .doc(mangaId)
          .collection('chapters')
          .get();
      final map = <String, int>{};
      for (var doc in snapshot.docs) {
        // num?.toInt(): viewCount có thể là int hoặc double do Firestore — luôn cast về int
        map[doc.id] = (doc.data()['viewCount'] as num?)?.toInt() ?? 0;
      }
      return map;
    } catch (e) {
      debugPrint('Lỗi khi tải thống kê chapter: $e');
      return {};
    }
  }

  /// Đánh giá truyện (1-5 sao). Lưu vào Document của manga để tiết kiệm Reads/Writes.
  Future<void> rateManga(String mangaId, int stars) async {
    try {
      final ref = _db.collection('comics').doc(mangaId);
      await ref.set({
        'ratingSum': FieldValue.increment(stars),
        'ratingCount': FieldValue.increment(1),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Lỗi khi đánh giá truyện: $e');
    }
  }

  /// Theo dõi điểm đánh giá trung bình realtime
  Stream<Map<String, dynamic>> streamMangaRating(String mangaId) {
    return _db.collection('comics').doc(mangaId).snapshots().map((doc) {
      final data = doc.data() ?? {};
      final sum = (data['ratingSum'] as num?)?.toInt() ?? 0;
      final count = (data['ratingCount'] as num?)?.toInt() ?? 0;
      return {'sum': sum, 'count': count};
    });
  }

  /// `Map<mangaId, {viewCount, likeCount}>` — gọi 1 lần để map stats vào danh sách truyện.
  Future<Map<String, Map<String, int>>> getAllMangaStats() async {
    try {
      final snapshot = await _db.collection('comics').get();
      final map = <String, Map<String, int>>{};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        map[doc.id] = {
          'viewCount': (data['viewCount'] as num?)?.toInt() ?? 0,
          'likeCount': (data['likeCount'] as num?)?.toInt() ?? 0,
        };
      }
      return map;
    } catch (e) {
      debugPrint('Lỗi khi tải thống kê toàn bộ truyện: $e');
      return {};
    }
  }

  /// Stream realtime stats — UI cập nhật ngay khi admin update hoặc user khác follow
  Stream<Map<String, int>> streamMangaStats(String mangaId) {
    return _db.collection('comics').doc(mangaId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) {
        return {'viewCount': 0, 'likeCount': 0};
      }
      final data = doc.data()!;
      return {
        'viewCount': (data['viewCount'] as num?)?.toInt() ?? 0,
        'likeCount': (data['likeCount'] as num?)?.toInt() ?? 0,
      };
    });
  }

  /// Stream realtime chapter views — cập nhật khi bất kỳ chapter nào được xem
  Stream<Map<String, int>> streamChapterViews(String mangaId) {
    return _db
        .collection('comics')
        .doc(mangaId)
        .collection('chapters')
        .snapshots()
        .map((snapshot) {
          final map = <String, int>{};
          for (var doc in snapshot.docs) {
            map[doc.id] = (doc.data()['viewCount'] as num?)?.toInt() ?? 0;
          }
          return map;
        });
  }
}
