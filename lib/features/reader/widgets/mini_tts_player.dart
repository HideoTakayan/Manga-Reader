import 'dart:ui';
import 'package:flutter/material.dart';
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
                      context.push('/reader/${tts.currentChapterId}?mangaId=${tts.currentMangaId}');
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

                                // Speed Cycle Button
                                InkWell(
                                  onTap: tts.cycleSpeed,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    margin: const EdgeInsets.symmetric(horizontal: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                                    ),
                                    child: Text(
                                      '${tts.rate.toStringAsFixed(tts.rate.truncateToDouble() == tts.rate ? 0 : 2)}x',
                                      style: const TextStyle(
                                        color: Colors.blueAccent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),

                                // Sleep Timer Popup
                                PopupMenuButton<int>(
                                  tooltip: 'Hẹn giờ tắt',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                  icon: Icon(
                                    tts.sleepMinutesRemaining > 0
                                        ? Icons.alarm_on_rounded
                                        : Icons.alarm_rounded,
                                    color: tts.sleepMinutesRemaining > 0
                                        ? Colors.amberAccent
                                        : Colors.white60,
                                    size: 20,
                                  ),
                                  color: const Color(0xFF25252A),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  onSelected: (minutes) => tts.setSleepTimer(minutes),
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 0,
                                      child: Text('Tắt hẹn giờ', style: TextStyle(color: Colors.white70)),
                                    ),
                                    const PopupMenuItem(
                                      value: 15,
                                      child: Text('15 phút', style: TextStyle(color: Colors.white)),
                                    ),
                                    const PopupMenuItem(
                                      value: 30,
                                      child: Text('30 phút', style: TextStyle(color: Colors.white)),
                                    ),
                                    const PopupMenuItem(
                                      value: 45,
                                      child: Text('45 phút', style: TextStyle(color: Colors.white)),
                                    ),
                                    const PopupMenuItem(
                                      value: 60,
                                      child: Text('60 phút', style: TextStyle(color: Colors.white)),
                                    ),
                                  ],
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
}
