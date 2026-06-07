import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../data/database_helper.dart';
import '../../data/content_type.dart';
import '../../data/models.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../../services/history_service.dart';
import '../../services/novel_service.dart';
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
  List<CloudManga> _mangas = [];
  List<LocalNovel> _localNovels = [];
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
      final localNovels = await NovelService.instance.getAll();
      final hList = await _fetchAndMergeHistory();
      if (mounted) {
        setState(() {
          _mangas = mangas;
          _localNovels = localNovels;
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
              orElse: () {
                if (item.mangaId.startsWith('LOCAL_NOVEL|')) {
                  final novelPath = item.mangaId.substring('LOCAL_NOVEL|'.length);
                  final localNovel = _localNovels.firstWhere(
                    (n) => n.path == novelPath,
                    orElse: () => LocalNovel(
                      path: novelPath,
                      title: item.chapterTitle ?? 'Truyện không tồn tại',
                      importedAt: DateTime.now(),
                    )
                  );
                  return CloudManga(
                    id: item.mangaId,
                    title: localNovel.title,
                    author: 'Local',
                    description: '',
                    coverFileId: localNovel.coverPath.isNotEmpty ? localNovel.coverPath : 'local_novel_placeholder',
                    genres: [],
                    status: '',
                    viewCount: 0,
                    likeCount: 0,
                    updatedAt: localNovel.importedAt,
                    contentType: MangaContentType.novel,
                  );
                }
                return CloudManga(
                  id: item.mangaId,
                  title: 'Truyện không tồn tại',
                  author: 'Không rõ tác giả',
                  description: '',
                  coverFileId: '',
                  genres: [],
                  status: '',
                  viewCount: 0,
                  likeCount: 0,
                  updatedAt: DateTime.now(),
                );
              },
            );

            // Ẩn dòng nếu không tìm thấy ảnh bìa (truyện đã bị xóa), ngoại trừ Local Novel
            if (manga.coverFileId.isEmpty && !item.mangaId.startsWith('LOCAL_NOVEL|')) {
              return const SizedBox.shrink();
            }

            final date =
                '${item.updatedAt.day}/${item.updatedAt.month} ${item.updatedAt.hour}:${item.updatedAt.minute.toString().padLeft(2, '0')}';

            return Container(
              height: 120,
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () async {
                  if (item.mangaId.startsWith('LOCAL_NOVEL|')) {
                    final novelPath = item.mangaId.substring('LOCAL_NOVEL|'.length);
                    final localNovel = _localNovels.firstWhere(
                      (n) => n.path == novelPath,
                      orElse: () => LocalNovel(
                        path: novelPath,
                        title: manga.title,
                        importedAt: DateTime.now(),
                      ),
                    );
                    await context.push('/novel-reader', extra: localNovel);
                  } else {
                    await context.push(
                      '/reader/${item.chapterId}?mangaId=${Uri.encodeComponent(item.mangaId)}',
                    );
                  }
                  _initData();
                },
                child: Row(
                  children: [
                    DriveImage(
                      fileId: manga.coverFileId,
                      width: 85,
                      height: 120,
                      fit: BoxFit.cover,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              manga.title,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.menu_book_rounded, size: 14, color: Colors.orangeAccent),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${item.chapterTitle ?? 'Chương ${item.chapterId}'} • Trang ${item.lastPageIndex + 1}',
                                    style: const TextStyle(
                                      color: Colors.orangeAccent,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.access_time_rounded, size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(
                                      date,
                                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                                    ),
                                  ],
                                ),
                                _ContentTypeBadge(type: manga.contentType),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ContentTypeBadge extends StatelessWidget {
  final MangaContentType type;
  const _ContentTypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        type.label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
      ),
    );
  }
}
