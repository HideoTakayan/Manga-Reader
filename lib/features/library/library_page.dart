import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:go_router/go_router.dart';
import 'following_page.dart';
import 'history_page.dart';

// LibraryPage là wrapper thuần túy — chỉ ghép 2 tab:

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Thư viện', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.85),
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(color: Colors.transparent),
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Quản lý danh mục',
              icon: Icon(Icons.category_outlined, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
              onPressed: () => context.push('/settings/categories'),
            ),
            IconButton(
              tooltip: 'Thống kê đọc',
              icon: const Icon(Icons.bar_chart_rounded, color: Colors.white70),
              onPressed: () => context.push('/analytics'),
            ),
          ],
          bottom: TabBar(
            indicatorColor: Theme.of(context).colorScheme.primary,
            indicatorWeight: 3,
            labelColor: Theme.of(context).colorScheme.primary,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            tabs: const [
              Tab(text: 'Đang theo dõi', icon: Icon(Icons.favorite)),
              Tab(text: 'Lịch sử', icon: Icon(Icons.history)),
            ],
          ),
        ),
        body: const TabBarView(children: [FollowingPage(), HistoryPage()]),
      ),
    );
  }
}
