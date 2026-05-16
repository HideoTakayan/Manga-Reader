import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfx/pdfx.dart';

import '../../data/database_helper.dart';
import '../../services/download_service.dart';

class StorageManagerPage extends StatefulWidget {
  const StorageManagerPage({super.key});

  @override
  State<StorageManagerPage> createState() => _StorageManagerPageState();
}

class _StorageManagerPageState extends State<StorageManagerPage> {
  late Future<_StorageSnapshot> _snapshotFuture;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = _loadSnapshot();
  }

  void _reload() {
    setState(() {
      _snapshotFuture = _loadSnapshot();
    });
  }

  Future<_StorageSnapshot> _loadSnapshot() async {
    final rows = await DatabaseHelper.instance.getAllDownloads();
    final groups = <String, _MangaStorageGroup>{};
    var totalBytes = 0;
    var missingCount = 0;
    var zeroByteCount = 0;

    for (final row in rows) {
      final chapterId = _readString(row, 'chapterId');
      final mangaId = _readString(row, 'mangaId');
      final mangaTitle = _readString(row, 'mangaTitle').isEmpty
          ? 'Không rõ tên truyện'
          : _readString(row, 'mangaTitle');
      final chapterTitle = _readString(row, 'chapterTitle').isEmpty
          ? chapterId
          : _readString(row, 'chapterTitle');
      final localPath = _readString(row, 'localPath');
      final dbSize = _readInt(row, 'fileSize');
      final downloadedAt = DateTime.fromMillisecondsSinceEpoch(
        _readInt(row, 'downloadDate'),
      );

      var exists = false;
      var actualSize = dbSize;
      if (localPath.isNotEmpty) {
        final file = File(localPath);
        exists = await file.exists();
        if (exists) {
          actualSize = await file.length();
        }
      }

      final isZeroByte = exists && actualSize <= 0;
      if (!exists) missingCount++;
      if (isZeroByte) zeroByteCount++;
      if (exists && actualSize > 0) totalBytes += actualSize;

      final item = _StorageChapterItem(
        chapterId: chapterId,
        mangaId: mangaId,
        mangaTitle: mangaTitle,
        chapterTitle: chapterTitle,
        localPath: localPath,
        sizeBytes: actualSize,
        exists: exists,
        isZeroByte: isZeroByte,
        downloadedAt: downloadedAt,
      );

      groups
          .putIfAbsent(
            mangaId,
            () => _MangaStorageGroup(mangaId: mangaId, mangaTitle: mangaTitle),
          )
          .chapters
          .add(item);
    }

    final sortedGroups = groups.values.toList()
      ..sort((a, b) => b.totalBytes.compareTo(a.totalBytes));

    return _StorageSnapshot(
      totalBytes: totalBytes,
      totalChapters: rows.length,
      missingCount: missingCount,
      zeroByteCount: zeroByteCount,
      groups: sortedGroups,
    );
  }

  Future<void> _deleteBrokenFiles(_StorageSnapshot snapshot) async {
    final broken = snapshot.groups
        .expand((group) => group.chapters)
        .where((chapter) => chapter.isBroken)
        .toList();
    if (broken.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa chapter lỗi?'),
        content: Text(
          'Xóa ${broken.length} chapter bị mất file hoặc file 0 byte khỏi máy và database local?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    for (final chapter in broken) {
      await DownloadService.instance.deleteDownload(chapter.chapterId);
    }
    if (!mounted) return;
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã xóa ${broken.length} chapter lỗi')),
    );
  }

  Future<void> _deleteFinishedReadChapters() async {
    final db = await DatabaseHelper.instance.database;
    final progressRows = await db.query(
      'reader_progress',
      where: 'progressPercent >= ?',
      whereArgs: [0.95],
    );
    if (progressRows.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có chapter nào đọc xong để xóa')),
      );
      return;
    }

    final chapterIds = progressRows
        .map((row) => row['chapterId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final downloads = await DatabaseHelper.instance.getAllDownloads();
    final deletable = downloads
        .where((row) => chapterIds.contains(row['chapterId']?.toString()))
        .toList();
    if (deletable.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không có chapter đã đọc xong trong tải xuống'),
        ),
      );
      return;
    }

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa chapter đã đọc xong?'),
        content: Text(
          'Xóa ${deletable.length} chapter có tiến độ đọc từ 95% trở lên khỏi bộ nhớ máy?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    for (final row in deletable) {
      await DownloadService.instance.deleteDownload(
        row['chapterId']?.toString() ?? '',
      );
    }
    if (!mounted) return;
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã xóa ${deletable.length} chapter đã đọc xong')),
    );
  }

  Future<void> _verifyChapter(_StorageChapterItem chapter) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await _verifyDownloadedFile(chapter);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(result)));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('File lỗi: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<String> _verifyDownloadedFile(_StorageChapterItem chapter) async {
    if (chapter.localPath.isEmpty) return 'Thiếu đường dẫn file';

    final file = File(chapter.localPath);
    if (!await file.exists()) return 'Không tìm thấy file local';

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return 'File 0 byte';

    final path = chapter.localPath.toLowerCase();
    if (path.endsWith('.pdf')) {
      PdfDocument? document;
      try {
        document = await PdfDocument.openData(bytes);
        if (document.pagesCount <= 0) return 'PDF không có trang';
        return 'PDF hợp lệ (${document.pagesCount} trang)';
      } finally {
        await document?.close();
      }
    }

    if (path.endsWith('.epub')) {
      final archive = ZipDecoder().decodeBytes(bytes);
      final hasContainer = archive.files.any(
        (file) => file.name.toLowerCase() == 'meta-inf/container.xml',
      );
      return hasContainer ? 'EPUB hợp lệ' : 'EPUB thiếu container.xml';
    }

    final archive = ZipDecoder().decodeBytes(bytes);
    final imageCount = archive.files.where((file) {
      if (!file.isFile) return false;
      return _isImagePath(file.name);
    }).length;
    if (imageCount <= 0) return 'Archive không có ảnh';
    return 'Archive hợp lệ ($imageCount ảnh)';
  }

  bool _isImagePath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  Future<void> _deleteManga(_MangaStorageGroup group) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa tải xuống?'),
        content: Text(
          'Xóa toàn bộ ${group.chapterCount} chapter đã tải của "${group.mangaTitle}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await DownloadService.instance.deleteMangaDownloads(
      group.mangaId,
      group.mangaTitle,
    );
    if (!mounted) return;
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã xóa tải xuống của ${group.mangaTitle}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý dung lượng'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<_StorageSnapshot>(
        future: _snapshotFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Không thể tải dữ liệu: ${snapshot.error}'));
          }

          final data = snapshot.data ?? _StorageSnapshot.empty();
          if (data.totalChapters == 0) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.storage_outlined,
                    size: 64,
                    color: theme.iconTheme.color?.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 12),
                  Text('Chưa có chapter tải xuống', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.push('/downloads'),
                    child: const Text('Mở hàng đợi tải xuống'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _StorageSummaryCard(
                  snapshot: data,
                  onDeleteBroken: data.brokenCount == 0
                      ? null
                      : () => _deleteBrokenFiles(data),
                  onDeleteRead: _deleteFinishedReadChapters,
                ),
                const SizedBox(height: 12),
                Text(
                  'Theo truyện',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...data.groups.map(
                  (group) => _MangaStorageCard(
                    group: group,
                    onDelete: () => _deleteManga(group),
                    onDeleteChapter: (chapter) async {
                      final messenger = ScaffoldMessenger.of(context);
                      await DownloadService.instance.deleteDownload(
                        chapter.chapterId,
                      );
                      if (!mounted) return;
                      _reload();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Đã xóa ${chapter.chapterTitle}'),
                        ),
                      );
                    },
                    onVerifyChapter: _verifyChapter,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return '';
    return value.toString().trim();
  }

  int _readInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _StorageSummaryCard extends StatelessWidget {
  final _StorageSnapshot snapshot;
  final VoidCallback? onDeleteBroken;
  final VoidCallback onDeleteRead;

  const _StorageSummaryCard({
    required this.snapshot,
    required this.onDeleteBroken,
    required this.onDeleteRead,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storage, color: Colors.teal),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _formatBytes(snapshot.totalBytes),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricChip(
                  icon: Icons.collections_bookmark,
                  label: '${snapshot.totalChapters} chapter',
                ),
                _MetricChip(
                  icon: Icons.menu_book,
                  label: '${snapshot.groups.length} truyện',
                ),
                _MetricChip(
                  icon: snapshot.brokenCount == 0
                      ? Icons.verified
                      : Icons.warning_amber,
                  label: snapshot.brokenCount == 0
                      ? 'Không có file lỗi'
                      : '${snapshot.brokenCount} file lỗi',
                  color: snapshot.brokenCount == 0 ? Colors.green : Colors.red,
                ),
              ],
            ),
            if (snapshot.brokenCount > 0) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onDeleteBroken,
                icon: const Icon(Icons.cleaning_services_outlined),
                label: const Text('Xóa chapter lỗi'),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onDeleteRead,
              icon: const Icon(Icons.auto_delete_outlined),
              label: const Text('Xóa chapter đã đọc xong'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MangaStorageCard extends StatelessWidget {
  final _MangaStorageGroup group;
  final VoidCallback onDelete;
  final Future<void> Function(_StorageChapterItem chapter) onDeleteChapter;
  final Future<void> Function(_StorageChapterItem chapter) onVerifyChapter;

  const _MangaStorageCard({
    required this.group,
    required this.onDelete,
    required this.onDeleteChapter,
    required this.onVerifyChapter,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.teal.withValues(alpha: 0.12),
          child: const Icon(Icons.menu_book, color: Colors.teal),
        ),
        title: Text(
          group.mangaTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${group.chapterCount} chapter • ${_formatBytes(group.totalBytes)}'
          '${group.brokenCount > 0 ? ' • ${group.brokenCount} lỗi' : ''}',
        ),
        trailing: IconButton(
          tooltip: 'Xóa tải xuống truyện này',
          icon: const Icon(Icons.delete_outline),
          onPressed: onDelete,
        ),
        children: [
          const Divider(height: 1),
          ...group.chapters.map(
            (chapter) => ListTile(
              dense: true,
              leading: Icon(
                chapter.isBroken ? Icons.error_outline : Icons.check_circle,
                color: chapter.isBroken ? Colors.red : Colors.green,
              ),
              title: Text(
                chapter.chapterTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                chapter.exists
                    ? '${_formatBytes(chapter.sizeBytes)} • ${_formatDate(chapter.downloadedAt)}'
                    : 'Không tìm thấy file local',
              ),
              trailing: Wrap(
                spacing: 0,
                children: [
                  IconButton(
                    tooltip: 'Kiểm tra file',
                    icon: Icon(
                      Icons.verified_outlined,
                      color: theme.iconTheme.color?.withValues(alpha: 0.7),
                    ),
                    onPressed: () => onVerifyChapter(chapter),
                  ),
                  IconButton(
                    tooltip: 'Xóa chapter',
                    icon: Icon(
                      Icons.close,
                      color: theme.iconTheme.color?.withValues(alpha: 0.7),
                    ),
                    onPressed: () => onDeleteChapter(chapter),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _MetricChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? Theme.of(context).colorScheme.primary;
    return Chip(
      avatar: Icon(icon, size: 16, color: resolvedColor),
      label: Text(label),
      side: BorderSide(color: resolvedColor.withValues(alpha: 0.25)),
      backgroundColor: resolvedColor.withValues(alpha: 0.08),
    );
  }
}

class _StorageSnapshot {
  final int totalBytes;
  final int totalChapters;
  final int missingCount;
  final int zeroByteCount;
  final List<_MangaStorageGroup> groups;

  const _StorageSnapshot({
    required this.totalBytes,
    required this.totalChapters,
    required this.missingCount,
    required this.zeroByteCount,
    required this.groups,
  });

  factory _StorageSnapshot.empty() {
    return const _StorageSnapshot(
      totalBytes: 0,
      totalChapters: 0,
      missingCount: 0,
      zeroByteCount: 0,
      groups: [],
    );
  }

  int get brokenCount => missingCount + zeroByteCount;
}

class _MangaStorageGroup {
  final String mangaId;
  final String mangaTitle;
  final List<_StorageChapterItem> chapters = [];

  _MangaStorageGroup({required this.mangaId, required this.mangaTitle});

  int get totalBytes => chapters.fold<int>(
    0,
    (sum, chapter) => sum + (chapter.exists ? chapter.sizeBytes : 0),
  );

  int get chapterCount => chapters.length;

  int get brokenCount => chapters.where((chapter) => chapter.isBroken).length;
}

class _StorageChapterItem {
  final String chapterId;
  final String mangaId;
  final String mangaTitle;
  final String chapterTitle;
  final String localPath;
  final int sizeBytes;
  final bool exists;
  final bool isZeroByte;
  final DateTime downloadedAt;

  const _StorageChapterItem({
    required this.chapterId,
    required this.mangaId,
    required this.mangaTitle,
    required this.chapterTitle,
    required this.localPath,
    required this.sizeBytes,
    required this.exists,
    required this.isZeroByte,
    required this.downloadedAt,
  });

  bool get isBroken => !exists || isZeroByte;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String _formatDate(DateTime value) {
  final diff = DateTime.now().difference(value);
  if (diff.inDays > 0) return '${diff.inDays} ngày trước';
  if (diff.inHours > 0) return '${diff.inHours} giờ trước';
  if (diff.inMinutes > 0) return '${diff.inMinutes} phút trước';
  return 'Mới đây';
}
