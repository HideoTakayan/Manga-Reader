import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// ----------------------------
  /// 🔹 ĐĂNG KÝ TÀI KHOẢN MỚI
  /// ----------------------------
  Future<void> register(String email, String password, String name) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      await _db.collection('users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid,
        'name': name,
        'email': email,
        'avatar': '',
        'bio': '',
        'createdAt': FieldValue.serverTimestamp(),
        'following': [],
        'followers': [],
        'isOnline': false,
        'lastSeen': null,
      });

      await cred.user!.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'Lỗi đăng ký tài khoản');
    }
  }

  /// ----------------------------
  /// 🔹 ĐĂNG NHẬP
  /// ----------------------------
  Future<void> login(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
    } on FirebaseAuthException catch (e) {
      throw Exception(_handleAuthError(e));
    }
  }

  /// ----------------------------
  /// 🔹 ĐĂNG XUẤT
  /// ----------------------------
  Future<void> logout() async {
    await _auth.signOut();
  }

  /// ----------------------------
  /// 🔹 LẤY USER HIỆN TẠI
  /// ----------------------------
  User? get currentUser => _auth.currentUser;

  /// ----------------------------
  /// 🔹 KIỂM TRA ĐĂNG NHẬP
  /// ----------------------------
  bool get isLoggedIn => _auth.currentUser != null;

  /// ----------------------------
  /// 🔹 HÀM XỬ LÝ LỖI (GỌN - RÕ)
  /// ----------------------------
  String _handleAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Email này đã được đăng ký.';
      case 'invalid-email':
        return 'Email không hợp lệ.';
      case 'weak-password':
        return 'Mật khẩu quá yếu.';
      case 'user-not-found':
        return 'Không tìm thấy người dùng.';
      case 'wrong-password':
        return 'Sai mật khẩu.';
      default:
        return e.message ?? 'Đã xảy ra lỗi không xác định.';
    }
  }
}
