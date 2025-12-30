import 'package:flutter/material.dart';
import '../../data/mock_catalog.dart';
import '../../data/models.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final comics = MockCatalog.comics()
        .where((c) =>
            c.title.toLowerCase().contains(query.toLowerCase()) ||
            c.author.toLowerCase().contains(query.toLowerCase()))
        .toList();

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
      body: comics.isEmpty
          ? const Center(
              child: Text('Không tìm thấy truyện nào',
                  style: TextStyle(color: Colors.white70)))
          : ListView.builder(
              itemCount: comics.length,
              itemBuilder: (context, i) {
                final comic = comics[i];
                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: comic.coverUrl,
                      width: 50,
                      height: 70,
                      fit: BoxFit.cover,
                    ),
                  ),
                  title: Text(comic.title,
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text(comic.author,
                      style: const TextStyle(color: Colors.white70)),
                  onTap: () => context.push('/detail/${comic.id}'),
                );
              },
            ),
    );
  }
}
