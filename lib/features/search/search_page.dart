import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/content_type.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../catalog/catalog_cache_service.dart';
import '../shared/drive_image.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum GenreFilterState { none, included, excluded }

enum SearchSortMode { updated, views, title }

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
  bool isLoading = true;

  Map<String, GenreFilterState> genreFilters = {};
  String? selectedStatus;
  SearchSortMode sortMode = SearchSortMode.updated;
  List<String> allGenres = [];
  final List<String> allStatuses = ['Đang Cập Nhật', 'Hoàn Thành', 'Drop'];
  late final MangaContentType contentType;

  // Debounce timer: chỏ 200ms sau khi user dừng gõ mới filter
  Timer? _debounce;
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
  void dispose() {
    _debounce?.cancel();
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

  Future<void> _clearRecentSearches() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xóa lịch sử tìm kiếm?'),
        content: const Text(
          'Toàn bộ từ khóa tìm kiếm gần đây sẽ bị xóa khỏi máy của bạn.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.redAccent)),
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
      final genres = <String>{};
      for (var c in allMangas) {
        genres.addAll(c.genres);
      }
      allGenres = genres.toList()..sort();
      isLoading = loading;
    });
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
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bộ Lọc Tìm Kiếm',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Thể loại',
                        style: Theme.of(context).textTheme.bodyMedium,
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
                            backgroundColor = Theme.of(context).primaryColor;
                            labelColor = Colors.white;
                            icon = const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.white,
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
                              setState(
                                () {},
                              ); // Rebuild danh sách kết quả bên dưới modal
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Trạng thái',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: allStatuses.map((status) {
                          final isSelected = selectedStatus == status;
                          return ChoiceChip(
                            label: Text(status),
                            selected: isSelected,
                            selectedColor: Theme.of(context).primaryColor,
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
                              setStateModal(
                                () => selectedStatus = selected ? status : null,
                              );
                              setState(() {}); // Rebuild kết quả ngay
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
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Áp dụng'),
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
            onChanged: (val) {
              // Debounce 200ms: chỏ user dừng gõ mới rebuild kết quả
              if (_debounce?.isActive ?? false) _debounce!.cancel();
              _debounce = Timer(const Duration(milliseconds: 200), () {
                setState(() => query = val);
                if (val.trim().length >= 2) {
                  _saveRecentSearch(val);
                }
              });
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
              suffixIcon: query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                      onPressed: () {
                        _textController.clear();
                        setState(() => query = '');
                      },
                    )
                  : null,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              genreFilters.isNotEmpty || selectedStatus != null
                  ? Icons.filter_list_alt
                  : Icons.filter_list,
              color: Theme.of(context).iconTheme.color,
            ),
            onPressed: _showFilterDialog,
          ),
          PopupMenuButton<SearchSortMode>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sắp xếp',
            initialValue: sortMode,
            onSelected: (value) => setState(() => sortMode = value),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: SearchSortMode.updated,
                child: Text('Mới cập nhật'),
              ),
              PopupMenuItem(
                value: SearchSortMode.views,
                child: Text('Lượt xem'),
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
                                Icon(Icons.history_rounded, size: 18, color: Colors.orangeAccent.withValues(alpha: 0.9)),
                                const SizedBox(width: 6),
                                const Text(
                                  'Tìm kiếm gần đây',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            InkWell(
                              onTap: _clearRecentSearches,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                child: Text('Xóa tất cả', style: TextStyle(color: Colors.white38, fontSize: 12)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _recentSearches.map((term) {
                            return InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                _textController.text = term;
                                setState(() => query = term);
                                _saveRecentSearch(term);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.search, size: 14, color: Colors.white54),
                                    const SizedBox(width: 6),
                                    Text(
                                      term,
                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                        const Divider(color: Colors.white10, height: 1),
                      ],
                    ),
                  ),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final normalizedQuery = CatalogCacheService.instance.normalize(
                        query,
                      );
                final mangas = allMangas.where((c) {
                  final searchText = CatalogCacheService.instance.normalize(
                    '${c.title} ${c.author} ${c.genres.join(' ')}',
                  );
                  final matchesQuery =
                      normalizedQuery.isEmpty ||
                      searchText.contains(normalizedQuery);

                  bool matchesGenre = true;
                  if (genreFilters.isNotEmpty) {
                    matchesGenre = genreFilters.entries.every((entry) {
                      if (entry.value == GenreFilterState.included) {
                        return c.genres.contains(entry.key);
                      }
                      if (entry.value == GenreFilterState.excluded) {
                        return !c.genres.contains(entry.key);
                      }
                      return true;
                    });
                  }

                  final matchesStatus =
                      selectedStatus == null || c.status == selectedStatus;

                  return matchesQuery && matchesGenre && matchesStatus;
                }).toList();

                switch (sortMode) {
                  case SearchSortMode.updated:
                    mangas.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
                    break;
                  case SearchSortMode.views:
                    mangas.sort((a, b) => b.viewCount.compareTo(a.viewCount));
                    break;
                  case SearchSortMode.title:
                    mangas.sort((a, b) => a.title.compareTo(b.title));
                    break;
                }

                if (mangas.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () => _loadMangas(forceRefresh: true),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 200),
                        Center(
                          child: Text(
                            contentType.isNovel
                                ? 'Không tìm thấy novel phù hợp'
                                : 'Không tìm thấy truyện tranh phù hợp',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).textTheme.bodySmall?.color,
                            ),
                          ),
                        ),
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
                          onTap: () => context.push('/detail/${manga.id}'),
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
                                        style: const TextStyle(color: Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.w600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 6),
                                      if (manga.genres.isNotEmpty)
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: manga.genres.take(3).map((genre) => Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              genre,
                                              style: const TextStyle(fontSize: 10, color: Colors.white70),
                                            ),
                                          )).toList(),
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
