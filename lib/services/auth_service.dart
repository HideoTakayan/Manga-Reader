import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

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
  /// 🔹 ĐỔI MẬT KHÂU
  /// ----------------------------
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Người dùng chưa đăng nhập');

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

  /// ----------------------------
  /// 🔹 QUÊN MẬT KHÂU (GỬI EMAIL)
  /// ----------------------------
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw Exception(_handleAuthError(e));
    }
  }

  /// ----------------------------
  /// 🔹 ĐĂNG NHẬP BẰNG GOOGLE
  /// ----------------------------
  Future<void> signInWithGoogle() async {
    try {
      // 0. Sign out first to force account picker
      await _googleSignIn.signOut();

      // 1. Trigger Google Sign-In flow (will show account picker)
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        // User cancelled the sign-in
        throw Exception('Đăng nhập bị hủy');
      }

      // 2. Obtain auth details
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // 3. Create Firebase credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 4. Sign in to Firebase
      final userCredential = await _auth.signInWithCredential(credential);

      // 5. Check if profile exists (sync Auth <-> Firestore)
      final userDoc = await _db
          .collection('users')
          .doc(userCredential.user!.uid)
          .get();

      if (!userDoc.exists) {
        // Create user profile if missing (fix for existing Auth users without Firestore doc)
        await _createUserProfile(
          uid: userCredential.user!.uid,
          email: userCredential.user!.email!,
          name: userCredential.user!.displayName ?? 'User',
          photoUrl: userCredential.user!.photoURL,
        );
      } else if (userCredential.additionalUserInfo?.isNewUser == true) {
        // If profile exists but it's a new sign-in (rare), nice to update timestamp maybe
        // But main fix is above.
      }
    } on FirebaseAuthException catch (e) {
      throw Exception(_handleAuthError(e));
    } catch (e) {
      throw Exception('Lỗi đăng nhập Google: ${e.toString()}');
    }
  }

  /// ----------------------------
  /// 🔹 TẠO PROFILE USER MỚI
  /// ----------------------------
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

  /// ----------------------------
  /// 🔹 LINK EMAIL/PASSWORD VỚI TÀI KHOẢN GOOGLE
  /// ----------------------------
  /// Cho phép user đã đăng nhập bằng Google thêm password
  /// để có thể đăng nhập bằng email/password sau này
  Future<void> linkEmailPassword(String password) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('Chưa đăng nhập');
    }

    if (user.email == null) {
      throw Exception('Tài khoản không có email');
    }

    try {
      // Create email/password credential
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );

      // Link with current account
      await user.linkWithCredential(credential);

      // Update Firestore to track both auth methods
      await _db.collection('users').doc(user.uid).update({
        'authProvider': 'google+email',
        'hasPassword': true,
      });
    } on FirebaseAuthException catch (e) {
      if (e.code == 'provider-already-linked') {
        throw Exception('Tài khoản đã có mật khẩu');
      } else if (e.code == 'credential-already-in-use') {
        throw Exception('Email này đã được sử dụng bởi tài khoản khác');
      }
      throw Exception(_handleAuthError(e));
    }
  }

  /// ----------------------------
  /// 🔹 ĐĂNG XUẤT
  /// ----------------------------
  Future<void> logout() async {
    await Future.wait([_auth.signOut(), _googleSignIn.signOut()]);
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
