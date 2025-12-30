import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  // Đăng ký
  Future<void> register(String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = cred.user;
    if (user != null) {
      // Tạo document trong Firestore
      await _firestore.collection('users').doc(user.uid).set({
        'email': email,
        'name': '', // ban đầu để trống
        'avatar': '',
        'bio': '',
        'following': [],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // Đăng nhập
  Future<void> login(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // Đăng xuất
  Future<void> logout() async {
    await _auth.signOut();
  }
}
