import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Các trang
import '../pages/home/home_page.dart';
import '../pages/library/following_page.dart';
import '../pages/chatpage/chat_page.dart';
import '../pages/settings/settings_page.dart';
import '../pages/settings/account/account_page.dart';
import '../pages/settings/account/edit_profile_page.dart';
import '../features/auth/login.dart';
import '../features/detail/comic_detail_page.dart';
import '../features/reader/reader_page.dart';
import '../pages/search/search_page.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/auth-check',
  routes: [
    // Kiểm tra đăng nhập
    GoRoute(
      path: '/auth-check',
      builder: (_, __) => const _AuthCheckPage(),
    ),

    // Trang đăng nhập
    GoRoute(
      path: '/login',
      builder: (_, __) => const LoginPage(),
    ),

    // Các trang chính (đã bỏ ShellRoute, vì HomePage có bottom nav riêng)
    GoRoute(
      path: '/',
      builder: (_, __) => const HomePage(),
    ),
    GoRoute(
      path: '/library/following',
      builder: (_, __) => const FollowingPage(),
    ),
    GoRoute(
      path: '/chatpage',
      builder: (_, __) => const ChatPage(),
    ),
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

    // Chi tiết truyện
    GoRoute(
      path: '/detail/:id',
      builder: (context, state) =>
          ComicDetailPage(comicId: state.pathParameters['id']!),
    ),

    // Đọc truyện
    GoRoute(
      path: '/reader/:chapterId',
      builder: (context, state) =>
          ReaderPage(chapterId: state.pathParameters['chapterId']!),
    ),

    // Search
    GoRoute(
      path: '/search',
      builder: (_, __) => const SearchPage(),
    ),
  ],
);

/// Trang kiểm tra login
class _AuthCheckPage extends StatelessWidget {
  const _AuthCheckPage({super.key});

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

        WidgetsBinding.instance.addPostFrameCallback(
          (_) => context.go('/'),
        );
        return const SizedBox.shrink();
      },
    );
  }
}
