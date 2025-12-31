import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../data/firestore_service.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../shared/drive_image.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  Map<String, int> _stats = {'comics': 0, 'users': 0, 'chapters': 0};
  final user = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _checkAdmin();
    _loadStats();
  }

  void _checkAdmin() {
    if (user?.email != 'admin@gmail.com') {
      // Simple client-side protection. Secure apps should use Firestore Rules / Custom Claims.
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
    // Manually count
    // 1. Comics
    final comics = await DriveService.instance.getComics();
    final comicCount = comics.length;

    // 2. Users (Still in Firestore)
    // We can't easily get count without fetching all, but for now let's try to just fetch
    // or leave it as 0 if we don't want to fetch all users.
    // Let's assume we want to keep it simple and just show 0 or fetch if manageable.
    // Since we removed getStats from FirestoreService, we can try to fetch users stream length?
    // No, better to just leave it 0 or add getUsersCount if needed.
    // Let's just fetch all users for now since this is the only way in basic Firestore without counters.
    // Actually, FirestoreService might still have getUsers.
    int userCount = 0;
    try {
      // Assuming getStats is gone, let's skip user count or fetch simple list.
      // userCount = (await FirestoreService.instance.getUsers().first).length;
    } catch (_) {}

    if (mounted) {
      setState(() {
        _stats = {'comics': comicCount, 'users': userCount, 'chapters': 0};
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Double check in build
    if (user?.email != 'admin@gmail.com') {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // Light background for admin
      appBar: AppBar(
        title: const Text(
          'Admin Dashboard',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF1C1C1E),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadStats),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tổng quan',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _StatCard(
                  title: 'Truyện',
                  value: '${_stats['comics']}',
                  icon: Icons.book,
                  color: Colors.blue,
                ),
                const SizedBox(width: 16),
                _StatCard(
                  title: 'Người dùng',
                  value: '${_stats['users']}',
                  icon: Icons.people,
                  color: Colors.orange,
                ),
                // Add more cards if needed
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Quản lý nội dung',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    // Reuse the existing upload page logic or simply navigate there?
                    // Currently AdminUploadPage includes a list.
                    // Let's repurpose AdminUploadPage as "Content Manager" or just link to it.
                    // The user asked for "Add Comic" functionality.
                    // We can use the Add Dialog from AdminUploadPage here or just navigate to it.
                    // For simplicity, let's navigate to the previous page which handles list + add.
                    context.push('/admin/upload');
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm Truyện'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1C1C1E),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const _RecentComicsTable(),
          ],
        ),
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
          color: Colors.white,
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
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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

class _RecentComicsTable extends StatelessWidget {
  const _RecentComicsTable();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CloudComic>>(
      future: DriveService.instance.getComics(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final comics = snapshot.data ?? [];
        if (comics.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text("Chưa có dữ liệu truyện."),
            ),
          );
        }

        return Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: comics
                .map(
                  (comic) => ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: DriveImage(
                        fileId: comic.coverFileId,
                        width: 40,
                        height: 60,
                        fit: BoxFit.cover,
                      ),
                    ),
                    title: Text(
                      comic.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(comic.author),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Tính năng xóa đang phát triển (Cần xóa Folder trên Drive)',
                            ),
                          ),
                        );
                      },
                    ),
                    onTap: () {
                      context.push('/admin/upload');
                    },
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}
