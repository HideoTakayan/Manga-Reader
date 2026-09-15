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
import 'services/level_service.dart';
import 'features/forum/services/leaderboard_service.dart';
import 'core/app_router.dart';
import 'core/theme.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'core/utils/archive_image_extractor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Bật Android Photo Picker (giao diện chọn ảnh hiện đại dạng bottom sheet như Messenger)
  final imagePickerPlatform = ImagePickerPlatform.instance;
  if (imagePickerPlatform is ImagePickerAndroid) {
    imagePickerPlatform.useAndroidPhotoPicker = true;
  }

  try {
    PaintingBinding.instance.imageCache
      ..maximumSize = 100
      ..maximumSizeBytes = 80 << 20; // ~80MB
  } catch (_) {}

  // ❗ Chỉ Firebase là bắt buộc trước runApp
  await _initFirebase();

  // Khởi tạo folder (cần thiết để không bị lỗi path ngay khi app mở)
  try {
    await FolderService.init();
  } catch (e) {
    debugPrint('⚠️ FolderService init error: $e');
  }

  // ✅ Khởi động UI ngay — không chờ các service nặng
  runApp(const ProviderScope(child: MangaApp()));

  // Phần còn lại chạy SONG SONG sau khi UI đã hiện — không block màn hình
  _initServicesInBackground();
}

/// Khởi tạo tất cả các service nặng SAU KHI UI đã render xong
Future<void> _initServicesInBackground() async {
  // Dọn dẹp cache cũ (không quan trọng, chạy luôn nền)
  try {
    ArchiveImageExtractor.cleanUpOldCache();
  } catch (_) {}

  // Đăng ký ngôn ngữ tiếng Việt
  try {
    timeago.setLocaleMessages('vi', timeago.ViMessages());
  } catch (_) {}

  // Chạy song song để tiết kiệm thời gian
  await Future.wait([
    _tryInit('AuthService', () => AuthService.init()),
    _tryInit('NotificationService', () => NotificationService.instance.initialize()),
    _tryInit('BackgroundService', () => BackgroundService.initialize()),
    _tryInit('LevelService', () => LevelService.instance.init()),
    _tryInit('DriveSession', () => DriveService.instance.restorePreviousSession()),
  ]);

  // LeaderboardService warmup (không cần await)
  try {
    LeaderboardService.instance.initWarmup();
  } catch (_) {}

  // Preload mangas sau khi session Drive đã khôi phục
  try {
    await DriveService.instance.preheatCdn();
    await DriveService.instance.getMangas();
    debugPrint('✅ Mangas preloaded in background');
  } catch (e) {
    debugPrint('⚠️ Mangas preload failed: $e');
  }

  // Lắng nghe auth state để sync lịch sử đọc
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

  // Khôi phục session nếu Firebase Auth bị mất
  if (FirebaseAuth.instance.currentUser == null) {
    try {
      await AuthService().restoreSession().timeout(const Duration(seconds: 1));
    } catch (_) {}
  }
}

/// Helper để bọc mỗi init trong try-catch không làm crash Future.wait
Future<void> _tryInit(String name, Future<void> Function() fn) async {
  try {
    await fn();
    debugPrint('✅ $name initialized');
  } catch (e) {
    debugPrint('⚠️ $name init error: $e');
  }
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
