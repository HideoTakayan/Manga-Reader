import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../data/database_helper.dart';
import '../../data/models.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../../services/history_service.dart';
import '../shared/drive_image.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<ReadingHistory> _historyList = [];
  List<CloudComic> _comics = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData({bool forceRefresh = false}) async {
    if (!mounted) return;
    // Chỉ hiển thị loading full màn hình khi load lần đầu (chưa có dữ liệu)
    if (!forceRefresh && _historyList.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      // 1. Tải danh sách truyện từ Drive (Metadata)
      final comics = await DriveService.instance.getComics(
        forceRefresh: forceRefresh,
      );

      // 2. Tải lịch sử đọc và gộp dữ liệu
      final hList = await _fetchAndMergeHistory();

      if (mounted) {
        setState(() {
          _comics = comics;
          _historyList = hList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('History Init Error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<List<ReadingHistory>> _fetchAndMergeHistory() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    // 1. Lấy lịch sử từ Local DB
    final localId = userId ?? 'guest';
    final localHistory = await DatabaseHelper.instance.getHistory(localId);

    // 2. Lấy lịch sử từ Cloud (nếu đã đăng nhập)
    List<ReadingHistory> cloudHistory = [];
    if (userId != null) {
      cloudHistory = await HistoryService.instance.getAllHistory();
    }

    // 3. Chiến lược gộp lịch sử (Merge Strategy):
    // - Ưu tiên bản ghi có 'updatedAt' mới nhất
    // - Gộp dựa trên comicId
    final historyMap = <String, ReadingHistory>{};
    for (var h in localHistory) {
      historyMap[h.comicId] = h;
    }
    for (var h in cloudHistory) {
      if (historyMap.containsKey(h.comicId)) {
        if (h.updatedAt.isAfter(historyMap[h.comicId]!.updatedAt)) {
          historyMap[h.comicId] = h;
        }
      } else {
        historyMap[h.comicId] = h;
      }
    }

    final merged = historyMap.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    // Đồng bộ ngược lại Local DB nếu đã đăng nhập để có dữ liệu offline mới nhất
    if (userId != null && merged.isNotEmpty) {
      for (var h in merged) {
        await DatabaseHelper.instance.saveHistory(h);
      }
    }

    return merged;
  }

  Future<void> _handleDeepClear() async {
    // Hiển thị trạng thái đang xử lý
    if (mounted) setState(() => _isLoading = true);

    final userId = FirebaseAuth.instance.currentUser?.uid;

    try {
      // 1. Xoá lịch sử Local
      await DatabaseHelper.instance.clearHistory('guest');
      if (userId != null) {
        await DatabaseHelper.instance.clearHistory(userId);
      }

      // 2. Xoá lịch sử Cloud trên Firestore
      if (userId != null) {
        await HistoryService.instance.clearAllHistory();
      }

      // 3. Cập nhật UI
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

            final comic = _comics.firstWhere(
              (c) => c.id == item.comicId,
              orElse: () => CloudComic(
                id: item.comicId,
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

            if (comic.coverFileId.isEmpty) return const SizedBox.shrink();

            final date =
                "${item.updatedAt.day}/${item.updatedAt.month} ${item.updatedAt.hour}:${item.updatedAt.minute.toString().padLeft(2, '0')}";

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
                    fileId: comic.coverFileId,
                    width: 60,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
                ),
                title: Text(
                  comic.title,
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
                  await context.push('/reader/${item.chapterId}');
                  _initData();
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
