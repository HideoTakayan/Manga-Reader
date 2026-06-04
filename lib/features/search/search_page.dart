import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../catalog/catalog_cache_service.dart';
import '../shared/drive_image.dart';
import 'package:go_router/go_router.dart';

enum GenreFilterState { none, included, excluded }

enum SearchSortMode { updated, views, title }

// Trang tìm kiếm — lọc realtime client-side trên catalog đã load sẵn.
// Hỗ trợ: tìm theo tên/tác giả + filter thể loại (include/exclude) + filter trạng thái.
// initialGenre: mở trang với genre được pre-select (navigate từ genre chip ở HomePage)
class SearchPage extends StatefulWidget {
  final String? initialGenre;
  const SearchPage({super.key, this.initialGenre});

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

  // Debounce timer: chỏ 200ms sau khi user dừng gõ mới filter
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.initialGenre != null) {
      genreFilters[widget.initialGenre!] = GenreFilterState.included;
    }
    _loadMangas();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
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
      allMangas = mangas;
      final genres = <String>{};
      for (var c in mangas) {
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
        title: TextField(
          autofocus: true,
          onChanged: (val) {
            // Debounce 200ms: chỏ user dừng gõ mới rebuild kết quả
            if (_debounce?.isActive ?? false) _debounce!.cancel();
            _debounce = Timer(const Duration(milliseconds: 200), () {
              setState(() => query = val);
            });
          },
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: 'Tìm truyện...',
            hintStyle: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
            border: InputBorder.none,
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
          : Builder(
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
                            'Không tìm thấy truyện nào',
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
                    itemBuilder: (context, i) {
                      final manga = mangas[i];
                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: DriveImage(
                            fileId: manga.coverFileId,
                            width: 50,
                            height: 70,
                            fit: BoxFit.cover,
                          ),
                        ),
                        title: Text(
                          manga.title,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              manga.author,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            // Chỉ hiện 3 genre đầu để không quá dài
                            if (manga.genres.isNotEmpty)
                              Text(
                                manga.genres.take(3).join(', '),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.color
                                          ?.withValues(alpha: 0.7),
                                    ),
                              ),
                          ],
                        ),
                        onTap: () => context.push('/detail/${manga.id}'),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
