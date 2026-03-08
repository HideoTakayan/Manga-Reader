import 'package:flutter/material.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../shared/drive_image.dart';
import 'package:go_router/go_router.dart';

enum GenreFilterState { none, included, excluded }

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
  String? selectedStatus; // 
  List<String> allGenres = []; 
  final List<String> allStatuses = ['Đang Cập Nhật', 'Hoàn Thành', 'Drop'];

  @override
  void initState() {
    super.initState();
    if (widget.initialGenre != null) {
      genreFilters[widget.initialGenre!] = GenreFilterState.included;
    }
    _loadMangas();
  }

  // Load toàn bộ catalog một lần duy nhất — filter chạy client-side sau đó
  // Dùng Set<String> để dedup genre tự động, rồi sort
  Future<void> _loadMangas({bool forceRefresh = false}) async {
    final mangas = await DriveService.instance.getMangas(
      forceRefresh: forceRefresh,
    );
    if (mounted) {
      setState(() {
        allMangas = mangas;
        // Gom tất cả genre từ mọi truyện → Set dedup → sort alphabetical
        final genres = <String>{};
        for (var c in mangas) {
          genres.addAll(c.genres);
        }
        allGenres = genres.toList()..sort();
        isLoading = false;
      });
    }
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
                                    ? Colors.grey.withOpacity(0.3)
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
                      const Text(
                        'Trạng thái',
                        style: TextStyle(color: Colors.white70),
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
          onChanged: (val) =>
              setState(() => query = val), // Filter realtime mỗi ký tự
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
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Builder(
              builder: (context) {
                final mangas = allMangas.where((c) {
                  final q = query.toLowerCase();
                  final matchesQuery =
                      c.title.toLowerCase().contains(q) ||
                      c.author.toLowerCase().contains(q);

                  bool matchesGenre = true;
                  if (genreFilters.isNotEmpty) {
                    matchesGenre = genreFilters.entries.every((entry) {
                      if (entry.value == GenreFilterState.included)
                        return c.genres.contains(entry.key);
                      if (entry.value == GenreFilterState.excluded)
                        return !c.genres.contains(entry.key);
                      return true;
                    });
                  }

                  final matchesStatus =
                      selectedStatus == null || c.status == selectedStatus;

                  return matchesQuery && matchesGenre && matchesStatus;
                }).toList();

                if (mangas.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () => _loadMangas(forceRefresh: true),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 200),
                        Center(
                          child: Text(
                            'Không tìm thấy truyện nào',
                            style: TextStyle(color: Colors.white70),
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
                                          ?.withOpacity(0.7),
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
