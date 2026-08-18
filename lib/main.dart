import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manga_reader/services/auth_service.dart';
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

  try {
    PaintingBinding.instance.imageCache
      ..maximumSize = 100
      ..maximumSizeBytes = 80 << 20; // ~80MB
  } catch (_) {}

  await _initFirebase();

  // Khởi tạo hệ thống thư mục
  try {
    await FolderService.init();
  } catch (e) {
    debugPrint('⚠️ FolderService init error: $e');
  }

  // Dọn dẹp cache rác cũ hơn 7 ngày từ các phiên trước
  try {
    ArchiveImageExtractor.cleanUpOldCache();
  } catch (_) {}

  // Đăng ký ngôn ngữ tiếng Việt cho timeago
  try {
    timeago.setLocaleMessages('vi', timeago.ViMessages());
  } catch (_) {}

  // Khởi tạo Hệ thống Thông báo (Cục bộ + Trình lắng nghe Firestore)
  try {
    await NotificationService.instance.initialize();
  } catch (e) {
    debugPrint('⚠️ NotificationService init error: $e');
  }

  try {
    await BackgroundService.initialize();
  } catch (e) {
    debugPrint('⚠️ BackgroundService init error: $e');
  }

  // Khởi tạo trạng thái đăng nhập từ bộ nhớ máy (hỗ trợ đọc offline khi mất mạng)
  try {
    await AuthService.init();
  } catch (e) {
    debugPrint('⚠️ AuthService.init error: $e');
  }

  // Tự động sync lịch sử đọc khi user đăng nhập (hoặc kết nối mạng trở lại).
  try {
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        AuthService.isPersistedLoggedIn = true;
        AuthService.persistedUid = user.uid;
        AuthService.persistedEmail = user.email ?? '';
        AuthService.persistedName = user.displayName ?? '';
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_logged_in', true);
        await prefs.setString('user_uid', user.uid);
        Future.microtask(() => SyncService.instance.syncPendingHistory());
      }
    });
  } catch (_) {}

  // Khôi phục thủ công phiên đăng nhập nếu Firebase Auth bị mất session
  if (FirebaseAuth.instance.currentUser == null) {
    try {
      await AuthService().restoreSession().timeout(const Duration(seconds: 1));
    } catch (_) {}
  }

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
    final themeMode = ref.watch(themeProvider);

    return MaterialApp.router(
      title: 'Manga Reader',
      theme: AppTheme.getTheme(themeMode),
      darkTheme: AppTheme.getTheme(themeMode),
      themeMode: ThemeMode.dark, // Luôn duy trì giao diện tối bảo vệ mắt
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
