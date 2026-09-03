import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../../data/content_type.dart';
import '../../../data/models_cloud.dart';
import '../../../data/models_group.dart';
import '../../../services/interaction_service.dart';
import '../../../services/group_service.dart';
import '../../../services/library_status_service.dart';
import '../../shared/drive_image.dart';
import '../../shared/custom_tag_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';

class MangaHeaderSection extends StatelessWidget {
  final CloudManga manga;
  final int chaptersLength;

  const MangaHeaderSection({
    super.key,
    required this.manga,
    required this.chaptersLength,
  });

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        // Nền mờ
        Positioned.fill(
          child: DriveImage(fileId: manga.coverFileId, fit: BoxFit.cover),
        ),
        // Lớp phủ làm tối và hiệu ứng kính mờ (Frosted Glass)
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: Container(color: Colors.black.withValues(alpha: 0.4)),
            ),
          ),
        ),
        // Gradient che dưới (Hòa vào nền Scaffold)
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, theme.scaffoldBackgroundColor],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),

        // Nội dung chính
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 80, 16, 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ảnh bìa chính
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 120,
                  height: 160,
                  child: DriveImage(
                    fileId: manga.coverFileId,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Thông tin bên phải
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      manga.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        manga.contentType.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: manga.author.trim().isEmpty
                          ? null
                          : () {
                              HapticFeedback.selectionClick();
                              context.push(
                                Uri(
                                  path: '/search-global',
                                  queryParameters: {
                                    'q': manga.author.trim(),
                                    'type': manga.contentType.name,
                                  },
                                ).toString(),
                              );
                            },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.person_outline,
                              size: 16,
                              color: Colors.orangeAccent,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                manga.author,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                  decorationColor: Colors.white54,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            manga.status,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.list, size: 16, color: Colors.white70),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${manga.contentType.unitLabel} $chaptersLength',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (manga.uploaderGroupId != null && manga.uploaderGroupId!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _GroupBadge(groupId: manga.uploaderGroupId!),
                    ],
                    const SizedBox(height: 8),
                    _MangaStatsRow(
                      mangaId: manga.id,
                      initialViewCount: manga.viewCount,
                      initialLikeCount: manga.likeCount,
                      formatCount: _formatCount,
                    ),
                    const SizedBox(height: 8),
                    _RatingWidget(mangaId: manga.id),
                    const SizedBox(height: 10),
                    _ReadingStatusChip(mangaId: manga.id),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Widget con StatefulWidget để cache stream stats — tránh tạo Firestore stream
/// mới mỗi lần StatelessWidget parent rebuild.
class _MangaStatsRow extends StatefulWidget {
  final String mangaId;
  final int initialViewCount;
  final int initialLikeCount;
  final String Function(int) formatCount;

  const _MangaStatsRow({
    required this.mangaId,
    required this.initialViewCount,
    required this.initialLikeCount,
    required this.formatCount,
  });

  @override
  State<_MangaStatsRow> createState() => _MangaStatsRowState();
}

class _MangaStatsRowState extends State<_MangaStatsRow> {
  late Stream<Map<String, int>> _statsStream;

  @override
  void initState() {
    super.initState();
    _statsStream = InteractionService.instance.streamMangaStats(widget.mangaId);
  }

  @override
  void didUpdateWidget(_MangaStatsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mangaId != widget.mangaId) {
      _statsStream = InteractionService.instance.streamMangaStats(widget.mangaId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, int>>(
      stream: _statsStream,
      builder: (context, statsSnapshot) {
        final stats = statsSnapshot.data ?? {
          'viewCount': widget.initialViewCount,
          'likeCount': widget.initialLikeCount,
        };
        final viewCount = stats['viewCount'] ?? 0;
        final likeCount = stats['likeCount'] ?? 0;

        return Row(
          children: [
            const Icon(Icons.remove_red_eye_outlined, size: 16, color: Colors.white70),
            const SizedBox(width: 4),
            Text(
              widget.formatCount(viewCount),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(width: 16),
            const Icon(Icons.favorite_border, size: 16, color: Colors.white70),
            const SizedBox(width: 4),
            Text(
              widget.formatCount(likeCount),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        );
      },
    );
  }
}

class _RatingWidget extends StatefulWidget {
  final String mangaId;
  const _RatingWidget({required this.mangaId});

  @override
  State<_RatingWidget> createState() => _RatingWidgetState();
}

class _RatingWidgetState extends State<_RatingWidget> {
  int _userRating = 0;
  bool _isRating = false;
  late Stream<Map<String, dynamic>> _ratingStream;

  @override
  void initState() {
    super.initState();
    _ratingStream = InteractionService.instance.streamMangaRating(widget.mangaId);
    _loadUserRating();
  }

  @override
  void didUpdateWidget(_RatingWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mangaId != widget.mangaId) {
      _ratingStream = InteractionService.instance.streamMangaRating(widget.mangaId);
    }
  }

  Future<void> _loadUserRating() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _userRating = prefs.getInt('rating_${widget.mangaId}') ?? 0;
      });
    }
  }

  Future<void> _rate(int stars) async {
    if (_isRating) return; // Chỉ chặn khi đang xử lý, cho phép thay đổi
    if (_userRating == stars) return; // Bấm cùng sao — không làm gì
    HapticFeedback.lightImpact();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vui lòng đăng nhập để đánh giá truyện.'),
          ),
        );
      }
      return;
    }

    setState(() => _isRating = true);

    try {
      await InteractionService.instance.rateManga(widget.mangaId, stars);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('rating_${widget.mangaId}', stars);
      if (mounted) {
        setState(() => _userRating = stars);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cảm ơn bạn đã đánh giá $stars sao!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể lưu đánh giá: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isRating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: _ratingStream,
      builder: (context, snapshot) {
        final data = snapshot.data ?? {'sum': 0, 'count': 0};
        final sum = _readInt(data, 'sum');
        final count = _readInt(data, 'count');
        final double average = count > 0 ? sum / count : 0.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Tooltip(
                  message: _userRating > 0
                      ? 'Bạn đã đánh giá $_userRating sao — bấm để thay đổi'
                      : 'Bấm sao để đánh giá',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(5, (index) {
                      final starValue = index + 1;
                      return GestureDetector(
                        onTap: () => _rate(starValue),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            starValue <=
                                    (_userRating > 0 ? _userRating : average.round())
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            key: ValueKey('star_${starValue}_${_userRating}_${average.round()}'),
                            size: 18,
                            color: _userRating > 0 && starValue <= _userRating
                                ? Colors.orangeAccent
                                : Colors.amber,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(width: 6),
                if (_isRating)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
                  )
                else
                  Flexible(
                    child: Text(
                      average > 0
                          ? '${average.toStringAsFixed(1)} ($count lượt)'
                          : 'Chưa có đánh giá',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
            if (_userRating > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Đánh giá của bạn: $_userRating ★',
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  int _readInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _ReadingStatusChip extends StatefulWidget {
  final String mangaId;
  const _ReadingStatusChip({required this.mangaId});

  @override
  State<_ReadingStatusChip> createState() => _ReadingStatusChipState();
}

class _ReadingStatusChipState extends State<_ReadingStatusChip> {
  LibraryStatusEntry? _entry;

  @override
  void initState() {
    super.initState();
    LibraryStatusService.instance.addListener(_loadStatus);
    _loadStatus();
  }

  @override
  void dispose() {
    LibraryStatusService.instance.removeListener(_loadStatus);
    super.dispose();
  }

  Future<void> _loadStatus() async {
    final entry = await LibraryStatusService.instance.getEntry(widget.mangaId);
    if (mounted) setState(() => _entry = entry);
  }

  void _showStatusDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Text(
                    'Trạng thái đọc',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Divider(color: Colors.white12),
                ...MangaReadingStatus.values.map((status) {
                  final isSelected = _entry?.status == status;
                  final (label, icon, color) = LibraryStatusService.getStatusDisplay(status);
                  return ListTile(
                    leading: Icon(icon, color: color),
                    title: Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? color : Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected ? Icon(Icons.check, color: color) : null,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await LibraryStatusService.instance.setStatus(widget.mangaId, status);
                    },
                  );
                }),
                if (_entry != null) ...[
                  const Divider(color: Colors.white12),
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    title: const Text('Xóa trạng thái', style: TextStyle(color: Colors.redAccent)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await LibraryStatusService.instance.removeEntry(widget.mangaId);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _entry?.status;
    final tags = _entry?.tags ?? [];
    final (label, icon, color) = status != null
        ? LibraryStatusService.getStatusDisplay(status)
        : ('Đặt trạng thái đọc', Icons.add_circle_outline, Colors.white60);

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Reading status chip
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _showStatusDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (status != null ? color : Colors.white).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: (status != null ? color : Colors.white30).withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.arrow_drop_down, size: 16, color: color),
              ],
            ),
          ),
        ),

        // Custom tags
        ...tags.map((tag) => CustomTagBadge(
              tag: tag,
              isSmall: true,
              onTap: () async {
                final updated = await CustomTagManagerDialog.show(
                  context,
                  mangaId: widget.mangaId,
                  currentTags: tags,
                );
                if (updated != null) _loadStatus();
              },
            )),

        // Add Tag button
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            final updated = await CustomTagManagerDialog.show(
              context,
              mangaId: widget.mangaId,
              currentTags: tags,
            );
            if (updated != null) _loadStatus();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white24,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bookmark_add_outlined, size: 13, color: Colors.orangeAccent),
                SizedBox(width: 4),
                Text(
                  '+ Nhãn',
                  style: TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// StatefulWidget riêng để cache Future getGroupById — tránh gọi network
// mỗi lần build() của MangaHeaderSection (StatelessWidget) bị trigger lại.
class _GroupBadge extends StatefulWidget {
  final String groupId;
  const _GroupBadge({required this.groupId});

  @override
  State<_GroupBadge> createState() => _GroupBadgeState();
}

class _GroupBadgeState extends State<_GroupBadge> {
  late final Future<ScanlationGroup?> _future;

  @override
  void initState() {
    super.initState();
    _future = GroupService.instance.getGroupById(widget.groupId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ScanlationGroup?>(
      future: _future,
      builder: (context, snapshot) {
        final group = snapshot.data;
        if (group == null) return const SizedBox.shrink();
        return InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            HapticFeedback.selectionClick();
            context.push('/group/profile/${group.id}', extra: group);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.groups_2_outlined, size: 16, color: Colors.lightBlueAccent),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'Nhóm dịch: ${group.name}',
                    style: const TextStyle(
                      color: Colors.lightBlueAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.lightBlueAccent,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
