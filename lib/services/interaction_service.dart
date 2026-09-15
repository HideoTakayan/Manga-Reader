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
      final chapterRef = _db
          .collection('comics')
          .doc(mangaId)
          .collection('chapters')
          .doc(chapterId);
      final mangaRef = _db.collection('comics').doc(mangaId);

      await Future.wait([
        chapterRef.set({
          'viewCount': FieldValue.increment(1),
        }, SetOptions(merge: true)),
        mangaRef.set({
          'viewCount': FieldValue.increment(1),
        }, SetOptions(merge: true)),
      ]);
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

  /// Đánh giá truyện (1-5 sao). Lưu theo userId vào subcollection `ratings` và cập nhật manga doc qua Transaction.
  Future<void> rateManga(String mangaId, int stars) async {
    final user = _auth.currentUser;
    if (user == null) {
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
      final ratingRef = _db
          .collection('comics')
          .doc(mangaId)
          .collection('ratings')
          .doc(user.uid);
      final mangaRef = _db.collection('comics').doc(mangaId);

      // Wrap entire operation in a transaction to avoid TOCTOU race conditions
      // where concurrent calls could read the same oldStars and apply the delta twice.
      await _db.runTransaction((transaction) async {
        final ratingDoc = await transaction.get(ratingRef);

        if (ratingDoc.exists && ratingDoc.data() != null) {
          // Đã có rating → update stars + điều chỉnh ratingSum
          final oldStars =
              (ratingDoc.data()!['stars'] as num?)?.toInt() ?? stars;
          final diff = stars - oldStars;

          transaction.set(ratingRef, {
            'userId': user.uid,
            'stars': stars,
            'ratedAt': FieldValue.serverTimestamp(),
          });

          if (diff != 0) {
            transaction.set(
              mangaRef,
              {'ratingSum': FieldValue.increment(diff)},
              SetOptions(merge: true),
            );
          }
        } else {
          // Chưa có rating → tạo mới + tăng ratingCount
          transaction.set(ratingRef, {
            'userId': user.uid,
            'stars': stars,
            'ratedAt': FieldValue.serverTimestamp(),
          });

          transaction.set(
            mangaRef,
            {
              'ratingSum': FieldValue.increment(stars),
              'ratingCount': FieldValue.increment(1),
            },
            SetOptions(merge: true),
          );
        }
      });
    } catch (e) {
      debugPrint('Lỗi khi đánh giá truyện: $e');
      rethrow;
    }
  }

  /// Lấy đánh giá của user hiện tại cho truyện này từ Firestore
  Future<int?> getUserRating(String mangaId) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      final doc = await _db
          .collection('comics')
          .doc(mangaId)
          .collection('ratings')
          .doc(user.uid)
          .get();
      if (doc.exists && doc.data() != null) {
        return (doc.data()!['stars'] as num?)?.toInt();
      }
    } catch (_) {}
    return null;
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

      await _db.runTransaction((transaction) async {
        final likeDoc = await transaction.get(likeRef);
        if (likeDoc.exists) return; // Đã like rồi thì không tăng nữa

        transaction.set(likeRef, {'likedAt': FieldValue.serverTimestamp()});
        transaction.set(
          mangaRef,
          {'likeCount': FieldValue.increment(1)},
          SetOptions(merge: true),
        );
      });
    } catch (e) {
      debugPrint('Lỗi khi like truyện: $e');
      rethrow;
    }
  }

  /// Bỏ like một bộ truyện. Nếu chưa like thì bỏ qua (idempotent), không giảm likeCount dưới 0.
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

      await _db.runTransaction((transaction) async {
        final likeDoc = await transaction.get(likeRef);
        if (!likeDoc.exists) return; // Chưa like thì không làm gì

        final mangaDoc = await transaction.get(mangaRef);
        final currentLikes = (mangaDoc.data()?['likeCount'] as num?)?.toInt() ?? 0;

        transaction.delete(likeRef);
        transaction.set(
          mangaRef,
          {'likeCount': currentLikes > 0 ? currentLikes - 1 : 0},
          SetOptions(merge: true),
        );
      });
    } catch (e) {
      debugPrint('Lỗi khi bỏ like truyện: $e');
      rethrow;
    }
  }
}
