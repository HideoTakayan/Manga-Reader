import 'package:flutter/material.dart';
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
          title: const Text('Theo dõi'),
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
        body: const TabBarView(children: [FollowingPage(), HistoryPage()]),
      ),
    );
  }
}
