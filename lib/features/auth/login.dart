import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';

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

  bool isLogin = true;
  bool _obscure = true;
  bool _obscureConfirm = true;

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

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
        await _auth.login(email, password);
      } else {
        await _auth.register(email, password, name);
      }

      EasyLoading.dismiss();

      if (mounted) {
        if (!isLogin) {
          EasyLoading.showSuccess(
            'Đăng ký thành công! Kiểm tra email xác minh.',
          );
        }

        context.go('/');
      }
    } catch (e) {
      EasyLoading.showError(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _signInWithGoogle() async {
    EasyLoading.show(status: 'Đang đăng nhập...');

    try {
      await _auth.signInWithGoogle();
      EasyLoading.dismiss();

      if (mounted) {
        context.go('/');
      }
    } catch (e) {
      EasyLoading.showError(e.toString().replaceAll('Exception: ', ''));
    }
  }

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
      fillColor: const Color(0xFF1A1A1C),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.orange.shade400, width: 1.4),
      ),
    );
  }

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
      backgroundColor: const Color(0xFF0E0E10),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 🔹 Icon quyển sách
              Icon(
                Icons.menu_book_rounded,
                color: Colors.orange.shade400,
                size: 85,
              ),

              // 🔹 Thêm chữ "MangaReader" ngay dưới icon
              const SizedBox(height: 10),
              Text(
                'MangaReader',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: Colors.orange.shade400,
                  shadows: [
                    Shadow(
                      color: Colors.orange.shade700.withOpacity(0.6),
                      offset: const Offset(0, 3),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 25),

              // 🔹 Tiêu đề đăng nhập / đăng ký
              Text(
                isLogin ? 'Đăng nhập' : 'Tạo tài khoản',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 35),

              if (!isLogin) ...[
                TextField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration(
                    'Tên hiển thị',
                    Icons.person_outline,
                  ),
                ),
                const SizedBox(height: 18),
              ],

              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Email', Icons.email_outlined),
              ),
              const SizedBox(height: 18),

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

              // 🔹 Nút Quên mật khẩu
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

              const SizedBox(height: 20), // Tăng khoảng cách nếu cần

              if (!isLogin) ...[
                SizedBox(height: 10), // Adjust spacing for register mode
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
                    shadowColor: Colors.orange.withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _submit,
                  child: Text(
                    isLogin ? 'Đăng nhập' : 'Đăng ký',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Divider with "hoặc"
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade700)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'hoặc',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.grey.shade700)),
                ],
              ),

              const SizedBox(height: 20),

              // Google Sign-In Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _signInWithGoogle,
                  icon: Icon(
                    Icons.g_mobiledata_rounded,
                    size: 32,
                    color: Colors.red.shade600,
                  ),
                  label: const Text(
                    'Đăng nhập bằng Google',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                    color: Colors.orange.shade400,
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
