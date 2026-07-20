import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

// InteractionService: quản lý lượt xem (viewCount) và lượt thích (likeCount).
// Dữ liệu lưu trong collection 'comics' (tên collection cũ, giữ lại để tương thích).
// Singleton để tránh tạo nhiều instance truy cập Firestore.
class InteractionService {
  static final InteractionService instance = InteractionService._();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
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
    if (_auth.currentUser == null) {
      throw Exception('Bạn cần đăng nhập để đánh giá truyện.');
    }
    if (stars < 1 || stars > 5) {
      throw ArgumentError.value(
        stars,
        'stars',
        'Điểm đánh giá phải từ 1 đến 5.',
      );
    }

    try {
      final ref = _db.collection('comics').doc(mangaId);
      await ref.set({
        'ratingSum': FieldValue.increment(stars),
        'ratingCount': FieldValue.increment(1),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Lỗi khi đánh giá truyện: $e');
      rethrow;
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

  /// Kiểm tra user hiện tại đã like truyện chưa.
  Future<bool> isLiked(String mangaId) async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      final doc = await _db
          .collection('comics')
          .doc(mangaId)
          .collection('likes')
          .doc(user.uid)
          .get();
      return doc.exists;
    } catch (e) {
      debugPrint('Lỗi kiểm tra like: $e');
      return false;
    }
  }

  /// Like một bộ truyện. Nếu đã like rồi thì bỏ qua (idempotent).
  Future<void> likeManga(String mangaId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Bạn cần đăng nhập để thích truyện.');
    try {
      final likeRef = _db
          .collection('comics')
          .doc(mangaId)
          .collection('likes')
          .doc(user.uid);
      final mangaRef = _db.collection('comics').doc(mangaId);
      // Dùng batch để ghi 2 document nguyên tử
      final batch = _db.batch();
      batch.set(likeRef, {'likedAt': FieldValue.serverTimestamp()});
      batch.set(
        mangaRef,
        {'likeCount': FieldValue.increment(1)},
        SetOptions(merge: true),
      );
      await batch.commit();
    } catch (e) {
      debugPrint('Lỗi khi like truyện: $e');
      rethrow;
    }
  }

  /// Bỏ like một bộ truyện. Nếu chưa like thì bỏ qua (idempotent).
  Future<void> unlikeManga(String mangaId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Bạn cần đăng nhập để bỏ thích truyện.');
    try {
      final likeRef = _db
          .collection('comics')
          .doc(mangaId)
          .collection('likes')
          .doc(user.uid);
      final mangaRef = _db.collection('comics').doc(mangaId);
      final batch = _db.batch();
      batch.delete(likeRef);
      batch.set(
        mangaRef,
        {'likeCount': FieldValue.increment(-1)},
        SetOptions(merge: true),
      );
      await batch.commit();
    } catch (e) {
      debugPrint('Lỗi khi bỏ like truyện: $e');
      rethrow;
    }
  }
}
