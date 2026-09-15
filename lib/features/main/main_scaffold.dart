import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

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

  List<int> _getActiveBranches() {
    return const [
      _Branch.home,
      _Branch.library,
      _Branch.following,
      _Branch.forum,
      _Branch.settings,
    ];
  }

  int _branchToTab(int branchIndex, List<int> activeBranches) {
    if (branchIndex == _Branch.admin || branchIndex == _Branch.group) {
      return activeBranches.indexOf(_Branch.settings);
    }
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
    final activeBranches = _getActiveBranches();
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
                            fontWeight: FontWeight.w600,
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
                        destinations: const [
                          NavigationDestination(
                            icon: Icon(Icons.home_outlined),
                            selectedIcon: Icon(Icons.home_rounded),
                            label: 'Trang chủ',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.collections_bookmark_outlined),
                            selectedIcon: Icon(Icons.collections_bookmark_rounded),
                            label: 'Thư viện',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.favorite_border_rounded),
                            selectedIcon: Icon(Icons.favorite_rounded),
                            label: 'Theo dõi',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.forum_outlined),
                            selectedIcon: Icon(Icons.forum_rounded),
                            label: 'Diễn đàn',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.settings_outlined),
                            selectedIcon: Icon(Icons.settings_rounded),
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
  }
}
