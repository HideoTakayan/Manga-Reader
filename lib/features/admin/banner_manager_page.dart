import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/content_type.dart';
import '../../data/drive_service.dart';
import '../../data/models_cloud.dart';
import '../catalog/catalog_cache_service.dart';
import '../shared/drive_image.dart';

class BannerManagerPage extends StatefulWidget {
  const BannerManagerPage({super.key});

  @override
  State<BannerManagerPage> createState() => _BannerManagerPageState();
}

class _BannerManagerPageState extends State<BannerManagerPage> {
  static const int _maxBannerItems = 20;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;
  List<CloudManga> _allMangas = [];
  List<String> _bannerMangaIds = [];
  List<String> _bannerNovelIds = [];
  MangaContentType _selectedContentType = MangaContentType.manga;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Map<String, CloudManga> get _mangaById => {
    for (final manga in _allMangas) manga.id: manga,
  };

  List<String> get _currentBannerIds => _selectedContentType.isNovel
      ? _bannerNovelIds
      : _bannerMangaIds;

  set _currentBannerIds(List<String> value) {
    if (_selectedContentType.isNovel) {
      _bannerNovelIds = value;
    } else {
      _bannerMangaIds = value;
    }
  }

  List<CloudManga> get _selectedMangas => _currentBannerIds
      .map((id) => _mangaById[id])
      .whereType<CloudManga>()
      .toList();

  List<CloudManga> get _filteredMangas {
    final query = CatalogCacheService.instance.normalize(_searchQuery.trim());
    final source = _allMangas
        .where((manga) => manga.contentType == _selectedContentType)
        .toList();
    if (query.isEmpty) return source;
    return source.where((manga) {
      final normTitle = CatalogCacheService.instance.normalize(manga.title);
      final normAuthor = CatalogCacheService.instance.normalize(manga.author);
      return normTitle.contains(query) || normAuthor.contains(query);
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
      final mangaBannerIds = doc.exists
          ? List<String>.from(doc.data()?['mangaIds'] ?? [])
          : <String>[];
      final novelBannerIds = doc.exists
          ? List<String>.from(doc.data()?['novelIds'] ?? [])
          : <String>[];

      if (!mounted) return;
      setState(() {
        _allMangas = mangas;
        _bannerMangaIds = mangaBannerIds
            .where(mangaIds.contains)
            .take(_maxBannerItems)
            .toList();
        _bannerNovelIds = novelBannerIds
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
            'novelIds': _bannerNovelIds,
            'updatedAt': FieldValue.serverTimestamp(),
          });

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
    final ids = List<String>.from(_currentBannerIds);
    if (!ids.contains(id) && ids.length >= _maxBannerItems) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Banner tối đa 20 truyện.')));
      return;
    }

    setState(() {
      final updatedIds = List<String>.from(_currentBannerIds);
      if (updatedIds.contains(id)) {
        updatedIds.remove(id);
        _currentBannerIds = updatedIds;
        return;
      }
      updatedIds.add(id);
      _currentBannerIds = updatedIds;
    });
  }

  void _reorderSelected(int oldIndex, int newIndex) {
    setState(() {
      final ids = List<String>.from(_currentBannerIds);
      if (newIndex > oldIndex) newIndex--;
      final id = ids.removeAt(oldIndex);
      ids.insert(newIndex, id);
      _currentBannerIds = ids;
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
                          'Đã chọn ${_currentBannerIds.length}/$_maxBannerItems',
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SegmentedButton<MangaContentType>(
                        segments: MangaContentType.values
                            .map(
                              (type) => ButtonSegment(
                                value: type,
                                label: Text(type.label),
                              ),
                            )
                            .toList(),
                        selected: {_selectedContentType},
                        onSelectionChanged: (value) {
                          setState(() => _selectedContentType = value.first);
                        },
                      ),
                      const SizedBox(width: 8),
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
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(fontSize: 13.5),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                              icon: const Icon(Icons.close, size: 18),
                            ),
                      hintText: 'Tìm truyện để thêm vào banner...',
                      hintStyle: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: (val) {
                      if (_debounce?.isActive ?? false) _debounce!.cancel();
                      _debounce = Timer(const Duration(milliseconds: 150), () {
                        if (mounted) setState(() => _searchQuery = val);
                      });
                    },
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _filteredMangas.length,
                    itemBuilder: (context, index) {
                      final manga = _filteredMangas[index];
                      final isSelected = _currentBannerIds.contains(manga.id);

                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
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
                          style: const TextStyle(fontWeight: FontWeight.w600),
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
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.view_carousel_outlined,
                size: 28,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Chưa chọn truyện nào cho banner',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
            const SizedBox(height: 4),
            Text(
              'Chọn các bộ truyện từ danh sách bên dưới để ghim lên đầu trang chủ.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 11.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            color: Theme.of(context).cardColor,
            elevation: 1,
            child: ListTile(
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: Icon(
                      Icons.drag_handle,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '#${index + 1}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              title: Text(
                manga.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                manga.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: 'Bỏ khỏi banner',
                onPressed: () => onRemove(manga.id),
                icon: const Icon(Icons.close, size: 18),
              ),
            ),
          );
        },
      ),
    );
  }
}
