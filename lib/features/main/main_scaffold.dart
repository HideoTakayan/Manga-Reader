import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/ui_service.dart';

class MainScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainScaffold({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    final currentUserEmail = FirebaseAuth.instance.currentUser?.email;
    final isAdmin =
        currentUserEmail == 'admin@gmail.com' ||
        currentUserEmail == 'anhlasinhvien2k51@gmail.com';

    /*
      Hệ thống Router Branch cố định:
      0: Trang chủ
      1: Thư viện (Custom)
      2: Theo dõi (Old Library)
      3: Quản trị
      4: Cài đặt
    */

    // Tính toán index hiển thị trên Bottom Bar
    int navIndex;
    if (isAdmin) {
      // Admin thấy đủ 5 tab -> Index khớp 1:1
      navIndex = navigationShell.currentIndex;
    } else {
      // User thường chỉ thấy 4 tab: 0, 1, 2, 4
      if (navigationShell.currentIndex == 4) {
        navIndex = 3; // Cài đặt (Router 4) hiển thị ở vị trí 3 trên UI
      } else if (navigationShell.currentIndex == 3) {
        navIndex = 0; // Backup, Admin page k nên được truy cập bởi User
      } else {
        navIndex = navigationShell.currentIndex;
      }
    }

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
                      indicatorColor: Colors.redAccent.withOpacity(0.15),
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
                        int targetBranch;
                        if (isAdmin) {
                          targetBranch = index;
                        } else {
                          targetBranch = (index == 3) ? 4 : index;
                        }

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
