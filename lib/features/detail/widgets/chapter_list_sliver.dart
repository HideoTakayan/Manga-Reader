import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../data/models_cloud.dart';
import '../../../data/models.dart';
import '../../../services/download_service.dart';

class ChapterListSliver extends StatelessWidget {
  final List<CloudChapter> displayChapters;
  final String mangaId;
  final CloudManga manga;
  final Manga? localMangaInfo;
  final Map<String, int> chapterViews;
  final ThemeData theme;
  final VoidCallback onChapterRead;

  const ChapterListSliver({
    super.key,
    required this.displayChapters,
    required this.mangaId,
    required this.manga,
    required this.localMangaInfo,
    required this.chapterViews,
    required this.theme,
    required this.onChapterRead,
  });

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays > 0) return '${diff.inDays} ngày trước';
    if (diff.inHours > 0) return '${diff.inHours} giờ trước';
    return 'Mới đây';
  }

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final ch = displayChapters[index];
        return InkWell(
          onTap: () async {
            await context.push(
              '/reader/${ch.id}?mangaId=${Uri.encodeComponent(mangaId)}',
            );
            // Khi quay lại, làm mới toàn bộ dữ liệu để cập nhật views/history
            onChapterRead();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.1),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    ch.title,
                    style: theme.textTheme.bodyLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatDate(ch.uploadedAt),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    // chapterViews is streamed once by the parent to avoid one Firestore listener per row.
                    Row(
                      children: [
                        Icon(
                          Icons.remove_red_eye,
                          size: 10,
                          color: theme.textTheme.bodySmall?.color,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${chapterViews[ch.id] ?? ch.viewCount}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                // Download Icon với 3 trạng thái
                StreamBuilder<Map<String, DownloadTask>>(
                  stream: DownloadService.instance.downloadStream,
                  builder: (context, downloadSnapshot) {
                    final task = downloadSnapshot.data?[ch.id];

                    // Nếu đang tải
                    if (task?.status == DownloadStatus.downloading) {
                      return SizedBox(
                        width: 32,
                        height: 32,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: task!.progress,
                              strokeWidth: 3,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Colors.blue,
                              ),
                              backgroundColor: Colors.grey.withValues(
                                alpha: 0.3,
                              ),
                            ),
                            Text(
                              '${(task.progress * 100).toInt()}%',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: theme.brightness == Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    // Nếu đang chờ trong queue
                    if (task?.status == DownloadStatus.queued) {
                      return SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.orange,
                          ),
                          backgroundColor: Colors.grey.withValues(alpha: 0.3),
                        ),
                      );
                    }

                    // Nếu bị tạm dừng
                    if (task?.status == DownloadStatus.paused) {
                      return IconButton(
                        icon: const Icon(
                          Icons.pause_circle,
                          size: 28,
                          color: Colors.orange,
                        ),
                        onPressed: () {
                          DownloadService.instance.resumeDownload(ch.id);
                        },
                      );
                    }

                    // Nếu lỗi
                    if (task?.status == DownloadStatus.failed) {
                      return IconButton(
                        icon: const Icon(
                          Icons.error,
                          size: 28,
                          color: Colors.red,
                        ),
                        onPressed: () {
                          DownloadService.instance.retryDownload(ch.id);
                        },
                      );
                    }

                    // Kiểm tra đã tải chưa
                    return FutureBuilder<bool>(
                      future: DownloadService.instance.isDownloaded(
                        ch.id,
                        mangaId:
                            mangaId, // Sử dụng bộ đệm (cache) để kiểm tra nhanh hơn
                      ),
                      builder: (context, snapshot) {
                        final isDownloaded = snapshot.data ?? false;

                        return IconButton(
                          icon: Icon(
                            isDownloaded
                                ? Icons.check_circle
                                : Icons.download_outlined,
                            size: 28,
                            color: isDownloaded
                                ? Colors.green
                                : theme.iconTheme.color?.withValues(alpha: 0.6),
                          ),
                          onPressed: () async {
                            if (isDownloaded) {
                              // Xóa tải xuống
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: theme.cardColor,
                                  title: Text(
                                    'Xóa chương đã tải?',
                                    style: theme.textTheme.titleLarge,
                                  ),
                                  content: Text(
                                    'Bạn có chắc muốn xóa "${ch.title}" khỏi bộ nhớ máy?',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Hủy'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text(
                                        'Xóa',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true) {
                                await DownloadService.instance.deleteDownload(
                                  ch.id,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Đã xóa chương'),
                                    ),
                                  );
                                }
                              }
                            } else {
                              // Tải chương
                              await DownloadService.instance.addToQueue(
                                chapterId: ch.id,
                                mangaId: mangaId,
                                mangaTitle: manga.title,
                                chapterTitle: ch.title,
                                fileType: ch.fileType,
                                mangaInfo: localMangaInfo,
                              );

                              if (context.mounted) {
                                final router = GoRouter.of(context);
                                final messenger = ScaffoldMessenger.of(context);
                                messenger.hideCurrentSnackBar();
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'Đã thêm vào hàng đợi tải',
                                    ),
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
                ),
              ],
            ),
          ),
        );
      }, childCount: displayChapters.length),
    );
  }
}
