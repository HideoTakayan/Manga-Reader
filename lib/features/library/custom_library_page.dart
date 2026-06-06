import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/library_service.dart';
import '../../services/library_status_service.dart';
import '../../services/local_scan_service.dart';
import '../../services/novel_service.dart';
import '../../data/database_helper.dart';
import '../../data/models.dart';
import '../../services/ui_service.dart';
import '../../services/download_service.dart';
import '../../data/drive_service.dart';
import '../shared/library_dialogs.dart';
import 'widgets/novel_list_tab.dart';
import 'widgets/category_manga_list.dart';

// Trang thư viện — quản lý truyện theo danh mục (tab), hỗ trợ chọn nhiều truyện,
// tìm kiếm, lọc theo trạng thái, tải xuống batch, và xóa khỏi thư viện.
class CustomLibraryPage extends StatefulWidget {
  const CustomLibraryPage({super.key});

  @override
  State<CustomLibraryPage> createState() => _CustomLibraryPageState();
}

class _CustomLibraryPageState extends State<CustomLibraryPage> {
  String _searchQuery = '';
  final List<String> _selectedStatuses =
      []; // Filter theo trạng thái: Đang tiến hành / Hoàn thành / Drop
  final List<MangaReadingStatus> _selectedReadingStatuses = [];
  final List<String> _selectedTags = [];
  LibrarySortMode _sortMode = LibrarySortMode.updatedDesc;
  LibraryViewMode _viewMode = LibraryViewMode.grid;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  // Set<String> thay vì List để O(1) lookup khi check isSelected
  final Set<String> _selectedMangaIds = {};

  // Counter dùng để force rebuild NovelListTab khi import EPUB mới
  // (AutomaticKeepAliveClientMixin giữ state nên setState() trên parent không đủ)
  int _novelRefreshKey = 0;

  @override
  void initState() {
    super.initState();
    _loadLibraryDisplayPrefs();
  }

  Future<void> _loadLibraryDisplayPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _sortMode = LibrarySortMode.values.firstWhere(
        (mode) => mode.name == prefs.getString('library_sort_mode'),
        orElse: () => LibrarySortMode.updatedDesc,
      );
      _viewMode = LibraryViewMode.values.firstWhere(
        (mode) => mode.name == prefs.getString('library_view_mode'),
        orElse: () => LibraryViewMode.grid,
      );
    });
  }

  Future<void> _setSortMode(
    LibrarySortMode mode,
    StateSetter setModalState,
  ) async {
    setState(() => _sortMode = mode);
    setModalState(() {});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('library_sort_mode', mode.name);
  }

  Future<void> _setViewMode(
    LibraryViewMode mode,
    StateSetter setModalState,
  ) async {
    setState(() => _viewMode = mode);
    setModalState(() {});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('library_view_mode', mode.name);
  }

  @override
  void dispose() {
    // Khi thoát khỏi trang, khôi phục bottom bar (ẩn khi selection mode)
    UiService.instance.setMainBottomBarVisible(true);
    _searchController.dispose();
    super.dispose();
  }

  /// Mở file picker để chọn file EPUB từ bộ nhớ máy và thêm vào thư viện.
  Future<void> _pickEpub() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub'],
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;

      int added = 0;
      for (final file in result.files) {
        if (file.path == null) continue;
        final name = file.name
            .replaceAll(RegExp(r'\.epub$', caseSensitive: false), '')
            .trim();
        final novel = LocalNovel(
          path: file.path!,
          title: name.isEmpty ? 'Truyện chữ' : name,
          importedAt: DateTime.now(),
        );
        final ok = await NovelService.instance.add(novel);
        if (ok) added++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              added > 0
                  ? 'Đã thêm $added truyện chữ vào thư viện'
                  : 'Truyện đã có trong thư viện rồi',
            ),
            backgroundColor: added > 0 ? Colors.green : Colors.orange,
          ),
        );
        setState(() {
          // Increment key để force rebuild NovelListTab
          if (added > 0) _novelRefreshKey++;
        });
      }
    } catch (e) {
      debugPrint('FilePicker error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể mở file. Vui lòng thử lại.')),
        );
      }
    }
  }

  // Bottom sheet lọc truyện — dùng StatefulBuilder
  void _showFilterBottomSheet() async {
    final allTags = await LibraryStatusService.instance.getAllTags();
    if (!mounted) return;

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
                            const Text(
                              'Trạng thái truyện',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildFilterItem('Đang tiến hành', setModalState),
                            _buildFilterItem('Đã hoàn thành', setModalState),
                            _buildFilterItem('Drop', setModalState),
                            const SizedBox(height: 16),
                            const Text(
                              'Trạng thái đọc',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...MangaReadingStatus.values.map(
                              (status) => _buildReadingStatusFilterItem(
                                status,
                                setModalState,
                              ),
                            ),
                            if (allTags.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              const Text(
                                'Tag tùy chỉnh',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: allTags.map((tag) {
                                  final selected = _selectedTags.contains(tag);
                                  return FilterChip(
                                    label: Text(tag),
                                    selected: selected,
                                    selectedColor: Colors.redAccent,
                                    checkmarkColor: Colors.white,
                                    labelStyle: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : Colors.white70,
                                    ),
                                    backgroundColor: const Color(0xFF2C2C2E),
                                    onSelected: (value) {
                                      setState(() {
                                        if (value) {
                                          _selectedTags.add(tag);
                                        } else {
                                          _selectedTags.remove(tag);
                                        }
                                      });
                                      setModalState(() {});
                                    },
                                  );
                                }).toList(),
                              ),
                            ],
                            if (_selectedStatuses.isNotEmpty ||
                                _selectedReadingStatuses.isNotEmpty ||
                                _selectedTags.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _selectedStatuses.clear();
                                    _selectedReadingStatuses.clear();
                                    _selectedTags.clear();
                                  });
                                  setModalState(() {});
                                },
                                icon: const Icon(Icons.clear),
                                label: const Text('Xóa bộ lọc'),
                              ),
                            ],
                          ],
                        ),
                        ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            _buildSortItem(
                              'Mới cập nhật',
                              Icons.update,
                              LibrarySortMode.updatedDesc,
                              setModalState,
                            ),
                            _buildSortItem(
                              'Tên A-Z',
                              Icons.sort_by_alpha,
                              LibrarySortMode.titleAsc,
                              setModalState,
                            ),
                            _buildSortItem(
                              'Trạng thái đọc',
                              Icons.bookmark_outline,
                              LibrarySortMode.readingStatus,
                              setModalState,
                            ),
                          ],
                        ),
                        ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            _buildViewItem(
                              'Lưới bìa',
                              Icons.grid_view,
                              LibraryViewMode.grid,
                              setModalState,
                            ),
                            _buildViewItem(
                              'Danh sách',
                              Icons.view_list,
                              LibraryViewMode.list,
                              setModalState,
                            ),
                          ],
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
          if (val == true) {
            _selectedStatuses.add(title);
          } else {
            _selectedStatuses.remove(title);
          }
        });
        setModalState(() {}); // Refresh checkbox trong modal
      },
    );
  }

  Widget _buildSortItem(
    String title,
    IconData icon,
    LibrarySortMode mode,
    StateSetter setModalState,
  ) {
    final selected = _sortMode == mode;
    return ListTile(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      leading: Icon(icon, color: selected ? Colors.redAccent : Colors.white70),
      trailing: selected
          ? const Icon(Icons.check, color: Colors.redAccent)
          : null,
      onTap: () => _setSortMode(mode, setModalState),
    );
  }

  Widget _buildViewItem(
    String title,
    IconData icon,
    LibraryViewMode mode,
    StateSetter setModalState,
  ) {
    final selected = _viewMode == mode;
    return ListTile(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      leading: Icon(icon, color: selected ? Colors.redAccent : Colors.white70),
      trailing: selected
          ? const Icon(Icons.check, color: Colors.redAccent)
          : null,
      onTap: () => _setViewMode(mode, setModalState),
    );
  }

  Widget _buildReadingStatusFilterItem(
    MangaReadingStatus status,
    StateSetter setModalState,
  ) {
    final isSelected = _selectedReadingStatuses.contains(status);
    return CheckboxListTile(
      title: Text(
        _readingStatusLabel(status),
        style: const TextStyle(color: Colors.white),
      ),
      value: isSelected,
      activeColor: Colors.redAccent,
      checkColor: Colors.white,
      onChanged: (val) {
        setState(() {
          if (val == true) {
            _selectedReadingStatuses.add(status);
          } else {
            _selectedReadingStatuses.remove(status);
          }
        });
        setModalState(() {});
      },
    );
  }

  String _readingStatusLabel(MangaReadingStatus status) {
    switch (status) {
      case MangaReadingStatus.reading:
        return 'Đang đọc';
      case MangaReadingStatus.completed:
        return 'Đã đọc xong';
      case MangaReadingStatus.paused:
        return 'Tạm dừng';
      case MangaReadingStatus.dropped:
        return 'Dropped';
      case MangaReadingStatus.planToRead:
        return 'Đọc sau';
    }
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
                final messenger = ScaffoldMessenger.of(context);
                if (!removeFromLibrary && !deleteDownloads) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Vui lòng chọn ít nhất 1 tùy chọn'),
                    ),
                  );
                  return;
                }

                Navigator.pop(ctx);

                if (!context.mounted) return;
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const Center(
                    child: CircularProgressIndicator(color: Colors.redAccent),
                  ),
                );

                try {
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
                        if (downloads.isNotEmpty) {
                          title = _readString(downloads.first, 'mangaTitle');
                          if (title.isEmpty) title = null;
                        }
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
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã xóa dữ liệu tải xuống của $successCount truyện',
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Lỗi khi xóa: $e'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                } finally {
                  if (context.mounted) {
                    Navigator.pop(context); // Tắt vòng xoay
                  }
                  _clearSelection();
                }
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
          // +1 cho tab "Truyện Chữ" cố định
          length: categories.length + 1,
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
                        // Menu 3 chấm — quản lý danh mục + nhập EPUB
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          color: const Color(0xFF2C2C2E),
                          onSelected: (val) {
                            if (val == 'categories') {
                              context.push('/settings/categories');
                            } else if (val == 'import_epub') {
                              _pickEpub();
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'import_epub',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.menu_book_outlined,
                                    color: Colors.blueAccent,
                                    size: 20,
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Nhập truyện chữ (EPUB)',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'categories',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.folder_outlined,
                                    color: Colors.white70,
                                    size: 20,
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Quản lý danh mục',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                bottom: TabBar(
                  isScrollable: true,
                  indicatorColor: Colors.white,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.grey,
                  indicatorWeight: 3,
                  tabs: [
                    ...categories.map((cat) => Tab(text: cat)),
                    // Tab cố định cho Truyện Chữ
                    const Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.menu_book_outlined, size: 14),
                          SizedBox(width: 4),
                          Text('Truyện Chữ'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              body: TabBarView(
                children: [
                  ...categories.map(
                    (cat) => CategoryMangaList(
                      category: cat,
                      searchQuery: _searchQuery,
                      selectedStatuses: _selectedStatuses,
                      selectedReadingStatuses: _selectedReadingStatuses,
                      selectedTags: _selectedTags,
                      sortMode: _sortMode,
                      viewMode: _viewMode,
                      selectedMangaIds: _selectedMangaIds,
                      onToggleSelect: (id) {
                        setState(() {
                          if (_selectedMangaIds.contains(id)) {
                            _selectedMangaIds.remove(id);
                          } else {
                            _selectedMangaIds.add(id);
                          }
                          UiService.instance.setMainBottomBarVisible(
                            _selectedMangaIds.isEmpty,
                          );
                        });
                      },
                    ),
                  ),
                  // Tab cố định: danh sách truyện chữ đã nhập
                  // ValueKey(_novelRefreshKey) force rebuild khi import EPUB mới
                  NovelListTab(key: ValueKey(_novelRefreshKey)),
                ],
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

                                if (!context.mounted) return;
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) => const Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.green,
                                    ),
                                  ),
                                );

                                try {
                                  int totalChapters = 0;
                                  final mangas = await DriveService.instance
                                      .getMangas();
                                  for (final mangaId in _selectedMangaIds) {
                                    final manga = mangas.firstWhere(
                                      (m) => m.id == mangaId,
                                      orElse: () => throw Exception(
                                        'Không tìm thấy truyện',
                                      ),
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
                                        mangaInfo: Manga(
                                          id: manga.id,
                                          title: manga.title,
                                          coverUrl: manga.coverFileId,
                                          author: manga.author,
                                          description: manga.description,
                                          genres: manga.genres,
                                          contentType: manga.contentType,
                                        ),
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
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Lỗi khi tải: $e'),
                                        backgroundColor: Colors.redAccent,
                                      ),
                                    );
                                  }
                                } finally {
                                  if (context.mounted) {
                                    Navigator.pop(context); // Tắt vòng xoay
                                  }
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

  String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return '';
    return value.toString().trim();
  }
}
