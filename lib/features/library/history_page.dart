import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../data/database_helper.dart';
import '../../data/models.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../../services/history_service.dart';
import '../shared/drive_image.dart';

// Trang lịch sử đọc truyện — dùng FutureBuilder thủ công (không dùng StreamBuilder)
// vì cần gộp 2 nguồn: SQLite local + Firestore cloud trước khi render.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<ReadingHistory> _historyList = [];
  List<CloudManga> _mangas = []; //
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  // Load dữ liệu: tải catalog Drive + gộp lịch sử local/cloud
  // forceRefresh: true khi pull-to-refresh (bỏ cache Drive)
  Future<void> _initData({bool forceRefresh = false}) async {
    if (!mounted) return;
    if (!forceRefresh && _historyList.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      final mangas = await DriveService.instance.getMangas(
        forceRefresh: forceRefresh,
      );
      final hList = await _fetchAndMergeHistory();
      if (mounted) {
        setState(() {
          _mangas = mangas;
          _historyList = hList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('History Init Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Gộp lịch sử local (SQLite) và cloud (Firestore)
  Future<List<ReadingHistory>> _fetchAndMergeHistory() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    // Guest dùng userId = 'guest' để lưu local — tránh conflict nếu sau đó đăng nhập
    final localId = userId ?? 'guest';
    final localHistory = await DatabaseHelper.instance.getHistory(localId);

    // Chỉ lấy cloud history nếu đã đăng nhập (guest không có Firestore)
    List<ReadingHistory> cloudHistory = [];
    if (userId != null) {
      cloudHistory = await HistoryService.instance.getAllHistory();
    }

    // Chiến lược gộp theo mangaId:
    // 1. Đổ local vào Map trước
    // 2. Duyệt cloud: nếu cùng mangaId → giữ bản có updatedAt mới hơn
    // 3. Kết quả: mỗi mangaId chỉ có 1 entry duy nhất (mới nhất)
    final historyMap = <String, ReadingHistory>{};
    for (var h in localHistory) {
      historyMap[h.mangaId] = h;
    }
    for (var h in cloudHistory) {
      if (historyMap.containsKey(h.mangaId)) {
        if (h.updatedAt.isAfter(historyMap[h.mangaId]!.updatedAt)) {
          historyMap[h.mangaId] = h; // Cloud mới hơn → ghi đè local
        }
      } else {
        historyMap[h.mangaId] = h; // Chỉ có trên cloud → thêm vào
      }
    }

    // Sort theo updatedAt giảm dần → mới đọc nhất lên đầu
    final merged = historyMap.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    // Đồng bộ ngược lại local DB: đảm bảo offline có dữ liệu mới nhất từ cloud
    if (userId != null && merged.isNotEmpty) {
      for (var h in merged) {
        await DatabaseHelper.instance.saveHistory(h);
      }
    }

    return merged;
  }

  // Xóa sạch lịch sử ở cả 2 nơi: SQLite (guest + uid) và Firestore
  Future<void> _handleDeepClear() async {
    if (mounted) setState(() => _isLoading = true);
    final userId = FirebaseAuth.instance.currentUser?.uid;

    try {
      // Xóa local: phải xóa cả 'guest' và uid (user có thể đã đọc trước khi đăng nhập)
      await DatabaseHelper.instance.clearHistory('guest');
      if (userId != null) {
        await DatabaseHelper.instance.clearHistory(userId);
      }
      // Xóa cloud
      if (userId != null) {
        await HistoryService.instance.clearAllHistory();
      }
      if (mounted) {
        setState(() {
          _historyList = [];
          _isLoading = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã xoá sạch lịch sử!')));
      }
    } catch (e) {
      debugPrint('Clear Error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi xoá lịch sử: $e')));
      }
    }
  }

  void _showDeleteConfirmDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: const Text('Xoá tất cả?'),
        content: const Text(
          'Hành động này sẽ xoá vĩnh viễn lịch sử đọc truyện của bạn (Cả trên máy và Cloud).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Huỷ'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handleDeepClear();
            },
            child: const Text('Xoá', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Hiện spinner khi _isLoading = true (lần đầu load)
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          title: const Text('Lịch Sử'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_historyList.isEmpty) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          title: const Text('Lịch Sử'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.history_toggle_off,
                size: 64,
                color: Theme.of(context).disabledColor,
              ),
              const SizedBox(height: 16),
              const Text(
                'Chưa có lịch sử đọc truyện.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: _initData, child: const Text('Tải lại')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Lịch sử đọc',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: _showDeleteConfirmDialog,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _initData(forceRefresh: true),
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: _historyList.length,
          itemBuilder: (context, index) {
            final item = _historyList[index];

            // Map mangaId → CloudManga. orElse: truyện đã bị xóa khỏi catalog
            final manga = _mangas.firstWhere(
              (c) => c.id == item.mangaId,
              orElse: () => CloudManga(
                id: item.mangaId,
                title: 'Truyện không tồn tại',
                author: 'Unknown',
                description: '',
                coverFileId: '',
                genres: [],
                status: '',
                viewCount: 0,
                likeCount: 0,
                updatedAt: DateTime.now(),
              ),
            );

            // Ẩn dòng nếu không tìm thấy ảnh bìa (truyện đã bị xóa)
            if (manga.coverFileId.isEmpty) return const SizedBox.shrink();

            final date =
                '${item.updatedAt.day}/${item.updatedAt.month} ${item.updatedAt.hour}:${item.updatedAt.minute.toString().padLeft(2, '0')}';

            return Card(
              color: Theme.of(context).cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: DriveImage(
                    fileId: manga.coverFileId,
                    width: 60,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
                ),
                title: Text(
                  manga.title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    // Hiện "chapterTitle • Trang X" — lastPageIndex là 0-based nên +1
                    Text(
                      '${item.chapterTitle ?? 'Chương ${item.chapterId}'} • Trang ${item.lastPageIndex + 1}',
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      date,
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
                onTap: () async {
                  await context.push(
                    '/reader/${item.chapterId}',
                  ); // Chờ user đọc xong
                  _initData(); // Reload để cập nhật lastPageIndex mới
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
