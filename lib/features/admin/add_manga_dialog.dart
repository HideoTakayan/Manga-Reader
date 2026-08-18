import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../data/content_type.dart';
import '../../data/drive_service.dart';

class AddMangaDialog extends StatefulWidget {
  final String? uploaderGroupId;
  final String? uploaderGroupName;

  const AddMangaDialog({super.key, this.uploaderGroupId, this.uploaderGroupName});

  @override
  State<AddMangaDialog> createState() => _AddMangaDialogState();
}

class _AddMangaDialogState extends State<AddMangaDialog> {
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _descController = TextEditingController();
  final _genresController = TextEditingController(); // Nhập dạng "Action, Romance, Fantasy"
  File? _coverFile;
  MangaContentType _contentType = MangaContentType.manga;
  bool _isUploading = false;

  // Mở file picker giới hạn chỉ ảnh, lưu file đã chọn vào _coverFile.
  Future<void> _pickCover() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      if (mounted) setState(() => _coverFile = File(result.files.single.path!));
    }
  }

  // Validate → upload lên Drive → đóng dialog trả về true (để dashboard biết cần refresh).
  Future<void> _submit() async {
    if (_titleController.text.isEmpty || _coverFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập tên và chọn ảnh bìa')),
      );
      return;
    }

    setState(() => _isUploading = true);
    try {
      await DriveService.instance.addManga(
        title: _titleController.text,
        author: _authorController.text,
        description: _descController.text,
        coverFile: _coverFile!,
        // Split chuỗi thể loại theo dấu phẩy, trim khoảng trắng, bỏ chuỗi rỗng
        genres: _genresController.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        status: 'Đang Cập Nhật',
        contentType: _contentType,
        uploaderGroupId: widget.uploaderGroupId,
        uploaderGroupName: widget.uploaderGroupName,
      );
      if (mounted) {
        Navigator.pop(context, true); // true = báo hiệu thêm thành công
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  InputDecoration _inputDeco(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      prefixIcon: Icon(icon, color: Colors.white54),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.orange, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: theme.dialogTheme.backgroundColor ?? theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        'Thêm Truyện Mới',
        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              style: const TextStyle(color: Colors.white),
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.sentences,
              decoration: _inputDeco('Tên truyện', Icons.title),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<MangaContentType>(
              initialValue: _contentType,
              decoration: _inputDeco('Loại nội dung', Icons.category),
              dropdownColor: const Color(0xFF2C2C2E),
              items: MangaContentType.values
                  .map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(
                        type.label,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _isUploading
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _contentType = value);
                      }
                    },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _authorController,
              style: const TextStyle(color: Colors.white),
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              decoration: _inputDeco('Tác giả', Icons.person_outline),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              decoration: _inputDeco('Mô tả', Icons.description_outlined),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _genresController,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDeco(
                'Thể loại (cách nhau bởi dấu phẩy)',
                Icons.local_offer_outlined,
              ),
            ),
            const SizedBox(height: 20),
            // Vùng chọn ảnh bìa — style xịn hơn
            InkWell(
              onTap: _isUploading ? null : _pickCover,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 20,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: _coverFile != null
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.white.withValues(alpha: 0.03),
                  border: Border.all(
                    color: _coverFile != null ? Colors.green : Colors.white24,
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _coverFile != null
                          ? Icons.check_circle
                          : Icons.add_photo_alternate,
                      color: _coverFile != null ? Colors.green : Colors.orange,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _coverFile == null
                            ? 'Tải lên Ảnh Bìa'
                            : 'Đã chọn: ${_coverFile!.path.split('/').last}',
                        style: TextStyle(
                          color: _coverFile != null
                              ? Colors.green
                              : Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_isUploading)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(
                  child: CircularProgressIndicator(color: Colors.orange),
                ),
              ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _isUploading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: const Text(
            'Lưu Truyện',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
