import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:go_router/go_router.dart';
import 'edit_categories_page.dart';
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
              icon: const Icon(Icons.category_outlined, color: Colors.white70),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const EditCategoriesPage()),
                );
              },
            ),
            IconButton(
              tooltip: 'Thống kê đọc',
              icon: const Icon(Icons.bar_chart_rounded, color: Colors.white70),
              onPressed: () => context.push('/analytics'),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.redAccent,
            indicatorWeight: 3,
            labelColor: Colors.white,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            unselectedLabelColor: Colors.white54,
            tabs: [
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
