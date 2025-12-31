import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MainScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainScaffold({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    final isAdmin =
        FirebaseAuth.instance.currentUser?.email == 'admin@gmail.com';

    // Map branch index to visual tab index
    int selectedIndex = navigationShell.currentIndex;
    if (!isAdmin && selectedIndex == 4) {
      selectedIndex = 3; // Settings is at index 3 for non-admins
    } else if (!isAdmin && selectedIndex == 3) {
      // Should not happen if logic is correct, but safe fallback
      selectedIndex = 0;
    }

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: Theme.of(
            context,
          ).bottomNavigationBarTheme.backgroundColor,
          indicatorColor: Colors.redAccent.withOpacity(0.15),
          labelTextStyle: WidgetStateProperty.all(
            TextStyle(
              color: Theme.of(context).textTheme.bodyMedium?.color,
              fontSize: 12,
            ),
          ),
          iconTheme: WidgetStateProperty.all(
            IconThemeData(color: Theme.of(context).iconTheme.color),
          ),
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) {
            int branchIndex = index;
            // Map visual tab index to branch index
            if (!isAdmin && index >= 3) {
              branchIndex = index + 1; // Skip 'Control' branch (index 3)
            }

            navigationShell.goBranch(
              branchIndex,
              initialLocation: branchIndex == navigationShell.currentIndex,
            );
          },
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home),
              label: 'Trang chủ',
            ),
            const NavigationDestination(
              icon: Icon(Icons.favorite),
              label: 'Following',
            ),
            const NavigationDestination(
              icon: Icon(Icons.search),
              label: 'Tìm kiếm',
            ),
            if (FirebaseAuth.instance.currentUser?.email == 'admin@gmail.com')
              const NavigationDestination(
                icon: Icon(Icons.admin_panel_settings),
                label: 'Quản trị',
              ),
            const NavigationDestination(
              icon: Icon(Icons.settings),
              label: 'Cài đặt',
            ),
          ],
        ),
      ),
    );
  }
}
