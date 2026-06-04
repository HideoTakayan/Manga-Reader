import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/drive_service.dart';
import '../../data/models_cloud.dart';
import '../shared/drive_image.dart';

class BannerManagerPage extends StatefulWidget {
  const BannerManagerPage({super.key});

  @override
  State<BannerManagerPage> createState() => _BannerManagerPageState();
}

class _BannerManagerPageState extends State<BannerManagerPage> {
  static const int _maxBannerItems = 20;

  final TextEditingController _searchController = TextEditingController();
  List<CloudManga> _allMangas = [];
  List<String> _bannerMangaIds = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<String, CloudManga> get _mangaById => {
    for (final manga in _allMangas) manga.id: manga,
  };

  List<CloudManga> get _selectedMangas => _bannerMangaIds
      .map((id) => _mangaById[id])
      .whereType<CloudManga>()
      .toList();

  List<CloudManga> get _filteredMangas {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _allMangas;
    return _allMangas.where((manga) {
      return manga.title.toLowerCase().contains(query) ||
          manga.author.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final mangas = await DriveService.instance.getMangas();
      final mangaIds = mangas.map((manga) => manga.id).toSet();
      final doc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('home_banner')
          .get();
      final bannerIds = doc.exists
          ? List<String>.from(doc.data()?['mangaIds'] ?? [])
          : <String>[];

      if (!mounted) return;
      setState(() {
        _allMangas = mangas;
        _bannerMangaIds = bannerIds
            .where(mangaIds.contains)
            .take(_maxBannerItems)
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  Future<void> _saveBanner() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('home_banner')
          .set({
            'mangaIds': _bannerMangaIds,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã lưu danh sách banner')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi khi lưu: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _toggleManga(String id) {
    if (!_bannerMangaIds.contains(id) &&
        _bannerMangaIds.length >= _maxBannerItems) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Banner tối đa 20 truyện.')));
      return;
    }

    setState(() {
      if (_bannerMangaIds.contains(id)) {
        _bannerMangaIds.remove(id);
        return;
      }
      _bannerMangaIds.add(id);
    });
  }

  void _reorderSelected(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final id = _bannerMangaIds.removeAt(oldIndex);
      _bannerMangaIds.insert(newIndex, id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý banner'),
        actions: [
          if (!_isLoading)
            TextButton.icon(
              onPressed: _isSaving ? null : _saveBanner,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: const Text('Lưu'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Đã chọn ${_bannerMangaIds.length}/$_maxBannerItems',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Tải lại',
                        onPressed: _loadData,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
                _SelectedBannerList(
                  selectedMangas: _selectedMangas,
                  onRemove: _toggleManga,
                  onReorder: _reorderSelected,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: _searchController.clear,
                              icon: const Icon(Icons.close),
                            ),
                      hintText: 'Tìm truyện để thêm vào banner',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _filteredMangas.length,
                    itemBuilder: (context, index) {
                      final manga = _filteredMangas[index];
                      final isSelected = _bannerMangaIds.contains(manga.id);

                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 44,
                            height: 64,
                            child: DriveImage(
                              fileId: manga.coverFileId,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        title: Text(
                          manga.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          manga.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Checkbox(
                          value: isSelected,
                          onChanged: (_) => _toggleManga(manga.id),
                        ),
                        onTap: () => _toggleManga(manga.id),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _SelectedBannerList extends StatelessWidget {
  final List<CloudManga> selectedMangas;
  final ValueChanged<String> onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;

  const _SelectedBannerList({
    required this.selectedMangas,
    required this.onRemove,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedMangas.isEmpty) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('Chưa chọn truyện nào cho banner.'),
      );
    }

    return SizedBox(
      height: 210,
      child: ReorderableListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        buildDefaultDragHandles: false,
        itemCount: selectedMangas.length,
        onReorder: onReorder,
        itemBuilder: (context, index) {
          final manga = selectedMangas[index];
          return Card(
            key: ValueKey(manga.id),
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle),
                  ),
                  const SizedBox(width: 8),
                  Text('#${index + 1}'),
                ],
              ),
              title: Text(
                manga.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                manga.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: 'Bỏ khỏi banner',
                onPressed: () => onRemove(manga.id),
                icon: const Icon(Icons.close),
              ),
            ),
          );
        },
      ),
    );
  }
}
