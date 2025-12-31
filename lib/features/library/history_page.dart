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
  late List<ReadingHistory> _historyList;
  late Future<List<CloudComic>> _comicsFuture;

  @override
  void initState() {
    super.initState();
    _historyList = []; // Initialize to empty list
    _refreshHistory();
    _comicsFuture = DriveService.instance.getComics();
  }

  Future<void> _refreshHistory() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    List<ReadingHistory> localHistory = [];
    List<ReadingHistory> cloudHistory = [];

    // 1. Fetch Local
    final localId = userId ?? 'guest';
    localHistory = await DatabaseHelper.instance.getHistory(localId);

    // 2. Fetch Cloud (if logged in)
    if (userId != null) {
      cloudHistory = await HistoryService.instance.getAllHistory();
    }

    // 3. Merge: Use Map to prioritize latest update
    final historyMap = <String, ReadingHistory>{};

    // Add local first
    for (var h in localHistory) {
      historyMap[h.comicId] = h;
    }

    // Add/Overwrite with Cloud (assuming cloud is source of truth or just merge)
    // Actually, we should check timestamps, but simpler to trust cloud if available?
    // Let's trust whichever is newer.
    for (var h in cloudHistory) {
      if (historyMap.containsKey(h.comicId)) {
        final local = historyMap[h.comicId]!;
        // If cloud is newer, replace
        if (h.updatedAt.isAfter(local.updatedAt)) {
          historyMap[h.comicId] = h;
        }
      } else {
        historyMap[h.comicId] = h;
      }
    }

    final mergedList = historyMap.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    setState(() {
      _historyList = mergedList;
    });
  }

  Future<void> _clearHistory() async {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    await DatabaseHelper.instance.clearHistory(userId);

    // Also clear cloud if logged in (optional, maybe ask user?)
    // For now, let's just clear local as "Clear History" usually implies device privacy
    // But if we sync, we probably want to clear all.
    // Let's clear cloud too for consistency if logged in.
    if (FirebaseAuth.instance.currentUser != null) {
      // Cloud delete requires looping or batch. HistoryService.deleteHistory is single.
      // We need a clearAll in Service or loop.
      // For safety, let's just loop over current list.
      for (var h in _historyList) {
        await HistoryService.instance.deleteHistory(h.comicId);
      }
    }

    _refreshHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Lịch sử đọc',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Xoá lịch sử?'),
                  content: const Text(
                    'Bạn có chắc muốn xoá toàn bộ lịch sử đọc không?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Huỷ'),
                    ),
                    TextButton(
                      onPressed: () {
                        _clearHistory();
                        Navigator.pop(context);
                      },
                      child: const Text(
                        'Xoá',
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
      body: FutureBuilder<List<CloudComic>>(
        future: _comicsFuture,
        builder: (context, comicsVerifySnapshot) {
          // We need comics list available to map IDs
          if (comicsVerifySnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final comics = comicsVerifySnapshot.data ?? [];

          // Use _historyList directly
          if (_historyList.isEmpty) {
            return const Center(
              child: Text(
                'Bạn chưa đọc truyện nào.',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: _historyList.length,
            itemBuilder: (context, index) {
              final item = _historyList[index];
              // Find comic in already loaded list
              final comicIndex = comics.indexWhere((c) => c.id == item.comicId);

              if (comicIndex == -1) {
                // Comic not found (maybe deleted), just skip or show placeholder logic
                return const SizedBox.shrink();
              }

              final comic = comics[comicIndex];

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
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        'Tác giả: ${comic.author}',
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.history,
                            size: 14,
                            color: Colors.redAccent.withOpacity(0.8),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${item.chapterTitle ?? 'Chương ${item.chapterId}'} - Trang ${item.lastPageIndex + 1}',
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            date,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.white,
                  ),
                  onTap: () async {
                    await context.push('/reader/${item.chapterId}');
                    _refreshHistory();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
