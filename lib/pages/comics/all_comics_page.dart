import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../data/mock_catalog.dart';
import '../../data/models.dart';

class AllComicsPage extends StatefulWidget {
  const AllComicsPage({super.key});

  @override
  State<AllComicsPage> createState() => _AllComicsPageState();
}

class _AllComicsPageState extends State<AllComicsPage> {
  late List<Comic> comics;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadComics();
  }

  Future<void> _loadComics() async {
    setState(() => isLoading = true);
    await Future.delayed(const Duration(milliseconds: 500)); // Giả lập API
    final allComics = MockCatalog.comics();
    setState(() {
      comics = List.from(allComics)
        ..sort((a, b) =>
            MockCatalog.viewsOf(b.id).compareTo(MockCatalog.viewsOf(a.id)));
      isLoading = false;
    });
  }

  void _sortComics(String criteria) {
    setState(() {
      switch (criteria) {
        case 'hot':
          comics.sort((a, b) =>
              MockCatalog.viewsOf(b.id).compareTo(MockCatalog.viewsOf(a.id)));
          break;
        case 'new':
          comics.sort((a, b) => b.id.compareTo(a.id));
          break;
        case 'az':
          comics.sort((a, b) => a.title.compareTo(b.title));
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E10),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Tất cả truyện',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort, color: Colors.white),
            onSelected: _sortComics,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'hot', child: Text('Phổ biến')),
              const PopupMenuItem(value: 'new', child: Text('Mới nhất')),
              const PopupMenuItem(value: 'az', child: Text('A → Z')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadComics,
        child: isLoading
            ? _buildShimmerGrid()
            : comics.isEmpty
                ? _buildEmptyState()
                : _buildComicGrid(),
      ),
    );
  }

  // Grid truyện
  Widget _buildComicGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.65,
      ),
      itemCount: comics.length,
      itemBuilder: (context, index) {
        final comic = comics[index];
        final views = MockCatalog.viewsOf(comic.id);
        return GestureDetector(
          onTap: () => context.push('/detail/${comic.id}'),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1D),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ảnh bìa
                Expanded(
                  flex: 4,
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(12)),
                    child: Stack(
                      children: [
                        CachedNetworkImage(
                          imageUrl: comic.coverUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          placeholder: (context, url) => Container(
                            color: Colors.grey[800],
                            child:
                                const Icon(Icons.image, color: Colors.white54),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey[800],
                            child: const Icon(Icons.broken_image,
                                color: Colors.white54),
                          ),
                        ),
                        // HOT tag
                        if (views > 20000)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'HOT',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // Thông tin
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          comic.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              comic.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 10),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.visibility,
                                    size: 12, color: Colors.white54),
                                const SizedBox(width: 2),
                                Text(
                                  _formatNumber(views),
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 10),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Trạng thái rỗng
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // SỬA LỖI: Dùng icon hợp lệ
          Icon(Icons.auto_stories, size: 64, color: Colors.white54),
          const SizedBox(height: 16),
          const Text(
            'Chưa có truyện nào',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }

  // Shimmer loading
  Widget _buildShimmerGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.65,
      ),
      itemCount: 6,
      itemBuilder: (context, index) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1D),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Expanded(
              flex: 4,
              child: Container(
                color: Colors.grey[800],
                margin: const EdgeInsets.all(4),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        color: Colors.grey[700],
                        height: 12,
                        width: double.infinity),
                    const SizedBox(height: 4),
                    Container(color: Colors.grey[700], height: 10, width: 60),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Format số
  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }
}
