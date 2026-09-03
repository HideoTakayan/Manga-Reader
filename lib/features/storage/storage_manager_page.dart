import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfx/pdfx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../data/database_helper.dart';
import '../../services/download_service.dart';
import '../../services/folder_service.dart';
import '../../core/utils/archive_image_extractor.dart';

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

    // 1. reader_cache (app temp dir)
    int cacheBytes = 0;
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory(p.join(tempDir.path, 'reader_cache'));
      if (await cacheDir.exists()) {
        final list = cacheDir.listSync(recursive: true).whereType<File>();
        for (final f in list) {
          cacheBytes += await f.length();
        }
      }
    } catch (_) {}

    // 2. temp_cache (MangaReader external storage)
    int tempCacheBytes = 0;
    try {
      final rootPath = FolderService.rootPath;
      if (rootPath != null) {
        final tempCacheDir = Directory('$rootPath/temp_cache');
        if (await tempCacheDir.exists()) {
          final list = tempCacheDir.listSync(recursive: true).whereType<File>();
          for (final f in list) {
            tempCacheBytes += await f.length();
          }
        }
      }
    } catch (_) {}

    // 3. external_imports (file tạm khi mở từ app khác)
    int externalCacheBytes = 0;
    try {
      final appCacheDir = await getApplicationCacheDirectory();
      final extDir = Directory(p.join(appCacheDir.path, 'external_imports'));
      if (await extDir.exists()) {
        final list = extDir.listSync(recursive: true).whereType<File>();
        for (final f in list) {
          externalCacheBytes += await f.length();
        }
      }
    } catch (_) {}

    // 4. _novels (EPUB đã lưu)
    int novelBytes = 0;
    try {
      final rootPath = FolderService.rootPath;
      if (rootPath != null) {
        final novelsDir = Directory('$rootPath/_novels');
        if (await novelsDir.exists()) {
          final list = novelsDir.listSync(recursive: true).whereType<File>();
          for (final f in list) {
            novelBytes += await f.length();
          }
        }
      }
    } catch (_) {}

    return _StorageSnapshot(
      totalBytes: totalBytes,
      totalChapters: rows.length,
      missingCount: missingCount,
      zeroByteCount: zeroByteCount,
      cacheBytes: cacheBytes,
      tempCacheBytes: tempCacheBytes,
      externalCacheBytes: externalCacheBytes,
      novelBytes: novelBytes,
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
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Xóa chapter lỗi?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Xóa ${broken.length} chapter bị mất file hoặc file 0 byte khỏi máy và database local?',
          style: const TextStyle(color: Colors.white70),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
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
    if (confirm != true) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      for (final chapter in broken) {
        await DownloadService.instance.deleteDownload(chapter.chapterId);
      }
    } finally {
      if (mounted) {
        Navigator.pop(context); // Tắt vòng xoay
      }
    }
    
    if (!mounted) return;
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã xóa ${broken.length} chapter lỗi')),
    );
  }

  Future<void> _deleteFinishedReadChapters() async {
    final db = await DatabaseHelper.instance.database;
    final Set<String> finishedChapterIds = {};

    // 1. Quét từ reader_progress (tiến độ >= 95%)
    try {
      final progressRows = await db.query(
        'reader_progress',
        columns: ['chapterId'],
        where: 'progressPercent >= ?',
        whereArgs: [0.95],
      );
      for (final row in progressRows) {
        final cid = row['chapterId']?.toString();
        if (cid != null && cid.isNotEmpty) finishedChapterIds.add(cid);
      }
    } catch (_) {}

    // 2. Quét từ reading_activity (các chương đã đọc)
    try {
      final activityRows = await db.query(
        'reading_activity',
        columns: ['chapterId'],
      );
      for (final row in activityRows) {
        final cid = row['chapterId']?.toString();
        if (cid != null && cid.isNotEmpty) finishedChapterIds.add(cid);
      }
    } catch (_) {}

    // 3. Quét từ history (nếu đã đọc đến trang cuối)
    try {
      final historyRows = await db.query(
        'history',
        columns: ['chapterId', 'lastPageIndex', 'totalPages'],
      );
      for (final row in historyRows) {
        final cid = row['chapterId']?.toString();
        final lastPage = (row['lastPageIndex'] as num?)?.toInt() ?? 0;
        final total = (row['totalPages'] as num?)?.toInt() ?? 0;
        if (cid != null && cid.isNotEmpty && total > 0 && lastPage >= total - 1) {
          finishedChapterIds.add(cid);
        }
      }
    } catch (_) {}

    if (finishedChapterIds.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có chapter nào đọc xong để xóa')),
      );
      return;
    }

    final downloads = await DatabaseHelper.instance.getAllDownloads();
    final deletable = downloads
        .where((row) => finishedChapterIds.contains(row['chapterId']?.toString()))
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
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Xóa chapter đã đọc xong?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Xóa ${deletable.length} chapter có tiến độ đọc từ 95% trở lên khỏi bộ nhớ máy?',
          style: const TextStyle(color: Colors.white70),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
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
    if (confirm != true) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      for (final row in deletable) {
        await DownloadService.instance.deleteDownload(
          row['chapterId']?.toString() ?? '',
        );
      }
    } finally {
      if (mounted) {
        Navigator.pop(context); // Tắt vòng xoay
      }
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

    final path = chapter.localPath.toLowerCase();
    if (path.endsWith('.pdf')) {
      PdfDocument? document;
      try {
        document = await PdfDocument.openFile(chapter.localPath);
        if (document.pagesCount <= 0) return 'PDF không có trang';
        return 'PDF hợp lệ (${document.pagesCount} trang)';
      } finally {
        await document?.close();
      }
    }

    InputFileStream? inputStream;
    try {
      if (path.endsWith('.epub')) {
        inputStream = InputFileStream(chapter.localPath);
        final archive = ZipDecoder().decodeBuffer(inputStream);
        final hasContainer = archive.files.any(
          (f) => f.name.toLowerCase() == 'meta-inf/container.xml',
        );
        return hasContainer ? 'EPUB hợp lệ' : 'EPUB thiếu container.xml';
      }

      inputStream = InputFileStream(chapter.localPath);
      Archive? archive;
      try {
        archive = ZipDecoder().decodeBuffer(inputStream);
      } catch (_) {
        try {
          inputStream.close();
          inputStream = InputFileStream(chapter.localPath);
          archive = TarDecoder().decodeBuffer(inputStream);
        } catch (_) {}
      }

      if (archive == null) return 'Không thể giải nén archive';

      final imageCount = archive.files.where((f) {
        if (!f.isFile) return false;
        return _isImagePath(f.name);
      }).length;
      if (imageCount <= 0) return 'Archive không có ảnh';
      return 'Archive hợp lệ ($imageCount ảnh)';
    } finally {
      inputStream?.close();
    }
  }

  bool _isImagePath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.jfif') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.avif') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.heif') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.gif');
  }

  Future<void> _deleteManga(_MangaStorageGroup group) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Xóa tải xuống?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Xóa toàn bộ ${group.chapterCount} chapter đã tải của "${group.mangaTitle}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
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
    if (confirm != true) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await DownloadService.instance.deleteMangaDownloads(
        group.mangaId,
        group.mangaTitle,
      );
    } finally {
      if (mounted) {
        Navigator.pop(context); // Tắt vòng xoay
      }
    }
    
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
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.cloud_off_rounded,
                        size: 44,
                        color: Colors.redAccent,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Không thể tải dữ liệu bộ nhớ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Thử lại'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data ?? _StorageSnapshot.empty();

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
                  onClearAllCache: _clearAllCache,
                ),
                const SizedBox(height: 12),
                Text(
                  'Truyện đã tải',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (data.groups.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 36,
                      horizontal: 20,
                    ),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.cyan.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.download_for_offline_outlined,
                            size: 48,
                            color: Colors.cyanAccent,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Chưa có truyện nào được tải về',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Tải các chương truyện yêu thích để đọc ngoại tuyến bất cứ khi nào không có mạng.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          alignment: WrapAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => context.push('/downloads'),
                              icon: const Icon(Icons.download_rounded, size: 16),
                              label: const Text('Hàng đợi tải'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white70,
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: () => context.go('/'),
                              icon: const Icon(Icons.explore_rounded, size: 16),
                              label: const Text('Khám phá truyện', style: TextStyle(fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.cyanAccent.shade700,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                else
                  ...data.groups.map(
                    (group) => _MangaStorageCard(
                      group: group,
                      onDelete: () => _deleteManga(group),
                      onTapDetail: group.mangaId.startsWith('LOCAL_NOVEL|') || group.mangaId.startsWith('LOCAL_MANGA|')
                          ? null
                          : () => context.push('/detail/${group.mangaId}'),
                      onDeleteChapter: (chapter) async {
                        final messenger = ScaffoldMessenger.of(context);
                      await DownloadService.instance.deleteDownload(
                        chapter.chapterId,
                      );
                      if (!context.mounted) return;
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

  Future<void> _clearAllCache() async {
    final freed = await _computeTotalCacheBytes();
    try {
      // 1. reader_cache
      await ArchiveImageExtractor.clearCache();
      // 2. temp_cache trong MangaReader root
      final rootPath = FolderService.rootPath;
      if (rootPath != null) {
        final tempCacheDir = Directory('$rootPath/temp_cache');
        if (await tempCacheDir.exists()) {
          await for (final entity in tempCacheDir.list(recursive: false)) {
            try { await entity.delete(recursive: true); } catch (_) {}
          }
        }
      }
      // 3. external_imports cache
      try {
        final appCacheDir = await getApplicationCacheDirectory();
        final extDir = Directory(p.join(appCacheDir.path, 'external_imports'));
        if (await extDir.exists()) {
          await for (final entity in extDir.list(recursive: false)) {
            try { await entity.delete(recursive: true); } catch (_) {}
          }
        }
      } catch (_) {}
      // 4. Memory Image Cache
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}

    if (!mounted) return;
    final freedStr = _formatBytes(freed);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          freed > 0
              ? '🧹 Đã giải phóng $freedStr bộ nhớ'
              : '✅ Bộ nhớ đệm đã sạch',
        ),
        backgroundColor: Colors.teal,
        behavior: SnackBarBehavior.floating,
      ),
    );
    _reload();
  }

  Future<int> _computeTotalCacheBytes() async {
    int total = 0;
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory(p.join(tempDir.path, 'reader_cache'));
      if (await cacheDir.exists()) {
        for (final f in cacheDir.listSync(recursive: true).whereType<File>()) {
          total += await f.length();
        }
      }
    } catch (_) {}
    try {
      final rootPath = FolderService.rootPath;
      if (rootPath != null) {
        final tempCacheDir = Directory('$rootPath/temp_cache');
        if (await tempCacheDir.exists()) {
          for (final f in tempCacheDir.listSync(recursive: true).whereType<File>()) {
            total += await f.length();
          }
        }
      }
    } catch (_) {}
    try {
      final appCacheDir = await getApplicationCacheDirectory();
      final extDir = Directory(p.join(appCacheDir.path, 'external_imports'));
      if (await extDir.exists()) {
        for (final f in extDir.listSync(recursive: true).whereType<File>()) {
          total += await f.length();
        }
      }
    } catch (_) {}
    return total;
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
  final VoidCallback onClearAllCache;

  const _StorageSummaryCard({
    required this.snapshot,
    required this.onDeleteBroken,
    required this.onDeleteRead,
    required this.onClearAllCache,
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
                  icon: Icons.book_outlined,
                  label: 'Truyện chữ: ${_formatBytes(snapshot.novelBytes)}',
                  color: Colors.deepPurpleAccent,
                ),
                _MetricChip(
                  icon: Icons.photo_library_outlined,
                  label: 'Bộ nhớ đệm: ${_formatBytes(snapshot.totalCacheBytes)}',
                  color: snapshot.totalCacheBytes > 0 ? Colors.orange : Colors.blueAccent,
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
            if (snapshot.totalCacheBytes > 0) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => onClearAllCache(),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange.withValues(alpha: 0.18),
                  foregroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(
                  '🧹 Dọn dẹp toàn bộ bộ nhớ đệm (${_formatBytes(snapshot.totalCacheBytes)})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (snapshot.cacheBytes > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _MetricChip(
                        icon: Icons.image_outlined,
                        label: 'Reader: ${_formatBytes(snapshot.cacheBytes)}',
                        color: Colors.orange,
                      ),
                    ),
                  if (snapshot.tempCacheBytes > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _MetricChip(
                        icon: Icons.folder_open,
                        label: 'Temp: ${_formatBytes(snapshot.tempCacheBytes)}',
                        color: Colors.orange,
                      ),
                    ),
                  if (snapshot.externalCacheBytes > 0)
                    _MetricChip(
                      icon: Icons.share,
                      label: 'Chia sẻ: ${_formatBytes(snapshot.externalCacheBytes)}',
                      color: Colors.orange,
                    ),
                ],
              ),
            ],
            if (snapshot.brokenCount > 0) ...[
              const SizedBox(height: 8),
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
  final VoidCallback? onTapDetail;
  final Future<void> Function(_StorageChapterItem chapter) onDeleteChapter;
  final Future<void> Function(_StorageChapterItem chapter) onVerifyChapter;

  const _MangaStorageCard({
    required this.group,
    required this.onDelete,
    this.onTapDetail,
    required this.onDeleteChapter,
    required this.onVerifyChapter,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ExpansionTile(
        leading: GestureDetector(
          onTap: onTapDetail,
          child: Tooltip(
            message: 'Xem chi tiết truyện',
            child: CircleAvatar(
              backgroundColor: Colors.teal.withValues(alpha: 0.12),
              child: const Icon(Icons.menu_book, color: Colors.teal),
            ),
          ),
        ),
        title: GestureDetector(
          onTap: onTapDetail,
          child: Text(
            group.mangaTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: onTapDetail != null ? Colors.teal.shade200 : null,
              decoration: onTapDetail != null ? TextDecoration.underline : null,
              decorationColor: Colors.teal.shade200,
            ),
          ),
        ),
        subtitle: Text(
          '${group.chapterCount} chapter • ${_formatBytes(group.totalBytes)}'
          '${group.brokenCount > 0 ? ' • ${group.brokenCount} lỗi' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
  final int cacheBytes;
  final int tempCacheBytes;
  final int externalCacheBytes;
  final int novelBytes;
  final List<_MangaStorageGroup> groups;

  const _StorageSnapshot({
    required this.totalBytes,
    required this.totalChapters,
    required this.missingCount,
    required this.zeroByteCount,
    required this.cacheBytes,
    this.tempCacheBytes = 0,
    this.externalCacheBytes = 0,
    this.novelBytes = 0,
    required this.groups,
  });

  factory _StorageSnapshot.empty() {
    return const _StorageSnapshot(
      totalBytes: 0,
      totalChapters: 0,
      missingCount: 0,
      zeroByteCount: 0,
      cacheBytes: 0,
      tempCacheBytes: 0,
      externalCacheBytes: 0,
      novelBytes: 0,
      groups: [],
    );
  }

  int get totalCacheBytes => cacheBytes + tempCacheBytes + externalCacheBytes;
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
