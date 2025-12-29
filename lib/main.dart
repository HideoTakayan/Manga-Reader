import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isObscured = true;

  // --- ĐÂY LÀ NƠI CHỨA CÁC SỰ KIỆN CỦA BẠN ---
  void _handleLogin() {
    // Sự kiện khi ấn nút Đăng nhập
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sự kiện: Đang xử lý đăng nhập...')),
    );
    print("Event: Login Clicked");
  }

  void _handleRegister() {
    // Sự kiện khi ấn vào Đăng ký ngay
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sự kiện: Chuyển sang màn hình đăng ký...')),
    );
    print("Event: Register Clicked");
  }
  // ------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Đăng nhập',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('Chào mừng trở lại!', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 40),

              // Email
              TextField(
                decoration: InputDecoration(
                  hintText: 'Email',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),

              // Mật khẩu
              TextField(
                obscureText: _isObscured,
                decoration: InputDecoration(
                  hintText: 'Mật khẩu',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_isObscured ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _isObscured = !_isObscured),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 30),

              // SỰ KIỆN 1: NÚT ĐĂNG NHẬP
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _handleLogin, // Gọi hàm sự kiện đăng nhập
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF0F4F9),
                    foregroundColor: const Color(0xFF4A6FA5),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: const Text('Đăng nhập', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 24),

              // SỰ KIỆN 2: DÒNG ĐĂNG KÝ
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Chưa có tài khoản? "),
                  GestureDetector(
                    onTap: _handleRegister, // Gọi hàm sự kiện đăng ký
                    child: const Text(
                      "Đăng ký ngay",
                      style: TextStyle(
                        color: Color(0xFF4A6FA5),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}