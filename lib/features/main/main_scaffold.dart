import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/ui_service.dart';
import '../../config/admin_config.dart';

// ── Branch indices trong GoRouter StatefulNavigationShell ──────────────────
// Thứ tự này phải khớp với thứ tự khai báo branches trong app_router.dart.
// Branches: 0=home, 1=library, 2=follow, 3=admin(admin only), 4=settings, 5=forum
abstract class _Branch {
  static const admin = 3;
  static const settings = 4;
  static const forum = 5;
  static const group = 6;
}

// MainScaffold là shell bao quanh toàn bộ app — chứa bottom navigation bar
// và nhúng nội dung các nhánh route thông qua StatefulNavigationShell của go_router.
class MainScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const MainScaffold({super.key, required this.navigationShell});

  /// Chuyển router branch index → UI tab index để highlight đúng tab.
  int _branchToTab(int branchIndex, bool isAdmin, bool hasGroup) {
    if (branchIndex == 0 || branchIndex == 1 || branchIndex == 2) return branchIndex;

    int currentTab = 3;

    if (isAdmin) {
      if (branchIndex == _Branch.admin) return currentTab;
      currentTab++;
    } else if (branchIndex == _Branch.admin) {
      return 0; // fallback home nếu vô nhầm
    }

    if (hasGroup && !isAdmin) {
      if (branchIndex == _Branch.group) return currentTab;
      currentTab++;
    } else if (branchIndex == _Branch.group) {
      return 0; // fallback
    }

    if (branchIndex == _Branch.forum) return currentTab;
    currentTab++;

    if (branchIndex == _Branch.settings) return currentTab;

    return 0;
  }

  /// Chuyển UI tab index → router branch index khi user tap tab.
  int _tabToBranch(int tabIndex, bool isAdmin, bool hasGroup) {
    if (tabIndex == 0 || tabIndex == 1 || tabIndex == 2) return tabIndex;

    int currentTab = 3;

    if (isAdmin) {
      if (tabIndex == currentTab) return _Branch.admin;
      currentTab++;
    }

    if (hasGroup && !isAdmin) {
      if (tabIndex == currentTab) return _Branch.group;
      currentTab++;
    }

    if (tabIndex == currentTab) return _Branch.forum;
    currentTab++;

    if (tabIndex == currentTab) return _Branch.settings;

    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isAdmin = AdminConfig.isAdmin(user?.email);

    return StreamBuilder<DocumentSnapshot>(
      stream: user != null
          ? FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots()
          : const Stream.empty(),
      builder: (context, snapshot) {
        bool hasGroup = false;
        if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          hasGroup = data['groupId'] != null && data['groupId'].toString().isNotEmpty;
        }

        final navIndex = _branchToTab(navigationShell.currentIndex, isAdmin, hasGroup);

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
                      indicatorColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
                      iconTheme: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return IconThemeData(color: Theme.of(context).colorScheme.primary);
                        }
                        return const IconThemeData(color: Colors.white54);
                      }),
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
                        final targetBranch = _tabToBranch(index, isAdmin, hasGroup);
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
                        if (hasGroup && !isAdmin)
                          const NavigationDestination(
                            icon: Icon(Icons.groups_outlined),
                            selectedIcon: Icon(Icons.groups),
                            label: 'Nhóm dịch',
                          ),
                        const NavigationDestination(
                          icon: Icon(Icons.forum_outlined),
                          selectedIcon: Icon(Icons.forum),
                          label: 'Diễn đàn',
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
      },
    );
  }
}
