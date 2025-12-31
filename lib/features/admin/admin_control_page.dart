import 'package:flutter/material.dart';
import '../../data/firestore_service.dart';
import '../../data/models_user.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../shared/drive_image.dart';

import 'chapter_manager_page.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';

class AdminControlPage extends StatelessWidget {
  const AdminControlPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0E0E10),
        appBar: AppBar(
          title: const Text(
            'Trung Tâm Quản Trị',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF0E0E10),
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: const TabBar(
            indicatorColor: Colors.orange,
            labelColor: Colors.orange,
            unselectedLabelColor: Colors.grey,
            indicatorWeight: 3,
            tabs: [
              Tab(text: 'Người Dùng', icon: Icon(Icons.people_outline)),
              Tab(text: 'Kho Truyện', icon: Icon(Icons.library_books_outlined)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_UserManagementTab(), _ComicManagementTab()],
        ),
      ),
    );
  }
}

class _UserManagementTab extends StatelessWidget {
  const _UserManagementTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CloudUser>>(
      stream: FirestoreService.instance.getUsers(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());

        final users = snapshot.data!;
        if (users.isEmpty)
          return const Center(
            child: Text(
              "Chưa có User nào",
              style: TextStyle(color: Colors.white54),
            ),
          );

        return ListView.separated(
          itemCount: users.length,
          separatorBuilder: (_, __) => const Divider(color: Colors.white10),
          itemBuilder: (context, index) {
            final user = users[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundImage: user.avatar.isNotEmpty
                    ? NetworkImage(user.avatar)
                    : null,
                backgroundColor: Colors.grey.shade800,
                child: user.avatar.isEmpty
                    ? Text(
                        user.name[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white),
                      )
                    : null,
              ),
              title: Text(
                user.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                user.email,
                style: const TextStyle(color: Colors.white60),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.white24),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (_) => _UserDetailDialog(user: user),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _UserDetailDialog extends StatelessWidget {
  final CloudUser user;
  const _UserDetailDialog({required this.user});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1C1C1E),
      title: Row(
        children: [
          CircleAvatar(
            backgroundImage: user.avatar.isNotEmpty
                ? NetworkImage(user.avatar)
                : null,
            backgroundColor: Colors.grey.shade800,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(user.name, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Email: ${user.email}',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text(
            'Ngày tham gia: ${user.createdAt.toLocal().toString().split(' ')[0]}',
            style: const TextStyle(color: Colors.white54),
          ),
          const Divider(color: Colors.white24),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng', style: TextStyle(color: Colors.orange)),
        ),
      ],
    );
  }
}

class _ComicManagementTab extends StatelessWidget {
  const _ComicManagementTab();

  void _showAddComicDialog(BuildContext context) {
    showDialog(context: context, builder: (_) => const _AddComicDialog());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddComicDialog(context),
        backgroundColor: Colors.orange,
        icon: const Icon(Icons.add, color: Colors.black),
        label: const Text(
          "Thêm Truyện",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: FutureBuilder<List<CloudComic>>(
        future: DriveService.instance.getComics(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());

          final comics = snapshot.data ?? [];
          if (comics.isEmpty) {
            return const Center(
              child: Text(
                "Kho truyện trống",
                style: TextStyle(color: Colors.white54),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: comics.length,
            itemBuilder: (context, index) {
              final comic = comics[index];
              return Card(
                color: const Color(0xFF1E1E20),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(10),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: DriveImage(
                      fileId: comic.coverFileId,
                      width: 50,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                  ),
                  title: Text(
                    comic.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comic.author,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      Text(
                        "${comic.description.length > 50 ? comic.description.substring(0, 50) : comic.description}...",
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "Tính năng xóa đang phát triển (Cần xóa Folder trên Drive)",
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChapterManagerPage(comic: comic),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
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
    // Validate
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vui lòng nhập tên truyện')));
      return;
    }

    if (_coverFile == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vui lòng chọn ảnh bìa')));
      return;
    }

    setState(() => _isUploading = true);
    try {
      await DriveService.instance.addComic(
        title: _titleController.text,
        author: _authorController.text,
        description: _descController.text,
        coverFile: _coverFile!,
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
      backgroundColor: const Color(0xFF1C1C1E),
      title: const Text(
        'Thêm Truyện Mới (Drive)',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTextField(_titleController, 'Tên truyện'),
            const SizedBox(height: 12),
            _buildTextField(_authorController, 'Tác giả'),
            const SizedBox(height: 12),
            _buildTextField(_descController, 'Mô tả ngắn', maxLines: 3),
            const SizedBox(height: 16),

            InkWell(
              onTap: _pickCover,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 150,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white24,
                    style: BorderStyle.solid,
                  ),
                  image: _coverFile != null
                      ? DecorationImage(
                          image: FileImage(_coverFile!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: _coverFile == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate,
                            color: Colors.white54,
                            size: 40,
                          ),
                          SizedBox(height: 8),
                          Text(
                            "Chọn Ảnh Bìa",
                            style: TextStyle(color: Colors.white54),
                          ),
                        ],
                      )
                    : null,
              ),
            ),

            if (_isUploading)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Center(
                  child: CircularProgressIndicator(color: Colors.orange),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          onPressed: _isUploading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.black,
          ),
          child: const Text('Lưu Truyện'),
        ),
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String label, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.black26,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.orange),
        ),
      ),
    );
  }
}
