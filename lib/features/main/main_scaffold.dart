import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../config/admin_config.dart';
import '../../services/auth_service.dart';
import '../../services/ui_service.dart';
import '../../services/external_file_service.dart';
import '../reader/widgets/mini_tts_player.dart';

/// Branch indices are defined in app_router.dart:
/// 0: Home, 1: Library, 2: Following, 3: Admin, 4: Settings, 5: Forum, 6: Group
abstract class _Branch {
  static const home = 0;
  static const library = 1;
  static const following = 2;
  static const admin = 3;
  static const settings = 4;
  static const forum = 5;
  static const group = 6;
}

class MainScaffold extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainScaffold({super.key, required this.navigationShell});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ExternalFileService.instance.init(context);
      }
    });
  }

  List<int> _getActiveBranches(bool isAdmin, bool hasGroup) {
    final branches = <int>[
      _Branch.home,
      _Branch.library,
      _Branch.following,
    ];
    if (isAdmin) {
      branches.add(_Branch.admin);
    } else if (hasGroup) {
      branches.add(_Branch.group);
    }
    branches.add(_Branch.forum);
    branches.add(_Branch.settings);
    return branches;
  }

  int _branchToTab(int branchIndex, List<int> activeBranches) {
    final tabIndex = activeBranches.indexOf(branchIndex);
    if (tabIndex != -1) return tabIndex;
    final fallbackIndex = activeBranches.indexOf(_Branch.settings);
    return fallbackIndex != -1 ? fallbackIndex : 0;
  }

  int _tabToBranch(int tabIndex, List<int> activeBranches) {
    if (tabIndex >= 0 && tabIndex < activeBranches.length) {
      return activeBranches[tabIndex];
    }
    return _Branch.home;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isAdmin = AdminConfig.isAdmin(
      user?.email ?? AuthService.persistedEmail,
    );

    return StreamBuilder<DocumentSnapshot>(
      stream: user != null
          ? FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots()
          : const Stream.empty(),
      builder: (context, snapshot) {
        bool hasGroup = false;
        if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          final groupId = data['groupId']?.toString().trim();
          hasGroup = groupId != null && groupId.isNotEmpty;
        }

        final activeBranches = _getActiveBranches(isAdmin, hasGroup);
        final navIndex = _branchToTab(
          widget.navigationShell.currentIndex,
          activeBranches,
        );

        ExternalFileService.instance.setContext(context);

        final isHome = widget.navigationShell.currentIndex == _Branch.home;

        return PopScope(
          canPop: isHome,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            widget.navigationShell.goBranch(
              _Branch.home,
              initialLocation: true,
            );
          },
          child: Scaffold(
            body: Stack(
              children: [
                widget.navigationShell,
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: MiniTtsPlayer(),
                ),
              ],
            ),
            bottomNavigationBar: ValueListenableBuilder<bool>(
              valueListenable: UiService.instance.isMainBottomBarVisible,
              builder: (context, isVisible, child) {
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, animation) => SizeTransition(
                    sizeFactor: animation,
                    axisAlignment: -1,
                    child: child,
                  ),
                  child: isVisible
                      ? NavigationBarTheme(
                          data: NavigationBarThemeData(
                            backgroundColor: Theme.of(
                              context,
                            ).bottomNavigationBarTheme.backgroundColor,
                            indicatorColor: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.18),
                            iconTheme: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.selected)) {
                                return IconThemeData(
                                  color: Theme.of(context).colorScheme.primary,
                                );
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
                              HapticFeedback.selectionClick();
                              final targetBranch = _tabToBranch(
                                index,
                                activeBranches,
                              );
                              widget.navigationShell.goBranch(
                                targetBranch,
                                initialLocation:
                                    targetBranch == widget.navigationShell.currentIndex,
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
                                )
                              else if (hasGroup)
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
        ),
      );
    },
  );
  }
}
