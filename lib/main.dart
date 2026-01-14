import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_options.dart';
import 'data/drive_service.dart';
import 'core/app_router.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🖼️ Giới hạn cache ảnh để tránh đầy RAM
  PaintingBinding.instance.imageCache
    ..maximumSize = 100
    ..maximumSizeBytes = 80 << 20; // ~80MB

  // 🚀 Khởi tạo Firebase
  await _initFirebase();

  // ☁️ Khôi phục phiên làm việc Google Drive (nếu có)
  // Lưu ý: Việc này có thể mất chút thời gian nhưng quan trọng để load dữ liệu
  try {
    await DriveService.instance.restorePreviousSession();
    debugPrint('✅ Drive Session Restored');
  } catch (e) {
    debugPrint('⚠️ Drive Session Restore Failed: $e');
  }

  // 🧩 Chạy ứng dụng
  runApp(const ProviderScope(child: ComicApp()));

  // ========================================
  // OPTIMIZATION: Preload comics in background
  // This warms the cache for faster chapter loading
  // ========================================
  Future.microtask(() async {
    try {
      await DriveService.instance.getComics();
      debugPrint('✅ Comics preloaded in background');
    } catch (e) {
      debugPrint('⚠️ Comics preload failed: $e');
    }
  });
}

Future<void> _initFirebase() async {
  try {
    // Chỉ khởi tạo nếu chưa có app nào
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    debugPrint('✅ Firebase initialized');
  } catch (e, s) {
    debugPrint('🔥 Firebase init error: $e\n$s');
  }
}

class ComicApp extends ConsumerWidget {
  const ComicApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Force Dark Mode always
    return MaterialApp.router(
      title: 'Comic Reader',
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark, // Enforce Dark Mode
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
      builder: EasyLoading.init(
        builder: (context, child) {
          return child ?? const SizedBox.shrink();
        },
      ),
    );
  }
}
