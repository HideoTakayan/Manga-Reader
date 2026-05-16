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
import 'edit_manga_dialog.dart';
import 'chapter_manager_page.dart';

// Trang quản trị dành cho Admin: xem thống kê, thêm/sửa/xóa truyện.
// Chỉ những email trong _adminEmails mới vào được — ngoài ra bị redirect về Home ngay.
class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  Map<String, int> _stats = {'mangas': 0, 'users': 0, 'chapters': 0};
  final user = FirebaseAuth.instance.currentUser;
  GoogleSignInAccount?
  _driveAccount; // null = chưa đăng nhập Drive (chưa có quyền ghi)
  late StreamSubscription<GoogleSignInAccount?> _authSubscription;

  // Whitelist email được vào trang Admin
  final _adminEmails = ['admin@gmail.com', 'anhlasinhvien2k51@gmail.com'];

  @override
  void initState() {
    super.initState();
    _checkAdmin(); // Kiểm tra quyền ngay khi mở trang
    _loadStats(); // Tải thống kê lên dashboard
    _driveAccount = DriveService.instance.currentUser;
    _authSubscription = DriveService.instance.onAuthStateChanged.listen((
      account,
    ) {
      if (mounted) setState(() => _driveAccount = account);
    });
  }

  @override
  void dispose() {
    _authSubscription
        .cancel(); // Hủy subscription khi rời trang để tránh memory leak
    super.dispose();
  }

  // Nếu email hiện tại không có trong whitelist, redirect về Home và hiện thông báo.
  // Dùng addPostFrameCallback vì không được điều hướng trong initState (widget chưa được gắn vào tree).
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

  // Tải số liệu thống kê: số truyện từ Drive cache, số user từ Firestore.
  // Dùng Aggregation Count trước (nhanh, ít đọc), fallback sang get() nếu Firestore rules không cho.
  // userCount = -1 báo hiệu không có quyền đọc → UI hiển thị "N/A".
  Future<void> _loadStats() async {
    final mangas = await DriveService.instance.getMangas();
    final mangaCount = mangas.length;

    int userCount = 0;
    try {
      // Cách 1: Aggregation Count — trả về số lượng mà không cần tải cả collection về
      final userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .count()
          .get();
      userCount = userSnapshot.count ?? 0;
    } catch (e) {
      debugPrint('Error loading user stats (count): $e');
      try {
        // Cách 2: Fallback — tải toàn bộ documents rồi đếm (tốn đọc hơn)
        final docs = await FirebaseFirestore.instance.collection('users').get();
        userCount = docs.size;
      } catch (e2) {
        debugPrint('Error loading user stats (fallback): $e2');
        userCount = -1; // -1 = không có quyền đọc collection users
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
    // Nếu chưa xác nhận quyền (kiểm tra email), hiện loading tạm để tránh flash nội dung Admin
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
                    color: Theme.of(
                      context,
                    ).iconTheme.color?.withValues(alpha: 0.1),
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
                  _buildDriveStatus(), // Banner trạng thái kết nối Drive
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
                      // userCount = -1 → hiện "N/A" thay vì số âm
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
                            _loadStats(); // Cập nhật số liệu sau khi thêm truyện
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


  // Banner hiển thị trạng thái kết nối Google Drive (đã đăng nhập OAuth chưa).
  // Xanh = đã kết nối (có quyền ghi), Đỏ = chưa kết nối (chỉ đọc được).
  Widget _buildDriveStatus() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _driveAccount != null
              ? [
                  Colors.green.withValues(alpha: 0.2),
                  Colors.green.withValues(alpha: 0.05),
                ]
              : [
                  Colors.red.withValues(alpha: 0.2),
                  Colors.red.withValues(alpha: 0.05),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _driveAccount != null
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.red.withValues(alpha: 0.3),
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
                    ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          // Nút Kết nối/Ngắt kết nối Drive OAuth
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              if (_driveAccount == null) {
                try {
                  await DriveService.instance.signIn();
                } catch (e) {
                  if (context.mounted) {
                    messenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                  }
                }
              } else {
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

  // Lưới 2 cột hiển thị toàn bộ truyện. Mỗi ô là _AdminMangaCard.
  // Dùng FutureBuilder vì dữ liệu Drive là bất đồng bộ.
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

// Card hiển thị một bộ truyện trong lưới Admin.
// Bấm vào thì mở bottom sheet với 3 lựa chọn: Quản lý Chương / Sửa Thông Tin / Xóa Truyện.
class _AdminMangaCard extends StatelessWidget {
  final CloudManga manga;
  final VoidCallback onRefresh; // Gọi lại để refresh dashboard sau khi sửa/xóa

  const _AdminMangaCard({required this.manga, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
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
                        ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Lớp InkWell phủ toàn bộ card để bắt sự kiện tap, hiện bottom sheet menu
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
                        // Điều hướng đến ChapterManagerPage để quản lý danh sách chapter
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
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    ChapterManagerPage(manga: manga),
                              ),
                            );
                          },
                        ),
                        // Mở EditMangaDialog để sửa tên/tác giả/bìa/thể loại
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
                        // Xóa truyện: xác nhận → loading overlay → gọi Drive API → refresh
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
                                      Navigator.pop(
                                        dialogContext,
                                      ); // Đóng dialog xác nhận

                                      // Hiện loading overlay — dùng rootNavigator để pop đúng dialog này sau
                                      showDialog(
                                        context: context,
                                        barrierDismissible: false,
                                        useRootNavigator: true,
                                        builder: (_) => const Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      );

                                      try {
                                        await DriveService.instance.deleteManga(
                                          manga.id,
                                        );

                                        if (context.mounted) {
                                          // Phải dùng rootNavigator để pop đúng loading dialog
                                          Navigator.of(
                                            context,
                                            rootNavigator: true,
                                          ).pop();
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

// Dialog thêm bộ truyện mới: điền tên/tác giả/mô tả/thể loại + chọn ảnh bìa → upload lên Drive.
// _isUploading dùng để disable nút Lưu và ẩn/hiện loading indicator trong khi upload.
class _AddMangaDialog extends StatefulWidget {
  const _AddMangaDialog();

  @override
  State<_AddMangaDialog> createState() => _AddMangaDialogState();
}

class _AddMangaDialogState extends State<_AddMangaDialog> {
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _descController = TextEditingController();
  final _genresController =
      TextEditingController(); // Nhập dạng "Action, Romance, Fantasy"
  File? _coverFile;
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
      );
      if (mounted) {
        Navigator.pop(context, true); // true = báo hiệu thêm thành công
      }
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
            // Vùng chọn ảnh bìa — icon chuyển xanh khi đã chọn file
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
          onPressed: _isUploading ? null : _submit, // Disable khi đang upload
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}

// Widget card thống kê nhỏ (số truyện, số user).
// Nhận vào title, value, icon, color để tái sử dụng cho nhiều loại số liệu.
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
              color: Colors.black.withValues(alpha: 0.1),
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
