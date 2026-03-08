import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
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
        title: Text(widget.manga.title),
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
                    border: Border.all(color: Colors.grey.withOpacity(0.2)),
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
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                ),
                                child: const Text('Xóa'),
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
                              ScaffoldMessenger.of(context).showSnackBar(
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
                                ScaffoldMessenger.of(context).showSnackBar(
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
                                ScaffoldMessenger.of(context).showSnackBar(
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
            builder: (_) => _AddChapterDialog(mangaId: widget.manga.id),
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
}

// Dialog thêm chapter mới: nhập tên + chọn file ZIP/CBZ/EPUB → upload lên Drive.
// Sau upload thành công: ghi thông báo realtime vào Firestore collection 'notifications'.
class _AddChapterDialog extends StatefulWidget {
  final String mangaId;
  const _AddChapterDialog({required this.mangaId});

  @override
  State<_AddChapterDialog> createState() => _AddChapterDialogState();
}

class _AddChapterDialogState extends State<_AddChapterDialog> {
  final _titleController = TextEditingController();
  File? _file;
  bool _isUploading = false;

  // Mở file picker giới hạn chỉ file zip/cbz/epub — đây là các định dạng reader hỗ trợ.
  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip', 'cbz', 'epub'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _file = File(result.files.single.path!));
    }
  }

  // Validate → upload qua DriveService → ghi thông báo vào Firestore → đóng dialog.
  Future<void> _submit() async {
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vui lòng nhập tên chương')));
      return;
    }
    if (_file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn file zip/epub')),
      );
      return;
    }

    setState(() => _isUploading = true);
    try {
      // Upload file lên folder manga trên Drive, đồng thời gửi push notification qua FCM
      await DriveService.instance.addChapter(
        mangaId: widget.mangaId,
        title: _titleController.text,
        file: _file!,
      );

      // Ghi thêm bản ghi vào Firestore để màn hình thông báo trong app đọc lại được lịch sử
      await FirebaseFirestore.instance.collection('notifications').add({
        'type': 'new_chapter', // Loại thông báo để app phân biệt xử lý
        'mangaId': widget.mangaId,
        'title': 'Truyện có chương mới!',
        'body': 'Đã cập nhật ${_titleController.text}',
        'timestamp': FieldValue.serverTimestamp(),
        'sender': 'admin',
      });

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
                    color: Colors.grey.withOpacity(0.5),
                    style: BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _file == null ? Icons.attach_file : Icons.check_circle,
                      color: _file == null ? Colors.grey : Colors.green,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _file == null
                            ? 'Chọn file (ZIP/EPUB)'
                            : path.basename(_file!.path),
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
