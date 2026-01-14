import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'following_page.dart';
import 'history_page.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Thư viện'),
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            onPressed: () => context.go('/'),
          ),
          bottom: TabBar(
            indicatorColor: Theme.of(context).primaryColor,
            labelColor: Theme.of(context).primaryColor,
            unselectedLabelColor: Colors.grey,
            tabs: const [
              Tab(text: 'Đang theo dõi', icon: Icon(Icons.favorite)),
              Tab(text: 'Lịch sử', icon: Icon(Icons.history)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            FollowingPage(), // Trang danh sách truyện đang theo dõi
            HistoryPage(), // Trang lịch sử đọc
          ],
        ),
      ),
    );
  }
}
