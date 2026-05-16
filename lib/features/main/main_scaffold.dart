import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/ui_service.dart';
import '../../config/admin_config.dart';

// ── Branch indices trong GoRouter StatefulNavigationShell ──────────────────
// Thứ tự này phải khớp với thứ tự khai báo branches trong app_router.dart.
// Branches: 0=home, 1=library, 2=follow, 3=admin(admin only), 4=settings
abstract class _Branch {
  static const admin = 3; // Chỉ tồn tại cho Admin users
  static const settings = 4; // Branch 4 với Admin, branch 3 với User thường
}

// ── UI tab indices (NavigationBar) ─────────────────────────────────────────
// Admin thấy 5 tabs: Home, Library, Follow, Admin, Settings.
// User thấy 4 tabs:  Home, Library, Follow, Settings.
// Tabs: 0=home, 1=library, 2=follow, 3=admin|settings, 4=settings(admin only)
abstract class _Tab {
  static const adminOrSettings = 3; // Admin tab cho admin / Settings cho user
}

// MainScaffold là shell bao quanh toàn bộ app — chứa bottom navigation bar
// và nhúng nội dung các nhánh route thông qua StatefulNavigationShell của go_router.
class MainScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const MainScaffold({super.key, required this.navigationShell});

  /// Chuyển router branch index → UI tab index để highlight đúng tab.
  int _branchToTab(int branchIndex, bool isAdmin) {
    if (isAdmin) return branchIndex; // Admin: 1-to-1 mapping
    // User thường: branch 3 (admin) không tồn tại, branch 4 (settings) → tab 3
    if (branchIndex == _Branch.settings) return _Tab.adminOrSettings;
    if (branchIndex == _Branch.admin) {
      return 0; // fallback: admin route → home tab
    }
    return branchIndex;
  }

  /// Chuyển UI tab index → router branch index khi user tap tab.
  int _tabToBranch(int tabIndex, bool isAdmin) {
    if (isAdmin) return tabIndex; // Admin: 1-to-1 mapping
    // User thường: tab 3 (Settings) → branch 4 (settings)
    if (tabIndex == _Tab.adminOrSettings) return _Branch.settings;
    return tabIndex;
  }

  @override
  Widget build(BuildContext context) {
    final currentUserEmail = FirebaseAuth.instance.currentUser?.email;
    final isAdmin = AdminConfig.isAdmin(currentUserEmail);
    final navIndex = _branchToTab(navigationShell.currentIndex, isAdmin);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: UiService.instance.isMainBottomBarVisible,
        builder: (context, isVisible, child) {
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) {
              return SizeTransition(
                sizeFactor: animation,
                axisAlignment: -1,
                child: child,
              );
            },
            child: isVisible
                ? NavigationBarTheme(
                    data: NavigationBarThemeData(
                      backgroundColor: Theme.of(
                        context,
                      ).bottomNavigationBarTheme.backgroundColor,
                      indicatorColor: Colors.redAccent.withValues(alpha: 0.15),
                      labelTextStyle: WidgetStateProperty.all(
                        const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    child: NavigationBar(
                      selectedIndex: navIndex,
                      onDestinationSelected: (index) {
                        final targetBranch = _tabToBranch(index, isAdmin);
                        navigationShell.goBranch(
                          targetBranch,
                          initialLocation:
                              targetBranch == navigationShell.currentIndex,
                        );
                      },
                      destinations: [
                        const NavigationDestination(
                          icon: Icon(Icons.home_outlined),
                          selectedIcon: Icon(Icons.home),
                          label: 'Trang chủ',
                        ),
                        const NavigationDestination(
                          icon: Icon(Icons.collections_bookmark_outlined),
                          selectedIcon: Icon(Icons.collections_bookmark),
                          label: 'Thư viện',
                        ),
                        const NavigationDestination(
                          icon: Icon(Icons.favorite_border),
                          selectedIcon: Icon(Icons.favorite),
                          label: 'Theo dõi',
                        ),
                        if (isAdmin)
                          const NavigationDestination(
                            icon: Icon(Icons.admin_panel_settings_outlined),
                            selectedIcon: Icon(Icons.admin_panel_settings),
                            label: 'Quản trị',
                          ),
                        const NavigationDestination(
                          icon: Icon(Icons.settings_outlined),
                          selectedIcon: Icon(Icons.settings),
                          label: 'Cài đặt',
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}
