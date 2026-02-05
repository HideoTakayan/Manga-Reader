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

  PaintingBinding.instance.imageCache
    ..maximumSize = 100
    ..maximumSizeBytes = 80 << 20; // ~80MB

  await _initFirebase();

  // Notification Service không cần init phức tạp nữa (Thuần In-App)

  try {
    await DriveService.instance.restorePreviousSession();
    debugPrint('✅ Drive Session Restored');
  } catch (e) {
    debugPrint('⚠️ Drive Session Restore Failed: $e');
  }
  runApp(const ProviderScope(child: ComicApp()));
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
    // Luôn bắt buộc Dark Mode
    return MaterialApp.router(
      title: 'Comic Reader',
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark, // Bắt buộc chế độ tối (Dark Mode)
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
