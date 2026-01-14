import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../shared/drive_image.dart';

class AdminUploadPage extends StatefulWidget {
  const AdminUploadPage({super.key});

  @override
  State<AdminUploadPage> createState() => _AdminUploadPageState();
}

class _AdminUploadPageState extends State<AdminUploadPage> {
  // Làm mới danh sách
  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<GoogleSignInAccount?>(
      stream: DriveService.instance.onAuthStateChanged,
      initialData: DriveService.instance.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Admin Dashboard'),
            actions: [
              if (user != null)
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Đăng xuất',
                  onPressed: () => DriveService.instance.signOut(),
                )
              else
                TextButton.icon(
                  icon: const Icon(Icons.login, color: Colors.white),
                  label: const Text(
                    'Login',
                    style: TextStyle(color: Colors.white),
                  ),
                  onPressed: () => DriveService.instance.signIn(),
                ),
            ],
          ),
          body: user == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('Bạn chưa kết nối Google Drive'),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => DriveService.instance.signIn(),
                        icon: const Icon(Icons.login),
                        label: const Text('Đăng nhập ngay'),
                      ),
                    ],
                  ),
                )
              : const _ComicList(),
          floatingActionButton: user == null
              ? null
              : FloatingActionButton(
                  onPressed: () async {
                    await showDialog(
                      context: context,
                      builder: (_) => const _AddComicDialog(),
                    );
                    _refresh();
                  },
                  child: const Icon(Icons.add),
                ),
        );
      },
    );
  }
}

class _ComicList extends StatelessWidget {
  const _ComicList();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CloudComic>>(
      future: DriveService.instance.getComics(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('Chưa có truyện nào'));
        }

        final comics = snapshot.data!;
        return ListView.builder(
          itemCount: comics.length,
          itemBuilder: (context, index) {
            final comic = comics[index];
            return ListTile(
              leading: DriveImage(
                fileId: comic.coverFileId,
                width: 50,
                height: 70,
                fit: BoxFit.cover,
              ),
              title: Text(comic.title),
              subtitle: Text(comic.author),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _ChapterManagerPage(comic: comic),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _AddComicDialog extends StatefulWidget {
  const _AddComicDialog();

  @override
  State<_AddComicDialog> createState() => _AddComicDialogState();
}

class _AddComicDialogState extends State<_AddComicDialog> {
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _descController = TextEditingController();
  final _genresController = TextEditingController(); // Đã thêm
  File? _coverFile;
  bool _isUploading = false;

  Future<void> _pickCover() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _coverFile = File(result.files.single.path!);
      });
    }
  }

  Future<void> _submit() async {
    if (_titleController.text.isEmpty || _coverFile == null) return;

    setState(() => _isUploading = true);
    try {
      await DriveService.instance.addComic(
        title: _titleController.text,
        author: _authorController.text,
        description: _descController.text,
        coverFile: _coverFile!,
        genres: _genresController.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        status: 'Đang Cập Nhật',
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
      title: const Text('Thêm Truyện Mới'),
      content: SingleChildScrollView(
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Tên truyện'),
            ),
            TextField(
              controller: _authorController,
              decoration: const InputDecoration(labelText: 'Tác giả'),
            ),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(labelText: 'Mô tả'),
            ),
            TextField(
              controller: _genresController,
              decoration: const InputDecoration(
                labelText: 'Thể loại (cách nhau bởi dấu phẩy)',
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _pickCover,
              icon: const Icon(Icons.image),
              label: Text(_coverFile == null ? 'Chọn Ảnh Bìa' : 'Đã chọn ảnh'),
            ),
            if (_isUploading)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: CircularProgressIndicator(),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          onPressed: _isUploading ? null : _submit,
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}

class _ChapterManagerPage extends StatefulWidget {
  final CloudComic comic;
  const _ChapterManagerPage({required this.comic});

  @override
  State<_ChapterManagerPage> createState() => _ChapterManagerPageState();
}

class _ChapterManagerPageState extends State<_ChapterManagerPage> {
  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('QL Chương: ${widget.comic.title}')),
      body: FutureBuilder<List<CloudChapter>>(
        future: DriveService.instance.getChapters(widget.comic.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final chapters = snapshot.data ?? [];
          if (chapters.isEmpty) {
            return const Center(child: Text('Chưa có chương nào'));
          }

          return ListView.builder(
            itemCount: chapters.length,
            itemBuilder: (context, index) {
              final chapter = chapters[index];
              return ListTile(
                title: Text(chapter.title),
                subtitle: Text(
                  '${chapter.fileType.toUpperCase()} - ${(chapter.sizeBytes / 1024 / 1024).toStringAsFixed(2)} MB',
                ),
              );
            },
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
        label: const Text('Up Chapter'),
        icon: const Icon(Icons.upload_file),
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
    if (_titleController.text.isEmpty || _file == null) return;

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
      title: const Text('Upload Chapter mới'),
      content: SingleChildScrollView(
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Tên Chapter (VD: Chapter 1)',
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.attach_file),
              label: Text(
                _file == null ? 'Chọn File (ZIP/CBZ/EPUB)' : 'Đã chọn file',
              ),
            ),
            if (_file != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  _file!.path.split('/').last,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            if (_isUploading)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: CircularProgressIndicator(),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          onPressed: _isUploading ? null : _submit,
          child: const Text('Upload'),
        ),
      ],
    );
  }
}
