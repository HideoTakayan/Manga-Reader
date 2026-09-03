import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../catalog/catalog_cache_service.dart';
import '../../../data/content_type.dart';
import '../../../data/models_cloud.dart';
import '../../../data/models.dart';
import '../../../data/database_helper.dart';
import '../../../services/download_service.dart';

class BulkDownloadSheet extends StatefulWidget {
  final List<CloudChapter> chapters;
  final CloudManga manga;
  final String? currentChapterId;

  const BulkDownloadSheet({
    super.key,
    required this.chapters,
    required this.manga,
    this.currentChapterId,
  });

  static Future<void> show(
    BuildContext context, {
    required List<CloudChapter> chapters,
    required CloudManga manga,
    String? currentChapterId,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final count = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BulkDownloadSheet(
        chapters: chapters,
        manga: manga,
        currentChapterId: currentChapterId,
      ),
    );

    if (count != null && count > 0 && context.mounted) {
      final router = GoRouter.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Đã thêm $count chương vào hàng đợi tải xuống'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'Xem',
            textColor: Colors.white,
            onPressed: () {
              messenger.hideCurrentSnackBar();
              router.push('/downloads');
            },
          ),
        ),
      );
    }
  }

  @override
  State<BulkDownloadSheet> createState() => _BulkDownloadSheetState();
}

class _BulkDownloadSheetState extends State<BulkDownloadSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Set<String> _selectedChapterIds = {};
  Set<String> _downloadedChapterIds = {};
  Set<String> _readChapterIds = {};
  bool _isLoading = true;

  int _rangeStartIndex = 0;
  int _rangeEndIndex = 0;
  final TextEditingController _chapterSearchController = TextEditingController();
  String _chapterSearchQuery = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _rangeStartIndex = 0;
    _rangeEndIndex = widget.chapters.isEmpty ? 0 : widget.chapters.length - 1;
    _loadDownloadedStatus();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _chapterSearchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDownloadedStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final downloaded = await DatabaseHelper.instance.getDownloadsByManga(widget.manga.id);
    final readIds = await DatabaseHelper.instance.getReadChapterIds(widget.manga.id, userId: uid);
    final downloadedSet = downloaded
        .map((d) => d['chapterId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    if (mounted) {
      setState(() {
        _downloadedChapterIds = downloadedSet;
        _readChapterIds = readIds;
        _isLoading = false;
      });
      _selectNextChapters(5);
    }
  }

  List<CloudChapter> get _undownloadedChapters {
    return widget.chapters.where((c) => !_downloadedChapterIds.contains(c.id)).toList();
  }

  int get _currentChapterIndex {
    if (widget.chapters.isEmpty) return 0;
    if (widget.currentChapterId == null) return 0;
    final idx = widget.chapters.indexWhere((c) => c.id == widget.currentChapterId);
    return idx >= 0 ? idx : 0;
  }

  void _selectNextChapters(int count) {
    if (widget.chapters.isEmpty) return;
    _selectedChapterIds.clear();
    final startIdx = _currentChapterIndex;
    final candidates = widget.chapters.skip(startIdx).where((c) => !_downloadedChapterIds.contains(c.id)).take(count);
    for (final c in candidates) {
      _selectedChapterIds.add(c.id);
    }
    setState(() {});
  }

  void _selectAllUndownloaded() {
    _selectedChapterIds.clear();
    for (final c in _undownloadedChapters) {
      _selectedChapterIds.add(c.id);
    }
    setState(() {});
  }

  void _selectUnreadUndownloaded() {
    _selectedChapterIds.clear();
    for (final c in _undownloadedChapters) {
      if (!_readChapterIds.contains(c.id)) {
        _selectedChapterIds.add(c.id);
      }
    }
    setState(() {});
  }

  void _invertSelection() {
    final inverted = <String>{};
    for (final c in _undownloadedChapters) {
      if (!_selectedChapterIds.contains(c.id)) {
        inverted.add(c.id);
      }
    }
    _selectedChapterIds.clear();
    _selectedChapterIds.addAll(inverted);
    setState(() {});
  }

  void _applyRangeSelection() {
    if (widget.chapters.isEmpty) return;
    _selectedChapterIds.clear();
    final start = _rangeStartIndex.clamp(0, widget.chapters.length - 1);
    final end = _rangeEndIndex.clamp(start, widget.chapters.length - 1);
    for (int i = start; i <= end; i++) {
      final c = widget.chapters[i];
      if (!_downloadedChapterIds.contains(c.id)) {
        _selectedChapterIds.add(c.id);
      }
    }
    setState(() {});
  }

  Future<void> _startDownload() async {
    if (_selectedChapterIds.isEmpty) return;

    final selectedList = widget.chapters.where((c) => _selectedChapterIds.contains(c.id)).toList();
    Navigator.pop(context, selectedList.length);

    final localInfo = Manga(
      id: widget.manga.id,
      title: widget.manga.title,
      coverUrl: widget.manga.coverFileId,
      author: widget.manga.author,
      description: widget.manga.description,
      genres: widget.manga.genres,
      contentType: widget.manga.contentType,
    );
    await DatabaseHelper.instance.saveLocalManga(localInfo);

    for (final chapter in selectedList) {
      await DownloadService.instance.addToQueue(
        chapterId: chapter.id,
        mangaId: widget.manga.id,
        mangaTitle: widget.manga.title,
        chapterTitle: chapter.title,
        fileType: chapter.fileType,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedCount = _selectedChapterIds.length;
    final isNovel = widget.manga.contentType == MangaContentType.novel;
    final estimatedMb = (selectedCount * (isNovel ? 0.6 : 14.5)).toStringAsFixed(1);

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, -4)),
        ],
      ),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header Sheet
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.download_for_offline, color: Colors.orange),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Tải chương hàng loạt',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Tổng: ${widget.chapters.length} chap • Chưa tải: ${_undownloadedChapters.length} chap',
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Đóng',
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                // Tabs
                TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.orange,
                  labelColor: Colors.orange,
                  unselectedLabelColor: Colors.white54,
                  tabs: const [
                    Tab(text: 'Tải nhanh'),
                    Tab(text: 'Theo khoảng'),
                    Tab(text: 'Chọn từng chap'),
                  ],
                ),

                // Tab Content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildQuickPresetTab(),
                      _buildRangePickerTab(),
                      _buildCheckboxListTab(),
                    ],
                  ),
                ),

                // Bottom Action Bar
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Đã chọn: $selectedCount chương',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Ước tính: ~$estimatedMb MB dung lượng',
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: selectedCount > 0 ? _startDownload : null,
                        icon: const Icon(Icons.download),
                        label: const Text('Bắt đầu tải', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.white12,
                          disabledForegroundColor: Colors.white38,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildQuickPresetTab() {
    final unreadUndownloadedCount = _undownloadedChapters
        .where((c) => !_readChapterIds.contains(c.id))
        .length;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildPresetTile(
          icon: Icons.bolt,
          title: '5 chương tiếp theo',
          subtitle: 'Tải 5 chap kế tiếp tính từ chap đang đọc',
          onTap: () => _selectNextChapters(5),
          isSelected: _selectedChapterIds.length == 5,
        ),
        const SizedBox(height: 12),
        _buildPresetTile(
          icon: Icons.flash_on,
          title: '10 chương tiếp theo',
          subtitle: 'Tải 10 chap kế tiếp để đọc offline',
          onTap: () => _selectNextChapters(10),
          isSelected: _selectedChapterIds.length == 10,
        ),
        const SizedBox(height: 12),
        _buildPresetTile(
          icon: Icons.offline_pin,
          title: '25 chương tiếp theo',
          subtitle: 'Tải gói 25 chap đọc thả ga',
          onTap: () => _selectNextChapters(25),
          isSelected: _selectedChapterIds.length == 25,
        ),
        const SizedBox(height: 12),
        _buildPresetTile(
          icon: Icons.mark_chat_unread_outlined,
          title: 'Chỉ các chương chưa đọc',
          subtitle: 'Tải $unreadUndownloadedCount chap chưa đọc và chưa tải về máy',
          onTap: _selectUnreadUndownloaded,
          isSelected: _selectedChapterIds.length == unreadUndownloadedCount && unreadUndownloadedCount > 0,
        ),
        const SizedBox(height: 12),
        _buildPresetTile(
          icon: Icons.all_inclusive,
          title: 'Tất cả chương chưa tải',
          subtitle: 'Tải toàn bộ ${_undownloadedChapters.length} chap còn lại',
          onTap: _selectAllUndownloaded,
          isSelected: _selectedChapterIds.length == _undownloadedChapters.length && _undownloadedChapters.isNotEmpty,
        ),
      ],
    );
  }

  Widget _buildPresetTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isSelected,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? Colors.orange.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? Colors.orange : Colors.white.withValues(alpha: 0.1),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.orange : Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isSelected ? Colors.orange : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              Icon(
                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isSelected ? Colors.orange : Colors.white30,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRangePickerTab() {
    if (widget.chapters.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
              child: const Icon(
                Icons.file_download_off_rounded,
                size: 40,
                color: Colors.white38,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Không có chương nào để tải',
              style: TextStyle(color: Colors.white60, fontSize: 14),
            ),
          ],
        ),
      );
    }
    final maxIdx = widget.chapters.length - 1;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Chọn phạm vi chương cần tải:',
            style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Từ chương', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      const SizedBox(height: 4),
                      DropdownButton<int>(
                        value: _rangeStartIndex,
                        isExpanded: true,
                        dropdownColor: Theme.of(context).cardColor,
                        underline: const SizedBox(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        items: List.generate(
                          widget.chapters.length,
                          (i) => DropdownMenuItem(
                            value: i,
                            child: Text(widget.chapters[i].title, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _rangeStartIndex = val;
                              if (_rangeEndIndex < _rangeStartIndex) {
                                _rangeEndIndex = _rangeStartIndex;
                              }
                            });
                            _applyRangeSelection();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Đến chương', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      const SizedBox(height: 4),
                      DropdownButton<int>(
                        value: _rangeEndIndex.clamp(_rangeStartIndex, maxIdx),
                        isExpanded: true,
                        dropdownColor: Theme.of(context).cardColor,
                        underline: const SizedBox(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        items: List.generate(
                          widget.chapters.length - _rangeStartIndex,
                          (offset) {
                            final i = _rangeStartIndex + offset;
                            return DropdownMenuItem(
                              value: i,
                              child: Text(widget.chapters[i].title, overflow: TextOverflow.ellipsis),
                            );
                          },
                        ),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _rangeEndIndex = val);
                            _applyRangeSelection();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: ElevatedButton.icon(
              onPressed: _applyRangeSelection,
              icon: const Icon(Icons.check),
              label: const Text('Áp dụng khoảng này', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white12,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckboxListTab() {
    final displayedChapters = _chapterSearchQuery.isEmpty
        ? widget.chapters
        : widget.chapters.where((c) {
            final q = CatalogCacheService.instance.normalize(_chapterSearchQuery.trim());
            final t = CatalogCacheService.instance.normalize(c.title);
            return t.contains(q);
          }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: TextField(
              controller: _chapterSearchController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Lọc nhanh tên hoặc số chương...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                prefixIcon: const Icon(Icons.search, size: 18, color: Colors.white38),
                suffixIcon: _chapterSearchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 14, color: Colors.white54),
                        onPressed: () {
                          _chapterSearchController.clear();
                          setState(() => _chapterSearchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (val) {
                if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 150), () {
                  if (mounted) setState(() => _chapterSearchQuery = val);
                });
              },
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              ActionChip(
                avatar: const Icon(Icons.select_all, size: 16),
                label: const Text('Tất cả chưa tải', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  _selectAllUndownloaded();
                },
              ),
              const SizedBox(width: 8),
              ActionChip(
                avatar: const Icon(Icons.mark_chat_unread_outlined, size: 16),
                label: const Text('Chỉ chưa đọc', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  _selectUnreadUndownloaded();
                },
              ),
              const SizedBox(width: 8),
              ActionChip(
                avatar: const Icon(Icons.swap_horiz, size: 16),
                label: const Text('Đảo chọn', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  _invertSelection();
                },
              ),
              const SizedBox(width: 8),
              ActionChip(
                avatar: const Icon(Icons.clear_all, size: 16),
                label: const Text('Bỏ chọn', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedChapterIds.clear());
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.white12),
        Expanded(
          child: displayedChapters.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                        child: const Icon(
                          Icons.search_off_rounded,
                          size: 32,
                          color: Colors.white38,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Không tìm thấy chương phù hợp',
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: displayedChapters.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
                  itemBuilder: (context, index) {
                    final chapter = displayedChapters[index];
                    final isDownloaded = _downloadedChapterIds.contains(chapter.id);
                    final isSelected = _selectedChapterIds.contains(chapter.id);

                    return CheckboxListTile(
                      value: isDownloaded ? true : isSelected,
                      enabled: !isDownloaded,
                      activeColor: isDownloaded ? Colors.green : Colors.orange,
                      title: Text(
                        chapter.title,
                        style: TextStyle(
                          color: isDownloaded ? Colors.white38 : Colors.white,
                          decoration: isDownloaded ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      subtitle: Text(
                        isDownloaded ? 'Đã tải xuống' : chapter.fileType.toUpperCase(),
                        style: TextStyle(color: isDownloaded ? Colors.green : Colors.white38, fontSize: 11),
                      ),
                      onChanged: isDownloaded
                          ? null
                          : (val) {
                              HapticFeedback.selectionClick();
                              setState(() {
                                if (val == true) {
                                  _selectedChapterIds.add(chapter.id);
                                } else {
                                  _selectedChapterIds.remove(chapter.id);
                                }
                              });
                            },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
