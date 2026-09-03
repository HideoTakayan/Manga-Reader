import 'dart:async';
import 'package:flutter/material.dart';
import '../../../data/models_cloud.dart';
import '../../../data/drive_service.dart';
import '../../catalog/catalog_cache_service.dart';

class MangaPickerSheet extends StatefulWidget {
  const MangaPickerSheet({super.key});

  @override
  State<MangaPickerSheet> createState() => _MangaPickerSheetState();
}

class _MangaPickerSheetState extends State<MangaPickerSheet> {
  late Future<List<CloudManga>> _mangasFuture;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _mangasFuture = DriveService.instance.getMangas();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: FutureBuilder<List<CloudManga>>(
            future: _mangasFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.redAccent.withValues(alpha: 0.12),
                          ),
                          child: const Icon(
                            Icons.cloud_off_rounded,
                            size: 40,
                            color: Colors.redAccent,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Không thể tải danh sách truyện',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${snapshot.error}',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final allMangas = snapshot.data ?? [];
              final normalizedQuery = CatalogCacheService.instance.normalize(_searchQuery.trim());
              final filteredMangas = allMangas.where((m) {
                if (normalizedQuery.isEmpty) return true;
                return CatalogCacheService.instance.normalize(m.title).contains(normalizedQuery) ||
                    CatalogCacheService.instance.normalize(m.author).contains(normalizedQuery);
              }).toList();

              return Column(
                children: [
                  const SizedBox(height: 16),
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Chọn truyện chia sẻ',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Tìm tên truyện hoặc tác giả...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: theme.cardColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                      ),
                      onChanged: (value) {
                        if (_debounce?.isActive ?? false) _debounce!.cancel();
                        _debounce = Timer(const Duration(milliseconds: 150), () {
                          if (mounted) setState(() => _searchQuery = value);
                        });
                      },
                    ),
                  ),
                  if (allMangas.isEmpty)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.05),
                              ),
                              child: const Icon(Icons.library_books_outlined, size: 44, color: Colors.white38),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Không có truyện nào',
                              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (filteredMangas.isEmpty)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.05),
                              ),
                              child: const Icon(Icons.search_off_rounded, size: 44, color: Colors.white38),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Không tìm thấy truyện phù hợp',
                              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 15),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Thử tìm bằng tên khác hoặc tác giả',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: filteredMangas.length,
                        itemBuilder: (context, index) {
                          final manga = filteredMangas[index];
                          final coverUrl = DriveService.instance.getThumbnailLink(manga.coverFileId);
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(
                                coverUrl,
                                width: 46,
                                height: 62,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 46,
                                  height: 62,
                                  color: Colors.white12,
                                  child: const Icon(Icons.book_rounded, color: Colors.white24, size: 22),
                                ),
                              ),
                            ),
                            title: Text(
                              manga.title,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              manga.author,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                            ),
                            onTap: () {
                              Navigator.of(context).pop(manga);
                            },
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
