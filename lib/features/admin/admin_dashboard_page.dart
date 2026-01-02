import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../shared/drive_image.dart';
import 'edit_comic_dialog.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  Map<String, int> _stats = {'comics': 0, 'users': 0, 'chapters': 0};
  final user = FirebaseAuth.instance.currentUser;
  GoogleSignInAccount? _driveAccount;
  late StreamSubscription<GoogleSignInAccount?> _authSubscription;

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
    if (user?.email != 'admin@gmail.com') {
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
    final comics = await DriveService.instance.getComics();
    final comicCount = comics.length;

    // Lấy số lượng user từ Firestore
    int userCount = 0;
    try {
      final userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .count()
          .get();
      userCount = userSnapshot.count ?? 0;
    } catch (e) {
      debugPrint('Error loading user stats: $e');
    }

    if (mounted) {
      setState(() {
        _stats = {'comics': comicCount, 'users': userCount, 'chapters': 0};
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (user?.email != 'admin@gmail.com') {
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
                        value: '${_stats['comics']}',
                        icon: Icons.book,
                        color: Colors.blueAccent,
                      ),
                      const SizedBox(width: 16),
                      _StatCard(
                        title: 'Người dùng',
                        value: '${_stats['users']}',
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
                        onPressed: () => context.push('/admin/upload'),
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
          _buildComicGrid(),
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
                // Confirm logout logic...
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

  Widget _buildComicGrid() {
    return FutureBuilder<List<CloudComic>>(
      future: DriveService.instance.getComics(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final comics = snapshot.data ?? [];
        if (comics.isEmpty) {
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
              final comic = comics[index];
              return _AdminComicCard(comic: comic, onRefresh: _loadStats);
            }, childCount: comics.length),
          ),
        );
      },
    );
  }
}

class _AdminComicCard extends StatelessWidget {
  final CloudComic comic;
  final VoidCallback onRefresh;

  const _AdminComicCard({required this.comic, required this.onRefresh});

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
                child: DriveImage(fileId: comic.coverFileId, fit: BoxFit.cover),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comic.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      comic.author,
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
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
              child: IconButton(
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                iconSize: 18,
                icon: const Icon(Icons.edit, color: Colors.white),
                onPressed: () {
                  // Show options: Chapter Manager / Edit Info
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
                            context.push('/admin/chapters', extra: comic);
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
                              builder: (_) => EditComicDialog(comic: comic),
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
                                  'Bạn có chắc muốn xóa truyện "${comic.title}" không? Hành động này không thể hoàn tác.',
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
                                      ); // Close dialog
                                      // Show loading
                                      showDialog(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (_) => const Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      );
                                      try {
                                        await DriveService.instance.deleteComic(
                                          comic.id,
                                        );
                                        if (context.mounted) {
                                          Navigator.pop(
                                            context,
                                          ); // Close loading
                                          onRefresh(); // Refresh parent
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
                                          Navigator.pop(
                                            context,
                                          ); // Close loading
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

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            Text(
              title,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}
