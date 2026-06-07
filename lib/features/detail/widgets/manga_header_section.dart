import 'package:flutter/material.dart';
import '../../../data/content_type.dart';
import '../../../data/models_cloud.dart';
import '../../../services/interaction_service.dart';
import '../../shared/drive_image.dart';
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
                    Row(
                      children: [
                        const Icon(
                          Icons.person_outline,
                          size: 16,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            manga.author,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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
                        Text(
                          manga.status,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.list, size: 16, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text(
                          '${manga.contentType.unitLabel} $chaptersLength',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder<Map<String, int>>(
                      stream: InteractionService.instance.streamMangaStats(
                        manga.id,
                      ),
                      builder: (context, statsSnapshot) {
                        final stats =
                            statsSnapshot.data ??
                            {
                              'viewCount': manga.viewCount,
                              'likeCount': manga.likeCount,
                            };
                        final viewCount = stats['viewCount'] ?? 0;
                        final likeCount = stats['likeCount'] ?? 0;

                        return Row(
                          children: [
                            const Icon(
                              Icons.remove_red_eye_outlined,
                              size: 16,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatCount(viewCount),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 16),
                            const Icon(
                              Icons.favorite_border,
                              size: 16,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatCount(likeCount),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    _RatingWidget(mangaId: manga.id),
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

class _RatingWidget extends StatefulWidget {
  final String mangaId;
  const _RatingWidget({required this.mangaId});

  @override
  State<_RatingWidget> createState() => _RatingWidgetState();
}

class _RatingWidgetState extends State<_RatingWidget> {
  int _userRating = 0;
  bool _isRating = false;

  @override
  void initState() {
    super.initState();
    _loadUserRating();
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
    if (_userRating > 0 || _isRating) return; // Chỉ cho rate 1 lần
    setState(() => _isRating = true);

    try {
      await InteractionService.instance.rateManga(widget.mangaId, stars);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('rating_${widget.mangaId}', stars);
      if (mounted) setState(() => _userRating = stars);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể lưu đánh giá. Vui lòng thử lại.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isRating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: InteractionService.instance.streamMangaRating(widget.mangaId),
      builder: (context, snapshot) {
        final data = snapshot.data ?? {'sum': 0, 'count': 0};
        final sum = _readInt(data, 'sum');
        final count = _readInt(data, 'count');
        final double average = count > 0 ? sum / count : 0.0;

        return Row(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (index) {
                final starValue = index + 1;
                return GestureDetector(
                  onTap: () => _rate(starValue),
                  child: Icon(
                    starValue <=
                            (_userRating > 0 ? _userRating : average.round())
                        ? Icons.star
                        : Icons.star_border,
                    size: 16,
                    color: Colors.amber,
                  ),
                );
              }),
            ),
            const SizedBox(width: 4),
            Text(
              average > 0
                  ? '${average.toStringAsFixed(1)} ($count)'
                  : 'Chưa có',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
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
