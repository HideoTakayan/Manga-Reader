import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

// AuthService: không phải Singleton — mỗi caller tạo instance mới.
// Thiết kế này OK vì FirebaseAuth/GoogleSignIn đều là Singleton bên dưới.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  /// Đăng ký tài khoản email/password + tạo Firestore profile + gửi email xác thực
  Future<void> register(String email, String password, String name) async {
    final normalizedEmail = email.trim().toLowerCase();
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      // Tạo document users/{uid} ngay sau khi tạo account
      await _db.collection('users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid,
        'name': name,
        'email': normalizedEmail,
        'avatar': '',
        'bio': '',
        'createdAt': FieldValue.serverTimestamp(),
        'following': [],
        'followers': [],
        'isOnline': false,
        'lastSeen': null,
        'authProvider': 'email',
        'hasPassword': true,
      });
      // Gửi email xác thực — user phải click link trước khi đăng nhập được
      await cred.user!.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'Lỗi đăng ký tài khoản');
    }
  }

  /// Đăng nhập email/password
  Future<void> login(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password.trim(),
      );
      final user = credential.user;
      if (user != null) {
        // Phục hồi profile nếu bị lỗi mạng lúc đăng ký
        final doc = await _db.collection('users').doc(user.uid).get();
        if (!doc.exists) {
          await _createUserProfile(
            uid: user.uid,
            email: user.email!,
            name: user.displayName ?? 'User',
          );
        }

        if (!user.emailVerified) {
          await _auth.signOut();
          throw Exception('Vui lòng xác minh email trước khi đăng nhập.');
        } else {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_provider', 'email');
          await prefs.setString('auth_email', email.trim().toLowerCase());
          await prefs.setString('auth_password', password.trim());
        }
      }
    } on FirebaseAuthException catch (e) {
      throw Exception(_handleAuthError(e));
    }
  }

  /// Đổi mật khẩu — PHẢI re-authenticate trước vì Firebase yêu cầu credential gần đây
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Người dùng chưa đăng nhập');

    // Tạo credential với mật khẩu hiện tại để re-authenticate
    final cred = EmailAuthProvider.credential(
      email: user.email!,
      password: currentPassword,
    );

    try {
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw Exception(_handleAuthError(e));
    }
  }

  /// Gửi email reset password — Firebase gửi link về hộp thư, không cần biết mật khẩu cũ
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw Exception(_handleAuthError(e));
    }
  }

  /// Đăng nhập bằng Google — 4 bước chuẩn: signOut trước → signIn → credential → Firebase
  Future<void> signInWithGoogle() async {
    try {
      // 0. signOut trước để luôn hiện account picker (tránh tự đăng nhập lại account cũ)
      await _googleSignIn.signOut();

      // 1. Mở Google account picker
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) throw Exception('Đăng nhập bị hủy');

      // 2. Lấy token
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // 3. Tạo Firebase credential từ Google token
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 4. Đăng nhập Firebase
      final userCredential = await _auth.signInWithCredential(credential);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_provider', 'google');

      // 5. Đảm bảo Firestore profile tồn tại (edge case: auth tồn tại nhưng doc bị xóa)
      final userDoc = await _db
          .collection('users')
          .doc(userCredential.user!.uid)
          .get();
      if (!userDoc.exists) {
        await _createUserProfile(
          uid: userCredential.user!.uid,
          email: userCredential.user!.email!,
          name: userCredential.user!.displayName ?? 'User',
          photoUrl: userCredential.user!.photoURL,
        );
      }
    } on FirebaseAuthException catch (e) {
      throw Exception(_handleAuthError(e));
    } catch (e) {
      throw Exception('Lỗi đăng nhập Google: ${e.toString()}');
    }
  }

  /// Tạo Firestore profile cho user mới — authProvider field dùng để phân biệt Google vs Email
  Future<void> _createUserProfile({
    required String uid,
    required String email,
    required String name,
    String? photoUrl,
  }) async {
    await _db.collection('users').doc(uid).set({
      'uid': uid,
      'name': name,
      'email': email,
      'avatar': photoUrl ?? '',
      'bio': '',
      'createdAt': FieldValue.serverTimestamp(),
      'following': [],
      'followers': [],
      'isOnline': false,
      'lastSeen': null,
      'authProvider': photoUrl != null ? 'google' : 'email',
    });
  }

  /// Liên kết email/password vào tài khoản Google hiện tại (credential linking)
  /// Sau đó user có thể đăng nhập bằng cả Google lẫn email/password
  Future<void> linkEmailPassword(String password) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Chưa đăng nhập');
    if (user.email == null) throw Exception('Tài khoản không có email');

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.linkWithCredential(credential);
      await _db.collection('users').doc(user.uid).update({
        'authProvider': 'google+email',
        'hasPassword': true,
      });
    } on FirebaseAuthException catch (e) {
      if (e.code == 'provider-already-linked') {
        throw Exception('Tài khoản đã có mật khẩu');
      }
      if (e.code == 'credential-already-in-use') {
        throw Exception('Email này đã được sử dụng bởi tài khoản khác');
      }
      throw Exception(_handleAuthError(e));
    }
  }

  /// Đăng xuất cả Firebase Auth lẫn Google Sign-In cùng lúc
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_provider');
    await prefs.remove('auth_email');
    await prefs.remove('auth_password');
    await Future.wait([_auth.signOut(), _googleSignIn.signOut()]);
  }

  /// Khôi phục phiên đăng nhập thủ công nếu Firebase Auth bị mất session trên Android
  Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final provider = prefs.getString('auth_provider');
    if (provider == 'google') {
      try {
        final googleUser = await _googleSignIn.signInSilently();
        if (googleUser != null) {
          final googleAuth = await googleUser.authentication;
          final credential = GoogleAuthProvider.credential(
            accessToken: googleAuth.accessToken,
            idToken: googleAuth.idToken,
          );
          await _auth.signInWithCredential(credential);
        }
      } catch (e) {
        // ignore
      }
    } else if (provider == 'email') {
      final e = prefs.getString('auth_email');
      final p = prefs.getString('auth_password');
      if (e != null && p != null) {
        try {
          await login(e, p);
        } catch (e) {
          // ignore
        }
      }
    }
  }

  User? get currentUser => _auth.currentUser;
  bool get isLoggedIn => _auth.currentUser != null;

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
