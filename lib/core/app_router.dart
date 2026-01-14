import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Các trang
import '../features/home/home_page.dart';
import '../features/library/library_page.dart';

import '../features/settings/settings_page.dart';
import '../features/settings/account/account_page.dart';
import '../features/settings/account/edit_profile_page.dart';
import '../features/auth/login.dart';
import '../features/detail/comic_detail_page.dart';
import '../features/reader/reader_page.dart';
import '../features/search/search_page.dart';
import '../features/main/main_scaffold.dart';

import '../features/admin/admin_dashboard_page.dart';
import '../features/admin/admin_upload_page.dart';
import '../features/admin/chapter_manager_page.dart';
import '../data/models_cloud.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/auth-check',
  routes: [
    // Màn hình kiểm tra trạng thái đăng nhập
    GoRoute(path: '/auth-check', builder: (_, __) => const _AuthCheckPage()),

    // Trang đăng nhập
    GoRoute(path: '/login', builder: (_, __) => const LoginPage()),

    // Shell Route cho giao diện chính có thanh điều hướng dưới cùng (BottomNavigationBar)
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return MainScaffold(navigationShell: navigationShell);
      },
      branches: [
        // Tab 1: Home
        StatefulShellBranch(
          routes: [GoRoute(path: '/', builder: (_, __) => const HomePage())],
        ),
        // Tab 2: Library (Following)
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/library', builder: (_, __) => const LibraryPage()),
          ],
        ),
        // Tab 3: Search
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/search',
              builder: (context, state) =>
                  SearchPage(initialGenre: state.uri.queryParameters['genre']),
            ),
          ],
        ),
        // Tab 4: Control (Admin)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/control',
              builder: (_, __) => const AdminDashboardPage(),
            ),
          ],
        ),
        // Tab 5: Settings
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
              ],
            ),
          ],
        ),
      ],
    ),

    // Chi tiết truyện (Không hiện BottomBar -> Nằm ngoài Shell Route)
    GoRoute(
      path: '/detail/:id',
      builder: (context, state) =>
          ComicDetailPage(comicId: state.pathParameters['id']!),
    ),

    // Đọc truyện (Không hiện BottomBar)
    GoRoute(
      path: '/reader/:chapterId',
      builder: (context, state) =>
          ReaderPage(chapterId: state.pathParameters['chapterId']!),
    ),

    // Tìm kiếm (Trang riêng biệt - Dùng cho nút Tìm kiếm ở Home)
    GoRoute(
      path: '/search-global',
      builder: (context, state) =>
          SearchPage(initialGenre: state.uri.queryParameters['genre']),
    ),

    // Admin Dashboard
    GoRoute(path: '/admin', builder: (_, __) => const AdminDashboardPage()),
    // Admin Upload
    GoRoute(path: '/admin/upload', builder: (_, __) => const AdminUploadPage()),

    // Chapter Manager
    GoRoute(
      path: '/admin/chapters',
      builder: (context, state) {
        final comic = state.extra as CloudComic;
        return ChapterManagerPage(comic: comic);
      },
    ),
  ],
);

/// Trang kiểm tra login
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
