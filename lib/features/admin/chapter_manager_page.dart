import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../../services/notification_service.dart';
import 'metadata_validator.dart';
import 'package:path/path.dart' as path;

// Trang quản lý chapter của một bộ truyện: xem, thêm, xóa, sắp xếp bằng kéo thả.
// Nhận CloudManga từ AdminDashboardPage — dùng manga.id để query Drive.
class ChapterManagerPage extends StatefulWidget {
  final CloudManga manga;
  const ChapterManagerPage({super.key, required this.manga});

  @override
  State<ChapterManagerPage> createState() => _ChapterManagerPageState();
}

class _ChapterManagerPageState extends State<ChapterManagerPage> {
  List<CloudChapter> _chapters = [];
  bool _isLoading = true;
  bool _isSavingOrder = false;
  bool _hasChanges = false; // true = thứ tự bị thay đổi → hiện nút "Lưu Thứ Tự"
  bool _isAscending = true; // Toggle hướng sort — đảo chiều sau mỗi lần bấm

  @override
  void initState() {
    super.initState();
    _loadChapters();
  }

  // Tải danh sách chapter từ Drive. Gọi lại sau mỗi thao tác thêm/xóa.
  Future<void> _loadChapters() async {
    setState(() => _isLoading = true);
    final chapters = await DriveService.instance.getChapters(widget.manga.id);
    if (mounted) {
      setState(() {
        _chapters = chapters;
        _isLoading = false;
        _hasChanges = false;
      });
    }
  }

  void _refresh() {
    _loadChapters();
  }

  // Natural Sort: trích số đầu tiên từ tên chapter bằng RegEx rồi so sánh số.
  // Tránh lỗi sort chuỗi kiểu "Chap 10" < "Chap 9" vì '1' < '9' theo ASCII.
  void _sortChapters() {
    setState(() {
      _chapters.sort((a, b) {
        // Trích số đầu tiên, hỗ trợ số thập phân: "Chap 9.5" → 9.5
        double? getNumber(String s) {
          final match = RegExp(r'(\d+(\.\d+)?)').firstMatch(s);
          return match != null ? double.parse(match.group(1)!) : null;
        }

        final numA = getNumber(a.title);
        final numB = getNumber(b.title);

        if (numA != null && numB != null) {
          if (numA == numB) {
            // Số bằng nhau → fallback so sánh chuỗi để sort ổn định
            return _isAscending
                ? a.title.compareTo(b.title)
                : b.title.compareTo(a.title);
          }
          return _isAscending ? numA.compareTo(numB) : numB.compareTo(numA);
        }

        // Không tìm thấy số → so sánh chuỗi thông thường
        return _isAscending
            ? a.title.compareTo(b.title)
            : b.title.compareTo(a.title);
      });

      _isAscending = !_isAscending; // Đảo chiều cho lần bấm tiếp theo
      _hasChanges = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isAscending
              ? 'Đã sắp xếp giảm dần (Cao -> Thấp)'
              : 'Đã sắp xếp tăng dần (Thấp -> Cao)',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // Trích danh sách ID theo thứ tự hiện tại → ghi vào info.json + catalog.json.
  Future<void> _saveOrder() async {
    setState(() => _isSavingOrder = true);
    try {
      final newOrder = _chapters.map((c) => c.id).toList();
      await DriveService.instance.saveChapterOrder(widget.manga.id, newOrder);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu thứ tự chương mới!')),
        );
        setState(() => _hasChanges = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi lưu thứ tự: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSavingOrder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.manga.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        actions: [
          // Nút sort — icon chuyển cam khi đã có thay đổi chưa lưu
          IconButton(
            onPressed: _chapters.isEmpty ? null : _sortChapters,
            tooltip: 'Tự động sắp xếp',
            icon: Icon(
              Icons.sort_by_alpha,
              color: _hasChanges ? Colors.orange : null,
            ),
          ),

          // Nút "Lưu Thứ Tự" chỉ hiện khi _hasChanges = true (có thay đổi chưa lưu)
          if (_hasChanges)
            TextButton.icon(
              onPressed: _isSavingOrder ? null : _saveOrder,
              icon: _isSavingOrder
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save, color: Colors.orange),
              label: Text(
                _isSavingOrder ? 'Đang lưu...' : 'Lưu Thứ Tự',
                style: const TextStyle(color: Colors.orange),
              ),
            ),
          IconButton(
            tooltip: 'Validate chapter',
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: _chapters.isEmpty
                ? null
                : () => _showValidationResult(
                    MetadataValidator.validateChapters(_chapters),
                  ),
          ),
        ],
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _chapters.isEmpty
          ? Center(
              child: Text(
                'Chưa có chương nào.\nBấm nút bên dưới để thêm!',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
              ),
            )
          // ReorderableListView: danh sách có tay cầm kéo thả — onReorder callback cập nhật _chapters
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _chapters.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  // Fix bug của ReorderableListView: khi kéo xuống, newIndex tăng thừa 1
                  if (oldIndex < newIndex) newIndex -= 1;
                  final item = _chapters.removeAt(oldIndex);
                  _chapters.insert(newIndex, item);
                  _hasChanges = true;
                });
              },
              itemBuilder: (context, index) {
                final chapter = _chapters[index];
                return Container(
                  // ValueKey bắt buộc với ReorderableListView để identify từng item
                  key: ValueKey(chapter.id),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey.withValues(alpha: 0.2),
                    ),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.drag_handle, color: Colors.grey),
                    title: Text(
                      chapter.title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    // Hiện định dạng file (ZIP/CBZ) và dung lượng
                    subtitle: Text(
                      '${chapter.fileType.toUpperCase()} • ${(chapter.sizeBytes / 1024 / 1024).toStringAsFixed(2)} MB',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(fontSize: 12),
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                      ),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: Theme.of(context).cardColor,
                            title: Text(
                              'Xác nhận xóa',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            content: Text(
                              'Bạn có chắc muốn xóa "${chapter.title}"?',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(
                                  'Hủy',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: TextButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(128, 48),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                  shape: const StadiumBorder(),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Xóa',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          try {
                            await DriveService.instance.deleteChapter(
                              chapter.id,
                            );
                            if (mounted) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Đã xóa chapter thành công'),
                                ),
                              );
                              _refresh();
                            }
                          } catch (e) {
                            // Nếu Drive trả 404 → file đã mất trên Drive nhưng app chưa biết.
                            // Xử lý như "đã xóa thành công": xóa khỏi list local, không báo lỗi.
                            final isNotFound =
                                e.toString().contains('404') ||
                                e.toString().contains('File not found');

                            if (mounted) {
                              if (isNotFound) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'File không tồn tại trên Drive, đã xóa khỏi danh sách local',
                                    ),
                                  ),
                                );
                                setState(
                                  () => _chapters.removeWhere(
                                    (c) => c.id == chapter.id,
                                  ),
                                );
                              } else {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('Lỗi xóa chapter: $e'),
                                  ),
                                );
                              }
                            }
                          }
                        }
                      },
                    ),
                  ),
                );
              },
            ),

      // FAB mở _AddChapterDialog, sau khi đóng thì _refresh() để cập nhật danh sách
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await showDialog(
            context: context,
            builder: (_) => _AddChapterDialog(
              mangaId: widget.manga.id,
              mangaTitle: widget.manga.title,
            ),
          );
          _refresh();
        },
        label: const Text('Thêm Chapter'),
        icon: const Icon(Icons.upload_file),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.black,
      ),
    );
  }

  void _showValidationResult(List<MetadataValidationIssue> issues) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        if (issues.isEmpty) {
          return const SizedBox(
            height: 160,
            child: Center(child: Text('Danh sách chapter hợp lệ')),
          );
        }

        return SafeArea(
          child: ListView.separated(
            itemCount: issues.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final issue = issues[index];
              final isError = issue.severity == MetadataIssueSeverity.error;
              return ListTile(
                leading: Icon(
                  isError ? Icons.error_outline : Icons.warning_amber,
                  color: isError ? Colors.red : Colors.orange,
                ),
                title: Text(
                  issue.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  issue.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// Dialog thêm chapter mới: nhập tên + chọn file ZIP/CBZ/EPUB → upload lên Drive.
// Sau upload thành công: ghi thông báo realtime vào Firestore collection 'notifications'.
class _AddChapterDialog extends StatefulWidget {
  final String mangaId;
  final String mangaTitle;
  const _AddChapterDialog({required this.mangaId, required this.mangaTitle});

  @override
  State<_AddChapterDialog> createState() => _AddChapterDialogState();
}

class _AddChapterDialogState extends State<_AddChapterDialog> {
  final _titleController = TextEditingController();
  final List<File> _files = [];
  bool _isUploading = false;

  // Mở file picker giới hạn chỉ file zip/cbz/epub — đây là các định dạng reader hỗ trợ.
  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip', 'cbz', 'epub', 'pdf'],
      allowMultiple: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _files
          ..clear()
          ..addAll(
            result.files
                .map((file) => file.path)
                .whereType<String>()
                .map(File.new),
          );
      });
    }
  }

  // Validate → upload qua DriveService → ghi thông báo vào Firestore → đóng dialog.
  Future<void> _submit() async {
    // Khi chỉ upload 1 file, tên chương là bắt buộc.
    // Khi upload nhiều file, tên tự động lấy từ tên file nên không cần validate.
    if (_files.length == 1 && _titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vui lòng nhập tên chương')));
      return;
    }
    if (_files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn file chapter')),
      );
      return;
    }

    setState(() => _isUploading = true);
    try {
      // Upload file lên folder manga trên Drive.
      String? uploadedChapterTitle;
      for (final file in _files) {
        final fallbackTitle = path.basenameWithoutExtension(file.path);
        final chapterTitle =
            _files.length == 1 && _titleController.text.trim().isNotEmpty
            ? _titleController.text.trim()
            : fallbackTitle;
        await DriveService.instance.addChapter(
          mangaId: widget.mangaId,
          title: chapterTitle,
          file: file,
        );
        uploadedChapterTitle ??= chapterTitle;
      }

      // Ghi thêm bản ghi vào Firestore để màn hình thông báo trong app đọc lại được lịch sử
      await NotificationService.instance.notifySubscribers(
        type: 'new_chapter',
        mangaId: widget.mangaId,
        title: '${widget.mangaTitle} có chương mới',
        body: _files.length == 1
            ? (uploadedChapterTitle ?? 'Chương mới')
            : '${_files.length} chương mới',
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).cardColor,
      title: Text(
        'Thêm Chapter Mới (Drive)',
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: InputDecoration(
                labelText: 'Tên Chapter (VD: Chap 1)',
                labelStyle: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                filled: true,
                fillColor: Theme.of(context).scaffoldBackgroundColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Vùng chọn file — icon chuyển xanh khi đã chọn, hiện tên file ngắn gọn
            InkWell(
              onTap: _pickFile,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.grey.withValues(alpha: 0.5),
                    style: BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _files.isEmpty ? Icons.attach_file : Icons.check_circle,
                      color: _files.isEmpty ? Colors.grey : Colors.green,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _files.isEmpty
                            ? 'Chọn file (ZIP/CBZ/PDF/EPUB)'
                            : _files.length == 1
                            ? path.basename(_files.first.path)
                            : 'Đã chọn ${_files.length} file',
                        style: Theme.of(context).textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // LinearProgressIndicator thay vì CircularProgressIndicator để tiết kiệm không gian
            if (_isUploading)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(color: Colors.orange),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Hủy',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
          ),
        ),
        ElevatedButton(
          onPressed: _isUploading ? null : _submit, // Disable khi đang upload
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.black,
          ),
          child: const Text('Thêm'),
        ),
      ],
    );
  }
}
