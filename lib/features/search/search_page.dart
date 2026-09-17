import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/content_type.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../catalog/catalog_cache_service.dart';
import '../shared/drive_image.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum GenreFilterState { none, included, excluded }

enum SearchSortMode { updated, views, likes, title }

/// Bộ lọc theo quy mô số chương của truyện
enum ChapterCountFilter {
  all,    // Tất cả
  short,  // Truyện ngắn (< 20 chap)
  medium, // Truyện vừa (20 - 100 chap)
  long,   // Truyện dài (> 100 chap)
}

extension ChapterCountFilterX on ChapterCountFilter {
  String get label {
    switch (this) {
      case ChapterCountFilter.all:
        return 'Tất cả';
      case ChapterCountFilter.short:
        return '< 20 chương';
      case ChapterCountFilter.medium:
        return '20 - 100 chương';
      case ChapterCountFilter.long:
        return '> 100 chương';
    }
  }
}

/// Chế độ kết hợp các thể loại được chọn
enum GenreMatchMode {
  and, // Khớp tất cả (AND) - Phải có đủ các thể loại đã chọn
  or,  // Khớp bất kỳ (OR) - Chỉ cần có 1 trong các thể loại đã chọn
}

// Trang tìm kiếm — lọc realtime client-side trên catalog đã load sẵn.
// Hỗ trợ: tìm theo tên/tác giả + filter thể loại (include/exclude) + filter trạng thái.
// initialGenre: mở trang với genre được pre-select (navigate từ genre chip ở HomePage)
class SearchPage extends StatefulWidget {
  final String? initialQuery;
  final String? initialGenre;
  final String? initialContentType;
  const SearchPage({
    super.key,
    this.initialQuery,
    this.initialGenre,
    this.initialContentType,
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String query = '';
  List<CloudManga> allMangas = [];
  List<CloudManga> _filteredMangas = [];
  bool isLoading = true;

  Map<String, GenreFilterState> genreFilters = {};
  String? selectedStatus;
  ChapterCountFilter selectedChapterCount = ChapterCountFilter.all;
  GenreMatchMode genreMatchMode = GenreMatchMode.and;
  SearchSortMode sortMode = SearchSortMode.updated;
  List<String> allGenres = [];
  final List<String> allStatuses = ['Đang Cập Nhật', 'Hoàn Thành', 'Drop'];
  late MangaContentType contentType;

  // Debounce timer: chỏ 200ms sau khi user dừng gõ mới filter
  Timer? _debounce;
  Timer? _recentSearchDebounce;
  final TextEditingController _textController = TextEditingController();
  List<String> _recentSearches = [];

  @override
  void initState() {
    super.initState();
    contentType = parseContentType(widget.initialContentType);
    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      query = widget.initialQuery!.trim();
      _textController.text = query;
    }
    if (widget.initialGenre != null) {
      genreFilters[widget.initialGenre!] = GenreFilterState.included;
    }
    _loadRecentSearches();
    _loadMangas();
  }

  @override
  void didUpdateWidget(covariant SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuery != widget.initialQuery ||
        oldWidget.initialGenre != widget.initialGenre ||
        oldWidget.initialContentType != widget.initialContentType) {
      final newType = parseContentType(widget.initialContentType);
      if (newType != contentType) {
        contentType = newType;
        _loadRecentSearches();
      }
      if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
        query = widget.initialQuery!.trim();
        _textController.text = query;
      }
      if (widget.initialGenre != null) {
        genreFilters.clear();
        genreFilters[widget.initialGenre!] = GenreFilterState.included;
      }
      _loadMangas();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _recentSearchDebounce?.cancel();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _recentSearches = prefs.getStringList('recent_searches_${contentType.name}') ?? [];
      });
    }
  }

  Future<void> _saveRecentSearch(String term) async {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return;
    final list = List<String>.from(_recentSearches);
    list.remove(trimmed);
    list.insert(0, trimmed);
    if (list.length > 8) list.removeRange(8, list.length);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent_searches_${contentType.name}', list);
    if (mounted) {
      setState(() => _recentSearches = list);
    }
  }

  Future<void> _removeRecentSearch(String term) async {
    final list = List<String>.from(_recentSearches)..remove(term);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent_searches_${contentType.name}', list);
    if (mounted) {
      setState(() => _recentSearches = list);
    }
  }

  List<_SearchIndexedManga> _indexedMangas = [];

  void _updateFilteredMangas() {
    final normalizedQuery = CatalogCacheService.instance.normalize(query);
    final normalizedGenreFilters = {
      for (final entry in genreFilters.entries)
        CatalogCacheService.instance.normalize(entry.key): entry.value,
    };

    final includedGenres = normalizedGenreFilters.entries
        .where((e) => e.value == GenreFilterState.included)
        .map((e) => e.key)
        .toList();
    final excludedGenres = normalizedGenreFilters.entries
        .where((e) => e.value == GenreFilterState.excluded)
        .map((e) => e.key)
        .toList();

    final result = <CloudManga>[];
    for (final item in _indexedMangas) {
      if (normalizedQuery.isNotEmpty &&
          !item.normalizedSearchText.contains(normalizedQuery)) {
        continue;
      }

      // 1. Lọc theo thể loại
      if (excludedGenres.isNotEmpty) {
        if (excludedGenres.any((g) => item.normalizedGenres.contains(g))) {
          continue;
        }
      }

      if (includedGenres.isNotEmpty) {
        if (genreMatchMode == GenreMatchMode.and) {
          if (!includedGenres.every((g) => item.normalizedGenres.contains(g))) {
            continue;
          }
        } else {
          if (!includedGenres.any((g) => item.normalizedGenres.contains(g))) {
            continue;
          }
        }
      }
      // Lọc theo trạng thái
      if (selectedStatus != null) {
        final statusLower = item.statusLower;
        bool matchesStatus = true;
        if (selectedStatus == 'Đang Cập Nhật' ||
            selectedStatus == 'Đang tiến hành') {
          matchesStatus = statusLower.contains('cập nhật') ||
              statusLower.contains('tiến hành') ||
              statusLower.contains('đang') ||
              statusLower.contains('ongoing');
        } else if (selectedStatus == 'Hoàn Thành') {
          matchesStatus = statusLower.contains('hoàn') ||
              statusLower.contains('full') ||
              statusLower.contains('complete');
        } else if (selectedStatus == 'Drop') {
          matchesStatus = statusLower.contains('drop') ||
              statusLower.contains('ngừng') ||
              statusLower.contains('pause');
        } else {
          matchesStatus = item.manga.status == selectedStatus;
        }
        if (!matchesStatus) continue;
      }

      // Lọc theo quy mô số chương
      if (selectedChapterCount != ChapterCountFilter.all) {
        final count = item.manga.chapterOrder.length;
        if (selectedChapterCount == ChapterCountFilter.short && (count == 0 || count >= 20)) {
          continue;
        } else if (selectedChapterCount == ChapterCountFilter.medium && (count < 20 || count > 100)) {
          continue;
        } else if (selectedChapterCount == ChapterCountFilter.long && count <= 100) {
          continue;
        }
      }

      result.add(item.manga);
    }

    switch (sortMode) {
      case SearchSortMode.updated:
        result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
      case SearchSortMode.views:
        result.sort((a, b) => b.viewCount.compareTo(a.viewCount));
        break;
      case SearchSortMode.likes:
        result.sort((a, b) => b.likeCount.compareTo(a.likeCount));
        break;
      case SearchSortMode.title:
        result.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
    }

    _filteredMangas = result;
  }

  Future<void> _clearRecentSearches() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Xóa lịch sử tìm kiếm?',
          style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Toàn bộ từ khóa tìm kiếm gần đây sẽ bị xóa khỏi máy của bạn.',
          style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('recent_searches_${contentType.name}');
    if (mounted) {
      setState(() => _recentSearches = []);
    }
  }

  // Load toàn bộ catalog một lần duy nhất — filter chạy client-side sau đó
  // Dùng Set<String> để dedup genre tự động, rồi sort
  Future<void> _loadMangas({bool forceRefresh = false}) async {
    final cached = await CatalogCacheService.instance.getCachedCatalog();
    if (mounted && cached.isNotEmpty && !forceRefresh) {
      _applyCatalog(cached, loading: false);
    }

    final mangas = await DriveService.instance.getMangas(
      forceRefresh: forceRefresh,
    );
    if (mangas.isNotEmpty) {
      await CatalogCacheService.instance.saveCatalog(mangas);
    }
    if (mounted) {
      _applyCatalog(mangas.isNotEmpty ? mangas : cached, loading: false);
    }
  }

  void _applyCatalog(List<CloudManga> mangas, {required bool loading}) {
    setState(() {
      allMangas = mangas
          .where((manga) => manga.contentType == contentType)
          .toList();
      _indexedMangas = allMangas.map((c) {
        return _SearchIndexedManga(
          manga: c,
          normalizedSearchText: CatalogCacheService.instance.normalize(
            '${c.title} ${c.author} ${c.genres.join(' ')}',
          ),
          normalizedGenres: c.genres
              .map((g) => CatalogCacheService.instance.normalize(g))
              .toSet(),
          statusLower: c.status.toLowerCase(),
        );
      }).toList();
      final genres = <String>{};
      for (var c in allMangas) {
        genres.addAll(c.genres);
      }
      allGenres = genres.toList()..sort();
      isLoading = loading;
      _updateFilteredMangas();
    });
  }

  List<_SearchSuggestion> _getSuggestions(String rawQuery) {
    final q = CatalogCacheService.instance.normalize(rawQuery.trim());
    if (q.isEmpty) return const [];

    final suggestions = <_SearchSuggestion>[];
    final seen = <String>{};

    // 1. Gợi ý thể loại khớp
    for (final genre in allGenres) {
      final normG = CatalogCacheService.instance.normalize(genre);
      if (normG.contains(q) && !seen.contains('g:$genre')) {
        seen.add('g:$genre');
        suggestions.add(_SearchSuggestion(
          type: _SuggestionType.genre,
          text: genre,
          displayText: '#$genre',
        ));
        if (suggestions.length >= 3) break;
      }
    }

    // 2. Gợi ý tựa truyện khớp
    for (final item in _indexedMangas) {
      final normTitle = CatalogCacheService.instance.normalize(item.manga.title);
      if (normTitle.contains(q) && !seen.contains('m:${item.manga.id}')) {
        seen.add('m:${item.manga.id}');
        suggestions.add(_SearchSuggestion(
          type: _SuggestionType.title,
          text: item.manga.title,
          displayText: item.manga.title,
          manga: item.manga,
        ));
        if (suggestions.length >= 6) break;
      }
    }

    // 3. Gợi ý tác giả khớp
    for (final item in _indexedMangas) {
      if (item.manga.author.isEmpty) continue;
      final normAuthor = CatalogCacheService.instance.normalize(item.manga.author);
      if (normAuthor.contains(q) && !seen.contains('a:${item.manga.author}')) {
        seen.add('a:${item.manga.author}');
        suggestions.add(_SearchSuggestion(
          type: _SuggestionType.author,
          text: item.manga.author,
          displayText: 'Tác giả: ${item.manga.author}',
        ));
        if (suggestions.length >= 8) break;
      }
    }

    return suggestions;
  }

  List<String> _getTrendingGenres() {
    const popularKeys = [
      'Action', 'Manhwa', 'Tu Tiên', 'Isekai', 'Romance', 'Huyền Huyễn',
      'Hài Hước', 'Phiêu Lưu', 'Hệ Thống', 'Học Đường', 'Shounen', 'Drama',
      'Fantasy', 'Chuyển Sinh', 'Võ Thuật', 'Truyện Chữ'
    ];

    final result = <String>[];
    for (final key in popularKeys) {
      for (final g in allGenres) {
        if (g.toLowerCase() == key.toLowerCase() && !result.contains(g)) {
          result.add(g);
          break;
        }
      }
    }
    for (final g in allGenres) {
      if (!result.contains(g) && result.length < 12) {
        result.add(g);
      }
    }
    return result;
  }

  void _showRandomMangaSheet() {
    final pool = _filteredMangas.isNotEmpty ? _filteredMangas : allMangas;
    if (pool.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không có truyện nào để chọn ngẫu nhiên'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    final random = Random();
    CloudManga currentManga = pool[random.nextInt(pool.length)];

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context).colorScheme.primary,
                                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.casino_rounded, color: Theme.of(context).colorScheme.onPrimary, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Khám Phá Ngẫu Nhiên',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      context.push('/detail/${currentManga.id}');
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Theme.of(context).dividerColor),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: currentManga.coverFileId.isNotEmpty
                                ? DriveImage(
                                    fileId: currentManga.coverFileId,
                                    width: 80,
                                    height: 110,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    width: 80,
                                    height: 110,
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
                                    child: Icon(
                                      Icons.menu_book,
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentManga.title,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  currentManga.author.isNotEmpty ? currentManga.author : 'Chưa rõ tác giả',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Builder(
                                      builder: (context) {
                                        final isCompleted = currentManga.status.toLowerCase() == 'hoàn thành';
                                        final statusColor = isCompleted
                                            ? Colors.greenAccent
                                            : Theme.of(context).colorScheme.primary;
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: statusColor.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: statusColor.withValues(alpha: 0.4),
                                            ),
                                          ),
                                          child: Text(
                                            currentManga.status.isNotEmpty ? currentManga.status : 'Đang cập nhật',
                                            style: TextStyle(
                                              color: statusColor,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 6),
                                    if (currentManga.genres.isNotEmpty)
                                      Expanded(
                                        child: Text(
                                          currentManga.genres.take(2).join(', '),
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
                                            fontSize: 11,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (currentManga.description.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      currentManga.description,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            setModalState(() {
                              final subPool = pool.where((m) => m.id != currentManga.id).toList();
                              final targetPool = subPool.isNotEmpty ? subPool : pool;
                              currentManga = targetPool[random.nextInt(targetPool.length)];
                            });
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Đổi truyện khác'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(context).colorScheme.primary,
                            side: BorderSide(color: Theme.of(context).colorScheme.primary),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            context.push('/detail/${currentManga.id}');
                          },
                          icon: const Icon(Icons.menu_book_rounded, size: 18),
                          label: const Text('Xem ngay', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Theme.of(context).colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPresetsRow() {
    return Container(
      height: 36,
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          _presetChip(
            icon: Icons.casino_rounded,
            label: 'Khám phá ngẫu nhiên',
            iconColor: Theme.of(context).colorScheme.primary,
            onTap: _showRandomMangaSheet,
          ),
          const SizedBox(width: 8),
          _presetChip(
            icon: Icons.emoji_events_rounded,
            label: 'Top đã xong',
            iconColor: Colors.amberAccent,
            isSelected: selectedStatus == 'Hoàn Thành' && sortMode == SearchSortMode.views,
            onTap: () {
              setState(() {
                if (selectedStatus == 'Hoàn Thành' && sortMode == SearchSortMode.views) {
                  selectedStatus = null;
                  sortMode = SearchSortMode.updated;
                } else {
                  selectedStatus = 'Hoàn Thành';
                  sortMode = SearchSortMode.views;
                }
                _updateFilteredMangas();
              });
            },
          ),

          const SizedBox(width: 8),
          _presetChip(
            icon: Icons.favorite_rounded,
            label: 'Yêu thích nhất',
            iconColor: Colors.redAccent,
            isSelected: sortMode == SearchSortMode.likes,
            onTap: () {
              setState(() {
                sortMode = sortMode == SearchSortMode.likes
                    ? SearchSortMode.updated
                    : SearchSortMode.likes;
                _updateFilteredMangas();
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _presetChip({
    required IconData icon,
    required String label,
    required Color iconColor,
    bool isSelected = false,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? iconColor.withValues(alpha: 0.2)
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? iconColor : Theme.of(context).dividerColor,
            width: isSelected ? 1.2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? (iconColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white)
                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) {
          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.5,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) {
              return SingleChildScrollView(
                controller: scrollController,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Bộ Lọc Tìm Kiếm',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (genreFilters.isNotEmpty ||
                              selectedStatus != null ||
                              selectedChapterCount != ChapterCountFilter.all ||
                              genreMatchMode != GenreMatchMode.and)
                            TextButton.icon(
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                setStateModal(() {
                                  genreFilters.clear();
                                  selectedStatus = null;
                                  selectedChapterCount = ChapterCountFilter.all;
                                  genreMatchMode = GenreMatchMode.and;
                                });
                                setState(() {
                                  _updateFilteredMangas();
                                });
                              },
                              icon: Icon(Icons.refresh, size: 16, color: Theme.of(context).colorScheme.primary),
                              label: Text(
                                'Đặt lại',
                                style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Thể loại',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (genreFilters.values.contains(GenreFilterState.included))
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ChoiceChip(
                                    label: const Text('AND (Đủ)', style: TextStyle(fontSize: 11)),
                                    selected: genreMatchMode == GenreMatchMode.and,
                                    selectedColor: Theme.of(context).colorScheme.primary,
                                    visualDensity: VisualDensity.compact,
                                    onSelected: (val) {
                                      if (val) {
                                        setStateModal(() => genreMatchMode = GenreMatchMode.and);
                                        setState(() => _updateFilteredMangas());
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 4),
                                  ChoiceChip(
                                    label: const Text('OR (1 trong các)', style: TextStyle(fontSize: 11)),
                                    selected: genreMatchMode == GenreMatchMode.or,
                                    selectedColor: Theme.of(context).colorScheme.primary,
                                    visualDensity: VisualDensity.compact,
                                    onSelected: (val) {
                                      if (val) {
                                        setStateModal(() => genreMatchMode = GenreMatchMode.or);
                                        setState(() => _updateFilteredMangas());
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Ấn 1 lần để chọn (v), ấn 2 lần để loại trừ (x)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: allGenres.map((genre) {
                          final filterState =
                              genreFilters[genre] ?? GenreFilterState.none;

                          Color? backgroundColor;
                          Color labelColor =
                              Theme.of(context).textTheme.bodyLarge?.color ??
                              Colors.black;
                          Widget? icon;

                          if (filterState == GenreFilterState.included) {
                            backgroundColor = Theme.of(context).colorScheme.primary;
                            labelColor = Theme.of(context).colorScheme.onPrimary;
                            icon = Icon(
                              Icons.check,
                              size: 16,
                              color: Theme.of(context).colorScheme.onPrimary,
                            );
                          } else if (filterState == GenreFilterState.excluded) {
                            backgroundColor = Colors.red;
                            labelColor = Colors.white;
                            icon = const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.white,
                            );
                          } else {
                            backgroundColor = Theme.of(context).cardColor;
                          }

                          return ActionChip(
                            avatar: icon,
                            label: Text(genre),
                            backgroundColor: backgroundColor,
                            labelStyle: TextStyle(color: labelColor),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: filterState == GenreFilterState.none
                                    ? Colors.grey.withValues(alpha: 0.3)
                                    : Colors.transparent,
                              ),
                            ),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              // Vòng toggle: none → included → excluded → xóa khỏi map (none)
                              setStateModal(() {
                                if (filterState == GenreFilterState.none) {
                                  genreFilters[genre] =
                                      GenreFilterState.included;
                                } else if (filterState ==
                                    GenreFilterState.included) {
                                  genreFilters[genre] =
                                      GenreFilterState.excluded;
                                } else {
                                  genreFilters.remove(
                                    genre,
                                  ); // Về none: xóa key hoàn toàn
                                }
                              });
                              setState(() {
                                _updateFilteredMangas();
                              }); // Rebuild danh sách kết quả bên dưới modal
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Trạng thái',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: allStatuses.map((status) {
                          final isSelected = selectedStatus == status;
                          return ChoiceChip(
                            label: Text(status),
                            selected: isSelected,
                            selectedColor: Theme.of(context).colorScheme.primary,
                            backgroundColor: Theme.of(context).cardColor,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : Theme.of(
                                      context,
                                    ).textTheme.bodyLarge?.color,
                            ),
                            // ChoiceChip: tap khi đang selected → deselect (null)
                            onSelected: (selected) {
                              HapticFeedback.selectionClick();
                              setStateModal(
                                () => selectedStatus = selected ? status : null,
                              );
                              setState(() {
                                _updateFilteredMangas();
                              }); // Rebuild kết quả ngay
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Số lượng chương',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: ChapterCountFilter.values.map((filter) {
                          final isSelected = selectedChapterCount == filter;
                          return ChoiceChip(
                            label: Text(filter.label),
                            selected: isSelected,
                            selectedColor: Theme.of(context).colorScheme.primary,
                            backgroundColor: Theme.of(context).cardColor,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : Theme.of(
                                      context,
                                    ).textTheme.bodyLarge?.color,
                            ),
                            onSelected: (selected) {
                              HapticFeedback.selectionClick();
                              setStateModal(
                                () => selectedChapterCount = selected ? filter : ChapterCountFilter.all,
                              );
                              setState(() {
                                _updateFilteredMangas();
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Theme.of(context).colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Áp dụng', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      // Padding để tránh bị keyboard che khuất
                      SizedBox(
                        height: MediaQuery.of(context).viewInsets.bottom,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            controller: _textController,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: (val) {
              if (val.trim().isEmpty) {
                if (_debounce?.isActive ?? false) _debounce!.cancel();
                if (query.isNotEmpty) {
                  query = '';
                  setState(() {
                    _updateFilteredMangas();
                  });
                } else {
                  setState(() {});
                }
              } else {
                if (_debounce?.isActive ?? false) _debounce!.cancel();
                _debounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      query = val;
                  setState(() {
                    _updateFilteredMangas();
                  });
                });
              }

              // Tự động lưu từ khóa nếu người dùng dừng gõ sau 1.5s
              if (_recentSearchDebounce?.isActive ?? false) {
                _recentSearchDebounce!.cancel();
              }
              if (val.trim().length >= 2) {
                _recentSearchDebounce = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      if (mounted && query.trim().length >= 2) {
                    _saveRecentSearch(query);
                  }
                });
              }
            },
            onSubmitted: (val) {
              if (val.trim().isNotEmpty) {
                _saveRecentSearch(val);
              }
            },
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: contentType.isNovel ? 'Tìm novel...' : 'Tìm truyện...',
              hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              suffixIcon: _textController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                      onPressed: () {
                        _textController.clear();
                        if (_debounce?.isActive ?? false) _debounce!.cancel();
                        query = '';
                        setState(() {
                          _updateFilteredMangas();
                        });
                      },
                    )
                  : null,
            ),
          ),
        ),
        actions: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              genreFilters.isNotEmpty ||
                      selectedStatus != null ||
                      selectedChapterCount != ChapterCountFilter.all
                  ? Icons.filter_list_alt
                  : Icons.filter_list,
              color: genreFilters.isNotEmpty ||
                      selectedStatus != null ||
                      selectedChapterCount != ChapterCountFilter.all
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).iconTheme.color,
            ),
            tooltip: 'Bộ lọc',
            onPressed: _showFilterDialog,
          ),
          PopupMenuButton<SearchSortMode>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sắp xếp',
            initialValue: sortMode,
            color: Theme.of(context).cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (value) {
              setState(() {
                sortMode = value;
                _updateFilteredMangas();
              });
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: SearchSortMode.updated,
                child: Text('Mới cập nhật'),
              ),
              PopupMenuItem(
                value: SearchSortMode.views,
                child: Text('Lượt xem cao nhất'),
              ),
              PopupMenuItem(
                value: SearchSortMode.likes,
                child: Text('Yêu thích nhất'),
              ),
              PopupMenuItem(
                value: SearchSortMode.title,
                child: Text('Tên A-Z'),
              ),
            ],
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thanh preset lọc nhanh
                if (query.isEmpty) _buildPresetsRow(),

                // Gợi ý thông minh (Autocomplete suggestions) khi đang gõ
                if (_textController.text.trim().isNotEmpty) ...[
                  Builder(
                    builder: (context) {
                      final suggestions = _getSuggestions(_textController.text);
                      if (suggestions.isEmpty) return const SizedBox.shrink();
                      return Container(
                        height: 38,
                        color: Theme.of(context).cardColor.withValues(alpha: 0.5),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          itemCount: suggestions.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 6),
                          itemBuilder: (context, idx) {
                            final sug = suggestions[idx];
                            return InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                if (sug.type == _SuggestionType.genre) {
                                  setState(() {
                                    genreFilters[sug.text] = GenreFilterState.included;
                                    _textController.clear();
                                    query = '';
                                    _updateFilteredMangas();
                                  });
                                } else if (sug.type == _SuggestionType.title && sug.manga != null) {
                                  context.push('/detail/${sug.manga!.id}');
                                } else {
                                  _textController.text = sug.text;
                                  _textController.selection = TextSelection.fromPosition(
                                    TextPosition(offset: sug.text.length),
                                  );
                                  query = sug.text;
                                  setState(() {
                                    _updateFilteredMangas();
                                  });
                                  _saveRecentSearch(sug.text);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: sug.type == _SuggestionType.genre
                                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: sug.type == _SuggestionType.genre
                                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)
                                        : Theme.of(context).dividerColor,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      sug.type == _SuggestionType.genre
                                          ? Icons.tag_rounded
                                          : sug.type == _SuggestionType.author
                                              ? Icons.person_rounded
                                              : Icons.auto_stories_rounded,
                                      size: 13,
                                      color: sug.type == _SuggestionType.genre
                                          ? Theme.of(context).colorScheme.primary
                                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      sug.displayText,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: sug.type == _SuggestionType.genre
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: sug.type == _SuggestionType.genre
                                            ? Theme.of(context).colorScheme.primary
                                            : Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ],

                // Tìm kiếm gần đây
                if (query.isEmpty && _recentSearches.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.history_rounded, size: 18, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.9)),
                                const SizedBox(width: 6),
                                Text(
                                  'Tìm kiếm gần đây',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            InkWell(
                              onTap: _clearRecentSearches,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                child: Text(
                                  'Xóa tất cả',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _recentSearches.map((term) {
                            return Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Theme.of(context).dividerColor),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                                    onTap: () {
                                      _textController.text = term;
                                      _textController.selection =
                                          TextSelection.fromPosition(
                                        TextPosition(offset: term.length),
                                      );
                                      query = term;
                                      setState(() {
                                        _updateFilteredMangas();
                                      });
                                      _saveRecentSearch(term);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.history,
                                            size: 14,
                                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            term,
                                            style: TextStyle(
                                              color: Theme.of(context).colorScheme.onSurface,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
                                    onTap: () => _removeRecentSearch(term),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
                                      child: Icon(
                                        Icons.close,
                                        size: 13,
                                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                        Divider(color: Theme.of(context).dividerColor, height: 1),
                      ],
                    ),
                  ),

                // Thể loại thịnh hành (Trending genres)
                if (query.isEmpty && allGenres.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.local_fire_department_rounded, size: 18, color: Colors.deepOrangeAccent),
                            const SizedBox(width: 6),
                            Text(
                              'Thể loại thịnh hành',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _getTrendingGenres().map((genre) {
                            final isSelected = genreFilters[genre] == GenreFilterState.included;
                            return InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    genreFilters.remove(genre);
                                  } else {
                                    genreFilters[genre] = GenreFilterState.included;
                                  }
                                  _updateFilteredMangas();
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.deepOrangeAccent.withValues(alpha: 0.25)
                                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected ? Colors.deepOrangeAccent : Theme.of(context).dividerColor,
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  genre,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.deepOrangeAccent
                                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                        Divider(color: Theme.of(context).dividerColor, height: 1),
                      ],
                    ),
                  ),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final mangas = _filteredMangas;

                if (mangas.isEmpty) {
                  final hasActiveFilter = query.isNotEmpty ||
                      genreFilters.isNotEmpty ||
                      selectedStatus != null;

                  return RefreshIndicator(
                    onRefresh: () => _loadMangas(forceRefresh: true),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 80),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              Icons.search_off_rounded,
                              size: 48,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Center(
                          child: Text(
                            contentType.isNovel
                                ? 'Không tìm thấy novel phù hợp'
                                : 'Không tìm thấy truyện tranh phù hợp',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40),
                            child: Text(
                              hasActiveFilter
                                  ? 'Thử thay đổi từ khóa hoặc xóa bớt các tiêu chí lọc thể loại/trạng thái.'
                                  : 'Danh mục hiện chưa có nội dung. Vui lòng thử lại sau.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                        if (hasActiveFilter) ...[
                          const SizedBox(height: 16),
                          Center(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                _textController.clear();
                                query = '';
                                genreFilters.clear();
                                selectedStatus = null;
                                genreMatchMode = GenreMatchMode.and;
                                setState(() {
                                  _updateFilteredMangas();
                                });
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('Xóa bộ lọc & tìm lại'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Theme.of(context).colorScheme.primary,
                                side: BorderSide(
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () => _loadMangas(forceRefresh: true),
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: mangas.length,
                    padding: const EdgeInsets.all(12),
                    itemBuilder: (context, i) {
                      final manga = mangas[i];
                      return Container(
                        height: 140,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () {
                            if (query.trim().isNotEmpty) {
                              _saveRecentSearch(query);
                            }
                            context.push('/detail/${manga.id}');
                          },
                          child: Row(
                            children: [
                              DriveImage(
                                fileId: manga.coverFileId,
                                width: 100,
                                height: 140,
                                fit: BoxFit.cover,
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        manga.title,
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        manga.author,
                                        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13, fontWeight: FontWeight.w600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 6),
                                      if (manga.genres.isNotEmpty)
                                        SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            children: manga.genres.take(3).map((genre) => Padding(
                                              padding: const EdgeInsets.only(right: 6),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  genre,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                                  ),
                                                ),
                                              ),
                                            )).toList(),
                                          ),
                                        ),
                                      const Spacer(),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.remove_red_eye_rounded, size: 14, color: Colors.grey),
                                              const SizedBox(width: 4),
                                              Text(
                                                manga.viewCount.toString(),
                                                style: const TextStyle(color: Colors.grey, fontSize: 12),
                                              ),
                                            ],
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: manga.status == 'Đang Cập Nhật' ? Colors.blue.withValues(alpha: 0.2) : Colors.green.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              manga.status,
                                              style: TextStyle(
                                                color: manga.status == 'Đang Cập Nhật' ? Colors.blueAccent : Colors.greenAccent,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
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
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchIndexedManga {
  final CloudManga manga;
  final String normalizedSearchText;
  final Set<String> normalizedGenres;
  final String statusLower;

  _SearchIndexedManga({
    required this.manga,
    required this.normalizedSearchText,
    required this.normalizedGenres,
    required this.statusLower,
  });
}

enum _SuggestionType { genre, title, author }

class _SearchSuggestion {
  final _SuggestionType type;
  final String text;
  final String displayText;
  final CloudManga? manga;

  const _SearchSuggestion({
    required this.type,
    required this.text,
    required this.displayText,
    this.manga,
  });
}
