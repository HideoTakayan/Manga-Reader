import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../shared/drive_image.dart';
import 'edit_manga_dialog.dart'; // Renamed import
import 'chapter_manager_page.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  Map<String, int> _stats = {'mangas': 0, 'users': 0, 'chapters': 0};
  final user = FirebaseAuth.instance.currentUser;
  GoogleSignInAccount? _driveAccount;
  late StreamSubscription<GoogleSignInAccount?> _authSubscription;

  // Danh sách Admin
  final _adminEmails = ['admin@gmail.com', 'anhlasinhvien2k51@gmail.com'];

  @override
  void initState() {
    super.initState();
    _checkAdmin();
    _loadStats();
    _driveAccount = DriveService.instance.currentUser;
    _authSubscription = DriveService.instance.onAuthStateChanged.listen((
      account,
    ) {
      if (mounted) {
        setState(() {
          _driveAccount = account;
        });
      }
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  void _checkAdmin() {
    if (!_adminEmails.contains(user?.email)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bạn không có quyền truy cập trang này'),
          ),
        );
      });
    }
  }

  Future<void> _loadStats() async {
    final mangas = await DriveService.instance.getMangas();
    final mangaCount = mangas.length;

    // Lấy số lượng user từ Firestore
    int userCount = 0;
    try {
      // Cách 1: Thử dùng Aggregation Count (nhanh & rẻ)
      final userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .count()
          .get();
      userCount = userSnapshot.count ?? 0;
    } catch (e) {
      debugPrint('Error loading user stats (count): $e');
      // Cách 2: Fallback dùng query snapshot nếu count() lỗi (ví dụ do rules cũ)
      try {
        final docs = await FirebaseFirestore.instance.collection('users').get();
        userCount = docs.size;
      } catch (e2) {
        debugPrint('Error loading user stats (fallback): $e2');
        // Permission denied -> Set userCount = -1 để UI biết
        userCount = -1;
      }
    }

    if (mounted) {
      setState(() {
        _stats = {'mangas': mangaCount, 'users': userCount, 'chapters': 0};
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_adminEmails.contains(user?.email)) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200.0,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                'Admin Dashboard',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context).colorScheme.surface,
                      Theme.of(context).scaffoldBackgroundColor,
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.admin_panel_settings,
                    size: 80,
                    color: Theme.of(context).iconTheme.color?.withOpacity(0.1),
                  ),
                ),
              ),
            ),
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            actions: [
              IconButton(
                icon: Icon(
                  Icons.refresh,
                  color: Theme.of(context).iconTheme.color,
                ),
                onPressed: _loadStats,
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDriveStatus(),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      _StatCard(
                        title: 'Truyện',
                        value: '${_stats['mangas']}',
                        icon: Icons.book,
                        color: Colors.blueAccent,
                      ),
                      const SizedBox(width: 16),
                      _StatCard(
                        title: 'Người dùng',
                        value: _stats['users'] == -1
                            ? 'N/A'
                            : '${_stats['users']}',
                        icon: Icons.people,
                        color: Colors.orangeAccent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Quản lý nội dung',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final result = await showDialog(
                            context: context,
                            builder: (_) => const _AddMangaDialog(),
                          );
                          if (result == true) {
                            _loadStats(); // Refresh stats if manga added
                          }
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Thêm Truyện'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          _buildMangaGrid(),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildDriveStatus() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _driveAccount != null
              ? [Colors.green.withOpacity(0.2), Colors.green.withOpacity(0.05)]
              : [Colors.red.withOpacity(0.2), Colors.red.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _driveAccount != null
              ? Colors.green.withOpacity(0.3)
              : Colors.red.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_queue,
            color: _driveAccount != null ? Colors.green : Colors.red,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Google Drive',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                Text(
                  _driveAccount != null
                      ? 'Kết nối: ${_driveAccount!.email}'
                      : 'Chưa kết nối',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.color?.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              if (_driveAccount == null) {
                try {
                  await DriveService.instance.signIn();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                  }
                }
              } else {
                // Logic đăng xuất sẽ được xử lý tại đây
                await DriveService.instance.signOut();
              }
            },
            child: Text(
              _driveAccount != null ? 'Ngắt kết nối' : 'Kết nối',
              style: TextStyle(
                color: _driveAccount != null
                    ? Colors.redAccent
                    : Colors.blueAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMangaGrid() {
    return FutureBuilder<List<CloudManga>>(
      future: DriveService.instance.getMangas(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final mangas = snapshot.data ?? [];
        if (mangas.isEmpty) {
          return const SliverToBoxAdapter(
            child: Center(child: Text('Chưa có truyện nào')),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.7,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final manga = mangas[index];
              return _AdminMangaCard(manga: manga, onRefresh: _loadStats);
            }, childCount: mangas.length),
          ),
        );
      },
    );
  }
}

class _AdminMangaCard extends StatelessWidget {
  final CloudManga manga;
  final VoidCallback onRefresh;

  const _AdminMangaCard({required this.manga, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: DriveImage(fileId: manga.coverFileId, fit: BoxFit.cover),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      manga.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      manga.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.color?.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Theme.of(context).cardColor,
                    builder: (ctx) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: Icon(
                            Icons.list,
                            color: Theme.of(context).iconTheme.color,
                          ),
                          title: Text(
                            'Quản lý Chương',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            // Điều hướng đến đúng trang ChapterManagerPage chuẩn (Giao diện ảnh 2)
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    ChapterManagerPage(manga: manga),
                              ),
                            );
                          },
                        ),

                        ListTile(
                          leading: Icon(
                            Icons.edit,
                            color: Theme.of(context).iconTheme.color,
                          ),
                          title: Text(
                            'Sửa Thông Tin',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          onTap: () async {
                            Navigator.pop(ctx);
                            await showDialog(
                              context: context,
                              builder: (_) => EditMangaDialog(manga: manga),
                            );
                            onRefresh();
                          },
                        ),
                        ListTile(
                          leading: const Icon(
                            Icons.delete,
                            color: Colors.redAccent,
                          ),
                          title: const Text(
                            'Xóa Truyện',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            showDialog(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                backgroundColor: Theme.of(context).cardColor,
                                title: Text(
                                  'Xóa Truyện?',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                content: Text(
                                  'Bạn có chắc muốn xóa truyện "${manga.title}" không? Hành động này không thể hoàn tác.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext),
                                    child: Text(
                                      'Hủy',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      // 1. Đóng hộp thoại xác nhận ngay lập tức
                                      Navigator.pop(dialogContext);

                                      // 2. Hiển thị loading overlay - dùng rootNavigator để tránh pop lộn trang
                                      showDialog(
                                        context: context,
                                        barrierDismissible: false,
                                        useRootNavigator: true,
                                        builder: (_) => const Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      );

                                      try {
                                        // 3. Thực hiện xóa (Hàm này giờ đã xóa khỏi cache trước nên rất nhanh)
                                        await DriveService.instance.deleteManga(
                                          manga.id,
                                        );

                                        if (context.mounted) {
                                          // 4. Đóng loading bằng rootNavigator
                                          Navigator.of(
                                            context,
                                            rootNavigator: true,
                                          ).pop();

                                          // 5. Cập nhật giao diện
                                          onRefresh();

                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text('Đã xóa truyện'),
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          // Đóng loading nếu lỗi
                                          Navigator.of(
                                            context,
                                            rootNavigator: true,
                                          ).pop();

                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(content: Text('Lỗi: $e')),
                                          );
                                        }
                                      }
                                    },
                                    child: const Text(
                                      'Xóa',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddMangaDialog extends StatefulWidget {
  const _AddMangaDialog();

  @override
  State<_AddMangaDialog> createState() => _AddMangaDialogState();
}

class _AddMangaDialogState extends State<_AddMangaDialog> {
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _descController = TextEditingController();
  final _genresController = TextEditingController();
  File? _coverFile;
  bool _isUploading = false;

  Future<void> _pickCover() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      if (mounted) {
        setState(() {
          _coverFile = File(result.files.single.path!);
        });
      }
    }
  }

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
        genres: _genresController.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        status: 'Đang Cập Nhật',
      );
      if (mounted) Navigator.pop(context, true);
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
        'Thêm Truyện Mới',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: const InputDecoration(labelText: 'Tên truyện'),
            ),
            TextField(
              controller: _authorController,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: const InputDecoration(labelText: 'Tác giả'),
            ),
            TextField(
              controller: _descController,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: const InputDecoration(labelText: 'Mô tả'),
            ),
            TextField(
              controller: _genresController,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: const InputDecoration(
                labelText: 'Thể loại (cách nhau bởi dấu phẩy)',
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _isUploading ? null : _pickCover,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.image,
                      color: _coverFile != null ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _coverFile == null
                            ? 'Chọn Ảnh Bìa'
                            : 'Đã chọn: ${_coverFile!.path.split('/').last}',
                        style: TextStyle(
                          color: _coverFile != null
                              ? Colors.green
                              : Theme.of(context).textTheme.bodyMedium?.color,
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
                padding: EdgeInsets.only(top: 16),
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

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    this.icon = Icons.analytics,
    this.color = Colors.blueAccent,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
