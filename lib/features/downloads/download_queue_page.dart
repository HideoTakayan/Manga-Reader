import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../services/download_service.dart';
import '../../services/folder_service.dart';

// Trang quản lý hàng đợi tải xuống — hiển thị tất cả task đang tải, chờ, lỗi, tạm dừng.
// Chuyển sang StatefulWidget để load dung lượng cache async và hiện trong stats bar.
class DownloadQueuePage extends StatefulWidget {
  const DownloadQueuePage({super.key});

  @override
  State<DownloadQueuePage> createState() => _DownloadQueuePageState();
}

class _DownloadQueuePageState extends State<DownloadQueuePage> {
  /// Dung lượng thư mục downloads (bytes) — null = đang tính
  int? _cacheSizeBytes;
  StreamSubscription<Map<String, DownloadTask>>? _downloadSub;
  Timer? _cacheDebounceTimer;

  @override
  void initState() {
    super.initState();
    _refreshCacheStats();
    // Debounce việc quét lại thư mục downloads (tối đa 1 lần mỗi 3 giây khi đang tải liên tục)
    _downloadSub = DownloadService.instance.downloadStream.listen((_) {
      if (_cacheDebounceTimer?.isActive ?? false) return;
      _cacheDebounceTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) _refreshCacheStats();
      });
    });
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    _cacheDebounceTimer?.cancel();
    super.dispose();
  }

  /// Scan thư mục downloads để tính tổng dung lượng file đã tải.
  /// Chỉ scan file (không đệ quy vào thư mục con của thư mục con)
  /// để tránh tốn quá nhiều I/O.
  Future<void> _refreshCacheStats() async {
    try {
      final downloadDir = Directory(FolderService.downloadPath);
      if (!await downloadDir.exists()) {
        if (mounted) setState(() => _cacheSizeBytes = 0);
        return;
      }

      int totalBytes = 0;
      await for (final entity in downloadDir.list(recursive: true)) {
        if (entity is File) {
          try {
            totalBytes += await entity.length();
          } catch (_) {}
        }
      }

      if (mounted) setState(() => _cacheSizeBytes = totalBytes);
    } catch (_) {
      // FolderService chưa init hoặc không có quyền — bỏ qua
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<Map<String, DownloadTask>>(
      stream: DownloadService.instance.downloadStream,
      initialData: DownloadService.instance.currentQueue,
      builder: (context, snapshot) {
        final queue = snapshot.data ?? {};
        final hasFailed = queue.values.any(
          (t) => t.status == DownloadStatus.failed,
        );
        final hasPaused = queue.values.any(
          (t) => t.status == DownloadStatus.paused,
        );
        final hasActive = queue.values.any(
          (t) =>
              t.status == DownloadStatus.downloading ||
              t.status == DownloadStatus.queued,
        );

        return Scaffold(
          appBar: AppBar(
            title: const Text('Hàng đợi tải xuống'),
            actions: [
              // Nút "Thử lại tất cả lỗi" — chỉ hiện khi có ít nhất 1 task bị lỗi
              if (hasFailed)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Thử lại tất cả lỗi',
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    DownloadService.instance.retryAllFailed();
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Đã thử lại tất cả tải xuống bị lỗi'),
                      ),
                    );
                  },
                ),
              // Nút "Tiếp tục tất cả" — chỉ hiện khi có ít nhất 1 task đang paused
              if (hasPaused)
                IconButton(
                  icon: const Icon(Icons.play_arrow),
                  tooltip: 'Tiếp tục tất cả',
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    DownloadService.instance.resumeAll();
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đã tiếp tục tất cả')),
                    );
                  },
                ),
              // Nút "Tạm dừng tất cả"
              if (hasActive)
                IconButton(
                  icon: const Icon(Icons.pause),
                  tooltip: 'Tạm dừng tất cả',
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    DownloadService.instance.pauseAll();
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đã tạm dừng tất cả')),
                    );
                  },
                ),
              // Nút "Xóa tất cả" — xóa toàn bộ hàng đợi sau khi xác nhận
              IconButton(
                icon: const Icon(Icons.clear_all),
                tooltip: 'Xóa tất cả',
                onPressed: () async {
                  if (DownloadService.instance.isQueueEmpty) {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Hàng đợi tải xuống đang trống'),
                      ),
                    );
                    return;
                  }
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (dialogCtx) => AlertDialog(
                      backgroundColor: Theme.of(dialogCtx).dialogTheme.backgroundColor ?? Theme.of(dialogCtx).cardColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      title: const Text(
                        'Xóa hàng đợi?',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      content: const Text(
                        'Bạn có chắc muốn xóa tất cả khỏi hàng đợi?',
                        style: TextStyle(color: Colors.white70),
                      ),
                      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogCtx, false),
                          child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(dialogCtx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                          child: const Text('Xóa', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true && context.mounted) {
                    DownloadService.instance.clearQueue();
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đã xóa hàng đợi')),
                    );
                  }
                },
              ),
            ],
          ),
          body: Builder(
            builder: (context) {
              final currentConcurrency = DownloadService.instance.maxConcurrentDownloads;
              final activeCount = queue.values
                  .where((t) => t.status == DownloadStatus.downloading)
                  .length;

              // Widget điều khiển đa luồng tải + stats cache
              Widget buildConcurrencyBar() {
                final sizeText = _cacheSizeBytes == null
                    ? 'Đang tính...'
                    : _formatBytes(_cacheSizeBytes!);
                final completedInQueue = queue.values
                    .where((t) => t.status == DownloadStatus.completed)
                    .length;

                return Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.bolt_rounded,
                              color: theme.colorScheme.primary,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Cấu hình Tải đa luồng',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  activeCount > 0
                                      ? 'Đang tải: $activeCount/$currentConcurrency luồng đồng thời'
                                      : 'Tối đa $currentConcurrency chương tải song song',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (activeCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 8,
                                    height: 8,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Đang tải',
                                    style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [1, 2, 3, 4, 6].map((threads) {
                          final isSelected = currentConcurrency == threads;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2.5),
                              child: InkWell(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  DownloadService.instance.setConcurrentDownloads(threads);
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected
                                          ? theme.colorScheme.primary
                                          : Colors.white.withValues(alpha: 0.1),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '$threads luồng',
                                      style: TextStyle(
                                        color: isSelected ? Colors.white : Colors.white70,
                                        fontSize: 11,
                                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      // Divider + Stats dung lượng cache
                      const SizedBox(height: 10),
                      Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _CacheStatChip(
                            icon: Icons.storage_rounded,
                            label: 'Đã dùng',
                            value: sizeText,
                            color: theme.colorScheme.primary,
                            onTap: () => context.push('/storage'),
                          ),
                          const SizedBox(width: 8),
                          _CacheStatChip(
                            icon: Icons.check_circle_rounded,
                            label: 'Xong (phiên này)',
                            value: '$completedInQueue chương',
                            color: Colors.greenAccent,
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }

              if (queue.isEmpty) {
                return Column(
                  children: [
                    buildConcurrencyBar(),
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.download_done_rounded,
                                  size: 64,
                                  color: theme.iconTheme.color?.withValues(alpha: 0.35),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Hàng đợi tải xuống đang trống',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Bạn có thể tải các chương truyện yêu thích để đọc ngoại tuyến bất cứ khi nào.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white54,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 12,
                                runSpacing: 10,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => context.push('/storage'),
                                    icon: const Icon(Icons.pie_chart_outline_rounded, size: 16),
                                    label: const Text('Quản lý dung lượng'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white70,
                                      side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () => context.go('/'),
                                    icon: const Icon(Icons.explore_rounded, size: 16),
                                    label: const Text('Khám phá truyện', style: TextStyle(fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              // Nhóm các task theo mangaId, bỏ qua task đã completed (không cần hiện nữa)
              final groupedByManga = <String, List<DownloadTask>>{};
              for (final task in queue.values) {
                if (task.status == DownloadStatus.completed) continue;
                groupedByManga.putIfAbsent(task.mangaId, () => []).add(task);
              }

              if (groupedByManga.isEmpty) {
                return Column(
                  children: [
                    buildConcurrencyBar(),
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check_circle_rounded,
                                  size: 64,
                                  color: Colors.greenAccent,
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'Đã tải xong tất cả chương',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Toàn bộ các chương trong hàng đợi đã được tải về máy thành công.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.white54,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 12,
                                runSpacing: 10,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      DownloadService.instance.clearQueue();
                                    },
                                    icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                                    label: const Text('Dọn dẹp danh sách'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white12,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () => context.push('/storage'),
                                    icon: const Icon(Icons.folder_outlined, size: 18),
                                    label: const Text('Xem trong máy'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blueAccent,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: buildConcurrencyBar(),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final mangaId = groupedByManga.keys.elementAt(index);
                        final tasks = groupedByManga[mangaId]!;
                        return _MangaDownloadGroup(
                          mangaId: mangaId,
                          mangaTitle: tasks.first.mangaTitle,
                          tasks: tasks,
                        );
                      },
                      childCount: groupedByManga.length,
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// Chip nhỏ hiển thị 1 thông số cache (icon + label + value).
/// Bấm vào sẽ navigate đến màn hình quản lý storage nếu có onTap.
class _CacheStatChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _CacheStatChip({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 15),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(color: Colors.white54, fontSize: 9),
                    ),
                    Text(
                      value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
                        builder: (dialogCtx) => AlertDialog(
                          backgroundColor: Theme.of(dialogCtx).dialogTheme.backgroundColor ?? Theme.of(dialogCtx).cardColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          title: const Text(
                            'Xóa tất cả?',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          content: Text(
                            'Xóa tất cả chương của "$mangaTitle" khỏi hàng đợi?',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogCtx, false),
                              child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(dialogCtx, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              ),
                              child: const Text('Xóa', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        if (!context.mounted) return;
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => const Center(child: CircularProgressIndicator()),
                        );
                        try {
                          for (final task in tasks) {
                            await DownloadService.instance.cancelDownload(
                              task.chapterId,
                            );
                          }
                        } finally {
                          if (context.mounted) {
                            Navigator.pop(context); // Tắt vòng xoay
                          }
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
          context.push(
            '/reader/${task.chapterId}?mangaId=${Uri.encodeComponent(task.mangaId)}',
          );
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
                value: task.progress > 0 ? task.progress : null,
                strokeWidth: 4,
                valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
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
        return SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: task.progress > 0 ? task.progress : 0.0,
                strokeWidth: 3.5,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
                backgroundColor: Colors.grey.withValues(alpha: 0.2),
              ),
              const Icon(Icons.pause, color: Colors.orange, size: 18),
            ],
          ),
        );
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
          'Đã tải xong • ${_formatBytes(task.totalBytes ?? task.downloadedBytes ?? 0)}',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.green),
        );
      case DownloadStatus.downloading:
        final percent = (task.progress * 100).toInt();
        final downloaded = _formatBytes(task.downloadedBytes ?? 0);
        final total = _formatBytes(task.totalBytes ?? 0);
        return Text(
          'Đang tải $percent% • $downloaded / $total',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
        );
      case DownloadStatus.queued:
        if (task.retryCount > 0) {
          return Text(
            'Tự động thử lại (${task.retryCount}/3)...',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.amber),
          );
        }
        if (task.progress > 0 && task.downloadedBytes != null) {
          final percent = (task.progress * 100).toInt();
          return Text(
            'Đang chờ tiếp tục ($percent%)...',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange.shade300),
          );
        }
        return Text('Đang chờ đến lượt tải...', style: theme.textTheme.bodySmall);
      case DownloadStatus.paused:
        final percent = (task.progress * 100).toInt();
        if (task.downloadedBytes != null && task.downloadedBytes! > 0) {
          final downloaded = _formatBytes(task.downloadedBytes!);
          final total = task.totalBytes != null ? ' / ${_formatBytes(task.totalBytes!)}' : '';
          return Text(
            'Đã tạm dừng ($percent%) • $downloaded$total',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.orangeAccent),
          );
        }
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

  // Nút hành động: pause/play/retry + nút xóa riêng từng task
  Widget _buildActionButton(BuildContext context, ThemeData theme) {
    if (task.status == DownloadStatus.completed) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (task.status == DownloadStatus.downloading || task.status == DownloadStatus.queued)
          IconButton(
            icon: const Icon(Icons.pause),
            tooltip: 'Tạm dừng',
            onPressed: () =>
                DownloadService.instance.pauseDownload(task.chapterId),
          )
        else if (task.status == DownloadStatus.paused)
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Tiếp tục',
            onPressed: () =>
                DownloadService.instance.resumeDownload(task.chapterId),
          )
        else if (task.status == DownloadStatus.failed)
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Thử lại',
            onPressed: () =>
                DownloadService.instance.retryDownload(task.chapterId),
          ),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          tooltip: 'Xóa khỏi hàng đợi',
          onPressed: () =>
              DownloadService.instance.cancelDownload(task.chapterId),
        ),
      ],
    );
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
