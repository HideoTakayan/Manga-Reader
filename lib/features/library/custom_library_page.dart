import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/library_service.dart';
import '../../services/local_scan_service.dart';
import '../../data/database_helper.dart';
import '../../services/ui_service.dart';
import '../../services/download_service.dart';
import '../../data/drive_service.dart';
import '../../data/models_cloud.dart';
import '../shared/drive_image.dart';
import '../shared/library_dialogs.dart';

// Trang thư viện — quản lý truyện theo danh mục (tab), hỗ trợ chọn nhiều truyện,
// tìm kiếm, lọc theo trạng thái, tải xuống batch, và xóa khỏi thư viện.
class CustomLibraryPage extends StatefulWidget {
  const CustomLibraryPage({super.key});

  @override
  State<CustomLibraryPage> createState() => _CustomLibraryPageState();
}

class _CustomLibraryPageState extends State<CustomLibraryPage> {
  String _searchQuery = '';
  List<String> _selectedStatuses =
      []; // Filter theo trạng thái: Đang tiến hành / Hoàn thành / Drop
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  // Set<String> thay vì List để O(1) lookup khi check isSelected
  final Set<String> _selectedMangaIds = {};

  @override
  void dispose() {
    // Khi thoát khỏi trang, khôi phục bottom bar (ẩn khi selection mode)
    UiService.instance.setMainBottomBarVisible(true);
    _searchController.dispose();
    super.dispose();
  }

  // Bottom sheet lọc truyện — dùng StatefulBuilder 
  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DefaultTabController(
              length: 3,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const TabBar(
                    indicatorColor: Colors.redAccent,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.grey,
                    tabs: [
                      Tab(text: 'Bộ lọc'),
                      Tab(text: 'Sắp xếp'),
                      Tab(text: 'Hiển thị'),
                    ],
                  ),
                  SizedBox(
                    height: 300,
                    child: TabBarView(
                      children: [
                        // Tab Bộ lọc: checkbox trạng thái
                        ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            _buildFilterItem('Đang tiến hành', setModalState),
                            _buildFilterItem('Đã hoàn thành', setModalState),
                            _buildFilterItem('Drop', setModalState),
                          ],
                        ),
                        const Center(
                          child: Text(
                            'Chưa khả dụng',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        const Center(
                          child: Text(
                            'Chưa khả dụng',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Cần gọi cả setState (page) và setModalState (modal) để đồng bộ checkbox
  Widget _buildFilterItem(String title, StateSetter setModalState) {
    final isSelected = _selectedStatuses.contains(title);
    return CheckboxListTile(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      value: isSelected,
      activeColor: Colors.redAccent,
      checkColor: Colors.white,
      onChanged: (val) {
        setState(() {
          if (val == true)
            _selectedStatuses.add(title);
          else
            _selectedStatuses.remove(title);
        });
        setModalState(() {}); // Refresh checkbox trong modal
      },
    );
  }

  // Thoát selection mode: xóa selectedIds, ẩn search nếu đang mở, hiện bottom bar
  void _clearSelection() {
    setState(() {
      _selectedMangaIds.clear();
      if (_isSearching) {
        _isSearching = false;
        _searchQuery = '';
        _searchController.clear();
      }
      UiService.instance.setMainBottomBarVisible(true);
    });
  }

  // Dialog xác nhận xóa: 2 checkbox độc lập — "Xóa khỏi thư viện" và "Xóa chương đã tải"
  void _confirmDeleteSelected(String currentCategory) {
    bool removeFromLibrary = true;
    bool deleteDownloads = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          title: const Text(
            'Gỡ bỏ',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CheckboxListTile(
                value: removeFromLibrary,
                onChanged: (val) =>
                    setDialogState(() => removeFromLibrary = val ?? false),
                title: const Text(
                  'Từ thư viện',
                  style: TextStyle(color: Colors.white),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: Colors.redAccent,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                value: deleteDownloads,
                onChanged: (val) =>
                    setDialogState(() => deleteDownloads = val ?? false),
                title: const Text(
                  'Các chương đã tải',
                  style: TextStyle(color: Colors.white),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: Colors.redAccent,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () async {
                if (!removeFromLibrary && !deleteDownloads) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Vui lòng chọn ít nhất 1 tùy chọn'),
                    ),
                  );
                  return;
                }

                Navigator.pop(ctx);

                // Xóa khỏi thư viện: lấy categories hiện tại → loại bỏ currentCategory → set lại
                if (removeFromLibrary) {
                  for (var id in _selectedMangaIds) {
                    final cats = await LibraryService.instance
                        .streamMangaCategories(id)
                        .first;
                    final newCats = cats
                        .where((c) => c != currentCategory)
                        .toList();
                    await LibraryService.instance.setMangaCategories(
                      id,
                      newCats,
                    );
                  }
                }

                // Xóa file tải: lấy tên truyện từ SQLite → gọi deleteMangaDownloads
                // (lấy tên vì DownloadService dùng tên để tìm đường dẫn folder)
                if (deleteDownloads) {
                  int successCount = 0;
                  for (final mangaId in _selectedMangaIds) {
                    String? title;
                    final localManga = await DatabaseHelper.instance
                        .getLocalManga(mangaId);
                    if (localManga != null) {
                      title = localManga.title;
                    } else {
                      // Fallback: tìm tên từ bảng downloads nếu không có trong local manga
                      final downloads = await DatabaseHelper.instance
                          .getDownloadsByManga(mangaId);
                      if (downloads.isNotEmpty)
                        title = downloads.first['mangaTitle'] as String?;
                    }
                    if (title != null) {
                      await DownloadService.instance.deleteMangaDownloads(
                        mangaId,
                        title,
                      );
                      successCount++;
                    }
                  }
                  if (mounted && successCount > 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Đã xóa dữ liệu tải xuống của $successCount truyện',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                }

                _clearSelection();
              },
              child: const Text(
                'OK',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // isSelectionMode = true khi có ít nhất 1 truyện được chọn → đổi AppBar + hiện action bar dưới
    final bool isSelectionMode = _selectedMangaIds.isNotEmpty;

    // StreamBuilder ngoài cùng: lắng nghe danh sách categories từ Firestore
    // Mỗi category → 1 Tab → 1 CategoryMangaList bên trong
    return StreamBuilder<List<String>>(
      stream: LibraryService.instance.streamCategories(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final categories = snapshot.data ?? ['Mặc định'];

        return DefaultTabController(
          length: categories.length,
          child: SafeArea(
            bottom: false,
            child: Scaffold(
              appBar: AppBar(
                // AppBar thay đổi hoàn toàn khi vào selection mode
                backgroundColor: isSelectionMode
                    ? const Color(0xFF1C1C1E)
                    : null,
                leading: isSelectionMode
                    ? IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: _clearSelection,
                        tooltip: 'Bỏ chọn',
                      )
                    : null,
                title: isSelectionMode
                    ? Text('${_selectedMangaIds.length} đang chọn')
                    : (_isSearching
                          ? TextField(
                              controller: _searchController,
                              autofocus: true,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'Tìm kiếm truyện trong mục...',
                                hintStyle: TextStyle(color: Colors.white54),
                                border: InputBorder.none,
                              ),
                              onChanged: (val) =>
                                  setState(() => _searchQuery = val),
                            )
                          : const Text('Thư viện')),
                actions: isSelectionMode
                    ? []
                    : [
                        IconButton(
                          icon: const Icon(Icons.sync_outlined),
                          tooltip: 'Quét truyện từ máy',
                          onPressed: () async {
                            final count = await LocalScanService.instance
                                .scanAndImport();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Đã tìm thấy $count truyện từ bộ nhớ máy',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                        IconButton(
                          icon: Icon(_isSearching ? Icons.close : Icons.search),
                          onPressed: () {
                            setState(() {
                              if (_isSearching) {
                                _isSearching = false;
                                _searchQuery = '';
                                _searchController.clear();
                              } else {
                                _isSearching = true;
                              }
                            });
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.filter_list),
                          onPressed: _showFilterBottomSheet,
                        ),
                        IconButton(
                          icon: const Icon(Icons.more_vert),
                          onPressed: () => context.push('/settings/categories'),
                        ),
                      ],
                bottom: TabBar(
                  isScrollable: true,
                  indicatorColor: Colors.white,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.grey,
                  indicatorWeight: 3,
                  tabs: categories.map((cat) => Tab(text: cat)).toList(),
                ),
              ),
              body: TabBarView(
                children: categories
                    .map(
                      (cat) => CategoryMangaList(
                        category: cat,
                        searchQuery: _searchQuery,
                        selectedStatuses: _selectedStatuses,
                        selectedMangaIds: _selectedMangaIds,
                        onToggleSelect: (id) {
                          setState(() {
                            if (_selectedMangaIds.contains(id))
                              _selectedMangaIds.remove(id);
                            else
                              _selectedMangaIds.add(id);
                            UiService.instance.setMainBottomBarVisible(
                              _selectedMangaIds.isEmpty,
                            );
                          });
                        },
                      ),
                    )
                    .toList(),
              ),
              // Action bar dưới — chỉ hiện khi selection mode
              bottomNavigationBar: isSelectionMode
                  ? Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: const BoxDecoration(
                        color: Color(0xFF1C1C1E),
                        border: Border(
                          top: BorderSide(color: Colors.white12, width: 0.5),
                        ),
                      ),
                      child: SafeArea(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            // Nút di chuyển sang danh mục khác
                            IconButton(
                              icon: const Icon(
                                Icons.folder_outlined,
                                color: Colors.white,
                              ),
                              onPressed: () async {
                                if (_selectedMangaIds.isNotEmpty) {
                                  final ids = _selectedMangaIds.toList();
                                  // Lấy categories của truyện đầu tiên làm trạng thái hiển thị ban đầu
                                  final cats = await LibraryService.instance
                                      .streamMangaCategories(ids.first)
                                      .first;
                                  if (context.mounted) {
                                    final success =
                                        await LibraryDialogs.showSetCategoryDialog(
                                          context,
                                          ids,
                                          cats,
                                        );
                                    if (success == true) _clearSelection();
                                  }
                                }
                              },
                            ),
                            // Nút tải tất cả chapter của các truyện đã chọn
                            IconButton(
                              icon: const Icon(
                                Icons.download_outlined,
                                color: Colors.white,
                              ),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: const Color(0xFF1C1C1E),
                                    title: const Text(
                                      'Tải xuống?',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    content: Text(
                                      'Tải tất cả chương của ${_selectedMangaIds.length} truyện đã chọn?',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text(
                                          'Hủy',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text(
                                          'Tải xuống',
                                          style: TextStyle(color: Colors.green),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm != true) return;

                                int totalChapters = 0;
                                for (final mangaId in _selectedMangaIds) {
                                  final mangas = await DriveService.instance
                                      .getMangas();
                                  final manga = mangas.firstWhere(
                                    (m) => m.id == mangaId,
                                    orElse: () =>
                                        throw Exception('Manga not found'),
                                  );
                                  final chapters = await DriveService.instance
                                      .getChapters(mangaId);
                                  for (final chapter in chapters) {
                                    await DownloadService.instance.addToQueue(
                                      chapterId: chapter.id,
                                      mangaId: mangaId,
                                      mangaTitle: manga.title,
                                      chapterTitle: chapter.title,
                                      fileType: chapter.fileType,
                                    );
                                    totalChapters++;
                                  }
                                }
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Đã thêm $totalChapters chương vào hàng đợi tải',
                                      ),
                                      backgroundColor: Colors.green,
                                      action: SnackBarAction(
                                        label: 'Xem',
                                        textColor: Colors.white,
                                        onPressed: () =>
                                            context.push('/downloads'),
                                      ),
                                    ),
                                  );
                                  _clearSelection();
                                }
                              },
                            ),
                            // Nút xóa — dùng Builder để lấy tabController.index (category hiện tại)
                            Builder(
                              builder: (ctx) {
                                final tabController = DefaultTabController.of(
                                  ctx,
                                );
                                return IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () {
                                    final currentCat =
                                        categories[tabController.index];
                                    _confirmDeleteSelected(currentCat);
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        );
      },
    );
  }
}

// Widget hiển thị danh sách truyện trong 1 category — chứa logic fetch + filter + search.
// Là StatelessWidget vì không cần state riêng, nhận toàn bộ state từ CustomLibraryPage.
class CategoryMangaList extends StatelessWidget {
  final String category;
  final String searchQuery;
  final List<String> selectedStatuses;
  final Set<String> selectedMangaIds;
  final Function(String) onToggleSelect;

  const CategoryMangaList({
    super.key,
    required this.category,
    required this.searchQuery,
    required this.selectedStatuses,
    required this.selectedMangaIds,
    required this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context) {
    // StreamBuilder lấy danh sách mangaId trong category này (Firestore realtime)
    return StreamBuilder<List<String>>(
      stream: LibraryService.instance.streamMangasInCategory(category),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());

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

        return FutureBuilder<List<CloudManga>>(
          future: fetchMangasWithFallback(),
          builder: (context, mangaSnapshot) {
            if (!mangaSnapshot.hasData) return const SizedBox.shrink();

            // Lọc chỉ lấy truyện có id trong danh sách category này
            final allMangasInCat = mangaSnapshot.data!
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
                  if (s == 'Đang tiến hành')
                    return statusLower.contains('cập nhật') ||
                        statusLower.contains('hành');
                  if (s == 'Đã hoàn thành') return statusLower.contains('hoàn');
                  if (s == 'Drop')
                    return statusLower.contains('drop') ||
                        statusLower.contains('ngừng');
                  return false;
                });
              }
              return matchesSearch && matchesStatus;
            }).toList();

            if (filteredMangas.isEmpty &&
                (searchQuery.isNotEmpty || selectedStatuses.isNotEmpty)) {
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
            color: Colors.white.withOpacity(0.1),
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
              if (isSelected) Container(color: Colors.white.withOpacity(0.2)),
              // Gradient từ trong suốt → đen ở dưới để nổi tên truyện
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.1),
                      Colors.black.withOpacity(0.8),
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
                    color: Colors.white.withOpacity(0.95),
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
