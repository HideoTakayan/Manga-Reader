import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../data/content_type.dart';
import '../../../data/models_cloud.dart';
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
  String _selectedGenre = 'Tất cả';
  String _selectedStatus = 'Tất cả';

  CloudManga? _currentManga;
  bool _isRolling = false;
  Timer? _rollTimer;
  int _rollStep = 0;

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
    _availableGenres = ['Tất cả', ...sorted];
  }

  List<CloudManga> _getFilteredMangas() {
    return widget.mangas.where((m) {
      if (m.contentType != _contentType) return false;
      if (_selectedGenre != 'Tất cả' && !m.genres.contains(_selectedGenre)) {
        return false;
      }
      if (_selectedStatus != 'Tất cả') {
        final isCompleted = m.status.toLowerCase().contains('hoàn thành') ||
            m.status.toLowerCase().contains('full') ||
            m.status.toLowerCase().contains('complete');
        if (_selectedStatus == 'Hoàn thành' && !isCompleted) return false;
        if (_selectedStatus == 'Đang tiến hành' && isCompleted) return false;
      }
      return true;
    }).toList();
  }

  void _pickRandomManga({bool animate = true}) {
    final pool = _getFilteredMangas();
    if (pool.isEmpty) {
      setState(() {
        _currentManga = null;
        _isRolling = false;
      });
      return;
    }

    if (!animate) {
      final random = Random();
      setState(() {
        _currentManga = pool[random.nextInt(pool.length)];
        _isRolling = false;
      });
      return;
    }

    _rollTimer?.cancel();
    setState(() {
      _isRolling = true;
      _rollStep = 0;
    });

    const totalSteps = 12;
    final random = Random();

    void nextStep() {
      if (!mounted) return;
      _rollStep++;
      HapticFeedback.selectionClick();

      setState(() {
        _currentManga = pool[random.nextInt(pool.length)];
      });

      if (_rollStep >= totalSteps) {
        setState(() => _isRolling = false);
        HapticFeedback.mediumImpact();
      } else {
        // Slow down dynamically as the roll progresses
        final nextDelayMs = 50 + (_rollStep * _rollStep * 2);
        _rollTimer = Timer(Duration(milliseconds: nextDelayMs), nextStep);
      }
    }

    nextStep();
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
            border: Border.all(color: Colors.white12),
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
                    color: Colors.white24,
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
                            gradient: const LinearGradient(
                              colors: [Colors.purpleAccent, Colors.deepPurpleAccent],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.casino_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Khám Phá Ngẫu Nhiên',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white60),
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
                    // Manga / Novel toggle
                    ChoiceChip(
                      label: Text(_contentType.isManga ? 'Manga' : 'Novel'),
                      avatar: Icon(
                        _contentType.isManga ? Icons.auto_stories : Icons.menu_book,
                        size: 16,
                      ),
                      selected: true,
                      selectedColor: Colors.purpleAccent,
                      labelStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      onSelected: (_) {
                        setState(() {
                          _contentType = _contentType.isManga
                              ? MangaContentType.novel
                              : MangaContentType.manga;
                          _extractGenres();
                          _selectedGenre = 'Tất cả';
                        });
                        _pickRandomManga(animate: true);
                      },
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
                        'Đang tiến hành',
                        'Hoàn thành',
                      ].map((s) => PopupMenuItem(
                            value: s,
                            child: Text(
                              s,
                              style: TextStyle(
                                color: _selectedStatus == s
                                    ? Colors.purpleAccent
                                    : Colors.white,
                                fontWeight: _selectedStatus == s
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          )).toList(),
                      child: Chip(
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _selectedStatus == 'Tất cả'
                                  ? 'Trạng thái'
                                  : _selectedStatus,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            const Icon(
                              Icons.arrow_drop_down,
                              size: 16,
                              color: Colors.white70,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Genre Selector
                    PopupMenuButton<String>(
                      tooltip: 'Thể loại',
                      color: theme.cardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      onSelected: (val) {
                        setState(() => _selectedGenre = val);
                        _pickRandomManga(animate: true);
                      },
                      itemBuilder: (_) => _availableGenres
                          .take(20)
                          .map((g) => PopupMenuItem(
                                value: g,
                                child: Text(
                                  g,
                                  style: TextStyle(
                                    color: _selectedGenre == g
                                        ? Colors.purpleAccent
                                        : Colors.white,
                                    fontWeight: _selectedGenre == g
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ))
                          .toList(),
                      child: Chip(
                        backgroundColor: _selectedGenre != 'Tất cả'
                            ? Colors.purpleAccent.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.08),
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _selectedGenre == 'Tất cả'
                                  ? 'Thể loại'
                                  : _selectedGenre,
                              style: TextStyle(
                                color: _selectedGenre != 'Tất cả'
                                    ? Colors.purpleAccent
                                    : Colors.white70,
                                fontSize: 12,
                                fontWeight: _selectedGenre != 'Tất cả'
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            const Icon(
                              Icons.arrow_drop_down,
                              size: 16,
                              color: Colors.white70,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(color: Colors.white10, height: 1),

              // Main Showcase Area
              Expanded(
                child: manga == null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.search_off_rounded,
                              size: 48,
                              color: Colors.white38,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Không tìm thấy truyện phù hợp bộ lọc',
                              style: TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _selectedGenre = 'Tất cả';
                                  _selectedStatus = 'Tất cả';
                                });
                                _pickRandomManga(animate: true);
                              },
                              child: const Text('Đặt lại bộ lọc'),
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
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Manga Cover
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.purpleAccent
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
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                            height: 1.25,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.person_outline,
                                              size: 14,
                                              color: Colors.white60,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                manga.author.isNotEmpty
                                                    ? manga.author
                                                    : 'Đang cập nhật',
                                                style: const TextStyle(
                                                  color: Colors.white70,
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
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.purpleAccent
                                                      .withValues(alpha: 0.2),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: Colors.purpleAccent
                                                        .withValues(alpha: 0.4),
                                                  ),
                                                ),
                                                child: Text(
                                                  manga.status,
                                                  style: const TextStyle(
                                                    color: Colors.purpleAccent,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '${manga.chapterOrder.length} ${manga.contentType.unitLabel}',
                                              style: const TextStyle(
                                                color: Colors.white60,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),

                                        // Genre tags
                                        Wrap(
                                          spacing: 4,
                                          runSpacing: 4,
                                          children: manga.genres
                                              .take(3)
                                              .map((g) => Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white
                                                          .withValues(
                                                              alpha: 0.08),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4),
                                                    ),
                                                    child: Text(
                                                      g,
                                                      style: const TextStyle(
                                                        color: Colors.white70,
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
                              const SizedBox(height: 16),

                              // Description Synopsis Box
                              if (manga.description.trim().isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: Text(
                                    manga.description.trim(),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
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
                            foregroundColor: Colors.purpleAccent,
                            side: const BorderSide(color: Colors.purpleAccent),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: _isRolling
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.purpleAccent,
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
                            backgroundColor: Colors.purpleAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.auto_stories_rounded, size: 20),
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
