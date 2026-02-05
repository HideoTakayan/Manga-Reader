import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Không cần init FCM hay xin quyền nữa

  /// Lấy danh sách thông báo (Kết hợp Global Notifs + Filter theo Following)
  Stream<List<Map<String, dynamic>>> streamUserNotifications() async* {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      yield [];
      return;
    }

    // Lắng nghe collection 'notifications' chung (được tạo bởi Admin)
    final notifStream = _db
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .limit(50) // Giới hạn 50 tin mới nhất
        .snapshots();

    // Mỗi khi có thông báo mới trên hệ thống
    await for (final snapshot in notifStream) {
      try {
        // 1. Lấy danh sách các truyện user đang THEO DÕI (Tim ❤️)
        // Thay vì dùng 'comic_subscriptions' (cái chuông), ta dùng 'following' (trái tim)
        final followingSnap = await _db
            .collection('users')
            .doc(userId)
            .collection('following')
            .get();

        final followingIds = followingSnap.docs.map((d) => d.id).toSet();

        // 2. Lọc thông báo: Chỉ lấy tin hệ thống HOẶC tin về truyện đang theo dõi
        final filteredNotifications = snapshot.docs
            .where((doc) {
              final data = doc.data();
              final comicId = data['comicId'];

              // Logic lọc:
              // - Nếu không có comicId (tin hệ thống) -> Lấy
              // - Nếu có comicId và user đang follow -> Lấy
              if (comicId == null || comicId == '') return true; // System notif
              return followingIds.contains(comicId);
            })
            .map((doc) {
              // Map dữ liệu để UI dễ dùng
              return {...doc.data(), 'id': doc.id};
            })
            .toList();

        yield filteredNotifications;
      } catch (e) {
        print('Error filtering notifications: $e');
        yield [];
      }
    }
  }

  /// Đánh dấu đã đọc thông báo (Lưu vào local/user prefs nếu cần, hoặc bỏ qua)
  /// Vì dùng Global Stream nên việc mark read cho từng user hơi khó nếu không lưu sub-collection.
  /// Tạm thời hàm này có thể disable hoặc implement kiểu lưu list id đã đọc vào local user settings.
  Future<void> markAsRead(String notificationId) async {
    // Logic đánh dấu đã đọc (Optional)
    print('Mark read: $notificationId (Todo implementation)');
  }

  // --- STUB METHODS FOR COMPATIBILITY ---
  // Các phương thức này được giữ lại để tránh lỗi compile ở các file khác
  // do chúng ta đã loại bỏ tính năng FCM Push và nút Chuông.

  Future<void> initialize() async {
    // Không cần xin quyền nữa
  }

  Stream<bool> streamSubscriptionStatus(String comicId) {
    return Stream.value(false); // Luôn trả về false
  }

  Future<void> toggleSubscription(String comicId) async {
    // Không làm gì cả
  }

  Stream<int> streamComicNotificationCount(String comicId) {
    return Stream.value(0);
  }

  Future<void> notifySubscribers({
    required String comicId,
    required String title,
    required String body,
  }) async {
    // Không làm gì vì Admin Dashboard đã tự ghi vào Firestore notifications collection
  }
}
