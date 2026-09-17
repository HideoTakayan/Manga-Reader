import 'dart:async';
import 'package:flutter/material.dart';
import '../../../data/models_cloud.dart';
import '../../../data/drive_service.dart';
import '../../catalog/catalog_cache_service.dart';
import '../../shared/drive_image.dart';

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
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final availableHeight = (screenHeight - bottomInset) * 0.75;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SizedBox(
          height: availableHeight.clamp(280.0, screenHeight * 0.85),
          child: Material(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            clipBehavior: Clip.antiAlias,
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
                        Text(
                          'Không thể tải danh sách truyện',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${snapshot.error}',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
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
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
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
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                              ),
                              child: Icon(
                                Icons.library_books_outlined,
                                size: 44,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Không có truyện nào',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
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
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                              ),
                              child: Icon(
                                Icons.search_off_rounded,
                                size: 44,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Không tìm thấy truyện phù hợp',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Thử tìm bằng tên khác hoặc tác giả',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                                fontSize: 12.5,
                              ),
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
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: SizedBox(
                                width: 46,
                                height: 62,
                                child: DriveImage(
                                  fileId: manga.coverFileId,
                                  fit: BoxFit.cover,
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
                              style: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                fontSize: 12,
                              ),
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
    ),
  );
}
}
