import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../data/content_type.dart';
import '../data/database_helper.dart';
import '../data/models.dart';
import 'folder_service.dart';
import 'library_service.dart';
import 'novel_service.dart';

class ExternalFileInfo {
  final String filePath;
  final String fileName;
  final String fileType;
  final int fileSize;

  const ExternalFileInfo({
    required this.filePath,
    required this.fileName,
    required this.fileType,
    required this.fileSize,
  });

  factory ExternalFileInfo.fromMap(Map<dynamic, dynamic> map) {
    return ExternalFileInfo(
      filePath: map['filePath']?.toString() ?? '',
      fileName: map['fileName']?.toString() ?? 'unknown_file',
      fileType: map['fileType']?.toString().toLowerCase() ?? 'epub',
      fileSize: (map['fileSize'] is int)
          ? map['fileSize'] as int
          : int.tryParse(map['fileSize']?.toString() ?? '0') ?? 0,
    );
  }

  String get formattedSize {
    if (fileSize <= 0) return '0 KB';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get cleanTitle {
    final name = p.basenameWithoutExtension(fileName);
    return name.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  }

  bool get isNovel => fileType == 'epub';
  bool get isComic => ['cbz', 'cbr', 'cbt', 'tar', 'zip', 'pdf'].contains(fileType);
}

class ExternalFileService {
  static final ExternalFileService instance = ExternalFileService._internal();
  ExternalFileService._internal();

  static const MethodChannel _channel = MethodChannel(
    'com.example.manga_reader/external_file',
  );

  bool _initialized = false;
  BuildContext? _currentContext;

  void setContext(BuildContext context) {
    _currentContext = context;
  }

  Future<void> init(BuildContext context) async {
    _currentContext = context;
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onFileOpened') {
        final data = call.arguments;
        if (data is Map) {
          final info = ExternalFileInfo.fromMap(data);
          if (info.filePath.isNotEmpty) {
            _showImportDialog(info);
          }
        }
      }
    });

    try {
      final initialData = await _channel.invokeMethod('getInitialFile');
      if (initialData is Map) {
        final info = ExternalFileInfo.fromMap(initialData);
        if (info.filePath.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showImportDialog(info);
          });
        }
      }
    } catch (e) {
      debugPrint('ExternalFileService init error: $e');
    }
  }

  String? _lastOpenedPath;
  DateTime? _lastOpenedTime;

  void _showImportDialog(ExternalFileInfo info) {
    final ctx = _currentContext;
    if (ctx == null || !ctx.mounted) return;

    final now = DateTime.now();
    if (_lastOpenedPath == info.filePath &&
        _lastOpenedTime != null &&
        now.difference(_lastOpenedTime!).inMilliseconds < 1500) {
      return;
    }
    _lastOpenedPath = info.filePath;
    _lastOpenedTime = now;

    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => _ExternalFileActionSheet(info: info),
    );
  }

  static String extractSeriesTitle(String cleanName) {
    final pattern = RegExp(
      r'^(.*?)(?:[\s_\-]+(?:c|chap|chapter|vol|volume|tập|tap|chương|chuong)[\s_\-]*\d+.*)$',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(cleanName.trim());
    if (match != null && match.group(1) != null && match.group(1)!.trim().isNotEmpty) {
      return match.group(1)!.trim();
    }
    return cleanName.trim();
  }

  /// Xử lý Đọc ngay
  Future<void> openDirectly(BuildContext context, ExternalFileInfo info) async {
    if (info.isNovel) {
      final novel = LocalNovel(
        path: info.filePath,
        title: info.cleanTitle,
        importedAt: DateTime.now(),
      );
      // Tự động thêm vào Thư viện Novel để hiển thị ngay trong tab Thư viện
      await NovelService.instance.add(novel);
      LibraryService.instance.notifyMappingChanged();

      final allNovels = await NovelService.instance.getAll();
      final targetNovel = allNovels.firstWhere(
        (n) => n.title == novel.title,
        orElse: () => novel,
      );

      if (context.mounted) {
        await context.push('/novel-reader', extra: targetNovel);
      }
    } else {
      // Manga / Comic (.cbz, .zip, .pdf) -> Lưu vào thư viện trước rồi mở đọc
      final seriesTitle = extractSeriesTitle(info.cleanTitle);
      await importToLibrary(info, seriesTitleOverride: seriesTitle);
      final safeTitle = FolderService.sanitize(seriesTitle);
      final mangaId = 'local_${safeTitle.hashCode}';
      final chapterId = 'local_${mangaId}_${info.fileName.hashCode}';

      if (context.mounted) {
        await context.push('/reader/$chapterId?mangaId=$mangaId');
      }
    }
  }

  /// Xử lý Lưu vĩnh viễn vào Thư viện MangaReader (Tự động gom chapter cùng bộ)
  Future<bool> importToLibrary(
    ExternalFileInfo info, {
    String? seriesTitleOverride,
  }) async {
    try {
      if (info.isNovel) {
        final novel = LocalNovel(
          path: info.filePath,
          title: info.cleanTitle,
          importedAt: DateTime.now(),
        );
        final added = await NovelService.instance.add(novel);
        LibraryService.instance.notifyMappingChanged();
        return added;
      } else {
        // Comic / Manga -> Sao chép vào /MangaReader/downloads/<Tên bộ>/<file>
        final seriesTitle = seriesTitleOverride?.trim().isNotEmpty == true
            ? seriesTitleOverride!.trim()
            : extractSeriesTitle(info.cleanTitle);
        final safeSeriesTitle = FolderService.sanitize(seriesTitle);
        final mangaDir = await FolderService.getMangaPathByTitle(seriesTitle);
        final targetPath = p.join(mangaDir, info.fileName);
        final targetFile = File(targetPath);

        if (!await targetFile.exists()) {
          final sourceFile = File(info.filePath);
          if (await sourceFile.exists()) {
            await sourceFile.copy(targetPath);
          }
        }

        // Tự động trích xuất ảnh bìa cho truyện tranh nếu chưa có
        final coverFile = File('$mangaDir/cover.jpg');
        if (!await coverFile.exists() && (info.fileType == 'cbz' || info.fileType == 'zip' || info.fileType == 'cbt' || info.fileType == 'tar' || info.fileType == 'cbr')) {
          try {
            var inputStream = InputFileStream(targetPath);
            Archive? archive;
            try {
              archive = ZipDecoder().decodeBuffer(inputStream);
            } catch (_) {
              try {
                inputStream.close();
                inputStream = InputFileStream(targetPath);
                archive = TarDecoder().decodeBuffer(inputStream);
              } catch (_) {}
            }

            if (archive != null) {
              final sortedFiles = archive.files.toList()
                ..sort((a, b) => a.name.compareTo(b.name));
              for (final file in sortedFiles) {
                if (!file.isFile) continue;
                final name = file.name.toLowerCase();
                if (name.endsWith('.jpg') ||
                    name.endsWith('.jpeg') ||
                    name.endsWith('.jfif') ||
                    name.endsWith('.png') ||
                    name.endsWith('.webp') ||
                    name.endsWith('.avif') ||
                    name.endsWith('.heic') ||
                    name.endsWith('.heif')) {
                  final content = file.content;
                  if (content != null) {
                    final bytes = content is Uint8List
                        ? content
                        : Uint8List.fromList(content as List<int>);
                    await coverFile.writeAsBytes(bytes);
                    break;
                  }
                }
              }
            }
            inputStream.close();
          } catch (_) {}
        }

        final mangaId = 'local_${safeSeriesTitle.hashCode}';
        final chapterId = 'local_${mangaId}_${info.fileName.hashCode}';
        final coverPath = await coverFile.exists() ? coverFile.path : '';

        final manga = Manga(
          id: mangaId,
          title: seriesTitle,
          coverUrl: coverPath,
          author: 'Cục bộ / Ngoại vi',
          description: 'Truyện tranh lưu trong bộ nhớ máy',
          genres: const ['Local'],
          contentType: MangaContentType.manga,
        );

        await DatabaseHelper.instance.saveLocalManga(manga);
        await DatabaseHelper.instance.saveDownload(
          chapterId: chapterId,
          mangaId: mangaId,
          mangaTitle: seriesTitle,
          chapterTitle: info.cleanTitle,
          localPath: targetPath,
          fileSize: await targetFile.exists()
              ? await targetFile.length()
              : info.fileSize,
        );

        try {
          await LibraryService.instance.addToCategory(mangaId, 'Mặc định');
        } catch (_) {}

        LibraryService.instance.notifyMappingChanged();
        return true;
      }
    } catch (e) {
      debugPrint('Import to library error: $e');
      return false;
    }
  }
}

class _ExternalFileActionSheet extends StatefulWidget {
  final ExternalFileInfo info;
  const _ExternalFileActionSheet({required this.info});

  @override
  State<_ExternalFileActionSheet> createState() =>
      _ExternalFileActionSheetState();
}

class _ExternalFileActionSheetState extends State<_ExternalFileActionSheet> {
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = widget.info;

    return Container(
      decoration: BoxDecoration(
        color: theme.dialogTheme.backgroundColor ?? theme.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 30,
            spreadRadius: 10,
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Header icon + Type badge
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: info.isNovel
                        ? [Colors.purpleAccent, Colors.deepPurple]
                        : [Colors.orangeAccent, Colors.deepOrange],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: (info.isNovel ? Colors.purpleAccent : Colors.orangeAccent)
                          .withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  info.isNovel ? Icons.menu_book_rounded : Icons.auto_stories_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            info.fileType.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          info.formattedSize,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      info.cleanTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blueAccent, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Phát hiện file truyện từ ứng dụng ngoài. Bạn có thể đọc ngay hoặc lưu vào Thư viện của máy.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Action Buttons
          Row(
            children: [
              // Nút Lưu vào Thư viện
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isSaving
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final navigator = Navigator.of(context);
                          setState(() => _isSaving = true);
                          final ok = await ExternalFileService.instance
                              .importToLibrary(info);
                          if (!mounted) return;
                          setState(() => _isSaving = false);
                          navigator.pop();
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? '✅ Đã lưu "${info.cleanTitle}" vào Thư viện!'
                                    : 'ℹ️ Truyện đã có sẵn trong Thư viện.',
                              ),
                              backgroundColor: ok ? Colors.green : Colors.blueGrey,
                            ),
                          );
                        },
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: const Text(
                    'Lưu Thư viện',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Nút Đọc ngay
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF7043), Color(0xFFFF9800)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF7043).withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      ExternalFileService.instance.openDirectly(context, info);
                    },
                    icon: const Icon(Icons.play_arrow_rounded, size: 22),
                    label: const Text(
                      'Đọc ngay',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
