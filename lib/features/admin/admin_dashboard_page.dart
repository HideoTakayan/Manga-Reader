import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../data/content_type.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../shared/drive_image.dart';
import 'edit_manga_dialog.dart';
import 'chapter_manager_page.dart';
import 'banner_manager_page.dart';
import 'reports_list_page.dart';
import 'users_list_page.dart';

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

  List<CloudManga> _allMangas = [];
  List<CloudManga> _filteredMangas = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isLoadingMangas = true;

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
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredMangas = _allMangas;
      } else {
        _filteredMangas = _allMangas.where((m) {
          return m.title.toLowerCase().contains(query) ||
              m.author.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
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
    setState(() => _isLoadingMangas = true);
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
        _allMangas = mangas;
        _isLoadingMangas = false;
        _stats = {'mangas': mangaCount, 'users': userCount, 'chapters': 0};
      });
      _onSearchChanged(); // Lọc lại danh sách sau khi tải xong
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
              _buildDriveAction(),
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
                  const SizedBox(height: 16),
                  Text(
                    'Công cụ quản trị',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _AdminToolButton(
                          icon: Icons.view_carousel,
                          label: 'Banner trang chủ',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const BannerManagerPage(),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _AdminToolButton(
                          icon: Icons.report_problem,
                          iconColor: Colors.orangeAccent,
                          label: 'Báo lỗi truyện',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ReportsListPage(),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),

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
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const UsersListPage(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Quản lý nội dung',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
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
                  _buildSearchBar(),
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

  Widget _buildDriveAction() {
    final isConnected = _driveAccount != null;
    return IconButton(
      tooltip: isConnected
          ? 'Đã kết nối Drive: ${_driveAccount!.email}'
          : 'Chưa kết nối Drive',
      icon: Icon(
        Icons.cloud_done,
        color: isConnected ? Colors.greenAccent : Colors.redAccent,
      ),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        if (!isConnected) {
          try {
            await DriveService.instance.signIn();
          } catch (e) {
            if (context.mounted) {
              messenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
            }
          }
        } else {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: Theme.of(context).cardColor,
              title: const Text('Ngắt kết nối Drive?'),
              content: Text(
                'Bạn đang kết nối với email: ${_driveAccount!.email}',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Hủy'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text(
                    'Ngắt kết nối',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            ),
          );
          if (confirm == true) {
            await DriveService.instance.signOut();
          }
        }
      },
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Tìm kiếm truyện theo tên hoặc tác giả...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  FocusScope.of(context).unfocus();
                },
              )
            : null,
        filled: true,
        fillColor: Theme.of(context).cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
      ),
    );
  }

  Widget _buildMangaGrid() {
    if (_isLoadingMangas) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(40.0),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_filteredMangas.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_off,
                  size: 64,
                  color: Theme.of(
                    context,
                  ).iconTheme.color?.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  _searchController.text.isEmpty
                      ? 'Chưa có truyện nào'
                      : 'Không tìm thấy truyện nào phù hợp',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).disabledColor,
                  ),
                ),
              ],
            ),
          ),
        ),
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
          final manga = _filteredMangas[index];
          return _AdminMangaCard(manga: manga, onRefresh: _loadStats);
        }, childCount: _filteredMangas.length),
      ),
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
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                manga.contentType.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
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
            const SizedBox(height: 12),
            DropdownButtonFormField<MangaContentType>(
              initialValue: _contentType,
              decoration: const InputDecoration(labelText: 'Loại nội dung'),
              items: MangaContentType.values
                  .map(
                    (type) =>
                        DropdownMenuItem(value: type, child: Text(type.label)),
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

class _AdminToolButton extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final VoidCallback onPressed;

  const _AdminToolButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: iconColor),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).cardColor,
        foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
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
  final VoidCallback? onTap;

  const _StatCard({
    required this.title,
    required this.value,
    this.icon = Icons.analytics,
    this.color = Colors.blueAccent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.15),
                color.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 28, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
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
      ),
    );
  }
}
