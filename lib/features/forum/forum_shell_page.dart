import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../config/admin_config.dart';

import 'admin_reports_screen.dart';
import 'forum_chat_page.dart';
import 'forum_share_page.dart';
import 'forum_discussion_page.dart';

class ForumShellPage extends StatelessWidget {
  const ForumShellPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isAdmin = AdminConfig.isAdmin(FirebaseAuth.instance.currentUser?.email);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Diễn đàn'),
          actions: [
            if (isAdmin)
              IconButton(
                icon: const Icon(Icons.admin_panel_settings),
                tooltip: 'Quản lý báo cáo',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AdminReportsScreen(),
                    ),
                  );
                },
              ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Diễn đàn'),
              Tab(text: 'Chia sẻ truyện'),
              Tab(text: 'Thảo luận'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [ForumChatPage(), ForumSharePage(), ForumDiscussionPage()],
        ),
      ),
    );
  }
}
