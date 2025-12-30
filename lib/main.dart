import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'core/app_router.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🖼️ Giới hạn cache ảnh để tránh đầy RAM
  PaintingBinding.instance.imageCache
    ..maximumSize = 100
    ..maximumSizeBytes = 80 << 20; // ~80MB

  // 🚀 Khởi tạo Firebase an toàn (dành cho hot reload)
  await _initFirebase();

  // 🧩 Chạy ứng dụng
  runApp(const ComicApp());
}

Future<void> _initFirebase() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        name: 'comic_app',
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    debugPrint('✅ Firebase initialized');
  } catch (e, s) {
    debugPrint('🔥 Firebase init error: $e\n$s');
  }
}

class ComicApp extends StatelessWidget {
  const ComicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Comic Reader',
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
      builder: EasyLoading.init(
        builder: (context, child) {
          // 🌗 Thêm hiệu ứng chuyển theme mượt mà
          return AnimatedTheme(
            data: AppTheme.dark,
            duration: const Duration(milliseconds: 300),
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}
