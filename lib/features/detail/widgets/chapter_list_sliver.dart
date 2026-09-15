import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/chapter_sort_helper.dart';
import '../../../data/database_helper.dart';
import '../../../data/models_cloud.dart';
import '../../../data/models.dart';
import '../../../services/download_service.dart';
import 'package:manga_reader/services/auth_service.dart';

class ChapterListSliver extends StatelessWidget {
  final List<CloudChapter> displayChapters;
  final List<CloudChapter>? allChapters;
  final String mangaId;
  final CloudManga manga;
  final Manga? localMangaInfo;
  final Map<String, int> chapterViews;
  final ThemeData theme;
  final VoidCallback onChapterRead;
  final Set<String> readChapterIds;
  final ReaderProgress? currentProgress;

  const ChapterListSliver({
    super.key,
    required this.displayChapters,
    this.allChapters,
    required this.mangaId,
    required this.manga,
    required this.localMangaInfo,
    required this.chapterViews,
    required this.theme,
    required this.onChapterRead,
    this.readChapterIds = const {},
    this.currentProgress,
  });

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays > 0) return '${diff.inDays} ngày trước';
    if (diff.inHours > 0) return '${diff.inHours} giờ trước';
    return 'Mới đây';
  }

  void _showChapterActionSheet({
    required BuildContext context,
    required CloudChapter chapter,
    required int index,
    required bool isRead,
  }) {
    HapticFeedback.mediumImpact();
    final uid = AuthService.safeUid;

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        chapter.title,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: theme.dividerColor),
              ListTile(
                leading: Icon(
                  Icons.chrome_reader_mode_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text(
                  'Đọc từ trang đầu',
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await context.push(
                    '/reader/${chapter.id}?mangaId=${Uri.encodeComponent(mangaId)}&page=0',
                  );
                  onChapterRead();
                },
              ),
              ListTile(
                leading: Icon(
                  isRead
                      ? Icons.mark_chat_unread_outlined
                      : Icons.check_circle_outline,
                  color: isRead ? Theme.of(context).colorScheme.primary : Colors.greenAccent,
                ),
                title: Text(
                  isRead ? 'Đánh dấu là chưa đọc' : 'Đánh dấu là đã đọc',
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (isRead) {
                    await DatabaseHelper.instance.markChapterAsUnread(
                      mangaId: mangaId,
                      chapterId: chapter.id,
                      userId: uid,
                    );
                  } else {
                    await DatabaseHelper.instance.markChapterAsRead(
                      mangaId: mangaId,
                      chapterId: chapter.id,
                      userId: uid,
                    );
                  }
                  onChapterRead();
                },
              ),
              ListTile(
                leading: const Icon(Icons.done_all, color: Colors.amberAccent),
                title: Text(
                  'Đánh dấu tất cả chương trước là đã đọc',
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ascendingChapters =
                      allChapters ?? ChapterSortHelper.sort(displayChapters);
                  final targetIndex = ascendingChapters.indexWhere(
                    (c) => c.id == chapter.id,
                  );
                  if (targetIndex >= 0) {
                    final previousChapterIds = ascendingChapters
                        .take(targetIndex + 1)
                        .map((c) => c.id)
                        .toList();
                    await DatabaseHelper.instance.markChaptersAsRead(
                      mangaId: mangaId,
                      chapterIds: previousChapterIds,
                      userId: uid,
                    );
                    onChapterRead();
                  }
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.remove_done,
                  color: Colors.deepOrangeAccent,
                ),
                title: Text(
                  'Đánh dấu tất cả chương sau là chưa đọc',
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ascendingChapters =
                      allChapters ?? ChapterSortHelper.sort(displayChapters);
                  final targetIndex = ascendingChapters.indexWhere(
                    (c) => c.id == chapter.id,
                  );
                  if (targetIndex >= 0) {
                    final subsequentChapterIds = ascendingChapters
                        .skip(targetIndex)
                        .map((c) => c.id)
                        .toList();
                    await DatabaseHelper.instance.markChaptersAsUnread(
                      mangaId: mangaId,
                      chapterIds: subsequentChapterIds,
                      userId: uid,
                    );
                    onChapterRead();
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (displayChapters.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_off_rounded,
                  size: 36,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
                ),
                const SizedBox(height: 8),
                Text(
                  'Không tìm thấy chương phù hợp',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final ch = displayChapters[index];
        final isRead = readChapterIds.contains(ch.id);
        final isCurrentlyReading =
            currentProgress != null &&
            currentProgress!.chapterId == ch.id &&
            !isRead;

        return InkWell(
          onTap: () async {
            HapticFeedback.selectionClick();
            await context.push(
              '/reader/${ch.id}?mangaId=${Uri.encodeComponent(mangaId)}',
            );
            // Khi quay lại, làm mới toàn bộ dữ liệu để cập nhật views/history
            onChapterRead();
          },
          onLongPress: () {
            _showChapterActionSheet(
              context: context,
              chapter: ch,
              index: index,
              isRead: isRead,
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isCurrentlyReading
                  ? theme.colorScheme.primary.withValues(alpha: 0.08)
                  : Colors.transparent,
              border: Border(
                left: isCurrentlyReading
                    ? BorderSide(color: theme.colorScheme.primary, width: 3.5)
                    : BorderSide.none,
                bottom: BorderSide(
                  color: isCurrentlyReading
                      ? theme.colorScheme.primary.withValues(alpha: 0.25)
                      : theme.dividerColor.withValues(alpha: 0.1),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          if (isCurrentlyReading) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Đang đọc',
                                style: TextStyle(
                                  color: theme.colorScheme.onPrimary,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ] else if (!isRead) ...[
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                          Expanded(
                            child: Text(
                              ch.title,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: isCurrentlyReading
                                    ? theme.colorScheme.primary
                                    : (isRead
                                        ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
                                        : theme.colorScheme.onSurface),
                                fontWeight: (isRead && !isCurrentlyReading)
                                    ? FontWeight.normal
                                    : FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            if (isCurrentlyReading &&
                                (currentProgress?.pageIndex ?? 0) > 0) ...[
                              Text(
                                'Đang ở trang ${currentProgress!.pageIndex + 1}',
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '•',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
                                  fontSize: 10,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              _formatDate(ch.uploadedAt),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isRead
                                    ? theme.colorScheme.onSurface.withValues(alpha: 0.24)
                                    : theme.colorScheme.onSurface.withValues(alpha: 0.54),
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '•',
                              style: TextStyle(
                                color: isRead
                                    ? theme.colorScheme.onSurface.withValues(alpha: 0.24)
                                    : theme.colorScheme.onSurface.withValues(alpha: 0.38),
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.remove_red_eye_outlined,
                              size: 11,
                              color: isRead
                                  ? theme.colorScheme.onSurface.withValues(alpha: 0.24)
                                  : theme.colorScheme.onSurface.withValues(alpha: 0.54),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${chapterViews[ch.id] ?? ch.viewCount}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isRead
                                    ? theme.colorScheme.onSurface.withValues(alpha: 0.24)
                                    : theme.colorScheme.onSurface.withValues(alpha: 0.54),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Nút Download độc lập (chỉ rebuild nút download khi có stream progress)
                _ChapterDownloadButton(
                  chapter: ch,
                  mangaId: mangaId,
                  manga: manga,
                  localMangaInfo: localMangaInfo,
                  theme: theme,
                  onStatusChanged: onChapterRead,
                ),
              ],
            ),
          ),
        );
      }, childCount: displayChapters.length),
    );
  }
}

class _ChapterDownloadButton extends StatelessWidget {
  final CloudChapter chapter;
  final String mangaId;
  final CloudManga manga;
  final Manga? localMangaInfo;
  final ThemeData theme;
  final VoidCallback? onStatusChanged;

  const _ChapterDownloadButton({
    required this.chapter,
    required this.mangaId,
    required this.manga,
    required this.localMangaInfo,
    required this.theme,
    this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, DownloadTask>>(
      stream: DownloadService.instance.downloadStream,
      initialData: DownloadService.instance.currentQueue,
      builder: (context, downloadSnapshot) {
        final task = downloadSnapshot.data?[chapter.id];

        // 1. Nếu đang tải
        if (task?.status == DownloadStatus.downloading) {
          final progressPercent = (task!.progress * 100).toInt();
          return Tooltip(
            message: 'Đang tải $progressPercent% • Bấm để tạm dừng',
            child: InkWell(
              onTap: () => DownloadService.instance.pauseDownload(chapter.id),
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: task.progress > 0 ? task.progress : null,
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.primary,
                      ),
                      backgroundColor: Colors.grey.withValues(alpha: 0.3),
                    ),
                    Text(
                      '$progressPercent%',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // 2. Nếu đang chờ trong queue
        if (task?.status == DownloadStatus.queued) {
          return Tooltip(
            message: 'Đang chờ tải • Bấm để tạm dừng',
            child: InkWell(
              onTap: () => DownloadService.instance.pauseDownload(chapter.id),
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Colors.orange,
                  ),
                  backgroundColor: Colors.grey.withValues(alpha: 0.3),
                ),
              ),
            ),
          );
        }

        // 3. Nếu bị tạm dừng
        if (task?.status == DownloadStatus.paused) {
          return IconButton(
            icon: const Icon(
              Icons.play_circle_outline_rounded,
              size: 28,
              color: Colors.orange,
            ),
            tooltip: 'Tiếp tục tải (${(task!.progress * 100).toInt()}%)',
            onPressed: () {
              DownloadService.instance.resumeDownload(chapter.id);
            },
          );
        }

        // 4. Nếu lỗi
        if (task?.status == DownloadStatus.failed) {
          return IconButton(
            icon: const Icon(Icons.error, size: 28, color: Colors.red),
            tooltip: 'Thử lại tải xuống',
            onPressed: () {
              DownloadService.instance.retryDownload(chapter.id);
            },
          );
        }

        // 5. Kiểm tra đã tải chưa (Database / Cache)
        return FutureBuilder<bool>(
          future: DownloadService.instance.isDownloaded(
            chapter.id,
            mangaId: mangaId,
          ),
          builder: (context, snapshot) {
            final isDownloaded = snapshot.data ?? false;

            return IconButton(
              icon: Icon(
                isDownloaded ? Icons.check_circle : Icons.download_outlined,
                size: 28,
                color: isDownloaded
                    ? Colors.green
                    : theme.iconTheme.color?.withValues(alpha: 0.6),
              ),
              onPressed: () async {
                HapticFeedback.lightImpact();
                if (isDownloaded) {
                  // Xóa tải xuống
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (dialogCtx) => AlertDialog(
                      backgroundColor:
                          Theme.of(dialogCtx).dialogTheme.backgroundColor ??
                          theme.cardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      title: Text(
                        'Xóa chương đã tải?',
                        style: TextStyle(
                          color: Theme.of(dialogCtx).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      content: Text(
                        'Bạn có chắc muốn xóa "${chapter.title}" khỏi bộ nhớ máy?',
                        style: TextStyle(
                          color: Theme.of(dialogCtx).colorScheme.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogCtx, false),
                          child: const Text(
                            'Hủy',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => Navigator.pop(dialogCtx, true),
                          child: const Text(
                            'Xóa',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    await DownloadService.instance.deleteDownload(chapter.id);
                    onStatusChanged?.call();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Đã xóa "${chapter.title}" khỏi máy'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  }
                } else {
                  // Tải chương
                  await DownloadService.instance.addToQueue(
                    chapterId: chapter.id,
                    mangaId: mangaId,
                    mangaTitle: manga.title,
                    chapterTitle: chapter.title,
                    fileType: chapter.fileType,
                    mangaInfo: localMangaInfo,
                  );

                  if (context.mounted) {
                    final router = GoRouter.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    messenger.hideCurrentSnackBar();
                    messenger.showSnackBar(
                      SnackBar(
                        content: const Text('Đã thêm vào hàng đợi tải'),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 3),
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
              },
            );
          },
        );
      },
    );
  }
}
