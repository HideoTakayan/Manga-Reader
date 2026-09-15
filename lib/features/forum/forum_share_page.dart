import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../catalog/catalog_cache_service.dart';
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedTag;
  String _sortBy = 'latest'; // 'latest', 'hot', 'comments'
  Timer? _searchDebounce;
  List<String> _existingTags = [];

  List<String> get _availableTags {
    final tagsSet = <String>{..._existingTags};
    for (final post in _posts) {
      for (final tag in post.tags) {
        final clean = tag.trim().toLowerCase().replaceAll('#', '');
        if (clean.isNotEmpty) tagsSet.add(clean);
      }
    }
    final list = tagsSet.toList()..sort();
    return list;
  }

  @override
  void initState() {
    super.initState();
    _loadTags();
    _loadPosts();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadTags() async {
    try {
      final tags = await _repository.fetchExistingTags(type: 'manga_share');
      if (mounted) {
        setState(() => _existingTags = tags);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
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

    if (refresh) {
      _loadTags();
    }

    try {
      final (newPosts, lastDoc) = await _repository.fetchSharePosts(
        startAfter: _lastDocument,
        tag: _selectedTag,
        sortBy: _sortBy,
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

  void _onTagSelected(String? tag) {
    if (_selectedTag == tag) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedTag = tag;
    });
    _loadPosts(refresh: true);
  }

  void _onSortChanged(String newSort) {
    if (_sortBy == newSort) return;
    HapticFeedback.selectionClick();
    setState(() {
      _sortBy = newSort;
    });
    _loadPosts(refresh: true);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
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
            final normAuthor = CatalogCacheService.instance.normalize(
              p.authorName,
            );
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

    final primary = Theme.of(context).colorScheme.primary;

    return Stack(
      children: [
        Column(
          children: [
            // Search Bar Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              color: Theme.of(context).cardColor.withValues(alpha: 0.6),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.15),
                  ),
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(fontSize: 14),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Tìm bài chia sẻ, tên truyện, tác giả...',
                    hintStyle: TextStyle(
                      color: Theme.of(
                        context,
                      ).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
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
                  onChanged: (val) {
                    if (_searchDebounce?.isActive ?? false) {
                      _searchDebounce!.cancel();
                    }
                    _searchDebounce = Timer(
                      const Duration(milliseconds: 200),
                      () {
                        if (mounted) setState(() => _searchQuery = val);
                      },
                    );
                  },
                ),
              ),
            ),

            // Top Hashtag Filter Bar
            Builder(
              builder: (context) {
                final availableTags = _availableTags;
                if (availableTags.isEmpty && _selectedTag == null) {
                  return const SizedBox.shrink();
                }

                return Container(
                  height: 44,
                  color: Theme.of(context).cardColor.withValues(alpha: 0.6),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    children: [
                      // "All" chip
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          label: const Text('Tất cả'),
                          selected: _selectedTag == null,
                          selectedColor: primary.withValues(alpha: 0.22),
                          labelStyle: TextStyle(
                            color: _selectedTag == null
                                ? primary
                                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                            fontWeight: _selectedTag == null
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 12,
                          ),
                          side: BorderSide(
                            color: _selectedTag == null
                                ? primary
                                : Theme.of(context).dividerColor.withValues(alpha: 0.2),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          onSelected: (_) => _onTagSelected(null),
                        ),
                      ),
                      // If custom active tag is not in available tags, show it
                      if (_selectedTag != null &&
                          !availableTags.contains(_selectedTag))
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            label: Text('#$_selectedTag'),
                            selected: true,
                            selectedColor: primary.withValues(alpha: 0.22),
                            labelStyle: TextStyle(
                              color: primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                            side: BorderSide(color: primary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            onSelected: (_) => _onTagSelected(null),
                          ),
                        ),
                      // Available dynamic tags
                      ...availableTags.map((tag) {
                        final isSelected = _selectedTag == tag;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            label: Text('#$tag'),
                            selected: isSelected,
                            selectedColor: primary.withValues(alpha: 0.22),
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? primary
                                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 12,
                            ),
                            side: BorderSide(
                              color: isSelected
                                  ? primary
                                  : Theme.of(context).dividerColor.withValues(alpha: 0.2),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            onSelected: (val) {
                              _onTagSelected(val ? tag : null);
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                );
              },
            ),

            // Sort Tab Bar
            Container(
              height: 38,
              color: Theme.of(context).cardColor.withValues(alpha: 0.4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Text(
                      'Sắp xếp:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(
                          context,
                        ).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildSortChip(
                      label: 'Mới nhất',
                      icon: Icons.access_time_rounded,
                      value: 'latest',
                      color: primary,
                    ),
                    const SizedBox(width: 6),
                    _buildSortChip(
                      label: 'Nhiều Tim',
                      icon: Icons.local_fire_department_rounded,
                      value: 'hot',
                      color: Colors.redAccent,
                    ),
                    const SizedBox(width: 6),
                    _buildSortChip(
                      label: 'Sôi nổi',
                      icon: Icons.chat_bubble_outline_rounded,
                      value: 'comments',
                      color: Colors.orangeAccent,
                    ),
                  ],
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
                                Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: primary.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: primary.withValues(alpha: 0.25),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Icon(
                                    _searchQuery.isEmpty
                                        ? Icons.share_outlined
                                        : Icons.search_off_rounded,
                                    size: 44,
                                    color: primary,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _searchQuery.isEmpty
                                      ? 'Chưa có bài chia sẻ nào'
                                      : 'Không tìm thấy bài chia sẻ phù hợp',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _searchQuery.isEmpty
                                      ? 'Chia sẻ bộ truyện yêu thích của bạn đến cộng đồng ngay!'
                                      : 'Thử tìm kiếm với từ khóa khác',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                                if (_searchQuery.isEmpty) ...[
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      HapticFeedback.lightImpact();
                                      if (FirebaseAuth.instance.currentUser ==
                                          null) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Vui lòng đăng nhập để chia sẻ',
                                            ),
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
                                    icon: const Icon(
                                      Icons.share_rounded,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'Chia sẻ truyện đầu tiên',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount:
                            filteredPosts.length +
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
                            onTagTap: (tag) => _onTagSelected(tag),
                            onDeleted: () {
                              setState(
                                () =>
                                    _posts.removeWhere((p) => p.id == post.id),
                              );
                            },
                            onTap: () async {
                              HapticFeedback.selectionClick();
                              final deleted = await context.push<bool>(
                                '/forum/detail/${post.id}',
                              );
                              if (deleted == true && mounted) {
                                setState(
                                  () => _posts.removeWhere(
                                    (p) => p.id == post.id,
                                  ),
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

        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            heroTag: 'create_share',
            tooltip: 'Chia sẻ truyện',
            onPressed: () async {
              HapticFeedback.lightImpact();
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

  Widget _buildSortChip({
    required String label,
    required IconData icon,
    required String value,
    required Color color,
  }) {
    final isSelected = _sortBy == value;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _onSortChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.18)
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color.withValues(alpha: 0.6) : Theme.of(context).dividerColor.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: isSelected ? color : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? color : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
