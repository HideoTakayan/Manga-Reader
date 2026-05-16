import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../data/drive_service.dart';
import '../../../data/models_cloud.dart';
import '../../../services/library_service.dart';
import '../../../services/library_status_service.dart';
import '../../../data/database_helper.dart';
import '../../shared/drive_image.dart';

// Widget hiển thị danh sách truyện trong 1 category — chứa logic fetch + filter + search.
// Là StatelessWidget vì không cần state riêng, nhận toàn bộ state từ CustomLibraryPage.
class CategoryMangaList extends StatelessWidget {
  final String category;
  final String searchQuery;
  final List<String> selectedStatuses;
  final List<MangaReadingStatus> selectedReadingStatuses;
  final List<String> selectedTags;
  final Set<String> selectedMangaIds;
  final Function(String) onToggleSelect;

  const CategoryMangaList({
    super.key,
    required this.category,
    required this.searchQuery,
    required this.selectedStatuses,
    required this.selectedReadingStatuses,
    required this.selectedTags,
    required this.selectedMangaIds,
    required this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context) {
    // StreamBuilder lấy danh sách mangaId trong category này (Firestore realtime)
    return StreamBuilder<List<String>>(
      stream: LibraryService.instance.streamMangasInCategory(category),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final mangaIds = snapshot.data ?? [];
        if (mangaIds.isEmpty) return _buildEmptyState(context);

        // fetchMangasWithFallback: thử Drive trước, nếu lỗi → fallback SQLite local
        Future<List<CloudManga>> fetchMangasWithFallback() async {
          try {
            final cloudMangas = await DriveService.instance.getMangas();
            // Nếu Drive trả về rỗng (offline/token lỗi) → ném exception để vào catch
            if (cloudMangas.isEmpty) throw Exception('Offline fallback');
            return cloudMangas;
          } catch (e) {
            // Offline mode: đọc từ SQLite, wrap thành CloudManga với status='Offline'
            final localMangas = await DatabaseHelper.instance
                .getAllLocalMangas();
            return localMangas
                .map(
                  (m) => CloudManga(
                    id: m.id,
                    title: m.title,
                    coverFileId: m.coverUrl,
                    author: m.author,
                    description: m.description,
                    updatedAt: DateTime.now(),
                    genres: m.genres,
                    status: 'Offline',
                    chapterOrder: [],
                  ),
                )
                .toList();
          }
        }

        Future<_CategoryMangaData> fetchCategoryData() async {
          final mangas = await fetchMangasWithFallback();
          final localStatusEntries = await LibraryStatusService.instance
              .getAll();
          final statusByMangaId = {
            for (final entry in localStatusEntries) entry.mangaId: entry,
          };
          return _CategoryMangaData(
            mangas: mangas,
            statusByMangaId: statusByMangaId,
          );
        }

        return FutureBuilder<_CategoryMangaData>(
          future: fetchCategoryData(),
          builder: (context, mangaSnapshot) {
            if (!mangaSnapshot.hasData) return const SizedBox.shrink();
            final data = mangaSnapshot.data!;

            // Lọc chỉ lấy truyện có id trong danh sách category này
            final allMangasInCat = data.mangas
                .where((m) => mangaIds.contains(m.id))
                .toList();

            // Áp dụng search + status filter
            final filteredMangas = allMangasInCat.where((m) {
              final matchesSearch = m.title.toLowerCase().contains(
                searchQuery.toLowerCase(),
              );
              bool matchesStatus = true;
              if (selectedStatuses.isNotEmpty) {
                // Map label UI → keyword trong status string từ Drive
                final statusLower = m.status.toLowerCase();
                matchesStatus = selectedStatuses.any((s) {
                  if (s == 'Đang tiến hành') {
                    return statusLower.contains('cập nhật') ||
                        statusLower.contains('hành');
                  }
                  if (s == 'Đã hoàn thành') return statusLower.contains('hoàn');
                  if (s == 'Drop') {
                    return statusLower.contains('drop') ||
                        statusLower.contains('ngừng');
                  }
                  return false;
                });
              }
              var matchesReadingStatus = true;
              var matchesTags = true;
              final localStatus = data.statusByMangaId[m.id];

              if (selectedReadingStatuses.isNotEmpty) {
                matchesReadingStatus =
                    localStatus != null &&
                    selectedReadingStatuses.contains(localStatus.status);
              }

              if (selectedTags.isNotEmpty) {
                matchesTags =
                    localStatus != null &&
                    selectedTags.every(localStatus.tags.contains);
              }

              return matchesSearch &&
                  matchesStatus &&
                  matchesReadingStatus &&
                  matchesTags;
            }).toList();

            if (filteredMangas.isEmpty &&
                (searchQuery.isNotEmpty ||
                    selectedStatuses.isNotEmpty ||
                    selectedReadingStatuses.isNotEmpty ||
                    selectedTags.isNotEmpty)) {
              return const Center(
                child: Text(
                  'Không tìm thấy truyện phù hợp',
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }
            if (filteredMangas.isEmpty) return _buildEmptyState(context);

            return GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.72,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: filteredMangas.length,
              itemBuilder: (context, index) {
                final manga = filteredMangas[index];
                return _MangaGridItem(
                  manga: manga,
                  isSelected: selectedMangaIds.contains(manga.id),
                  isSelectionMode: selectedMangaIds.isNotEmpty,
                  onToggle: () => onToggleSelect(manga.id),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_books_outlined,
            size: 80,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 16),
          const Text(
            'Chưa có truyện nào',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => context.go('/'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
            child: const Text(
              'Thêm truyện',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

// Card 1 truyện trong grid — animation viền trắng khi selected, overlay mờ + checkmark icon.
// onTap: nếu đang selection mode → toggle chọn, không thì navigate đến detail.
// onLongPress: luôn toggle chọn (để bắt đầu selection mode).
class _MangaGridItem extends StatelessWidget {
  final CloudManga manga;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onToggle;

  const _MangaGridItem({
    required this.manga,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isSelectionMode
          ? onToggle
          : () => context.push('/detail/${manga.id}'),
      onLongPress: onToggle, // Long press để bắt đầu selection mode
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          // Viền trắng 3px khi selected — AnimatedContainer animate smooth
          border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(isSelected ? 9 : 12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              DriveImage(fileId: manga.coverFileId, fit: BoxFit.cover),
              // Overlay mờ trắng khi selected
              if (isSelected)
                Container(color: Colors.white.withValues(alpha: 0.2)),
              // Gradient từ trong suốt → đen ở dưới để nổi tên truyện
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.1),
                      Colors.black.withValues(alpha: 0.8),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Text(
                  manga.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
              ),
              // Badge số chapter ở góc trên trái — FutureBuilder gọi getChapters mỗi lần build
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: FutureBuilder<List<CloudChapter>>(
                    future: DriveService.instance.getChapters(manga.id),
                    builder: (context, snapshot) {
                      final count = snapshot.data?.length ?? 0;
                      return Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                ),
              ),
              // Checkmark icon ở góc trên phải khi selected
              if (isSelected)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.check, size: 16, color: Colors.black),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryMangaData {
  final List<CloudManga> mangas;
  final Map<String, LibraryStatusEntry> statusByMangaId;

  const _CategoryMangaData({
    required this.mangas,
    required this.statusByMangaId,
  });
}
