import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import '../../data/database_helper.dart';
import '../../data/models.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../shared/drive_image.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late Future<List<ReadingHistory>> _historyFuture;
  late Future<List<CloudComic>> _comicsFuture;

  @override
  void initState() {
    super.initState();
    _refreshHistory();
    _comicsFuture = DriveService.instance.getComics();
  }

  void _refreshHistory() {
    setState(() {
      _historyFuture = DatabaseHelper.instance.getHistory();
    });
  }

  Future<void> _clearHistory() async {
    await DatabaseHelper.instance.clearHistory();
    _refreshHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      appBar: AppBar(
        title: const Text(
          'Lịch sử đọc',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1C1C1E),
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

          return FutureBuilder<List<ReadingHistory>>(
            future: _historyFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final historyList = snapshot.data ?? [];

              if (historyList.isEmpty) {
                return const Center(
                  child: Text(
                    'Bạn chưa đọc truyện nào.',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                itemCount: historyList.length,
                itemBuilder: (context, index) {
                  final item = historyList[index];
                  // Find comic in already loaded list
                  final comicIndex = comics.indexWhere(
                    (c) => c.id == item.comicId,
                  );

                  if (comicIndex == -1) {
                    // Comic not found (maybe deleted), just skip or show placeholder logic
                    return const SizedBox.shrink();
                  }

                  final comic = comics[comicIndex];

                  final date =
                      "${item.updatedAt.day}/${item.updatedAt.month} ${item.updatedAt.hour}:${item.updatedAt.minute.toString().padLeft(2, '0')}";

                  return Card(
                    color: const Color(0xFF2C2C2E),
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
                        style: const TextStyle(
                          color: Colors.white,
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
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                            ),
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
                              Text(
                                'Đọc chương ${item.chapterId} - Trang ${item.lastPageIndex + 1}',
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
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
          );
        },
      ),
    );
  }
}
