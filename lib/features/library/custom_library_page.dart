import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
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
import '../../services/external_file_service.dart';
import '../shared/library_dialogs.dart';
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
  bool _filterDownloadedOnly = false;
  LibrarySortMode _sortMode = LibrarySortMode.updatedDesc;
  LibraryViewMode _viewMode = LibraryViewMode.grid;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  // Set<String> thay vì List để O(1) lookup khi check isSelected
  final Set<String> _selectedMangaIds = {};

  // Counter dùng để force rebuild NovelListTab khi import EPUB mới
  // (AutomaticKeepAliveClientMixin giữ state nên setState() trên parent không đủ)
  int _novelRefreshKey = 0;
  late Stream<List<String>> _categoriesStream;

  @override
  void initState() {
    super.initState();
    _categoriesStream = LibraryService.instance.streamCategories();
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
    HapticFeedback.selectionClick();
    setState(() => _sortMode = mode);
    setModalState(() {});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('library_sort_mode', mode.name);
  }

  Future<void> _setViewMode(
    LibraryViewMode mode,
    StateSetter setModalState,
  ) async {
    HapticFeedback.selectionClick();
    setState(() => _viewMode = mode);
    setModalState(() {});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('library_view_mode', mode.name);
  }

  @override
  void dispose() {
    // Khi thoát khỏi trang, khôi phục bottom bar (ẩn khi selection mode)
    UiService.instance.setMainBottomBarVisible(true);
    _searchDebounce?.cancel();
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

      LibraryService.instance.notifyMappingChanged();

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
          if (added > 0) _novelRefreshKey++;
        });
      }
    } catch (e) {
      debugPrint('FilePicker error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể mở file. Vui lòng thử lại.')),
        );
      }
    }
  }

  /// Mở file picker để chọn file CBZ/ZIP/PDF từ bộ nhớ máy và thêm vào thư viện.
  Future<void> _pickComic() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['cbz', 'cbr', 'zip', 'pdf'],
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;

      int added = 0;
      for (final file in result.files) {
        if (file.path == null) continue;
        final info = ExternalFileInfo(
          filePath: file.path!,
          fileName: file.name,
          fileType: file.extension?.toLowerCase() ?? 'cbz',
          fileSize: file.size,
        );
        final ok = await ExternalFileService.instance.importToLibrary(
          info,
        );
        if (ok) added++;
      }

      LibraryService.instance.notifyMappingChanged();

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              added > 0
                  ? 'Đã thêm $added truyện tranh vào thư viện'
                  : 'Truyện đã có trong thư viện rồi',
            ),
            backgroundColor: added > 0 ? Colors.green : Colors.orange,
          ),
        );
        setState(() {});
      }
    } catch (e) {
      debugPrint('Pick comic error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.75,
              ),
              color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.85),
              child: StatefulBuilder(
                builder: (context, setModalState) {
                  final primaryColor = Theme.of(context).colorScheme.primary;
                  return DefaultTabController(
                    length: 3,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 10),
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TabBar(
                          indicatorColor: primaryColor,
                          labelColor: Theme.of(context).colorScheme.onSurface,
                          unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                          tabs: const [
                            Tab(text: 'Bộ lọc'),
                            Tab(text: 'Sắp xếp'),
                            Tab(text: 'Hiển thị'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                      children: [
                        // Tab Bộ lọc: checkbox trạng thái
                        ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            Text(
                              'Trạng thái truyện',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildFilterItem('Đang tiến hành', setModalState),
                            _buildFilterItem('Đã hoàn thành', setModalState),
                            _buildFilterItem('Drop', setModalState),
                            const SizedBox(height: 16),
                            Text(
                              'Trạng thái đọc',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
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
                              Text(
                                'Tag tùy chỉnh',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface,
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
                                    selectedColor: primaryColor,
                                    checkmarkColor: Theme.of(context).colorScheme.onPrimary,
                                    labelStyle: TextStyle(
                                      color: selected
                                          ? Theme.of(context).colorScheme.onPrimary
                                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                                    ),
                                    backgroundColor: Theme.of(context).cardColor,
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
                            const SizedBox(height: 16),
                            Text(
                              'Ngoại tuyến & Tải xuống',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              activeColor: primaryColor,
                              checkColor: Theme.of(context).colorScheme.onPrimary,
                              title: Text(
                                'Chỉ truyện đã tải về (Offline)',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: Text(
                                'Chỉ hiện các truyện có chương tải về hoặc file CBZ/EPUB nội bộ',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                  fontSize: 11,
                                ),
                              ),
                              value: _filterDownloadedOnly,
                              onChanged: (val) {
                                setState(() => _filterDownloadedOnly = val ?? false);
                                setModalState(() {});
                              },
                            ),
                            if (_selectedStatuses.isNotEmpty ||
                                _selectedReadingStatuses.isNotEmpty ||
                                _selectedTags.isNotEmpty ||
                                _filterDownloadedOnly) ...[
                              const SizedBox(height: 16),
                              TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _selectedStatuses.clear();
                                    _selectedReadingStatuses.clear();
                                    _selectedTags.clear();
                                    _filterDownloadedOnly = false;
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
              ),
            ),
          ),
        );
      },
    );
  }

  // Cần gọi cả setState (page) và setModalState (modal) để đồng bộ checkbox
  Widget _buildFilterItem(String title, StateSetter setModalState) {
    final isSelected = _selectedStatuses.contains(title);
    return CheckboxListTile(
      title: Text(
        title,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
      ),
      value: isSelected,
      activeColor: Theme.of(context).colorScheme.primary,
      checkColor: Theme.of(context).colorScheme.onPrimary,
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
    final primaryColor = Theme.of(context).colorScheme.primary;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return ListTile(
      title: Text(title, style: TextStyle(color: onSurface)),
      leading: Icon(icon, color: selected ? primaryColor : onSurface.withValues(alpha: 0.6)),
      trailing: selected
          ? Icon(Icons.check, color: primaryColor)
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
    final primaryColor = Theme.of(context).colorScheme.primary;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return ListTile(
      title: Text(title, style: TextStyle(color: onSurface)),
      leading: Icon(icon, color: selected ? primaryColor : onSurface.withValues(alpha: 0.6)),
      trailing: selected
          ? Icon(Icons.check, color: primaryColor)
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
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
      ),
      value: isSelected,
      activeColor: Theme.of(context).colorScheme.primary,
      checkColor: Theme.of(context).colorScheme.onPrimary,
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
          backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                if (!removeFromLibrary && !deleteDownloads) {
                  messenger.hideCurrentSnackBar();
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
                  builder: (_) => PopScope(
                    canPop: false,
                    child: Dialog(
                      backgroundColor: Theme.of(context).cardColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 20),
                            const Flexible(
                              child: Text(
                                'Đang xóa dữ liệu...',
                                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );

                try {
                  // Xóa khỏi thư viện: lấy categories hiện tại → loại bỏ currentCategory → set lại (chạy song song)
                  if (removeFromLibrary) {
                    final removeFutures = _selectedMangaIds.map((id) async {
                      if (id.startsWith('LOCAL_NOVEL|')) {
                        await NovelService.instance.remove(id.substring('LOCAL_NOVEL|'.length));
                        return;
                      }
                      final cats = await LibraryService.instance
                          .getMangaCategories(id);
                      final newCats = cats
                          .where((c) => c != currentCategory)
                          .toList();
                      await LibraryService.instance.setMangaCategories(
                        id,
                        newCats,
                      );
                    });
                    await Future.wait(removeFutures);
                  }

                  // Xóa file tải: lấy tên truyện từ SQLite → gọi deleteMangaDownloads (chạy song song)
                  if (deleteDownloads) {
                    final deleteFutures = _selectedMangaIds.map((mangaId) async {
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
                        return true;
                      }
                      return false;
                    });
                    final results = await Future.wait(deleteFutures);
                    final successCount = results.where((r) => r).length;

                    if (mounted && successCount > 0) {
                      messenger.hideCurrentSnackBar();
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
                    messenger.hideCurrentSnackBar();
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
      initialData: LibraryService.instance.currentCategories.isNotEmpty
          ? LibraryService.instance.currentCategories
          : null,
      stream: _categoriesStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final categories = snapshot.data ?? ['Mặc định'];
        final canPop = !isSelectionMode && !_isSearching;

        return DefaultTabController(
          length: categories.length,
          child: SafeArea(
            bottom: false,
            child: PopScope(
              canPop: canPop,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) return;
                if (isSelectionMode) {
                  _clearSelection();
                } else if (_isSearching) {
                  setState(() {
                    _isSearching = false;
                    _searchQuery = '';
                    _searchController.clear();
                  });
                }
              },
              child: Scaffold(
              appBar: AppBar(
                // AppBar thay đổi hoàn toàn khi vào selection mode
                backgroundColor: isSelectionMode
                    ? const Color(0xFF1C1C1E)
                    : Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.85),
                flexibleSpace: isSelectionMode
                    ? null
                    : ClipRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(color: Colors.transparent),
                        ),
                      ),
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
                              textInputAction: TextInputAction.search,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'Tìm kiếm truyện trong mục...',
                                hintStyle: TextStyle(color: Colors.white54),
                                border: InputBorder.none,
                              ),
                              onChanged: (val) {
                                if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
                                _searchDebounce = Timer(const Duration(milliseconds: 150), () {
                                  if (mounted) setState(() => _searchQuery = val);
                                });
                              },
                            )
                          : const Text('Thư viện')),
                actions: isSelectionMode
                    ? [
                        Builder(
                          builder: (tabCtx) {
                            return IconButton(
                              icon: const Icon(Icons.select_all, color: Colors.white),
                              tooltip: 'Chọn tất cả trong mục',
                              onPressed: () async {
                                final tabIndex = DefaultTabController.of(tabCtx).index;
                                final currentCat = categories[tabIndex.clamp(0, categories.length - 1)];
                                final ids = await LibraryService.instance
                                    .streamMangasInCategory(currentCat)
                                    .first
                                    .timeout(const Duration(seconds: 3),
                                        onTimeout: () => <String>[]);
                                if (!mounted) return;
                                setState(() {
                                  if (_selectedMangaIds.containsAll(ids)) {
                                    _selectedMangaIds.removeAll(ids);
                                    if (_selectedMangaIds.isEmpty) {
                                      _clearSelection();
                                    }
                                  } else {
                                    _selectedMangaIds.addAll(ids);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ]
                    : (_isSearching
                        ? [
                            IconButton(
                              icon: const Icon(Icons.close),
                              tooltip: 'Đóng tìm kiếm',
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                setState(() {
                                  _isSearching = false;
                                  _searchQuery = '';
                                  _searchController.clear();
                                });
                              },
                            ),
                          ]
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
                              icon: const Icon(Icons.search),
                              tooltip: 'Tìm kiếm truyện',
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _isSearching = true;
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.filter_list),
                              tooltip: 'Bộ lọc & sắp xếp',
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                _showFilterBottomSheet();
                              },
                            ),
                            // Menu 3 chấm — quản lý danh mục + nhập truyện
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert),
                              color: Theme.of(context).cardColor,
                              onSelected: (val) async {
                                if (val == 'categories') {
                                  context.push('/settings/categories');
                                } else if (val == 'import_epub') {
                                  _pickEpub();
                                } else if (val == 'import_comic') {
                                  _pickComic();
                                } else if (val == 'scan_all') {
                                  final count = await LocalScanService.instance.scanAndImport();
                                  LibraryService.instance.notifyMappingChanged();
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Đã quét và đồng bộ $count truyện cục bộ'),
                                      backgroundColor: Theme.of(context).colorScheme.primary,
                                    ),
                                  );
                                  setState(() {});
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'import_epub',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.menu_book_outlined,
                                        color: Colors.amber,
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
                                PopupMenuItem(
                                  value: 'import_comic',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.auto_stories_outlined,
                                        color: Theme.of(context).colorScheme.primary,
                                        size: 20,
                                      ),
                                      SizedBox(width: 12),
                                      Text(
                                        'Nhập truyện tranh (CBZ, ZIP, PDF)',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'scan_all',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.refresh_rounded,
                                        color: Colors.tealAccent,
                                        size: 20,
                                      ),
                                      SizedBox(width: 12),
                                      Text(
                                        'Quét lại bộ nhớ máy',
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
                          ]),
                bottom: TabBar(
                  isScrollable: true,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.grey,
                  tabAlignment: TabAlignment.start,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 16),
                  tabs: categories.map((cat) {
                    return GestureDetector(
                      onLongPress: () {
                        HapticFeedback.mediumImpact();
                        context.push('/settings/categories');
                      },
                      child: Tab(text: cat),
                    );
                  }).toList(),
                ),
              ),
              body: TabBarView(
                children: categories.map((cat) {
                  return CategoryMangaList(
                    key: ValueKey('$cat-$_novelRefreshKey'),
                    category: cat,
                    searchQuery: _searchQuery,
                    selectedStatuses: _selectedStatuses,
                    selectedReadingStatuses: _selectedReadingStatuses,
                    selectedTags: _selectedTags,
                    filterDownloadedOnly: _filterDownloadedOnly,
                    sortMode: _sortMode,
                    viewMode: _viewMode,
                    selectedMangaIds: _selectedMangaIds,
                    onToggleSelect: (mangaId) {
                      setState(() {
                        if (_selectedMangaIds.contains(mangaId)) {
                          _selectedMangaIds.remove(mangaId);
                        } else {
                          _selectedMangaIds.add(mangaId);
                        }
                        UiService.instance.setMainBottomBarVisible(
                          _selectedMangaIds.isEmpty,
                        );
                      });
                    },
                  );
                }).toList(),
              ),
              // Action bar dưới — chỉ hiện khi selection mode
              bottomNavigationBar: isSelectionMode
                  ? Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        border: const Border(
                          top: BorderSide(color: Colors.white12, width: 0.5),
                        ),
                      ),
                      child: SafeArea(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            // Nút di chuyển sang danh mục khác
                            IconButton(
                              tooltip: 'Chuyển danh mục',
                              icon: const Icon(
                                Icons.folder_outlined,
                                color: Colors.white,
                              ),
                              onPressed: () async {
                                if (_selectedMangaIds.isNotEmpty) {
                                  final ids = _selectedMangaIds.toList();
                                  // Lấy categories của truyện đầu tiên làm trạng thái hiển thị ban đầu
                                  final cats = await LibraryService.instance
                                      .getMangaCategories(ids.first);
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
                              tooltip: 'Tải các truyện đã chọn',
                              icon: const Icon(
                                Icons.download_outlined,
                                color: Colors.white,
                              ),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    title: const Text(
                                      'Tải xuống?',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Theme.of(ctx).colorScheme.primary,
                                          foregroundColor: Theme.of(ctx).colorScheme.onPrimary,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Tải xuống', style: TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm != true) return;

                                if (!context.mounted) return;
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) => PopScope(
                                    canPop: false,
                                    child: Dialog(
                                      backgroundColor: Theme.of(context).cardColor,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                color: Theme.of(context).colorScheme.primary,
                                              ),
                                            ),
                                            const SizedBox(width: 20),
                                            const Flexible(
                                              child: Text(
                                                'Đang thêm vào hàng đợi tải...',
                                                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );

                                try {
                                  int totalChapters = 0;
                                  int skippedLocal = 0;
                                  final mangas = await DriveService.instance
                                      .getMangas();
                                  for (final mangaId in _selectedMangaIds) {
                                    if (mangaId.startsWith('LOCAL_NOVEL|') ||
                                        mangaId.startsWith('local_')) {
                                      skippedLocal++;
                                      continue;
                                    }
                                    final matchIndex = mangas.indexWhere(
                                      (m) => m.id == mangaId,
                                    );
                                    if (matchIndex == -1) continue;
                                    final manga = mangas[matchIndex];
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
                                    final skippedMsg = skippedLocal > 0
                                        ? ' (đã bỏ qua $skippedLocal truyện cục bộ)'
                                        : '';
                                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Đã thêm $totalChapters chương vào hàng đợi tải$skippedMsg',
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
                                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
                                  tooltip: 'Xóa khỏi thư viện',
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
