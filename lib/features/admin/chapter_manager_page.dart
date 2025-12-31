import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import 'package:path/path.dart' as path;

class ChapterManagerPage extends StatefulWidget {
  final CloudComic comic;
  const ChapterManagerPage({super.key, required this.comic});

  @override
  State<ChapterManagerPage> createState() => _ChapterManagerPageState();
}

class _ChapterManagerPageState extends State<ChapterManagerPage> {
  List<CloudChapter> _chapters = [];
  bool _isLoading = true;
  bool _isSavingOrder = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadChapters();
  }

  Future<void> _loadChapters() async {
    setState(() => _isLoading = true);
    final chapters = await DriveService.instance.getChapters(widget.comic.id);
    if (mounted) {
      setState(() {
        _chapters = chapters;
        _isLoading = false;
        _hasChanges = false;
      });
    }
  }

  // To refresh list after add/delete
  void _refresh() {
    _loadChapters();
  }

  Future<void> _saveOrder() async {
    setState(() => _isSavingOrder = true);
    try {
      final newOrder = _chapters.map((c) => c.id).toList();
      await DriveService.instance.saveChapterOrder(widget.comic.id, newOrder);
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
        title: Text(widget.comic.title),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        actions: [
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
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _chapters.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (oldIndex < newIndex) {
                    newIndex -= 1;
                  }
                  final item = _chapters.removeAt(oldIndex);
                  _chapters.insert(newIndex, item);
                  _hasChanges = true;
                });
              },
              itemBuilder: (context, index) {
                final chapter = _chapters[index];
                return Container(
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
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Lỗi xóa chapter: $e')),
                              );
                            }
                          }
                        }
                      },
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await showDialog(
            context: context,
            builder: (_) => _AddChapterDialog(comicId: widget.comic.id),
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

class _AddChapterDialog extends StatefulWidget {
  final String comicId;
  const _AddChapterDialog({required this.comicId});

  @override
  State<_AddChapterDialog> createState() => _AddChapterDialogState();
}

class _AddChapterDialogState extends State<_AddChapterDialog> {
  final _titleController = TextEditingController();
  File? _file;
  bool _isUploading = false;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip', 'cbz', 'epub'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _file = File(result.files.single.path!);
      });
    }
  }

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
      await DriveService.instance.addChapter(
        comicId: widget.comicId,
        title: _titleController.text,
        file: _file!,
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
          onPressed: _isUploading ? null : _submit,
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
