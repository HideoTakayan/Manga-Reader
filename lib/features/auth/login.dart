import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';

// Trang đăng nhập / đăng ký .
// Giao tiếp hoàn toàn qua AuthService, không tự gọi Firebase trực tiếp.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  final _auth = AuthService();

  bool isLogin = true; // true = form đăng nhập, false = form đăng ký
  bool _obscure = true; // Ẩn/hiện mật khẩu
  bool _obscureConfirm = true; // Ẩn/hiện ô xác nhận mật khẩu

  // Xử lý submit cho cả 2 luồng (đăng nhập + đăng ký) trong cùng 1 hàm.
  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    // Validate: đăng ký cần thêm tên + xác nhận mật khẩu
    if (!isLogin) {
      if (name.isEmpty ||
          email.isEmpty ||
          password.isEmpty ||
          confirm.isEmpty) {
        EasyLoading.showError('Vui lòng nhập đầy đủ thông tin');
        return;
      }
      if (password != confirm) {
        EasyLoading.showError('Mật khẩu xác nhận không khớp');
        return;
      }
    } else {
      if (email.isEmpty || password.isEmpty) {
        EasyLoading.showError('Vui lòng nhập email và mật khẩu');
        return;
      }
    }

    EasyLoading.show(status: isLogin ? 'Đang đăng nhập...' : 'Đang đăng ký...');

    try {
      if (isLogin) {
        await _auth.login(
          email,
          password,
        ); // Firebase signInWithEmailAndPassword
      } else {
        await _auth.register(
          email,
          password,
          name,
        ); // Firebase createUserWithEmailAndPassword
      }

      EasyLoading.dismiss();

      if (mounted) {
        if (!isLogin) {
          // Nhắc user kiểm tra email xác minh sau khi đăng ký thành công
          EasyLoading.showSuccess(
            'Đăng ký thành công! Kiểm tra email xác minh.',
          );
        }
        context.go(
          '/',
        ); // Điều hướng về Home sau khi đăng nhập/đăng ký thành công
      }
    } catch (e) {
      // AuthService ném Exception với message tiếng Việt — xóa prefix "Exception: " cho gọn
      EasyLoading.showError(e.toString().replaceAll('Exception: ', ''));
    }
  }

  // Đăng nhập bằng Google OAuth — AuthService xử lý toàn bộ luồng popup + token.
  Future<void> _signInWithGoogle() async {
    EasyLoading.show(status: 'Đang đăng nhập...');
    try {
      await _auth.signInWithGoogle();
      EasyLoading.dismiss();
      if (mounted) context.go('/');
    } catch (e) {
      EasyLoading.showError(e.toString().replaceAll('Exception: ', ''));
    }
  }

  // Helper tạo InputDecoration đồng nhất cho tất cả TextField trong form.
  // suffix dùng để gắn nút show/hide mật khẩu.
  InputDecoration _inputDecoration(
    String label,
    IconData icon, {
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70, fontSize: 15),
      prefixIcon: Icon(icon, color: Colors.orange.shade300),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.white10),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.white10),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.orange.shade400, width: 1.5),
      ),
    );
  }

  // Dialog quên mật khẩu: nhập email → gọi AuthService.sendPasswordResetEmail() → Firebase gửi link.
  // Pre-fill email từ ô email trên form để tiện cho user.
  Future<void> _showForgotPasswordDialog() async {
    final resetEmailCtrl = TextEditingController(text: _emailCtrl.text);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Quên mật khẩu?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Nhập email của bạn để nhận liên kết đặt lại mật khẩu.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: resetEmailCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Email', Icons.email_outlined),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = resetEmailCtrl.text.trim();
              if (email.isEmpty) {
                EasyLoading.showError('Vui lòng nhập email');
                return;
              }
              Navigator.pop(ctx);
              EasyLoading.show(status: 'Đang gửi...');
              try {
                await _auth.sendPasswordResetEmail(email);
                EasyLoading.showSuccess('Đã gửi email khôi phục!');
              } catch (e) {
                EasyLoading.showError(
                  e.toString().replaceAll('Exception: ', ''),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade400,
              foregroundColor: Colors.black,
            ),
            child: const Text('Gửi'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient Mesh
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1E0B2D), // Deep Purple
                  Color(0xFF0E0E10), // Black
                  Color(0xFF3B1010), // Dark Red
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),
          
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 20,
                          spreadRadius: -5,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.menu_book_rounded,
                          color: Colors.orange.shade400,
                          size: 70,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'MangaReader',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: Colors.orange.shade400,
                            shadows: [
                              Shadow(
                                color: Colors.orange.shade700.withValues(alpha: 0.6),
                                offset: const Offset(0, 3),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 25),
                        Text(
                          isLogin ? 'Đăng nhập' : 'Tạo tài khoản',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 30),
                        if (!isLogin) ...[
                          TextField(
                            controller: _nameCtrl,
                            style: const TextStyle(color: Colors.white),
                            decoration: _inputDecoration(
                              'Tên hiển thị',
                              Icons.person_outline,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration('Email', Icons.email_outlined),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passCtrl,
                          obscureText: _obscure,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration(
                            'Mật khẩu',
                            Icons.lock_outline,
                            suffix: IconButton(
                              icon: Icon(
                                _obscure ? Icons.visibility_off : Icons.visibility,
                                color: Colors.orange.shade300,
                              ),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (isLogin)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _showForgotPasswordDialog,
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 0),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'Quên mật khẩu?',
                                style: TextStyle(
                                  color: Colors.orange.shade300,
                                  fontSize: 14,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 20),
                        if (!isLogin) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: _confirmCtrl,
                            obscureText: _obscureConfirm,
                            style: const TextStyle(color: Colors.white),
                            decoration: _inputDecoration(
                              'Xác nhận mật khẩu',
                              Icons.lock_outline,
                              suffix: IconButton(
                                icon: Icon(
                                  _obscureConfirm
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.orange.shade300,
                                ),
                                onPressed: () =>
                                    setState(() => _obscureConfirm = !_obscureConfirm),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                        ] else
                          const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade400,
                              foregroundColor: Colors.black,
                              elevation: 4,
                              shadowColor: Colors.orange.withValues(alpha: 0.4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: _submit,
                            child: Text(
                              isLogin ? 'Đăng nhập' : 'Đăng ký',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.2))),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'hoặc',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.2))),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.1),
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.transparent),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: _signInWithGoogle,
                            icon: Icon(
                              Icons.g_mobiledata_rounded,
                              size: 36,
                              color: Colors.red.shade400,
                            ),
                            label: const Text(
                              'Đăng nhập bằng Google',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextButton(
                          onPressed: () => setState(() => isLogin = !isLogin),
                          child: Text(
                            isLogin
                                ? 'Chưa có tài khoản? Đăng ký ngay'
                                : 'Đã có tài khoản? Đăng nhập',
                            style: TextStyle(
                              color: Colors.orange.shade300,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
