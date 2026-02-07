import 'package:cloud_firestore/cloud_firestore.dart';

class InteractionService {
  static final InteractionService instance = InteractionService._();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  InteractionService._();

  /// Tăng tổng lượt xem của một bộ truyện (Manga View) lên 1 đơn vị
  /// Dữ liệu được lưu trong Collection 'comics' trên Firestore (Giữ nguyên tên collection cũ)
  Future<void> incrementMangaView(String mangaId) async {
    try {
      final ref = _db.collection('comics').doc(mangaId);
      await ref.set({
        'viewCount': FieldValue.increment(1),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Lỗi khi tăng lượt xem truyện: $e');
    }
  }

  /// Tăng lượt xem của một chương cụ thể (Chapter View)
  /// Đồng thời gọi hàm tăng lượt xem tổng của truyện đó
  Future<void> incrementChapterView(String mangaId, String chapterId) async {
    try {
      // 1. Tăng view count trong subcollection 'chapters'
      final chapterRef = _db
          .collection('comics')
          .doc(mangaId)
          .collection('chapters')
          .doc(chapterId);

      await chapterRef.set({
        'viewCount': FieldValue.increment(1),
      }, SetOptions(merge: true));

      // 2. Tăng view tổng của manga luôn để đảm bảo tính nhất quán
      await incrementMangaView(mangaId);
    } catch (e) {
      print('Lỗi khi tăng lượt xem chapter: $e');
    }
  }

  /// Lấy thống kê lượt xem của TẤT CẢ các chương trong một bộ truyện
  /// Trả về Map<ChapterId, ViewCount> để hiển thị bên cạnh tên chương
  Future<Map<String, int>> getChapterViews(String mangaId) async {
    try {
      final snapshot = await _db
          .collection('comics')
          .doc(mangaId)
          .collection('chapters')
          .get();

      final map = <String, int>{};
      for (var doc in snapshot.docs) {
        map[doc.id] = (doc.data()['viewCount'] as num?)?.toInt() ?? 0;
      }
      return map;
    } catch (e) {
      print('Lỗi khi tải thống kê chapter: $e');
      return {};
    }
  }

  /// Lấy thống kê (Lượt xem, Lượt thích) của TOÀN BỘ truyện có trong hệ thống
  /// Dùng để map dữ liệu vào danh sách truyện lấy từ Drive
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
      print('Lỗi khi tải thống kê toàn bộ truyện: $e');
      return {};
    }
  }

  /// Luồng sự kiện theo dõi thời gian thực (Realtime Stream) thống kê của một truyện
  /// Giúp cập nhật UI ngay lập tức khi có lượt xem hoặc lượt thích mới
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

  /// Luồng sự kiện theo dõi thời gian thực lượt xem của TẤT CẢ các chương trong một truyện
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
