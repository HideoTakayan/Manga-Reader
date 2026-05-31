import 'package:flutter/material.dart';

import 'forum_chat_page.dart';
import 'forum_share_page.dart';
import 'forum_discussion_page.dart';

class ForumShellPage extends StatelessWidget {
  const ForumShellPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Diễn đàn'),
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
