import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/content_type.dart';
import '../../data/models.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../../data/database_helper.dart';
import '../../services/follow_service.dart';
import '../catalog/catalog_cache_service.dart';
import '../shared/drive_image.dart';
import '../shared/custom_tag_widgets.dart';
import '../../services/library_status_service.dart';

enum FollowFilterStatus {
  all,
  hasNew,
  reading,
  completed,
  paused,
  unread,
}

enum FollowSortOrder {
  updated,
  recentlyRead,
  title,
}

class FollowedMangaData {
  final List<CloudManga> mangas;
  final Map<String, ReadingHistory> historyMap;
  final Map<String, LibraryStatusEntry> statusMap;

  FollowedMangaData({
    required this.mangas,
    required this.historyMap,
    required this.statusMap,
  });
}

// Trang danh sách truyện đang theo dõi.
// Dữ liệu follow lưu trong Firestore: users/{uid}/following/{mangaId}
class FollowingPage extends StatefulWidget {
  const FollowingPage({super.key});

  @override
  State<FollowingPage> createState() => _FollowingPageState();
}

class _FollowingPageState extends State<FollowingPage> {
  int _refreshKey = 0;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  MangaContentType? _selectedTypeFilter;
  FollowFilterStatus _selectedStatusFilter = FollowFilterStatus.all;
  String? _selectedCustomTag;
  FollowSortOrder _sortOrder = FollowSortOrder.updated;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    LibraryStatusService.instance.addListener(_onLibraryStatusChanged);
  }

  void _onLibraryStatusChanged() {
    if (mounted) setState(() => _refreshKey++);
  }

  @override
  void dispose() {
    LibraryStatusService.instance.removeListener(_onLibraryStatusChanged);
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _confirmUnfollow(CloudManga manga) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Bỏ theo dõi?', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        content: Text('Bạn có chắc muốn bỏ theo dõi "${manga.title}"?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Bỏ theo dõi', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FollowService.instance.unfollowManga(manga.id);
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã bỏ theo dõi "${manga.title}"'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  // Lọc từ toàn bộ catalog Drive chỉ lấy các manga user đang theo dõi kèm lịch sử đọc
  Future<FollowedMangaData> _getFollowedMangas(List<String> followedIds, String userId) async {
    List<CloudManga> allMangas = [];
    try {
      allMangas = await DriveService.instance.getMangas(
        forceRefresh: false,
      );
    } catch (e) {
      debugPrint('⚠️ Drive getMangas failed in FollowingPage: $e, falling back to cache');
      try {
        allMangas = await CatalogCacheService.instance.getCachedCatalog();
      } catch (_) {}
    }

    final mangaById = <String, CloudManga>{
      for (final manga in allMangas)
        if (followedIds.contains(manga.id)) manga.id: manga,
    };

    // Kiểm tra thêm trong local SQLite nếu còn thiếu truyện
    final missingIds = followedIds.where((id) => !mangaById.containsKey(id)).toList();
    if (missingIds.isNotEmpty) {
      try {
        final allLocal = await DatabaseHelper.instance.getAllLocalMangas();
        final localMap = {for (final m in allLocal) m.id: m};
        for (final id in missingIds) {
          final local = localMap[id];
          if (local != null) {
            mangaById[id] = CloudManga(
              id: local.id,
              title: local.title,
              coverFileId: local.coverUrl,
              author: local.author,
              description: local.description,
              genres: local.genres,
              status: 'Offline',
              updatedAt: DateTime.now(),
              chapterOrder: const [],
              contentType: local.contentType,
            );
          }
        }
      } catch (_) {}
    }

    final mangas = [
      for (final id in followedIds)
        if (mangaById[id] != null) mangaById[id]!,
    ];

    // Lấy lịch sử đọc của user để tính toán badge "Chương mới" / "Chưa đọc"
    final historyList = await DatabaseHelper.instance.getHistory(userId);
    final historyMap = {for (final h in historyList) h.mangaId: h};

    // Lấy trạng thái đọc (reading, completed, paused, v.v.)
    final statusList = await LibraryStatusService.instance.getAll();
    final statusMap = {for (final s in statusList) s.mangaId: s};

    return FollowedMangaData(mangas: mangas, historyMap: historyMap, statusMap: statusMap);
  }

  Future<void> _handleRefresh() async {
    await DriveService.instance.getMangas(forceRefresh: true);
    if (mounted) setState(() => _refreshKey++);
  }

  Future<void> _showReadingStatusSheet(CloudManga manga, LibraryStatusEntry? currentEntry) async {
    final selected = await showModalBottomSheet<MangaReadingStatus>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Trạng thái đọc: ${manga.title}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Divider(),
                ...MangaReadingStatus.values.map((status) {
                  final isSelected = currentEntry?.status == status;
                  final (label, icon, color) = LibraryStatusService.getStatusDisplay(status);
                  return ListTile(
                    leading: Icon(icon, color: color),
                    title: Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? color : Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected ? Icon(Icons.check, color: color) : null,
                    onTap: () => Navigator.pop(ctx, status),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null) {
      await LibraryStatusService.instance.setStatus(manga.id, selected);
      if (mounted) {
        setState(() => _refreshKey++);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã cập nhật trạng thái: ${_statusLabel(selected)}'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _statusLabel(MangaReadingStatus status) {
    return LibraryStatusService.getStatusDisplay(status).$1;
  }

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inDays > 30) {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } else if (diff.inDays > 0) {
      return '${diff.inDays} ngày trước';
    } else if (diff.inHours > 0) {
      return '${diff.inHours} giờ trước';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes} phút trước';
    } else {
      return 'Vừa xong';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.redAccent.withValues(alpha: 0.12),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.favorite_border_rounded,
                    size: 54,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Theo dõi truyện yêu thích',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Đăng nhập để lưu danh sách theo dõi, đồng bộ tiến độ đọc và nhận thông báo chương mới.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white60,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => context.push('/login'),
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text(
                    'Đăng nhập ngay',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final followingRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('following');

    return StreamBuilder<QuerySnapshot>(
      stream: followingRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.redAccent.withValues(alpha: 0.12),
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.25),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.cloud_off_rounded,
                      size: 44,
                      color: Colors.redAccent,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Lỗi kết nối máy chủ',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${snapshot.error}',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ],
              ),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: Stack(
              children: [
                Align(
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.favorite_border_rounded,
                        size: 72,
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Chưa theo dõi truyện nào',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Nhấn vào biểu tượng trái tim ở trang chi tiết\nđể nhận thông báo và theo dõi truyện yêu thích',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white38,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 48),
                        child: ElevatedButton.icon(
                          onPressed: () => context.go('/search-global'),
                          icon: const Icon(Icons.explore_rounded, size: 18),
                          label: const Text('Khám phá truyện', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orangeAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final followedIds = docs.map((d) => d.id).toList();

        return FutureBuilder<FollowedMangaData>(
          key: ValueKey(_refreshKey),
          future: _getFollowedMangas(followedIds, user.uid),
          builder: (context, mangaSnapshot) {
            if (mangaSnapshot.connectionState == ConnectionState.waiting &&
                !mangaSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            if (mangaSnapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.redAccent.withValues(alpha: 0.12),
                          border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.25),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.cloud_off_rounded,
                          size: 44,
                          color: Colors.redAccent,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Không thể tải dữ liệu truyện',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${mangaSnapshot.error}',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Colors.white54),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _handleRefresh,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Thử lại'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final data = mangaSnapshot.data;
            final mangas = data?.mangas ?? [];
            final historyMap = data?.historyMap ?? {};
            final statusMap = data?.statusMap ?? {};

            if (mangas.isEmpty &&
                mangaSnapshot.connectionState == ConnectionState.done) {
              return RefreshIndicator(
                onRefresh: _handleRefresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 120),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.05),
                            ),
                            child: Icon(
                              Icons.auto_stories_outlined,
                              size: 48,
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Không tìm thấy dữ liệu truyện theo dõi',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            // Thu thập tất cả Custom Tags đang có của các truyện
            final allCustomTags = <String>{};
            for (final m in mangas) {
              final entry = statusMap[m.id];
              if (entry != null && entry.tags.isNotEmpty) {
                allCustomTags.addAll(entry.tags);
              }
            }

            // Tính toán thống kê theo trạng thái
            int hasNewCount = 0;
            int unreadCount = 0;
            int readingCount = 0;
            int completedCount = 0;
            int pausedCount = 0;

            for (final m in mangas) {
              final hist = historyMap[m.id];
              final status = statusMap[m.id]?.status;

              if (hist == null &&
                  status != MangaReadingStatus.completed &&
                  status != MangaReadingStatus.reading) {
                unreadCount++;
              } else if (hist != null &&
                  m.updatedAt.isAfter(hist.updatedAt.add(const Duration(minutes: 5)))) {
                hasNewCount++;
              }

              if (status == MangaReadingStatus.completed) {
                completedCount++;
              } else if (status == MangaReadingStatus.paused ||
                  status == MangaReadingStatus.planToRead ||
                  status == MangaReadingStatus.dropped) {
                pausedCount++;
              } else if (status == MangaReadingStatus.reading || (status == null && hist != null)) {
                readingCount++;
              }
            }

            final query = CatalogCacheService.instance.normalize(_searchQuery);
            final filteredMangas = mangas.where((m) {
              // Lọc theo ContentType
              if (_selectedTypeFilter != null && m.contentType != _selectedTypeFilter) {
                return false;
              }

              // Lọc theo Custom Tag
              if (_selectedCustomTag != null) {
                final tags = statusMap[m.id]?.tags ?? [];
                if (!tags.contains(_selectedCustomTag)) return false;
              }

              final hist = historyMap[m.id];
              final isUnread = hist == null;
              final hasNew = hist != null &&
                  m.updatedAt.isAfter(hist.updatedAt.add(const Duration(minutes: 5)));
              final status = statusMap[m.id]?.status;

              if (_selectedStatusFilter == FollowFilterStatus.hasNew && !hasNew) {
                return false;
              }
              if (_selectedStatusFilter == FollowFilterStatus.unread &&
                  (!isUnread ||
                      status == MangaReadingStatus.completed ||
                      status == MangaReadingStatus.reading)) {
                return false;
              }
              if (_selectedStatusFilter == FollowFilterStatus.reading &&
                  status != MangaReadingStatus.reading &&
                  (status != null || hist == null)) {
                return false;
              }
              if (_selectedStatusFilter == FollowFilterStatus.completed &&
                  status != MangaReadingStatus.completed) {
                return false;
              }
              if (_selectedStatusFilter == FollowFilterStatus.paused &&
                  status != MangaReadingStatus.paused &&
                  status != MangaReadingStatus.planToRead &&
                  status != MangaReadingStatus.dropped) {
                return false;
              }

              if (query.isEmpty) return true;
              final normTitle = CatalogCacheService.instance.normalize(m.title);
              final normAuthor = CatalogCacheService.instance.normalize(m.author);
              final normGenres = CatalogCacheService.instance.normalize(m.genres.join(' '));
              return normTitle.contains(query) ||
                  normAuthor.contains(query) ||
                  normGenres.contains(query);
            }).toList();

            // Sắp xếp danh sách
            switch (_sortOrder) {
              case FollowSortOrder.updated:
                filteredMangas.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
                break;
              case FollowSortOrder.recentlyRead:
                filteredMangas.sort((a, b) {
                  final aDate = historyMap[a.id]?.updatedAt ?? DateTime(2000);
                  final bDate = historyMap[b.id]?.updatedAt ?? DateTime(2000);
                  return bDate.compareTo(aDate);
                });
                break;
              case FollowSortOrder.title:
                filteredMangas.sort(
                  (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
                );
                break;
            }

            return Scaffold(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              body: Column(
              children: [
                // Thanh tìm kiếm + Nút sắp xếp
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 38,
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(19),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: TextField(
                            controller: _searchController,
                            style: const TextStyle(fontSize: 13, color: Colors.white),
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              hintText: 'Tìm theo tên truyện, tác giả hoặc thể loại...',
                              hintStyle: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12.5,
                              ),
                              prefixIcon: const Icon(
                                Icons.search,
                                size: 16,
                                color: Colors.white54,
                              ),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(
                                        Icons.clear,
                                        size: 14,
                                        color: Colors.white54,
                                      ),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            onChanged: (val) {
                              if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
                              _searchDebounce = Timer(const Duration(milliseconds: 200), () {
                                if (mounted) setState(() => _searchQuery = val);
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<FollowSortOrder>(
                        icon: const Icon(Icons.sort_rounded, size: 20, color: Colors.orangeAccent),
                        tooltip: 'Sắp xếp danh sách',
                        initialValue: _sortOrder,
                        color: Theme.of(context).cardColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        onSelected: (val) {
                          setState(() => _sortOrder = val);
                        },
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                            value: FollowSortOrder.updated,
                            child: Row(
                              children: [
                                Icon(Icons.update_rounded, size: 16, color: Colors.orangeAccent),
                                SizedBox(width: 8),
                                Text('Mới cập nhật'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: FollowSortOrder.recentlyRead,
                            child: Row(
                              children: [
                                Icon(Icons.history_rounded, size: 16, color: Colors.cyanAccent),
                                SizedBox(width: 8),
                                Text('Đọc gần đây nhất'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: FollowSortOrder.title,
                            child: Row(
                              children: [
                                Icon(Icons.sort_by_alpha_rounded, size: 16, color: Colors.tealAccent),
                                SizedBox(width: 8),
                                Text('Tên A-Z'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Thanh Filter cuộn ngang thông minh và ngăn nắp
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      _buildFilterChip(
                        label: 'Tất cả (${mangas.length})',
                        isSelected: _selectedStatusFilter == FollowFilterStatus.all &&
                            _selectedTypeFilter == null &&
                            _selectedCustomTag == null,
                        onTap: () => setState(() {
                          _selectedStatusFilter = FollowFilterStatus.all;
                          _selectedTypeFilter = null;
                          _selectedCustomTag = null;
                        }),
                      ),
                      const SizedBox(width: 6),
                      _buildFilterChip(
                        label: '🔥 Có mới ($hasNewCount)',
                        isSelected: _selectedStatusFilter == FollowFilterStatus.hasNew,
                        highlightColor: Colors.deepOrangeAccent,
                        onTap: () => setState(() {
                          _selectedStatusFilter = _selectedStatusFilter == FollowFilterStatus.hasNew
                              ? FollowFilterStatus.all
                              : FollowFilterStatus.hasNew;
                        }),
                      ),
                      const SizedBox(width: 6),
                      _buildFilterChip(
                        label: '📖 Đang đọc ($readingCount)',
                        isSelected: _selectedStatusFilter == FollowFilterStatus.reading,
                        highlightColor: Colors.greenAccent,
                        onTap: () => setState(() {
                          _selectedStatusFilter = _selectedStatusFilter == FollowFilterStatus.reading
                              ? FollowFilterStatus.all
                              : FollowFilterStatus.reading;
                        }),
                      ),
                      const SizedBox(width: 6),
                      _buildFilterChip(
                        label: '✅ Đã xong ($completedCount)',
                        isSelected: _selectedStatusFilter == FollowFilterStatus.completed,
                        highlightColor: Colors.blueAccent,
                        onTap: () => setState(() {
                          _selectedStatusFilter = _selectedStatusFilter == FollowFilterStatus.completed
                              ? FollowFilterStatus.all
                              : FollowFilterStatus.completed;
                        }),
                      ),
                      const SizedBox(width: 6),
                      _buildFilterChip(
                        label: '⏸️ Tạm dừng ($pausedCount)',
                        isSelected: _selectedStatusFilter == FollowFilterStatus.paused,
                        highlightColor: Colors.amberAccent,
                        onTap: () => setState(() {
                          _selectedStatusFilter = _selectedStatusFilter == FollowFilterStatus.paused
                              ? FollowFilterStatus.all
                              : FollowFilterStatus.paused;
                        }),
                      ),
                      const SizedBox(width: 6),
                      _buildFilterChip(
                        label: '⭐ Chưa đọc ($unreadCount)',
                        isSelected: _selectedStatusFilter == FollowFilterStatus.unread,
                        highlightColor: Colors.purpleAccent,
                        onTap: () => setState(() {
                          _selectedStatusFilter = _selectedStatusFilter == FollowFilterStatus.unread
                              ? FollowFilterStatus.all
                              : FollowFilterStatus.unread;
                        }),
                      ),
                      const SizedBox(width: 6),
                      Container(height: 16, width: 1, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 2)),
                      const SizedBox(width: 6),
                      _buildFilterChip(
                        label: 'Truyện tranh',
                        isSelected: _selectedTypeFilter == MangaContentType.manga,
                        highlightColor: Colors.blueAccent,
                        onTap: () => setState(() => _selectedTypeFilter =
                            _selectedTypeFilter == MangaContentType.manga ? null : MangaContentType.manga),
                      ),
                      const SizedBox(width: 6),
                      _buildFilterChip(
                        label: 'Tiểu thuyết',
                        isSelected: _selectedTypeFilter == MangaContentType.novel,
                        highlightColor: Colors.purpleAccent,
                        onTap: () => setState(() => _selectedTypeFilter =
                            _selectedTypeFilter == MangaContentType.novel ? null : MangaContentType.novel),
                      ),

                      // Filter theo Custom Tags của user
                      if (allCustomTags.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(height: 16, width: 1, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 2)),
                        const SizedBox(width: 6),
                        ...allCustomTags.map((tag) {
                          final isSelected = _selectedCustomTag == tag;
                          final tagColor = CustomTagHelper.getColorForTag(tag);
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _buildFilterChip(
                              label: '🏷️ $tag',
                              isSelected: isSelected,
                              highlightColor: tagColor,
                              onTap: () => setState(() => _selectedCustomTag = isSelected ? null : tag),
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),

                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _handleRefresh,
                    child: filteredMangas.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: const [
                              SizedBox(height: 120),
                              Center(
                                child: Text(
                                  'Không tìm thấy truyện phù hợp',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            itemCount: filteredMangas.length,
                            itemBuilder: (context, index) {
                              final manga = filteredMangas[index];
                              final hist = historyMap[manga.id];
                              final isUnread = hist == null;
                              final hasNew = hist != null &&
                                  manga.updatedAt.isAfter(hist.updatedAt.add(const Duration(minutes: 5)));
                              final currentEntry = statusMap[manga.id];
                              final timeAgo = _formatTimeAgo(manga.updatedAt);

                              return Container(
                                height: 132,
                                margin: const EdgeInsets.symmetric(
                                  vertical: 5,
                                  horizontal: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: hasNew
                                        ? Colors.deepOrangeAccent.withValues(alpha: 0.35)
                                        : Colors.white.withValues(alpha: 0.06),
                                    width: hasNew ? 1.2 : 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: hasNew
                                          ? Colors.deepOrangeAccent.withValues(alpha: 0.12)
                                          : Colors.black.withValues(alpha: 0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () => context.push('/detail/${manga.id}'),
                                  child: Row(
                                    children: [
                                      // Cover Image with Badges
                                      Stack(
                                        children: [
                                          manga.coverFileId.isNotEmpty
                                              ? DriveImage(
                                                  fileId: manga.coverFileId,
                                                  width: 90,
                                                  height: 132,
                                                  fit: BoxFit.cover,
                                                )
                                              : Container(
                                                  width: 90,
                                                  height: 132,
                                                  decoration: BoxDecoration(
                                                    color: Colors.blueGrey.withValues(alpha: 0.2),
                                                  ),
                                                  child: const Center(
                                                    child: Icon(
                                                      Icons.menu_book_rounded,
                                                      size: 36,
                                                      color: Colors.white38,
                                                    ),
                                                  ),
                                                ),

                                          // New Chapter Badge Overlay
                                          if (hasNew)
                                            Positioned(
                                              top: 6,
                                              left: 6,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  gradient: const LinearGradient(
                                                    colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)],
                                                  ),
                                                  borderRadius: BorderRadius.circular(6),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.redAccent.withValues(alpha: 0.5),
                                                      blurRadius: 6,
                                                      offset: const Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.bolt_rounded, color: Colors.white, size: 10),
                                                    SizedBox(width: 2),
                                                    Text(
                                                      'MỚI',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.w900,
                                                        letterSpacing: 0.5,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            )
                                          else if (isUnread &&
                                              (currentEntry == null ||
                                                  currentEntry.status == MangaReadingStatus.planToRead))
                                            Positioned(
                                              top: 6,
                                              left: 6,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.purple.withValues(alpha: 0.85),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Text(
                                                  'CHƯA ĐỌC',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 8.5,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),

                                          // Content Type Badge (Bottom-left of cover)
                                          Positioned(
                                            bottom: 6,
                                            left: 6,
                                            child: _ContentTypeBadge(type: manga.contentType),
                                          ),
                                        ],
                                      ),

                                      // Manga Information & Tags Layout
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // Title & Actions Menu
                                              Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      manga.title,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 14,
                                                        height: 1.25,
                                                      ),
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  PopupMenuButton<String>(
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(),
                                                    color: Theme.of(context).cardColor,
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                    icon: const Icon(Icons.more_vert, size: 18, color: Colors.white38),
                                                    onSelected: (val) async {
                                                      if (val == 'detail') {
                                                        context.push('/detail/${manga.id}');
                                                      } else if (val == 'status') {
                                                        _showReadingStatusSheet(manga, currentEntry);
                                                      } else if (val == 'tags') {
                                                        final updated = await CustomTagManagerDialog.show(
                                                          context,
                                                          mangaId: manga.id,
                                                          currentTags: currentEntry?.tags ?? [],
                                                        );
                                                        if (updated != null && mounted) {
                                                          setState(() => _refreshKey++);
                                                        }
                                                      } else if (val == 'unfollow') {
                                                        _confirmUnfollow(manga);
                                                      }
                                                    },
                                                    itemBuilder: (ctx) => [
                                                      const PopupMenuItem(
                                                        value: 'detail',
                                                        child: Row(
                                                          children: [
                                                            Icon(Icons.info_outline, size: 18),
                                                            SizedBox(width: 10),
                                                            Text('Xem chi tiết'),
                                                          ],
                                                        ),
                                                      ),
                                                      const PopupMenuItem(
                                                        value: 'status',
                                                        child: Row(
                                                          children: [
                                                            Icon(Icons.bookmark_border_rounded, size: 18, color: Colors.greenAccent),
                                                            SizedBox(width: 10),
                                                            Text('Đổi trạng thái đọc'),
                                                          ],
                                                        ),
                                                      ),
                                                      const PopupMenuItem(
                                                        value: 'tags',
                                                        child: Row(
                                                          children: [
                                                            Icon(Icons.sell_outlined, size: 18, color: Colors.purpleAccent),
                                                            SizedBox(width: 10),
                                                            Text('Quản lý nhãn (Tags)'),
                                                          ],
                                                        ),
                                                      ),
                                                      const PopupMenuItem(
                                                        value: 'unfollow',
                                                        child: Row(
                                                          children: [
                                                            Icon(Icons.heart_broken_outlined, size: 18, color: Colors.redAccent),
                                                            SizedBox(width: 10),
                                                            Text('Bỏ theo dõi', style: TextStyle(color: Colors.redAccent)),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),

                                              // Reading Progress & Updated Time
                                              Builder(
                                                builder: (context) {
                                                  IconData progressIcon;
                                                  Color progressColor;
                                                  String progressText;

                                                  if (hist != null) {
                                                    progressIcon = Icons.history_rounded;
                                                    progressColor = hasNew ? Colors.deepOrangeAccent : Colors.white54;
                                                    progressText = (hist.chapterTitle != null && hist.chapterTitle!.isNotEmpty)
                                                        ? 'Đã đọc: ${hist.chapterTitle}'
                                                        : 'Đã đọc chương ${hist.chapterId}';
                                                  } else {
                                                    if (currentEntry?.status == MangaReadingStatus.completed) {
                                                      progressIcon = Icons.check_circle_outline_rounded;
                                                      progressColor = Colors.blueAccent;
                                                      progressText = 'Đã hoàn thành toàn bộ';
                                                    } else if (currentEntry?.status == MangaReadingStatus.reading) {
                                                      progressIcon = Icons.menu_book_rounded;
                                                      progressColor = Colors.greenAccent;
                                                      progressText = 'Đang theo dõi đọc';
                                                    } else if (currentEntry?.status == MangaReadingStatus.paused) {
                                                      progressIcon = Icons.pause_circle_outline_rounded;
                                                      progressColor = Colors.amberAccent;
                                                      progressText = 'Tạm dừng đọc';
                                                    } else if (currentEntry?.status == MangaReadingStatus.dropped) {
                                                      progressIcon = Icons.cancel_outlined;
                                                      progressColor = Colors.redAccent;
                                                      progressText = 'Bỏ dở';
                                                    } else {
                                                      progressIcon = Icons.auto_stories_outlined;
                                                      progressColor = Colors.white54;
                                                      progressText = 'Chưa bắt đầu đọc';
                                                    }
                                                  }

                                                  return Row(
                                                    children: [
                                                      Icon(progressIcon, size: 12.5, color: hasNew ? Colors.deepOrangeAccent : progressColor),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          progressText,
                                                          style: TextStyle(
                                                            color: hasNew ? Colors.deepOrangeAccent : (hist != null ? Colors.white70 : progressColor),
                                                            fontSize: 11,
                                                            fontWeight: (hasNew || currentEntry?.status == MangaReadingStatus.completed) ? FontWeight.w600 : FontWeight.normal,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      Text(
                                                        timeAgo,
                                                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                                                      ),
                                                    ],
                                                  );
                                                },
                                              ),

                                              const Spacer(),

                                              // Tags & Status Row
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Wrap(
                                                      spacing: 4,
                                                      runSpacing: 2,
                                                      children: [
                                                        // Reading Status Chip
                                                        if (currentEntry != null)
                                                          Builder(
                                                            builder: (context) {
                                                              final (label, _, color) = LibraryStatusService.getStatusDisplay(currentEntry.status);
                                                              return Container(
                                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                                decoration: BoxDecoration(
                                                                  color: color.withValues(alpha: 0.15),
                                                                  borderRadius: BorderRadius.circular(5),
                                                                  border: Border.all(
                                                                    color: color.withValues(alpha: 0.4),
                                                                    width: 0.8,
                                                                  ),
                                                                ),
                                                                child: Text(
                                                                  label,
                                                                  style: TextStyle(
                                                                    fontSize: 9.5,
                                                                    fontWeight: FontWeight.bold,
                                                                    color: color,
                                                                  ),
                                                                ),
                                                              );
                                                            },
                                                          ),

                                                        // Custom Tags (Take top 2)
                                                        if (currentEntry != null && currentEntry.tags.isNotEmpty)
                                                          ...currentEntry.tags.take(2).map((t) => CustomTagBadge(
                                                            tag: t,
                                                            isSmall: true,
                                                            onTap: () async {
                                                              final updated = await CustomTagManagerDialog.show(
                                                                context,
                                                                mangaId: manga.id,
                                                                currentTags: currentEntry.tags,
                                                              );
                                                              if (updated != null && mounted) {
                                                                setState(() => _refreshKey++);
                                                              }
                                                            },
                                                          )),

                                                        // Genre Chip (First genre)
                                                        if (manga.genres.isNotEmpty)
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                            decoration: BoxDecoration(
                                                              color: Colors.white.withValues(alpha: 0.06),
                                                              borderRadius: BorderRadius.circular(5),
                                                              border: Border.all(color: Colors.white12, width: 0.8),
                                                            ),
                                                            child: Text(
                                                              manga.genres.first,
                                                              style: const TextStyle(
                                                                fontSize: 9.5,
                                                                color: Colors.white60,
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),

                                                  // Quick Action Button
                                                  InkWell(
                                                    onTap: () => context.push('/detail/${manga.id}'),
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                                      decoration: BoxDecoration(
                                                        color: hasNew
                                                            ? Colors.deepOrangeAccent.withValues(alpha: 0.2)
                                                            : Colors.orangeAccent.withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(8),
                                                        border: Border.all(
                                                          color: hasNew
                                                              ? Colors.deepOrangeAccent.withValues(alpha: 0.5)
                                                              : Colors.orangeAccent.withValues(alpha: 0.4),
                                                          width: 0.9,
                                                        ),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Text(
                                                            hasNew ? 'Đọc ngay' : 'Đọc tiếp',
                                                            style: TextStyle(
                                                              color: hasNew
                                                                  ? Colors.deepOrangeAccent
                                                                  : Colors.orangeAccent,
                                                              fontSize: 10.5,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                          const SizedBox(width: 2),
                                                          Icon(
                                                            Icons.arrow_forward_ios_rounded,
                                                            color: hasNew
                                                                ? Colors.deepOrangeAccent
                                                                : Colors.orangeAccent,
                                                            size: 9,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
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
                ),
              ],
            ),
          );
          },
        );
      },
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    Color? highlightColor,
    required VoidCallback onTap,
  }) {
    final activeColor = highlightColor ?? Colors.orangeAccent;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.2) : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? activeColor : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 1.2 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? (highlightColor ?? Colors.white) : Colors.white70,
          ),
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
    final isNovel = type == MangaContentType.novel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: isNovel
            ? Colors.purple.withValues(alpha: 0.85)
            : Colors.blue.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type.label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}
