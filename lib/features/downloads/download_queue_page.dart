import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/download_service.dart';

// Trang quản lý hàng đợi tải xuống — hiển thị tất cả task đang tải, chờ, lỗi, tạm dừng.
// Là StatelessWidget vì toàn bộ state đến từ DownloadService.downloadStream (Stream).
class DownloadQueuePage extends StatelessWidget {
  const DownloadQueuePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hàng đợi tải xuống'),
        actions: [
          // Nút "Tiếp tục tất cả" — chỉ hiện khi có ít nhất 1 task đang paused
          StreamBuilder<Map<String, DownloadTask>>(
            stream: DownloadService.instance.downloadStream,
            builder: (context, snapshot) {
              final queue = snapshot.data ?? {};
              final hasFailed = queue.values.any(
                (t) => t.status == DownloadStatus.failed,
              );
              if (!hasFailed) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Thử lại tất cả lỗi',
                onPressed: () {
                  DownloadService.instance.retryAllFailed();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Đã thử lại tất cả tải xuống bị lỗi'),
                    ),
                  );
                },
              );
            },
          ),
          StreamBuilder<Map<String, DownloadTask>>(
            stream: DownloadService.instance.downloadStream,
            builder: (context, snapshot) {
              final queue = snapshot.data ?? {};
              final hasPaused = queue.values.any(
                (t) => t.status == DownloadStatus.paused,
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
          StreamBuilder<Map<String, DownloadTask>>(
            stream: DownloadService.instance.downloadStream,
            builder: (context, snapshot) {
              final queue = snapshot.data ?? {};
              final hasActive = queue.values.any(
                (t) =>
                    t.status == DownloadStatus.downloading ||
                    t.status == DownloadStatus.queued,
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
          // Nút "Xóa tất cả" — xóa toàn bộ hàng đợi sau khi xác nhận
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
      // Toàn bộ body là 1 StreamBuilder lắng nghe DownloadService — tự rebuild khi có thay đổi
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
                    color: theme.iconTheme.color?.withValues(alpha: 0.3),
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

          // Nhóm các task theo mangaId, bỏ qua task đã completed (không cần hiện nữa)
          final groupedByManga = <String, List<DownloadTask>>{};
          for (final task in queue.values) {
            if (task.status == DownloadStatus.completed) continue;
            groupedByManga.putIfAbsent(task.mangaId, () => []).add(task);
          }

          return ListView.builder(
            itemCount: groupedByManga.length,
            itemBuilder: (context, index) {
              final mangaId = groupedByManga.keys.elementAt(index);
              final tasks = groupedByManga[mangaId]!;
              return _MangaDownloadGroup(
                mangaId: mangaId,
                mangaTitle: tasks.first.mangaTitle,
                tasks: tasks,
              );
            },
          );
        },
      ),
    );
  }
}

// Card gom nhóm tất cả chapter đang tải của cùng 1 bộ truyện.
// Hiển thị tên truyện + tiến độ "X/Y chương" + nút xóa cả nhóm.
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
          // Header: bấm → navigate đến trang chi tiết truyện
          InkWell(
            onTap: () => context.push('/detail/$mangaId'),
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
                  // Xóa toàn bộ chapter của truyện này khỏi queue bằng cancelDownload()
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
          // Danh sách từng chapter, spread ra thành children
          ...tasks.map((task) => _ChapterDownloadItem(task: task)),
        ],
      ),
    );
  }
}

// Một dòng hiển thị trạng thái của 1 chapter trong queue.
// Bao gồm: status icon, tên chapter, text mô tả trạng thái, nút hành động.
// Bấm vào dòng (khi completed) → navigate đến reader.
class _ChapterDownloadItem extends StatelessWidget {
  final DownloadTask task;
  const _ChapterDownloadItem({required this.task});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        // Chỉ cho mở reader khi đã tải xong
        if (task.status == DownloadStatus.completed) {
          context.push('/reader/${task.chapterId}');
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _buildStatusIcon(context, theme, task),
            const SizedBox(width: 16),
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
            _buildActionButton(context, theme),
          ],
        ),
      ),
    );
  }

  // Icon phân biệt trạng thái — downloading hiện circular progress + % ở giữa
  Widget _buildStatusIcon(
    BuildContext context,
    ThemeData theme,
    DownloadTask task,
  ) {
    switch (task.status) {
      case DownloadStatus.completed:
        return const Icon(Icons.check_circle, color: Colors.green, size: 32);
      case DownloadStatus.downloading:
        // Stack: circular progress + text % chồng nhau
        return SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: task.progress, // 0.0 → 1.0
                strokeWidth: 4,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                backgroundColor: Colors.grey.withValues(alpha: 0.2),
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
        // Spinner không xác định (value = null) — đang chờ đến lượt
        return SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
            backgroundColor: Colors.grey.withValues(alpha: 0.2),
          ),
        );
      case DownloadStatus.paused:
        return const Icon(Icons.pause_circle, color: Colors.orange, size: 32);
      case DownloadStatus.failed:
        return const Icon(Icons.error, color: Colors.red, size: 32);
      default:
        return Icon(
          Icons.download,
          color: theme.iconTheme.color?.withValues(alpha: 0.6),
          size: 32,
        );
    }
  }

  // Text mô tả theo trạng thái — downloading hiện "X% • downloaded / total"
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

  // Nút hành động: pause khi đang tải/chờ, play khi paused, retry khi lỗi, cancel mặc định
  Widget _buildActionButton(BuildContext context, ThemeData theme) {
    switch (task.status) {
      case DownloadStatus.downloading:
      case DownloadStatus.queued:
        return IconButton(
          icon: const Icon(Icons.pause),
          tooltip: 'Tạm dừng',
          onPressed: () =>
              DownloadService.instance.pauseDownload(task.chapterId),
        );
      case DownloadStatus.paused:
        return IconButton(
          icon: const Icon(Icons.play_arrow),
          tooltip: 'Tiếp tục',
          onPressed: () =>
              DownloadService.instance.resumeDownload(task.chapterId),
        );
      case DownloadStatus.failed:
        return IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Thử lại',
          onPressed: () =>
              DownloadService.instance.retryDownload(task.chapterId),
        );
      default:
        return IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Xóa',
          onPressed: () =>
              DownloadService.instance.cancelDownload(task.chapterId),
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
