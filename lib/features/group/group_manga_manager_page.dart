import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../shared/drive_image.dart';
import '../admin/edit_manga_dialog.dart';
import '../admin/add_manga_dialog.dart';
import '../admin/chapter_manager_page.dart';
import '../../data/models_group.dart';
import '../../data/content_type.dart';

class GroupMangaManagerPage extends StatefulWidget {
  final ScanlationGroup group;
  const GroupMangaManagerPage({super.key, required this.group});

  @override
  State<GroupMangaManagerPage> createState() => _GroupMangaManagerPageState();
}

class _GroupMangaManagerPageState extends State<GroupMangaManagerPage> {
  List<CloudManga> _allGroupMangas = [];
  List<CloudManga> _filteredMangas = [];
  bool _isLoading = true;
  StreamSubscription<dynamic>? _authSubscription;
  dynamic _driveAccount;

  final TextEditingController _searchController = TextEditingController();
  MangaContentType? _selectedTypeFilter;

  @override
  void initState() {
    super.initState();
    _driveAccount = DriveService.instance.currentUser;
    _authSubscription = DriveService.instance.onAuthStateChanged.listen((account) {
      if (mounted) setState(() => _driveAccount = account);
    });
    _loadMangas();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMangas() async {
    setState(() => _isLoading = true);
    final allMangas = await DriveService.instance.getMangas(forceRefresh: true);
    if (mounted) {
      setState(() {
        _allGroupMangas = allMangas.where((m) => m.uploaderGroupId == widget.group.id).toList();
        _applyFilters();
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    _filteredMangas = _allGroupMangas.where((m) {
      final matchesSearch = query.isEmpty ||
          m.title.toLowerCase().contains(query) ||
          m.author.toLowerCase().contains(query);
      final matchesType = _selectedTypeFilter == null || m.contentType == _selectedTypeFilter;
      return matchesSearch && matchesType;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _driveAccount != null;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).cardColor,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.group.name,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white),
            ),
            Text(
              '${_allGroupMangas.length} bộ truyện đã đăng',
              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6)),
            ),
          ],
        ),
        actions: [
          _buildDriveAction(),
          IconButton(
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _loadMangas,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        elevation: 4,
        onPressed: () async {
          final result = await showDialog<bool>(
            context: context,
            builder: (_) => AddMangaDialog(
              uploaderGroupId: widget.group.id,
              uploaderGroupName: widget.group.name,
            ),
          );
          if (result == true) {
            _loadMangas();
          }
        },
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Đăng Truyện Mới', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // Search & Filter Header
          Container(
            color: Theme.of(context).cardColor,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Column(
              children: [
                // Search Box
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    onChanged: (_) => setState(_applyFilters),
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm truyện theo tên, tác giả...',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded, color: Colors.blueAccent, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.white54),
                              onPressed: () {
                                _searchController.clear();
                                setState(_applyFilters);
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Content Type Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _buildFilterChip('Tất cả', null),
                      const SizedBox(width: 8),
                      _buildFilterChip('Truyện tranh', MangaContentType.manga),
                      const SizedBox(width: 8),
                      _buildFilterChip('Novel / EPUB', MangaContentType.novel),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Manga Grid or Empty State
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.blueAccent),
                  )
                : _filteredMangas.isEmpty
                    ? _buildEmptyState(isConnected)
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        physics: const BouncingScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.68,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                        itemCount: _filteredMangas.length,
                        itemBuilder: (context, index) {
                          final manga = _filteredMangas[index];
                          return _GroupMangaCard(
                            manga: manga,
                            onRefresh: _loadMangas,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, MangaContentType? type) {
    final theme = Theme.of(context);
    final isSelected = _selectedTypeFilter == type;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTypeFilter = type;
          _applyFilters();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueAccent : theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.blueAccent : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildDriveAction() {
    final isConnected = _driveAccount != null;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: isConnected
            ? const Color(0xFF10B981).withValues(alpha: 0.15)
            : const Color(0xFFEF4444).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isConnected
              ? const Color(0xFF10B981).withValues(alpha: 0.4)
              : const Color(0xFFEF4444).withValues(alpha: 0.4),
        ),
      ),
      child: IconButton(
        tooltip: isConnected ? 'Đã kết nối: ${_driveAccount!.email}' : 'Chưa kết nối Drive (Bấm để kết nối)',
        icon: Icon(
          Icons.cloud_done_rounded,
          size: 20,
          color: isConnected ? const Color(0xFF34D399) : const Color(0xFFF87171),
        ),
        onPressed: () async {
          if (!isConnected) {
            try {
              await DriveService.instance.signIn();
            } catch (e) {
              if (!mounted) return;
              final errStr = e.toString().toLowerCase();
              if (errStr.contains('huỷ') || errStr.contains('cancel')) {
                return;
              }
              _showDriveAccessRequestDialog();
            }
          } else {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: Theme.of(context).dialogTheme.backgroundColor ?? Theme.of(context).cardColor,
                title: const Text('Ngắt kết nối Drive?', style: TextStyle(color: Colors.white)),
                content: Text('Bạn đang kết nối với email: ${_driveAccount!.email}', style: const TextStyle(color: Colors.white70)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Ngắt kết nối', style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            );
            if (confirm == true) await DriveService.instance.signOut();
          }
        },
      ),
    );
  }

  void _showDriveAccessRequestDialog() {
    final user = FirebaseAuth.instance.currentUser;
    final emailController = TextEditingController(text: user?.email ?? '');
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).dialogTheme.backgroundColor ?? Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Yêu cầu quyền truy cập Drive', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tài khoản Google của bạn chưa được Admin cấp quyền truy cập Google Drive.\n\nNhập email Google bên dưới, Admin sẽ thêm bạn vào danh sách cho phép:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Email Google',
                labelStyle: const TextStyle(color: Color(0xFFFFB74D)),
                hintText: 'example@gmail.com',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFFFFB74D)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await FirebaseFirestore.instance.collection('drive_access_requests').doc(user?.uid ?? email).set({
                  'email': email,
                  'uid': user?.uid ?? '',
                  'displayName': user?.displayName ?? '',
                  'groupId': widget.group.id,
                  'groupName': widget.group.name,
                  'status': 'pending',
                  'createdAt': FieldValue.serverTimestamp(),
                });
                if (mounted) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Đã gửi yêu cầu cho Admin! Vui lòng chờ Admin thêm email của bạn vào danh sách cho phép.'),
                      duration: Duration(seconds: 4),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(SnackBar(content: Text('Lỗi gửi yêu cầu: $e')));
                }
              }
            },
            child: const Text('Gửi yêu cầu', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isConnected) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blueAccent.withValues(alpha: 0.12),
              ),
              child: const Icon(Icons.auto_stories_outlined, size: 40, color: Colors.blueAccent),
            ),
            const SizedBox(height: 16),
            const Text(
              'Không tìm thấy bộ truyện nào',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _searchController.text.isNotEmpty
                  ? 'Không có kết quả khớp với từ khóa tìm kiếm.'
                  : 'Nhóm chưa đăng truyện nào. Bấm nút "Đăng Truyện Mới" bên dưới để tải lên bộ truyện đầu tiên!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

// ── VIP MANGA CARD ─────────────────────────────────────────────────────────

class _GroupMangaCard extends StatelessWidget {
  final CloudManga manga;
  final VoidCallback onRefresh;

  const _GroupMangaCard({required this.manga, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DriveImage(fileId: manga.coverFileId, fit: BoxFit.cover),
          
          // Gradient Overlay
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black38, Color(0xF2000000)],
                stops: [0.35, 0.65, 1.0],
              ),
            ),
          ),

          // Content Type Frosted Glass Tag
          Positioned(
            top: 8,
            left: 8,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    manga.contentType.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Manga Details Text
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    manga.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    manga.author.isNotEmpty ? manga.author : 'Chưa rõ tác giả',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.remove_red_eye_rounded, size: 12, color: const Color(0xFFFFB74D)),
                      const SizedBox(width: 3),
                      Text(
                        '${manga.viewCount}',
                        style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.favorite_rounded, size: 12, color: Colors.pinkAccent),
                      const SizedBox(width: 3),
                      Text(
                        '${manga.likeCount}',
                        style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Ripple Tap Overlay
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _showMangaActions(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMangaActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  manga.title,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              const Divider(color: Colors.white12),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.list_alt_rounded, color: Colors.blueAccent, size: 22),
                ),
                title: const Text('Quản lý Chương', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('Thêm chapter, xoá, đổi thứ tự kéo thả', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ChapterManagerPage(manga: manga)),
                  );
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.edit_note_rounded, color: Colors.amberAccent, size: 22),
                ),
                title: const Text('Sửa Thông Tin Truyện', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('Đổi tên, tác giả, thể loại, ảnh bìa, trạng thái', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final result = await showDialog<bool>(
                    context: context,
                    builder: (_) => EditMangaDialog(manga: manga),
                  );
                  if (result == true) {
                    onRefresh();
                  }
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 22),
                ),
                title: const Text('Xóa Truyện', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                subtitle: const Text('Xóa hoàn toàn bộ truyện và các chương trên Drive', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeleteManga(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteManga(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(context).dialogTheme.backgroundColor ?? Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xác nhận xóa truyện?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Bạn có chắc chắn muốn xóa bộ truyện "${manga.title}"?\n\nToàn bộ chương và dữ liệu trên Google Drive sẽ bị xóa vĩnh viễn.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(dialogContext);
              showDialog(
                context: context,
                barrierDismissible: false,
                useRootNavigator: true,
                builder: (_) => const Center(
                  child: CircularProgressIndicator(color: Colors.redAccent),
                ),
              );
              try {
                await DriveService.instance.deleteManga(manga.id);
                if (context.mounted) {
                  Navigator.of(context, rootNavigator: true).pop();
                  onRefresh();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã xóa truyện thành công')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.of(context, rootNavigator: true).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Lỗi khi xóa truyện: $e')),
                  );
                }
              }
            },
            child: const Text('Xóa vĩnh viễn', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
