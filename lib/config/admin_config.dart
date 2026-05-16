// Cấu hình quyền Admin — danh sách email được phép truy cập Admin Dashboard.
// Tập trung tại một chỗ để dễ bảo trì, không hardcode rải rác trong nhiều file.
class AdminConfig {
  AdminConfig._();

  static const List<String> _adminEmails = [
    'admin@gmail.com',
    'anhlasinhvien2k51@gmail.com',
  ];

  /// Kiểm tra xem email có thuộc nhóm admin không.
  /// Trả về false nếu email null hoặc rỗng.
  static bool isAdmin(String? email) {
    final normalizedEmail = email?.trim().toLowerCase();
    if (normalizedEmail == null || normalizedEmail.isEmpty) return false;
    return _adminEmails.contains(normalizedEmail);
  }
}
