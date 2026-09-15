import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../data/content_type.dart';
import '../../../data/models_cloud.dart';
import '../../../data/drive_service.dart';
import '../../shared/drive_image.dart';

class RandomMangaDialog extends StatefulWidget {
  final List<CloudManga> mangas;
  final MangaContentType initialContentType;

  const RandomMangaDialog({
    super.key,
    required this.mangas,
    required this.initialContentType,
  });

  static Future<void> show(
    BuildContext context, {
    required List<CloudManga> mangas,
    required MangaContentType initialContentType,
  }) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => RandomMangaDialog(
        mangas: mangas,
        initialContentType: initialContentType,
      ),
    );
  }

  @override
  State<RandomMangaDialog> createState() => _RandomMangaDialogState();
}

class _RandomMangaDialogState extends State<RandomMangaDialog>
    with SingleTickerProviderStateMixin {
  late MangaContentType _contentType;
  List<String> _selectedGenres = [];
  String _selectedStatus = 'Tất cả';

  CloudManga? _currentManga;
  bool _isRolling = false;
  Timer? _rollTimer;
  int _rollStep = 0;
  
  int? _realChapterCount;
  bool _isFetchingChapters = false;

  List<String> _availableGenres = ['Tất cả'];

  @override
  void initState() {
    super.initState();
    _contentType = widget.initialContentType;
    _extractGenres();
    _pickRandomManga(animate: false);
  }

  @override
  void dispose() {
    _rollTimer?.cancel();
    super.dispose();
  }

  void _extractGenres() {
    final genreSet = <String>{};
    for (final m in widget.mangas) {
      if (m.contentType == _contentType) {
        genreSet.addAll(m.genres);
      }
    }
    final sorted = genreSet.toList()..sort();
    _availableGenres = sorted;
  }

  List<CloudManga> _getFilteredMangas() {
    return widget.mangas.where((m) {
      if (m.contentType != _contentType) return false;
      if (_selectedGenres.isNotEmpty) {
        if (!_selectedGenres.every((g) => m.genres.contains(g))) return false;
      }
      if (_selectedStatus != 'Tất cả') {
        final ms = m.status.toLowerCase().trim();
        final ss = _selectedStatus.toLowerCase().trim();
        if (ss == 'đang cập nhật' && !ms.contains('cập nhật') && !ms.contains('tiến hành')) return false;
        if (ss == 'hoàn thành' && !ms.contains('hoàn thành')) return false;
        if (ss == 'drop' && !ms.contains('drop')) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _fetchRealChapterCount(String mangaId) async {
    setState(() {
      _isFetchingChapters = true;
      _realChapterCount = null;
    });
    try {
      final chapters = await DriveService.instance.getChapters(mangaId);
      if (mounted && _currentManga?.id == mangaId) {
        setState(() {
          _realChapterCount = chapters.length;
          _isFetchingChapters = false;
        });
      }
    } catch (e) {
      if (mounted && _currentManga?.id == mangaId) {
        setState(() => _isFetchingChapters = false);
      }
    }
  }

  void _pickRandomManga({bool animate = true}) {
    final pool = _getFilteredMangas();
    if (pool.isEmpty) {
      setState(() {
        _currentManga = null;
        _isRolling = false;
        _isFetchingChapters = false;
        _realChapterCount = null;
      });
      return;
    }

    final previousId = _currentManga?.id;
    if (!animate) {
      final random = Random();
      final targetPool = (pool.length > 1 && previousId != null)
          ? pool.where((m) => m.id != previousId).toList()
          : pool;
      setState(() {
        _currentManga = targetPool[random.nextInt(targetPool.length)];
        _isRolling = false;
        _realChapterCount = null;
      });
      if (_currentManga != null && _currentManga!.chapterOrder.isEmpty) {
        _fetchRealChapterCount(_currentManga!.id);
      }
      return;
    }

    _rollTimer?.cancel();
    setState(() {
      _isRolling = true;
      _rollStep = 0;
      _realChapterCount = null;
    });

    const totalSteps = 12;
    final random = Random();

    void nextStep() {
      if (!mounted) return;
      _rollStep++;
      HapticFeedback.selectionClick();

      if (_rollStep >= totalSteps) {
        // Đảm bảo khi có nhiều hơn 1 truyện thì kết quả quay ra là truyện mới
        final finalPool = (pool.length > 1 && previousId != null)
            ? pool.where((m) => m.id != previousId).toList()
            : pool;
        setState(() {
          _currentManga = finalPool[random.nextInt(finalPool.length)];
          _isRolling = false;
        });
        HapticFeedback.mediumImpact();
        if (_currentManga != null && _currentManga!.chapterOrder.isEmpty) {
          _fetchRealChapterCount(_currentManga!.id);
        }
      } else {
        setState(() {
          _currentManga = pool[random.nextInt(pool.length)];
        });
        // Slow down dynamically as the roll progresses
        final nextDelayMs = 50 + (_rollStep * _rollStep * 2);
        _rollTimer = Timer(Duration(milliseconds: nextDelayMs), nextStep);
      }
    }

    nextStep();
  }
  Future<void> _showGenreMultiSelectDialog() async {
    final primary = Theme.of(context).colorScheme.primary;
    final selected = await showDialog<List<String>>(
      context: context,
      builder: (ctx) {
        final localSelected = List<String>.from(_selectedGenres);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              title: const Text('Chọn Thể Loại'),
              content: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _availableGenres.map((g) {
                    final isSelected = localSelected.contains(g);
                    return FilterChip(
                      selected: isSelected,
                      selectedColor: primary.withValues(alpha: 0.25),
                      checkmarkColor: primary,
                      label: Text(
                        g, 
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected ? primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        )
                      ),
                      onSelected: (selected) {
                        setDialogState(() {
                          if (selected) {
                            localSelected.add(g);
                          } else {
                            localSelected.remove(g);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    localSelected.clear();
                    setDialogState(() {});
                  },
                  child: const Text('Bỏ chọn tất cả'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, localSelected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  child: const Text('Áp dụng'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected != null) {
      setState(() {
        _selectedGenres = selected;
      });
      _pickRandomManga(animate: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final manga = _currentManga;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor.withValues(alpha: isDark ? 0.94 : 0.97),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              // Drag Handle Bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Title Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                theme.colorScheme.primary,
                                theme.colorScheme.primary.withValues(alpha: 0.7),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.casino_rounded,
                            color: theme.colorScheme.onPrimary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Khám Phá Ngẫu Nhiên',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Filter Chips Row
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    // Manga / Novel toggle (Đồng bộ kiểu dáng với Trang chủ)
                    InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _contentType = _contentType.isManga
                              ? MangaContentType.novel
                              : MangaContentType.manga;
                          _extractGenres();
                          _selectedGenres.clear();
                        });
                        _pickRandomManga(animate: true);
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _contentType.isManga
                              ? theme.colorScheme.primary.withValues(alpha: 0.15)
                              : Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _contentType.isManga
                                ? theme.colorScheme.primary.withValues(alpha: 0.4)
                                : Colors.amber.withValues(alpha: 0.4),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _contentType.isManga
                                  ? Icons.auto_stories_rounded
                                  : Icons.menu_book_rounded,
                              size: 14,
                              color: _contentType.isManga
                                  ? theme.colorScheme.primary
                                  : Colors.amber,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _contentType.isManga ? 'Manga' : 'Novel',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _contentType.isManga
                                    ? theme.colorScheme.primary
                                    : Colors.amber,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Status chip
                    PopupMenuButton<String>(
                      tooltip: 'Trạng thái',
                      color: theme.cardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      onSelected: (val) {
                        setState(() => _selectedStatus = val);
                        _pickRandomManga(animate: true);
                      },
                      itemBuilder: (_) => [
                        'Tất cả',
                        'Đang Cập Nhật',
                        'Hoàn Thành',
                        'Drop',
                      ].map((s) => PopupMenuItem(
                            value: s,
                            child: Text(
                              s,
                              style: TextStyle(
                                fontSize: 14,
                                color: _selectedStatus == s
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface,
                                fontWeight: _selectedStatus == s
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          )).toList(),
                      child: Chip(
                        backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _selectedStatus == 'Tất cả'
                                  ? 'Trạng thái'
                                  : _selectedStatus,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                                fontSize: 12,
                              ),
                            ),
                            Icon(
                              Icons.arrow_drop_down,
                              size: 16,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Genre Selector
                    GestureDetector(
                      onTap: _showGenreMultiSelectDialog,
                      child: Chip(
                        backgroundColor: _selectedGenres.isNotEmpty
                            ? theme.colorScheme.primary.withValues(alpha: 0.2)
                            : theme.colorScheme.onSurface.withValues(alpha: 0.08),
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _selectedGenres.isEmpty
                                  ? 'Thể loại'
                                  : '${_selectedGenres.length} thể loại',
                              style: TextStyle(
                                color: _selectedGenres.isNotEmpty
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface.withValues(alpha: 0.8),
                                fontSize: 12,
                                fontWeight: _selectedGenres.isNotEmpty
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            Icon(
                              Icons.arrow_drop_down,
                              size: 16,
                              color: _selectedGenres.isNotEmpty
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface.withValues(alpha: 0.8),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Divider(color: theme.dividerColor, height: 1),

              // Main Showcase Area
              Expanded(
                child: manga == null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 48,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Không tìm thấy truyện phù hợp bộ lọc',
                              style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                              label: const Text('Đặt lại bộ lọc'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: theme.colorScheme.primary,
                                side: BorderSide(color: theme.colorScheme.primary),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () {
                                setState(() {
                                  _selectedGenres.clear();
                                  _selectedStatus = 'Tất cả';
                                });
                                _pickRandomManga(animate: true);
                              },
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          child: Column(
                            key: ValueKey(manga.id),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: _isRolling
                                    ? null
                                    : () {
                                        Navigator.pop(context);
                                        context.push('/detail/${manga.id}', extra: manga);
                                      },
                                behavior: HitTestBehavior.opaque,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                  // Manga Cover
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        boxShadow: [
                                          BoxShadow(
                                            color: theme.colorScheme.primary
                                                .withValues(alpha: 0.3),
                                            blurRadius: 16,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: SizedBox(
                                        width: 110,
                                        height: 155,
                                        child: DriveImage(
                                          fileId: manga.coverFileId,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),

                                  // Manga Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          manga.title,
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                            color: theme.colorScheme.onSurface,
                                            height: 1.25,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.person_outline,
                                              size: 14,
                                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                manga.author.isNotEmpty
                                                    ? manga.author
                                                    : 'Đang cập nhật',
                                                style: TextStyle(
                                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                                  fontSize: 12,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Builder(
                                                builder: (context) {
                                                  final isCompleted = manga.status == 'Hoàn Thành';
                                                  final statusColor = isCompleted
                                                      ? Colors.greenAccent
                                                      : theme.colorScheme.primary;
                                                  return Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: statusColor
                                                          .withValues(alpha: 0.2),
                                                      borderRadius:
                                                          BorderRadius.circular(6),
                                                      border: Border.all(
                                                        color: statusColor
                                                            .withValues(alpha: 0.4),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      manga.status,
                                                      style: TextStyle(
                                                        color: statusColor,
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Builder(builder: (context) {
                                                int count = manga.chapterOrder.length;
                                                if (count == 0 && _realChapterCount != null) {
                                                  count = _realChapterCount!;
                                                }
                                                return Text(
                                                  count > 0
                                                      ? '$count ${manga.contentType.unitLabel}'
                                                      : (_isFetchingChapters 
                                                          ? 'Đang kiểm tra...' 
                                                          : 'Chưa rõ số ${manga.contentType.unitLabel.toLowerCase()}'),
                                                  style: TextStyle(
                                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                                    fontSize: 12,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                );
                                              }),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),

                                        // Genre tags
                                        Wrap(
                                          spacing: 4,
                                          runSpacing: 4,
                                          children: manga.genres
                                              .map((g) => Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: theme.colorScheme.onSurface
                                                          .withValues(
                                                              alpha: 0.08),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4),
                                                    ),
                                                    child: Text(
                                                      g,
                                                      style: TextStyle(
                                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                                                        fontSize: 10,
                                                      ),
                                                    ),
                                                  ))
                                              .toList(),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                              // Description Synopsis Box
                              if (manga.description.trim().isNotEmpty) ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
                                  ),
                                  child: Text(
                                    manga.description.trim(),
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                            ],
                          ),
                        ),
                      ),
              ),

              // Bottom Actions Bar
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                  child: Row(
                    children: [
                      // Re-roll button
                      Expanded(
                        flex: 4,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.primary,
                            side: BorderSide(color: theme.colorScheme.primary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: _isRolling
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: theme.colorScheme.primary,
                                  ),
                                )
                              : const Icon(Icons.casino_rounded, size: 20),
                          label: Text(
                            _isRolling ? 'Đang quay...' : 'Quay bộ khác',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onPressed: _isRolling
                              ? null
                              : () => _pickRandomManga(animate: true),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Read Now button
                      Expanded(
                        flex: 5,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: Icon(
                            _contentType.isManga
                                ? Icons.auto_stories_rounded
                                : Icons.menu_book_rounded,
                            size: 20,
                          ),
                          label: const Text(
                            'Xem & Đọc ngay',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onPressed: manga == null || _isRolling
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  context.push('/detail/${manga.id}', extra: manga);
                                },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
