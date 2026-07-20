import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'firebase_options.dart';
import 'data/drive_service.dart';
import 'services/folder_service.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'services/sync_service.dart';
import 'core/app_router.dart';
import 'core/theme.dart';
import 'core/utils/archive_image_extractor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  PaintingBinding.instance.imageCache
    ..maximumSize = 100
    ..maximumSizeBytes = 80 << 20; // ~80MB

  await _initFirebase();

  // Khởi tạo hệ thống thư mục
  await FolderService.init();

  // Dọn dẹp cache của Reader từ các phiên đọc trước (tránh rác hệ thống)
  ArchiveImageExtractor.clearCache();

  // Đăng ký ngôn ngữ tiếng Việt cho timeago
  timeago.setLocaleMessages('vi', timeago.ViMessages());

  // Khởi tạo Hệ thống Thông báo (Cục bộ + Trình lắng nghe Firestore)
  await NotificationService.instance.initialize();
  await BackgroundService.initialize();

  // Fix #9: Tự động sync lịch sử đọc khi user đăng nhập (hoặc kết nối mạng trở lại).
  // authStateChanges bắn event mỗi khi login state thay đổi — đây là hook tự nhiên
  // để trigger sync mà không cần package connectivity_plus.
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user != null) {
      Future.microtask(() => SyncService.instance.syncPendingHistory());
    }
  });

  try {
    await DriveService.instance.restorePreviousSession();
    debugPrint('✅ Drive Session Restored');
  } catch (e) {
    debugPrint('⚠️ Drive Session Restore Failed: $e');
  }
  runApp(const ProviderScope(child: MangaApp()));
  Future.microtask(() async {
    try {
      await DriveService.instance.getMangas();
      debugPrint('✅ Mangas preloaded in background');
    } catch (e) {
      debugPrint('⚠️ Mangas preload failed: $e');
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

class MangaApp extends ConsumerWidget {
  const MangaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Luôn bắt buộc Dark Mode
    return MaterialApp.router(
      title: 'Manga Reader',
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
