import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/download_service.dart';

/// Màn hình quản lý hàng đợi tải xuống (giống Mihon)
class DownloadQueuePage extends StatelessWidget {
  const DownloadQueuePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hàng đợi tải xuống'),
        actions: [
          // Nút Resume All
          StreamBuilder<Map<String, DownloadTask>>(
            stream: DownloadService.instance.downloadStream,
            builder: (context, snapshot) {
              final queue = snapshot.data ?? {};
              final hasPaused = queue.values.any(
                (task) => task.status == DownloadStatus.paused,
              );

              if (!hasPaused) return const SizedBox.shrink();

              return IconButton(
                icon: const Icon(Icons.play_arrow),
                tooltip: 'Tiếp tục tất cả',
                onPressed: () {
                  DownloadService.instance.resumeAll();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã tiếp tục tất cả')),
                  );
                },
              );
            },
          ),
          // Nút Pause All
          StreamBuilder<Map<String, DownloadTask>>(
            stream: DownloadService.instance.downloadStream,
            builder: (context, snapshot) {
              final queue = snapshot.data ?? {};
              final hasActive = queue.values.any(
                (task) =>
                    task.status == DownloadStatus.downloading ||
                    task.status == DownloadStatus.queued,
              );

              if (!hasActive) return const SizedBox.shrink();

              return IconButton(
                icon: const Icon(Icons.pause),
                tooltip: 'Tạm dừng tất cả',
                onPressed: () {
                  DownloadService.instance.pauseAll();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã tạm dừng tất cả')),
                  );
                },
              );
            },
          ),
          // Nút Clear All
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: 'Xóa tất cả',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: theme.cardColor,
                  title: Text(
                    'Xóa hàng đợi?',
                    style: theme.textTheme.titleLarge,
                  ),
                  content: Text(
                    'Bạn có chắc muốn xóa tất cả khỏi hàng đợi?',
                    style: theme.textTheme.bodyMedium,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Hủy'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text(
                        'Xóa',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );

              if (confirm == true && context.mounted) {
                DownloadService.instance.clearQueue();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã xóa hàng đợi')),
                );
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<Map<String, DownloadTask>>(
        stream: DownloadService.instance.downloadStream,
        builder: (context, snapshot) {
          final queue = snapshot.data ?? {};

          if (queue.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.download_done,
                    size: 64,
                    color: theme.iconTheme.color?.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Không có tải xuống nào',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            );
          }

          // Group theo manga (chỉ hiển thị tasks chưa completed)
          final groupedByManga = <String, List<DownloadTask>>{};
          for (final task in queue.values) {
            // Ẩn tasks đã completed
            if (task.status == DownloadStatus.completed) continue;

            groupedByManga.putIfAbsent(task.mangaId, () => []).add(task);
          }

          return ListView.builder(
            itemCount: groupedByManga.length,
            itemBuilder: (context, index) {
              final mangaId = groupedByManga.keys.elementAt(index);
              final tasks = groupedByManga[mangaId]!;
              final mangaTitle = tasks.first.mangaTitle;

              return _MangaDownloadGroup(
                mangaId: mangaId,
                mangaTitle: mangaTitle,
                tasks: tasks,
              );
            },
          );
        },
      ),
    );
  }
}

/// Widget hiển thị nhóm download của một manga
class _MangaDownloadGroup extends StatelessWidget {
  final String mangaId;
  final String mangaTitle;
  final List<DownloadTask> tasks;

  const _MangaDownloadGroup({
    required this.mangaId,
    required this.mangaTitle,
    required this.tasks,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completedCount = tasks
        .where((t) => t.status == DownloadStatus.completed)
        .length;
    final totalCount = tasks.length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: () => context.push('/manga/$mangaId'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mangaTitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$completedCount/$totalCount chương',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  // Actions
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Xóa tất cả chương của truyện này',
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: theme.cardColor,
                          title: Text(
                            'Xóa tất cả?',
                            style: theme.textTheme.titleLarge,
                          ),
                          content: Text(
                            'Xóa tất cả chương của "$mangaTitle" khỏi hàng đợi?',
                            style: theme.textTheme.bodyMedium,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Hủy'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text(
                                'Xóa',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        for (final task in tasks) {
                          await DownloadService.instance.cancelDownload(
                            task.chapterId,
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          // Danh sách chapters
          ...tasks.map((task) => _ChapterDownloadItem(task: task)),
        ],
      ),
    );
  }
}

/// Widget hiển thị một chapter đang tải
class _ChapterDownloadItem extends StatelessWidget {
  final DownloadTask task;

  const _ChapterDownloadItem({required this.task});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () {
        // Có thể mở reader nếu đã tải xong
        if (task.status == DownloadStatus.completed) {
          context.push('/reader/${task.chapterId}');
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Status Icon
            _buildStatusIcon(context, theme, task),
            const SizedBox(width: 16),
            // Chapter Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.chapterTitle,
                    style: theme.textTheme.bodyLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  _buildStatusText(theme),
                ],
              ),
            ),
            // Action Button
            _buildActionButton(context, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(
    BuildContext context,
    ThemeData theme,
    DownloadTask task,
  ) {
    switch (task.status) {
      case DownloadStatus.completed:
        return const Icon(Icons.check_circle, color: Colors.green, size: 32);
      case DownloadStatus.downloading:
        return SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: task.progress,
                strokeWidth: 4,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                backgroundColor: Colors.grey.withOpacity(0.2),
              ),
              Text(
                '${(task.progress * 100).toInt()}%',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      case DownloadStatus.queued:
        return SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
            backgroundColor: Colors.grey.withOpacity(0.2),
          ),
        );
      case DownloadStatus.paused:
        return const Icon(Icons.pause_circle, color: Colors.orange, size: 32);
      case DownloadStatus.failed:
        return const Icon(Icons.error, color: Colors.red, size: 32);
      default:
        return Icon(
          Icons.download,
          color: theme.iconTheme.color?.withOpacity(0.6),
          size: 32,
        );
    }
  }

  Widget _buildStatusText(ThemeData theme) {
    switch (task.status) {
      case DownloadStatus.completed:
        return Text(
          'Đã tải • ${_formatBytes(task.totalBytes ?? 0)}',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.green),
        );
      case DownloadStatus.downloading:
        final percent = (task.progress * 100).toInt();
        final downloaded = _formatBytes(task.downloadedBytes ?? 0);
        final total = _formatBytes(task.totalBytes ?? 0);
        return Text(
          'Đang tải $percent% • $downloaded / $total',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.primaryColor),
        );
      case DownloadStatus.queued:
        return Text('Đang chờ...', style: theme.textTheme.bodySmall);
      case DownloadStatus.paused:
        return Text(
          'Đã tạm dừng',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange),
        );
      case DownloadStatus.failed:
        return Text(
          'Lỗi: ${task.errorMessage ?? "Không xác định"}',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      default:
        return Text('', style: theme.textTheme.bodySmall);
    }
  }

  Widget _buildActionButton(BuildContext context, ThemeData theme) {
    switch (task.status) {
      case DownloadStatus.downloading:
      case DownloadStatus.queued:
        return IconButton(
          icon: const Icon(Icons.pause),
          tooltip: 'Tạm dừng',
          onPressed: () {
            DownloadService.instance.pauseDownload(task.chapterId);
          },
        );
      case DownloadStatus.paused:
        return IconButton(
          icon: const Icon(Icons.play_arrow),
          tooltip: 'Tiếp tục',
          onPressed: () {
            DownloadService.instance.resumeDownload(task.chapterId);
          },
        );
      case DownloadStatus.failed:
        return IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Thử lại',
          onPressed: () {
            DownloadService.instance.retryDownload(task.chapterId);
          },
        );
      default:
        return IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Xóa',
          onPressed: () {
            DownloadService.instance.cancelDownload(task.chapterId);
          },
        );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
