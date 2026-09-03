import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../services/tts_service.dart';
import '../../../services/novel_service.dart';
import '../../shared/drive_image.dart';

class MiniTtsPlayer extends StatelessWidget {
  const MiniTtsPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: TtsService.instance,
      builder: (context, _) {
        final tts = TtsService.instance;
        if (!tts.isVisible) {
          return const SizedBox.shrink();
        }

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onLongPress: () {
                  HapticFeedback.mediumImpact();
                  _showTtsQuickControlSheet(context, tts);
                },
                onTap: () {
                  if (tts.currentChapterId != null && tts.currentMangaId != null) {
                    if (tts.currentMangaId!.startsWith('LOCAL_NOVEL|')) {
                      final path = tts.currentMangaId!.replaceFirst('LOCAL_NOVEL|', '');
                      context.push(
                        '/novel-reader',
                        extra: LocalNovel(
                          title: tts.mangaTitle ?? 'Truyện chữ',
                          path: path,
                          importedAt: DateTime.now(),
                        ),
                      );
                    } else {
                      context.push(
                        '/reader/${tts.currentChapterId}?mangaId=${Uri.encodeComponent(tts.currentMangaId!)}',
                      );
                    }
                  }
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E22).withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Thin Progress Bar
                          if (tts.totalChunks > 0)
                            LinearProgressIndicator(
                              value: tts.progress,
                              minHeight: 2,
                              backgroundColor: Colors.white10,
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                            ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            child: Row(
                              children: [
                                // Cover Thumbnail
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: tts.coverUrl != null && tts.coverUrl!.isNotEmpty
                                        ? DriveImage(
                                            fileId: tts.coverUrl!,
                                            fit: BoxFit.cover,
                                          )
                                        : Container(
                                            color: Colors.blueAccent.withValues(alpha: 0.2),
                                            child: const Icon(
                                              Icons.auto_stories,
                                              color: Colors.blueAccent,
                                              size: 20,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 10),

                                // Title and chapter info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        tts.currentChapterTitle ?? 'Đang đọc truyện chữ',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              tts.mangaTitle ?? (tts.totalChunks > 0 ? 'Đoạn ${tts.chunkIndex + 1}/${tts.totalChunks}' : 'Giọng đọc AI'),
                                              style: const TextStyle(
                                                color: Colors.white60,
                                                fontSize: 11,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (tts.sleepMinutesRemaining > 0) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: Colors.amber.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                '${tts.sleepMinutesRemaining}p',
                                                style: const TextStyle(
                                                  color: Colors.amberAccent,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // Quick Control Sheet Button (Tune)
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                  tooltip: 'Tùy chỉnh đọc AI',
                                  icon: const Icon(
                                    Icons.tune_rounded,
                                    color: Colors.white70,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    _showTtsQuickControlSheet(context, tts);
                                  },
                                ),

                                // Previous Chunk Button
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                  tooltip: 'Đoạn trước',
                                  icon: const Icon(
                                    Icons.skip_previous_rounded,
                                    color: Colors.white70,
                                    size: 22,
                                  ),
                                  onPressed: tts.prevChunk,
                                ),

                                // Play / Pause Button
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  tooltip: tts.isPlaying ? 'Tạm dừng' : 'Tiếp tục',
                                  icon: Icon(
                                    tts.isPlaying
                                        ? Icons.pause_circle_filled_rounded
                                        : Icons.play_circle_filled_rounded,
                                    color: Colors.blueAccent,
                                    size: 30,
                                  ),
                                  onPressed: tts.togglePlayPause,
                                ),

                                // Next Chunk Button
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                  tooltip: 'Đoạn tiếp',
                                  icon: const Icon(
                                    Icons.skip_next_rounded,
                                    color: Colors.white70,
                                    size: 22,
                                  ),
                                  onPressed: tts.nextChunk,
                                ),

                                // Close Button
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                  tooltip: 'Tắt',
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.white38,
                                    size: 18,
                                  ),
                                  onPressed: tts.stopAndHide,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showTtsQuickControlSheet(BuildContext context, TtsService tts) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return ListenableBuilder(
          listenable: tts,
          builder: (context, _) {
            final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
            final sleepPresets = [0, 15, 30, 45, 60];

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle Bar
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
                    const SizedBox(height: 16),

                    // Header Info
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: tts.coverUrl != null && tts.coverUrl!.isNotEmpty
                                ? DriveImage(
                                    fileId: tts.coverUrl!,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: Colors.blueAccent.withValues(alpha: 0.2),
                                    child: const Icon(
                                      Icons.auto_stories,
                                      color: Colors.blueAccent,
                                      size: 24,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tts.currentChapterTitle ?? 'Đang đọc truyện chữ',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${tts.mangaTitle ?? 'Giọng đọc AI'} • Đoạn ${tts.chunkIndex + 1}/${max(1, tts.totalChunks)}',
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Progress bar
                    if (tts.totalChunks > 0) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: tts.progress,
                          minHeight: 6,
                          backgroundColor: Colors.white10,
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],

                    const Divider(color: Colors.white12),
                    const SizedBox(height: 10),

                    // Speed Setting Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.speed_rounded, size: 18, color: Colors.blueAccent),
                            SizedBox(width: 8),
                            Text(
                              'Tốc độ đọc',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                            ),
                          ],
                        ),
                        Text(
                          '${tts.rate.toStringAsFixed(2)}x',
                          style: const TextStyle(
                            color: Colors.blueAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: speeds.map((speed) {
                          final isSelected = (tts.rate - speed).abs() < 0.05;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text('${speed}x'),
                              selected: isSelected,
                              selectedColor: Colors.blueAccent,
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.white : Colors.white70,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                              onSelected: (selected) {
                                if (selected) {
                                  HapticFeedback.selectionClick();
                                  tts.setRate(speed);
                                }
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Sleep Timer Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.timer_rounded, size: 18, color: Colors.amberAccent),
                            SizedBox(width: 8),
                            Text(
                              'Hẹn giờ tắt',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                            ),
                          ],
                        ),
                        if (tts.sleepMinutesRemaining > 0)
                          Text(
                            'Còn ${tts.sleepMinutesRemaining} phút',
                            style: const TextStyle(
                              color: Colors.amberAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: sleepPresets.map((mins) {
                          final isSelected = mins == 0
                              ? tts.sleepMinutesRemaining <= 0
                              : tts.sleepMinutesRemaining == mins;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(mins == 0 ? 'Tắt hẹn giờ' : '$mins phút'),
                              selected: isSelected,
                              selectedColor: Colors.amberAccent,
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.black : Colors.white70,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                              onSelected: (selected) {
                                if (selected) {
                                  HapticFeedback.selectionClick();
                                  tts.setSleepTimer(mins);
                                }
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Large Playback Controls
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          iconSize: 36,
                          icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
                          tooltip: 'Đoạn trước',
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            tts.prevChunk();
                          },
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          iconSize: 56,
                          icon: Icon(
                            tts.isPlaying
                                ? Icons.pause_circle_filled_rounded
                                : Icons.play_circle_filled_rounded,
                            color: Colors.blueAccent,
                          ),
                          tooltip: tts.isPlaying ? 'Tạm dừng' : 'Tiếp tục',
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            tts.togglePlayPause();
                          },
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          iconSize: 36,
                          icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                          tooltip: 'Đoạn tiếp',
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            tts.nextChunk();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: const BorderSide(color: Colors.redAccent),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.stop_circle_outlined, size: 18),
                            label: const Text('Dừng đọc', style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: () {
                              Navigator.pop(ctx);
                              tts.stopAndHide();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.fullscreen_rounded, size: 18),
                            label: const Text('Mở trình đọc', style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: () {
                              Navigator.pop(ctx);
                              if (tts.currentChapterId != null && tts.currentMangaId != null) {
                                if (tts.currentMangaId!.startsWith('LOCAL_NOVEL|')) {
                                  final path = tts.currentMangaId!.replaceFirst('LOCAL_NOVEL|', '');
                                  context.push(
                                    '/novel-reader',
                                    extra: LocalNovel(
                                      title: tts.mangaTitle ?? 'Truyện chữ',
                                      path: path,
                                      importedAt: DateTime.now(),
                                    ),
                                  );
                                } else {
                                  context.push(
                                    '/reader/${tts.currentChapterId}?mangaId=${Uri.encodeComponent(tts.currentMangaId!)}',
                                  );
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
