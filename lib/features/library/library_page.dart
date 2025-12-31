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
        backgroundColor: const Color(0xFF1C1C1E),
        appBar: AppBar(
          title: const Text('Thư viện'),
          backgroundColor: const Color(0xFF1C1C1E),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            onPressed: () => context.go('/'),
          ),
          bottom: const TabBar(
            indicatorColor: Colors.amber,
            labelColor: Colors.amber,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: 'Đang theo dõi'),
              Tab(text: 'Lịch sử'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            FollowingPage(), // Ta tái sử dụng widget FollowingPage cũ (nhưng cần bỏ Scaffold bên trong nó đi nếu muốn mượt)
            // Tuy nhiên để nhanh, ta cứ để lồng Scaffold cũng được, hoặc sửa FollowingPage.
            // Tốt nhất là sửa FollowingPage để bỏ Scaffold nếu nó được dùng trong TabBarView.
            // Nhưng ở đây mình sẽ wrap HistoryPage.
            HistoryPage(),
          ],
        ),
      ),
    );
  }
}
