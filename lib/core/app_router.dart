import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../features/home/home_page.dart';
import '../features/library/library_page.dart';
import '../features/library/custom_library_page.dart';
import '../features/library/edit_categories_page.dart';
import '../features/settings/settings_page.dart';
import '../features/settings/account/account_page.dart';
import '../features/settings/account/edit_profile_page.dart';
import '../features/settings/help_page.dart';
import '../features/auth/login.dart';
import '../features/detail/manga_detail_page.dart';
import '../features/reader/reader_page.dart';
import '../features/search/search_page.dart';
import '../features/main/main_scaffold.dart';
import '../features/notification/notification_list_page.dart';
import '../features/admin/admin_dashboard_page.dart';
import '../features/admin/chapter_manager_page.dart';
import '../features/downloads/download_queue_page.dart';
import '../features/backup/backup_restore_page.dart';
import '../features/storage/storage_manager_page.dart';
import '../features/library/reading_analytics_page.dart';
import '../features/reader/local_novel_reader_page.dart';
import '../data/models_cloud.dart';
import '../services/novel_service.dart';
import '../config/admin_config.dart';

// Cấu hình GoRouter chính của ứng dụng
final GoRouter appRouter = GoRouter(
  initialLocation:
      '/auth-check', // Trang mặc định ban đầu để kiểm tra trạng thái đăng nhập
  routes: [
    // Route kiểm tra trạng thái đăng nhập ban đầu (màn hình trấn an), tự động chuyển hướng sau khi check Firebase Auth
    GoRoute(path: '/auth-check', builder: (_, __) => const _AuthCheckPage()),
    // Route trang đăng nhập / đăng ký (hiển thị khi chưa có tài khoản hoặc chưa đăng nhập)
    GoRoute(path: '/login', builder: (_, __) => const LoginPage()),

    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return MainScaffold(navigationShell: navigationShell);
      },
      branches: [
        // Index 0: Trang chủ
        StatefulShellBranch(
          routes: [GoRoute(path: '/', builder: (_, __) => const HomePage())],
        ),
        // Index 1: Thư viện
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/my-library',
              builder: (_, __) => const CustomLibraryPage(),
            ),
          ],
        ),
        // Index 2: Theo dõi
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/following',
              builder: (_, __) => const LibraryPage(),
            ),
          ],
        ),
        // Index 3: Admin (Sẽ bị ẩn ở UI nếu k phải admin)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/control',
              builder: (context, state) =>
                  _AdminRouteGuard(child: const AdminDashboardPage()),
            ),
          ],
        ),
        // Index 4: Cài đặt
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (_, __) => const SettingsPage(),
              routes: [
                GoRoute(
                  path: 'account',
                  builder: (_, __) => const AccountPage(),
                  routes: [
                    GoRoute(
                      path: 'edit',
                      builder: (_, __) => const EditProfilePage(),
                    ),
                  ],
                ),
                GoRoute(path: 'help', builder: (_, __) => const HelpPage()),
                GoRoute(
                  path: 'categories',
                  builder: (_, __) => const EditCategoriesPage(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),

    // Route trang chi tiết truyện - nhận mangaId qua URL (/detail/abc123)
    GoRoute(
      path: '/detail/:id',
      builder: (context, state) =>
          MangaDetailPage(mangaId: state.pathParameters['id']!),
    ),
    // Route màn hình đọc truyện - nhận chapterId qua URL (/reader/xyz789)
    GoRoute(
      path: '/reader/:chapterId',
      builder: (context, state) =>
          ReaderPage(chapterId: state.pathParameters['chapterId']!),
    ),
    // Route trang tìm kiếm toàn cục - có thể nhận query parameter ?genre=Action
    GoRoute(
      path: '/search-global',
      builder: (context, state) =>
          SearchPage(initialGenre: state.uri.queryParameters['genre']),
    ),

    // Route trang thống kê đọc (Analytics)
    GoRoute(
      path: '/analytics',
      builder: (context, state) => const ReadingAnalyticsPage(),
    ),
    // Route trang danh sách thông báo của người dùng
    GoRoute(
      path: '/notifications',
      builder: (context, state) => const NotificationListPage(),
    ),
    // Route trang quản lý hàng đợi tải xuống (xem tiến độ, tạm dừng, xóa)
    // Được gọi từ: nút Đười tải xuống trong settings_page
    GoRoute(
      path: '/downloads',
      builder: (context, state) => const DownloadQueuePage(),
    ),
    GoRoute(
      path: '/storage',
      builder: (context, state) => const StorageManagerPage(),
    ),
    GoRoute(
      path: '/backup',
      builder: (context, state) => const BackupRestorePage(),
    ),
    // Route màn hình đọc truyện chữ (EPUB) cục bộ — nhận LocalNovel qua state.extra
    GoRoute(
      path: '/novel-reader',
      builder: (context, state) {
        if (state.extra is! LocalNovel) {
          return const _MissingRouteDataPage();
        }
        final novel = state.extra as LocalNovel;
        return LocalNovelReaderPage(novel: novel);
      },
    ),
    // Route trang quản lý chương dành cho Admin - nhận object CloudManga qua state.extra
    GoRoute(
      path: '/admin/chapters',
      builder: (context, state) {
        if (!AdminConfig.isAdmin(FirebaseAuth.instance.currentUser?.email)) {
          return const _ForbiddenPage();
        }
        if (state.extra is! CloudManga) {
          return const _NotFoundPage(
            returnPath: '/admin/control',
            returnLabel: 'Về trang quản trị',
          );
        }
        final manga = state.extra as CloudManga;
        return ChapterManagerPage(manga: manga);
      },
    ),
  ],
);

// Widget dùng để kiểm tra trạng thái xác thực người dùng ban đầu
// Tự động chuyển hướng tới màn hình trang chủ nếu đã đăng nhập, ngược lại ra màn hình đăng nhập.
class _AuthCheckPage extends StatelessWidget {
  const _AuthCheckPage();
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snapshot.hasData) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => context.go('/login'),
          );
          return const SizedBox.shrink();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) => context.go('/'));
        return const SizedBox.shrink();
      },
    );
  }
}

class _AdminRouteGuard extends StatelessWidget {
  final Widget child;
  const _AdminRouteGuard({required this.child});

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (!AdminConfig.isAdmin(email)) return const _ForbiddenPage();
    return child;
  }
}

class _ForbiddenPage extends StatelessWidget {
  const _ForbiddenPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Không có quyền truy cập')),
      body: Center(
        child: FilledButton(
          onPressed: () => context.go('/'),
          child: const Text('Về trang chủ'),
        ),
      ),
    );
  }
}

class _MissingRouteDataPage extends StatelessWidget {
  const _MissingRouteDataPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Không tìm thấy dữ liệu')),
      body: Center(
        child: FilledButton(
          onPressed: () => context.go('/'),
          child: const Text('Về trang chủ'),
        ),
      ),
    );
  }
}

class _NotFoundPage extends StatelessWidget {
  final String returnPath;
  final String returnLabel;
  const _NotFoundPage({
    this.returnPath = '/',
    this.returnLabel = 'Về trang chủ',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: ValueKey(returnLabel),
      appBar: AppBar(title: const Text('Không tìm thấy dữ liệu')),
      body: Center(
        child: FilledButton(
          onPressed: () => context.go(returnPath),
          child: const Text('Về trang quản trị'),
        ),
      ),
    );
  }
}
