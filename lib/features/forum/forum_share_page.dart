import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/firebase_forum_repository.dart';
import 'models/forum_post.dart';
import 'widgets/forum_post_card.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ForumSharePage extends StatefulWidget {
  const ForumSharePage({super.key});

  @override
  State<ForumSharePage> createState() => _ForumSharePageState();
}

class _ForumSharePageState extends State<ForumSharePage> {
  final _repository = FirebaseForumRepository();
  final List<ForumPost> _posts = [];
  bool _isLoading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPosts({bool refresh = false}) async {
    if (_isLoading) return;
    if (!refresh && !_hasMore) return;

    setState(() {
      _isLoading = true;
      if (refresh) {
        _posts.clear();
        _lastDocument = null;
        _hasMore = true;
      }
    });

    try {
      final (newPosts, lastDoc) = await _repository.fetchSharePosts(
        startAfter: _lastDocument,
      );

      if (!mounted) return;

      setState(() {
        _posts.addAll(newPosts);
        _lastDocument = lastDoc;
        if (newPosts.length < 20) {
          _hasMore = false;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi tải bài chia sẻ: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadPosts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => _loadPosts(refresh: true),
          child: _posts.isEmpty && !_isLoading
              ? ListView(
                  children: const [
                    SizedBox(height: 100),
                    Center(child: Text('Chưa có bài chia sẻ nào')),
                  ],
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(bottom: 80, top: 8),
                  itemCount: _posts.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _posts.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final post = _posts[index];
                    return ForumPostCard(
                      post: post,
                      onTap: () {
                        context.push('/forum/detail/${post.id}');
                      },
                    );
                  },
                ),
        ),

        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            heroTag: 'create_share',
            onPressed: () async {
              if (FirebaseAuth.instance.currentUser == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Vui lòng đăng nhập để đăng bài'),
                  ),
                );
                return;
              }
              final created = await context.push<bool>(
                '/forum/create?type=manga_share',
              );
              if (created == true && mounted) {
                await _loadPosts(refresh: true);
              }
            },
            child: const Icon(Icons.share),
          ),
        ),
      ],
    );
  }
}
