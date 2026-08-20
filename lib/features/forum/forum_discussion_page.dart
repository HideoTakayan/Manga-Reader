import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../catalog/catalog_cache_service.dart';
import 'services/firebase_forum_repository.dart';
import 'models/forum_post.dart';
import 'widgets/forum_post_card.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ForumDiscussionPage extends StatefulWidget {
  const ForumDiscussionPage({super.key});

  @override
  State<ForumDiscussionPage> createState() => _ForumDiscussionPageState();
}

class _ForumDiscussionPageState extends State<ForumDiscussionPage> {
  final _repository = FirebaseForumRepository();
  final List<ForumPost> _posts = [];
  bool _isLoading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
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
      final (newPosts, lastDoc) = await _repository.fetchDiscussionPosts(
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
        ).showSnackBar(SnackBar(content: Text('Lỗi tải bài viết: $e')));
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
    if (_searchQuery.isNotEmpty) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadPosts();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredPosts = _searchQuery.isEmpty
        ? _posts
        : _posts.where((p) {
            final q = CatalogCacheService.instance.normalize(_searchQuery);
            final normBody = CatalogCacheService.instance.normalize(p.body);
            final normAuthor =
                CatalogCacheService.instance.normalize(p.authorName);
            final normSharedTitle = p.sharedMangaTitle != null
                ? CatalogCacheService.instance.normalize(p.sharedMangaTitle!)
                : '';
            final normSharedAuthor = p.sharedMangaAuthor != null
                ? CatalogCacheService.instance.normalize(p.sharedMangaAuthor!)
                : '';
            return normBody.contains(q) ||
                normAuthor.contains(q) ||
                normSharedTitle.contains(q) ||
                normSharedAuthor.contains(q);
          }).toList();

    return Stack(
      children: [
        Column(
          children: [
            // Search Bar Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              color: Theme.of(context).cardColor.withValues(alpha: 0.6),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
                  ),
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Tìm bài viết, tác giả, nội dung...',
                    hintStyle: TextStyle(
                      color: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.color
                          ?.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                ),
              ),
            ),

            // Posts Feed
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _loadPosts(refresh: true),
                child: filteredPosts.isEmpty && !_isLoading
                    ? ListView(
                        children: [
                          const SizedBox(height: 100),
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _searchQuery.isEmpty
                                      ? Icons.forum_outlined
                                      : Icons.search_off_rounded,
                                  size: 48,
                                  color: Theme.of(context).disabledColor,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _searchQuery.isEmpty
                                      ? 'Chưa có bài viết nào'
                                      : 'Không tìm thấy bài viết phù hợp',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        color: Theme.of(context).disabledColor,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: filteredPosts.length +
                            ((_hasMore && _searchQuery.isEmpty) ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == filteredPosts.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          final post = filteredPosts[index];
                          return ForumPostCard(
                            post: post,
                            onDeleted: () {
                              setState(
                                () => _posts.removeWhere((p) => p.id == post.id),
                              );
                            },
                            onTap: () async {
                              final deleted = await context.push<bool>(
                                '/forum/detail/${post.id}',
                              );
                              if (deleted == true && mounted) {
                                setState(
                                  () =>
                                      _posts.removeWhere((p) => p.id == post.id),
                                );
                              }
                            },
                          );
                        },
                      ),
              ),
            ),
          ],
        ),

        // FAB
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            heroTag: 'create_discussion',
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
                '/forum/create?type=discussion',
              );
              if (created == true && mounted) {
                await _loadPosts(refresh: true);
              }
            },
            child: const Icon(Icons.edit),
          ),
        ),
      ],
    );
  }
}
