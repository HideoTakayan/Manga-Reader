import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../services/novel_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Tab Truyện Chữ — hiển thị danh sách EPUB đã nhập từ máy
// ─────────────────────────────────────────────────────────────────────────────
class NovelListTab extends StatefulWidget {
  const NovelListTab({super.key});

  @override
  State<NovelListTab> createState() => _NovelListTabState();
}

class _NovelListTabState extends State<NovelListTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // Giữ state khi switch tab

  List<LocalNovel> _novels = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final novels = await NovelService.instance.getAll();
    if (mounted) {
      setState(() {
        _novels = novels;
        _isLoading = false;
      });
    }
  }

  Future<void> _remove(LocalNovel novel) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text(
          'Xóa khỏi thư viện?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '"${novel.title}"\n(File gốc trên máy sẽ không bị xóa)',
          style: const TextStyle(color: Colors.white60),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await NovelService.instance.remove(novel.path);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.blueAccent),
      );
    }

    if (_novels.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.menu_book_rounded,
              size: 80,
              color: Colors.white.withValues(alpha: 0.08),
            ),
            const SizedBox(height: 16),
            const Text(
              'Chưa có truyện chữ nào',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Dùng menu ⋮ → "Nhập truyện chữ (EPUB)"\nđể thêm truyện từ máy',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white30,
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: Colors.blueAccent,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _novels.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final novel = _novels[index];
          final isMissingLegacy = novel.path.startsWith('MISSING_FILE_Legacy|');
          final exists = isMissingLegacy
              ? false
              : File(novel.path).existsSync();
          return _NovelTile(
            novel: novel,
            fileExists: exists,
            isMissingLegacy: isMissingLegacy,
            onTap: () {
              if (isMissingLegacy) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Sách "${novel.title}" ở bản cũ không còn tồn tại trên máy.',
                    ),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }
              if (!exists) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Không tìm thấy file "${novel.title}"'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              context.push('/novel-reader', extra: novel);
            },
            onLongPress: () => _remove(novel),
          );
        },
      ),
    );
  }
}

class _NovelTile extends StatelessWidget {
  final LocalNovel novel;
  final bool fileExists;
  final bool isMissingLegacy;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _NovelTile({
    required this.novel,
    required this.fileExists,
    this.isMissingLegacy = false,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isMissingLegacy
                  ? Colors.redAccent.withValues(alpha: 0.5)
                  : (fileExists
                        ? Colors.white12
                        : Colors.orange.withValues(alpha: 0.5)),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                // Icon bìa sách
                Container(
                  width: 46,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isMissingLegacy
                          ? [Colors.red[900]!, Colors.red[700]!]
                          : (fileExists
                                ? [
                                    const Color(0xFF1A3A6B),
                                    const Color(0xFF2A5D9F),
                                  ]
                                : [
                                    const Color(0xFF4A2800),
                                    const Color(0xFF7A4500),
                                  ]),
                    ),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 6,
                        offset: const Offset(2, 2),
                      ),
                    ],
                  ),
                  child:
                      novel.coverPath.isNotEmpty &&
                          File(novel.coverPath).existsSync() &&
                          !isMissingLegacy
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.file(
                            File(novel.coverPath),
                            width: 46,
                            height: 64,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Icon(
                          isMissingLegacy
                              ? Icons.error_outline
                              : (fileExists
                                    ? Icons.menu_book_rounded
                                    : Icons.broken_image_outlined),
                          color: isMissingLegacy
                              ? Colors.red[200]
                              : (fileExists
                                    ? Colors.blue[200]
                                    : Colors.orange[300]),
                          size: 26,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        novel.title,
                        style: TextStyle(
                          color: isMissingLegacy
                              ? Colors.red[300]
                              : (fileExists
                                    ? Colors.white
                                    : Colors.orange[300]),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isMissingLegacy
                            ? '❌ Sách cũ bị lỗi không mở được (Giữ lâu để xóa)'
                            : (fileExists
                                  ? 'EPUB • Giữ lâu để xóa'
                                  : '⚠️ File không còn tồn tại'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: isMissingLegacy
                      ? Colors.red.withValues(alpha: 0.4)
                      : (fileExists
                            ? Colors.white24
                            : Colors.orange.withValues(alpha: 0.4)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
