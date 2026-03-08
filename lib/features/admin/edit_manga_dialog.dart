import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../data/drive_service.dart';
import '../../data/models_cloud.dart';
import '../shared/drive_image.dart';

// Dialog sửa thông tin bộ truyện: tên, tác giả, mô tả, thể loại, trạng thái, ảnh bìa.
// Nhận CloudManga hiện tại → pre-fill form → Admin sửa → gọi DriveService.updateManga().
class EditMangaDialog extends StatefulWidget {
  final CloudManga manga;
  const EditMangaDialog({super.key, required this.manga});

  @override
  State<EditMangaDialog> createState() => _EditMangaDialogState();
}

class _EditMangaDialogState extends State<EditMangaDialog> {
  late TextEditingController _titleController;
  late TextEditingController _authorController;
  late TextEditingController _descriptionController;
  late TextEditingController
  _genresController; // Chuỗi dạng "Action, Romance, Fantasy"

  String _status = 'Đang Cập Nhật';
  final List<String> _statusOptions = ['Đang Cập Nhật', 'Hoàn Thành', 'Drop'];

  File? _newCoverFile; // null = giữ nguyên bìa cũ, khác null = thay bìa mới
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill form với dữ liệu hiện tại của truyện
    _titleController = TextEditingController(text: widget.manga.title);
    _authorController = TextEditingController(text: widget.manga.author);
    _descriptionController = TextEditingController(
      text: widget.manga.description,
    );
    // Join list genres thành chuỗi phân cách bởi dấu phẩy để hiển thị trong TextField
    _genresController = TextEditingController(
      text: widget.manga.genres.join(', '),
    );

    // Nếu status từ Drive không khớp với _statusOptions (DB cũ/typo) → fallback về mặc định
    _status = widget.manga.status.isEmpty
        ? 'Đang Cập Nhật'
        : widget.manga.status;
    if (!_statusOptions.contains(_status)) {
      _status = 'Đang Cập Nhật';
    }
  }

  @override
  void dispose() {
    // Giải phóng controller để tránh memory leak
    _titleController.dispose();
    _authorController.dispose();
    _descriptionController.dispose();
    _genresController.dispose();
    super.dispose();
  }

  // Mở file picker chỉ ảnh — kết quả lưu vào _newCoverFile.
  // Ảnh preview trong dialog chuyển sang Image.file ngay khi chọn.
  Future<void> _pickCoverImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _newCoverFile = File(result.files.single.path!));
    }
  }

  // Lưu tất cả thay đổi: validate → gọi DriveService → phát hiện thay đổi → ghi thông báo Firestore.
  Future<void> _saveChanges() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tên truyện không được để trống')),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      // updateManga xử lý: cập nhật info.json trên Drive, catalog.json tổng,
      // upload bìa mới (nếu có), xóa bìa cũ, và gửi push notification nếu status thay đổi.
      await DriveService.instance.updateManga(
        mangaId: widget.manga.id,
        title: _titleController.text.trim(),
        author: _authorController.text.trim(),
        description: _descriptionController.text.trim(),
        // Split chuỗi thể loại theo dấu phẩy → List<String> sạch
        genres: _genresController.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        status: _status,
        newCoverFile: _newCoverFile, // null = không thay bìa
      );

      // Phát hiện các thay đổi quan trọng để ghi log thông báo vào Firestore.
      // Chỉ ghi khi thực sự có thay đổi — tránh spam thông báo khi Admin bấm Lưu mà không sửa gì.
      List<String> changes = [];
      if (_newCoverFile != null) changes.add('Ảnh bìa mới');
      if (_status != widget.manga.status) changes.add('Trạng thái: $_status');
      if (_titleController.text.trim() != widget.manga.title)
        changes.add('Đổi tên truyện');

      if (changes.isNotEmpty) {
        await FirebaseFirestore.instance.collection('notifications').add({
          'type':
              'info_update', // Phân biệt với 'new_chapter' để app xử lý hiển thị khác
          'mangaId': widget.manga.id,
          'mangaTitle': _titleController.text.trim(),
          'title': '${_titleController.text.trim()} vừa cập nhật thông tin',
          'body': 'Cập nhật: ${changes.join(', ')}',
          'timestamp': FieldValue.serverTimestamp(),
          'sender': 'admin',
        });
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cập nhật & Đã gửi thông báo!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).cardColor,
      title: Text(
        'Chỉnh Sửa Truyện',
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview ảnh bìa — bấm vào để đổi bìa.
            // Nếu chưa chọn file mới: hiện bìa Drive cũ (DriveImage).
            // Nếu đã chọn: hiện preview file local (Image.file) ngay lập tức.
            Center(
              child: GestureDetector(
                onTap: _pickCoverImage,
                child: Container(
                  width: 120,
                  height: 160,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange, width: 2),
                  ),
                  child: _newCoverFile != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.file(_newCoverFile!, fit: BoxFit.cover),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: DriveImage(
                            fileId: widget.manga.coverFileId,
                            fit: BoxFit.cover,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _pickCoverImage,
                icon: const Icon(Icons.image, color: Colors.orange),
                label: const Text(
                  'Đổi ảnh bìa',
                  style: TextStyle(color: Colors.orange),
                ),
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _titleController,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: InputDecoration(
                labelText: 'Tên truyện',
                labelStyle: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.orange),
                ),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _authorController,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: InputDecoration(
                labelText: 'Tác giả',
                labelStyle: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.orange),
                ),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _descriptionController,
              style: Theme.of(context).textTheme.bodyLarge,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Mô tả',
                labelStyle: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.orange),
                ),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _genresController,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: InputDecoration(
                labelText: 'Thể loại (ngăn cách bởi dấu phẩy)',
                labelStyle: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.orange),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Dropdown chọn trạng thái: Đang Cập Nhật / Hoàn Thành / Drop.
            // DropdownButtonHideUnderline để ẩn gạch chân mặc định, dùng Border tùy chỉnh thay.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _status,
                  dropdownColor: Theme.of(context).cardColor,
                  style: Theme.of(context).textTheme.bodyLarge,
                  isExpanded: true,
                  items: _statusOptions
                      .map(
                        (value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        ),
                      )
                      .toList(),
                  onChanged: (newValue) => setState(() => _status = newValue!),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isUploading ? null : () => Navigator.of(context).pop(),
          child: Text(
            'Hủy',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
          ),
        ),
        ElevatedButton(
          onPressed: _isUploading ? null : _saveChanges,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.black,
          ),
          // Nút "Lưu" chuyển thành spinner nhỏ khi đang upload — tránh user bấm nhiều lần
          child: _isUploading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : const Text('Lưu'),
        ),
      ],
    );
  }
}
