import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/models_cloud.dart';
import '../../data/models_group.dart';
import '../../data/drive_service.dart';
import '../../data/content_type.dart';
import '../../services/group_service.dart';
import '../catalog/catalog_cache_service.dart';
import '../shared/drive_image.dart';

class GroupProfilePage extends StatefulWidget {
  final String groupId;
  final ScanlationGroup? initialGroup;

  const GroupProfilePage({
    super.key,
    required this.groupId,
    this.initialGroup,
  });

  @override
  State<GroupProfilePage> createState() => _GroupProfilePageState();
}

class _GroupProfilePageState extends State<GroupProfilePage> {
  ScanlationGroup? _group;
  List<CloudManga> _allMangas = [];
  List<CloudManga> _filteredMangas = [];
  bool _isLoading = true;
  MangaContentType? _selectedTypeFilter;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _group = widget.initialGroup;
    _loadGroupData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadGroupData() async {
    setState(() => _isLoading = true);

    try {
      _group ??= await GroupService.instance.getGroupById(widget.groupId);

      final allMangas = await DriveService.instance.getMangas(forceRefresh: true);
      _allMangas = allMangas.where((m) => m.uploaderGroupId == widget.groupId).toList();
      _applyFilter();
    } catch (e) {
      debugPrint('Error loading group profile: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyFilter() {
    final query = CatalogCacheService.instance.normalize(_searchQuery);
    _filteredMangas = _allMangas.where((m) {
      final matchesType =
          _selectedTypeFilter == null || m.contentType == _selectedTypeFilter;
      if (!matchesType) return false;
      if (query.isEmpty) return true;
      final normTitle = CatalogCacheService.instance.normalize(m.title);
      final normAuthor = CatalogCacheService.instance.normalize(m.author);
      final normGenres =
          CatalogCacheService.instance.normalize(m.genres.join(' '));
      return normTitle.contains(query) ||
          normAuthor.contains(query) ||
          normGenres.contains(query);
    }).toList();
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading && _group == null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Colors.blueAccent),
        ),
      );
    }

    if (_group == null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(
          child: Text('Không tìm thấy thông tin nhóm dịch', style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    final totalViews = _allMangas.fold<int>(0, (sum, m) => sum + m.viewCount);
    final totalLikes = _allMangas.fold<int>(0, (sum, m) => sum + m.likeCount);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: _loadGroupData,
        color: Colors.blueAccent,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            // 1. Sliver App Bar with Group Header
            SliverAppBar(
              expandedHeight: 220,
              pinned: true,
              backgroundColor: theme.cardColor,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                onPressed: () => context.pop(),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Gradient Backdrop
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.blueAccent.withValues(alpha: 0.3),
                            theme.scaffoldBackgroundColor,
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 20,
                      left: 20,
                      right: 20,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 36,
                            backgroundColor: Colors.blueAccent.withValues(alpha: 0.2),
                            child: const Icon(
                              Icons.groups_2_rounded,
                              size: 40,
                              color: Colors.blueAccent,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _group!.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.people_outline, size: 14, color: Colors.white60),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${_group!.members.length} thành viên',
                                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                                    ),
                                    const SizedBox(width: 12),
                                    const Icon(Icons.calendar_today_outlined, size: 14, color: Colors.white60),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${_group!.createdAt.day}/${_group!.createdAt.month}/${_group!.createdAt.year}',
                                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 2. Body Details
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Description
                    if (_group!.description.trim().isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.info_outline, size: 16, color: Colors.blueAccent),
                                SizedBox(width: 6),
                                Text(
                                  'Giới thiệu nhóm',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _group!.description,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Stats Ribbon
                    Row(
                      children: [
                        _buildStatPill('Đầu truyện', '${_allMangas.length}', Icons.auto_stories, Colors.blueAccent),
                        const SizedBox(width: 10),
                        _buildStatPill('Lượt xem', _formatCount(totalViews), Icons.remove_red_eye_outlined, Colors.orangeAccent),
                        const SizedBox(width: 10),
                        _buildStatPill('Lượt thích', _formatCount(totalLikes), Icons.favorite_border, Colors.pinkAccent),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Search Bar
                    Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(19),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style:
                            const TextStyle(fontSize: 13, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Tìm truyện của nhóm...',
                          hintStyle: const TextStyle(
                            color: Colors.white38,
                            fontSize: 13,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            size: 16,
                            color: Colors.white54,
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear,
                                    size: 14,
                                    color: Colors.white54,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _searchQuery = '';
                                      _applyFilter();
                                    });
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 8),
                        ),
                        onChanged: (val) {
                          setState(() {
                            _searchQuery = val.trim();
                            _applyFilter();
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Filter Chips
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Truyện Đã Dịch (${_filteredMangas.length})',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            _buildFilterChip('Tất cả', null),
                            const SizedBox(width: 6),
                            _buildFilterChip('Manga', MangaContentType.manga),
                            const SizedBox(width: 6),
                            _buildFilterChip('Novel', MangaContentType.novel),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),

            if (_filteredMangas.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _searchQuery.isNotEmpty
                          ? 'Không tìm thấy bộ truyện nào phù hợp.'
                          : 'Nhóm chưa đăng tải bộ truyện nào trong mục này.',
                      style: const TextStyle(color: Colors.white54, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.68,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final manga = _filteredMangas[index];
                      return _GroupMangaItemCard(manga: manga);
                    },
                    childCount: _filteredMangas.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatPill(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, MangaContentType? type) {
    final isSelected = _selectedTypeFilter == type;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTypeFilter = type;
          _applyFilter();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueAccent : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.blueAccent : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _GroupMangaItemCard extends StatelessWidget {
  final CloudManga manga;
  const _GroupMangaItemCard({required this.manga});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        context.push('/detail/${manga.id}', extra: manga);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DriveImage(
                    fileId: manga.coverFileId,
                    fit: BoxFit.cover,
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        manga.contentType.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    manga.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    manga.author.isNotEmpty ? manga.author : 'Không rõ tác giả',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
