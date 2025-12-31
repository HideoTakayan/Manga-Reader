import 'package:flutter/material.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../shared/drive_image.dart';
import 'package:go_router/go_router.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String query = '';
  List<CloudComic> allComics = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadComics();
  }

  Future<void> _loadComics() async {
    final comics = await DriveService.instance.getComics();
    if (mounted) {
      setState(() {
        allComics = comics;
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1E),
        title: TextField(
          autofocus: true,
          onChanged: (val) => setState(() => query = val),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Tìm truyện...',
            hintStyle: TextStyle(color: Colors.white70),
            border: InputBorder.none,
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Builder(
              builder: (context) {
                final comics = allComics.where((c) {
                  final q = query.toLowerCase();
                  return c.title.toLowerCase().contains(q) ||
                      c.author.toLowerCase().contains(q);
                }).toList();

                if (comics.isEmpty) {
                  return const Center(
                    child: Text(
                      'Không tìm thấy truyện nào',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: comics.length,
                  itemBuilder: (context, i) {
                    final comic = comics[i];
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: DriveImage(
                          fileId: comic.coverFileId,
                          width: 50,
                          height: 70,
                          fit: BoxFit.cover,
                        ),
                      ),
                      title: Text(
                        comic.title,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        comic.author,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      onTap: () => context.push('/detail/${comic.id}'),
                    );
                  },
                );
              },
            ),
    );
  }
}
