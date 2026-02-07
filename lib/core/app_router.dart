import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../features/home/home_page.dart';
import '../features/library/library_page.dart';
import '../features/library/custom_library_page.dart';
import '../features/library/edit_categories_page.dart';
import '../features/settings/settings_page.dart';
import '../features/settings/account/account_page.dart';
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
import '../data/models_cloud.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/auth-check',
  routes: [
    GoRoute(path: '/auth-check', builder: (_, __) => const _AuthCheckPage()),
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
              builder: (_, __) => const AdminDashboardPage(),
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

    GoRoute(
      path: '/detail/:id',
      builder: (context, state) =>
          MangaDetailPage(mangaId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/reader/:chapterId',
      builder: (context, state) =>
          ReaderPage(chapterId: state.pathParameters['chapterId']!),
    ),
    GoRoute(
      path: '/search-global',
      builder: (context, state) =>
          SearchPage(initialGenre: state.uri.queryParameters['genre']),
    ),
    GoRoute(
      path: '/notifications',
      builder: (context, state) => const NotificationListPage(),
    ),
    GoRoute(
      path: '/downloads',
      builder: (context, state) => const DownloadQueuePage(),
    ),
    GoRoute(
      path: '/admin/chapters',
      builder: (context, state) {
        final manga = state.extra as CloudManga;
        return ChapterManagerPage(manga: manga);
      },
    ),
  ],
);

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
