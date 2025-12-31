import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../shared/drive_image.dart';

class AllComicsPage extends StatefulWidget {
  const AllComicsPage({super.key});

  @override
  State<AllComicsPage> createState() => _AllComicsPageState();
}

class _AllComicsPageState extends State<AllComicsPage> {
  // DriveService.getComics returns a Future, needing FutureBuilder.
  String _sortCriteria = 'new';
  late Future<List<CloudComic>> _comicsFuture;

  @override
  void initState() {
    super.initState();
    _comicsFuture = DriveService.instance.getComics();
  }

  void _sortComics(String criteria) {
    setState(() {
      _sortCriteria = criteria;
    });
  }

  void _refresh() {
    setState(() {
      _comicsFuture = DriveService.instance.getComics();
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
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _refresh,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort, color: Colors.white),
            onSelected: _sortComics,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'new', child: Text('Mới nhất')),
              const PopupMenuItem(value: 'az', child: Text('A → Z')),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<CloudComic>>(
        future: _comicsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildShimmerGrid();
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Lỗi tải dữ liệu: ${snapshot.error}',
                style: const TextStyle(color: Colors.white),
              ),
            );
          }

          var comics = snapshot.data ?? [];

          // Sorting
          if (_sortCriteria == 'new') {
            comics.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          } else if (_sortCriteria == 'az') {
            comics.sort((a, b) => a.title.compareTo(b.title));
          }

          if (comics.isEmpty) {
            return _buildEmptyState();
          }

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
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12),
                          ),
                          child: DriveImage(
                            fileId: comic.coverFileId,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
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
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
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
        },
      ),
    );
  }

  // Trạng thái rỗng
  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_stories, size: 64, color: Colors.white54),
          SizedBox(height: 16),
          Text(
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
                      width: double.infinity,
                    ),
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
}
