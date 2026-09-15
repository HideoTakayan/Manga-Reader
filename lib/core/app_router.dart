import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
import '../features/forum/forum_shell_page.dart';
import '../features/forum/forum_post_detail_page.dart';
import '../features/forum/forum_create_post_page.dart';
import '../features/notification/notification_list_page.dart';
import '../features/admin/admin_dashboard_page.dart';
import '../features/admin/chapter_manager_page.dart';
import '../features/group/group_dashboard_page.dart';
import '../features/group/group_profile_page.dart';
import '../data/models_group.dart';
import '../features/downloads/download_queue_page.dart';
import '../features/backup/backup_restore_page.dart';
import '../features/storage/storage_manager_page.dart';
import '../features/library/reading_analytics_page.dart';
import '../features/reader/local_novel_reader_page.dart';
import '../data/models_cloud.dart';
import '../services/novel_service.dart';
import '../services/auth_service.dart';
import '../config/admin_config.dart';

// Stream wrapper để GoRouter tự động reload khi trạng thái Firebase Auth thay đổi
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen(
      (dynamic _) => notifyListeners(),
    );
  }
  late final StreamSubscription<dynamic> _subscription;
  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

// Cấu hình GoRouter chính của ứng dụng
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'rootNavigator');

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation:
      '/', // Mặc định vào thẳng Home, redirect sẽ tự chặn nếu chưa đăng nhập
  refreshListenable: GoRouterRefreshStream(
    FirebaseAuth.instance.authStateChanges(),
  ),
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    final isAuthenticated = user != null || AuthService.isPersistedLoggedIn;
    final isGoingToLogin = state.uri.path == '/login';

    // Bắt buộc đăng nhập: nếu chưa đăng nhập và không phải đang ở trang /login -> chuyển đến /login
    if (!isAuthenticated && !isGoingToLogin) {
      return '/login';
    }

    // Đã đăng nhập mà cố vào trang login -> Đẩy về trang chủ
    if (isAuthenticated && isGoingToLogin) {
      return '/';
    }

    return null;
  },
  routes: [
    // Route trang đăng nhập / đăng ký (hiển thị khi chưa có tài khoản hoặc chưa đăng nhập)
    GoRoute(path: '/login', builder: (_, __) => const LoginPage()),

    StatefulShellRoute.indexedStack(
      parentNavigatorKey: rootNavigatorKey,
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
              ],
            ),
          ],
        ),
        // Index 5: Diễn đàn
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/forum',
              builder: (context, state) {
                final tabStr = state.uri.queryParameters['tab'];
                final initialIndex = int.tryParse(tabStr ?? '') ?? 0;
                return ForumShellPage(initialIndex: initialIndex);
              },
              routes: [
                GoRoute(
                  path: 'create',
                  builder: (context, state) {
                    final type =
                        state.uri.queryParameters['type'] ?? 'discussion';
                    final manga = state.extra as CloudManga?;
                    return ForumCreatePostPage(
                      type: type,
                      initialManga: manga,
                    );
                  },
                ),
                GoRoute(
                  path: 'detail/:id',
                  builder: (context, state) =>
                      ForumPostDetailPage(postId: state.pathParameters['id']!),
                ),
              ],
            ),
          ],
        ),
        // Index 6: Nhóm dịch
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/group',
              redirect: (context, state) {
                final email = FirebaseAuth.instance.currentUser?.email;
                return AdminConfig.isAdmin(email) ? '/admin/control' : null;
              },
              builder: (_, __) => const _GroupMemberRouteGuard(),
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
    // Route màn hình đọc truyện - nhận chapterId qua URL (/reader/xyz789?page=12)
    GoRoute(
      path: '/reader/:chapterId',
      builder: (context, state) => ReaderPage(
        chapterId: state.pathParameters['chapterId']!,
        mangaId: state.uri.queryParameters['mangaId'],
        initialPageIndex: int.tryParse(state.uri.queryParameters['page'] ?? ''),
      ),
    ),
    // Route trang tìm kiếm toàn cục - có thể nhận query parameter ?q=...&genre=...&type=...
    GoRoute(
      path: '/search-global',
      builder: (context, state) => SearchPage(
        initialQuery: state.uri.queryParameters['q'],
        initialGenre: state.uri.queryParameters['genre'],
        initialContentType: state.uri.queryParameters['type'],
      ),
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
    // Route trang quản lý danh mục (Category)
    // Cung cấp cả /settings/categories và /categories để hỗ trợ mọi nơi gọi trong app
    GoRoute(
      path: '/settings/categories',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const EditCategoriesPage(),
    ),
    GoRoute(
      path: '/categories',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const EditCategoriesPage(),
    ),
    // Route trang trợ giúp FAQs & Hướng dẫn
    GoRoute(
      path: '/settings/help',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const HelpPage(),
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
    // Route hồ sơ nhóm dịch công khai
    GoRoute(
      path: '/group/profile/:id',
      builder: (context, state) {
        final groupId = state.pathParameters['id']!;
        final group = state.extra as ScanlationGroup?;
        return GroupProfilePage(groupId: groupId, initialGroup: group);
      },
    ),
  ],
);

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

/// Group Dashboard belongs to a scanlation group, not to the Admin role.
/// GoRouter redirects admins synchronously above. Group membership is stored
/// in Firestore, so this guard waits for that document before showing the
/// dashboard and keeps non-members out of an empty, misleading screen.
class _GroupMemberRouteGuard extends StatelessWidget {
  const _GroupMemberRouteGuard();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const _NotFoundPage(
        returnPath: '/settings',
        returnLabel: 'Mở cài đặt',
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data?.data();
        final groupId = data?['groupId']?.toString().trim();
        if (groupId == null || groupId.isEmpty) {
          return const _NotFoundPage(
            returnPath: '/settings',
            returnLabel: 'Mở cài đặt',
          );
        }

        return const GroupDashboardPage();
      },
    );
  }
}

class _ErrorStateScaffold extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final String headline;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _ErrorStateScaffold({
    super.key,
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.headline,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: isDark ? 0.12 : 0.08),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: iconColor.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: iconColor.withValues(alpha: isDark ? 0.2 : 0.1),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(icon, size: 54, color: iconColor),
              ),
              const SizedBox(height: 24),
              Text(
                headline,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.65),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.home_rounded, size: 18),
                label: Text(
                  actionLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForbiddenPage extends StatelessWidget {
  const _ForbiddenPage();

  @override
  Widget build(BuildContext context) {
    return _ErrorStateScaffold(
      title: 'Không có quyền',
      icon: Icons.lock_person_rounded,
      iconColor: Colors.amberAccent,
      headline: 'Không có quyền truy cập',
      message: 'Khu vực này yêu cầu quyền quản trị viên hoặc thành viên nhóm dịch. Vui lòng kiểm tra lại tài khoản của bạn.',
      actionLabel: 'Về trang chủ',
      onAction: () => context.go('/'),
    );
  }
}

class _MissingRouteDataPage extends StatelessWidget {
  const _MissingRouteDataPage();

  @override
  Widget build(BuildContext context) {
    return _ErrorStateScaffold(
      title: 'Thiếu dữ liệu',
      icon: Icons.help_outline_rounded,
      iconColor: Colors.orangeAccent,
      headline: 'Không tìm thấy dữ liệu',
      message: 'Liên kết điều hướng bị thiếu thông số hoặc dữ liệu truyện đã không còn tồn tại trên hệ thống.',
      actionLabel: 'Về trang chủ',
      onAction: () => context.go('/'),
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
    return _ErrorStateScaffold(
      key: ValueKey(returnLabel),
      title: '404',
      icon: Icons.search_off_rounded,
      iconColor: Colors.cyanAccent,
      headline: 'Trang không tồn tại',
      message: 'Đường dẫn bạn yêu cầu không thể tìm thấy hoặc đã bị di dời sang vị trí khác.',
      actionLabel: returnLabel,
      onAction: () => context.go(returnPath),
    );
  }
}

