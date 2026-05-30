import 'package:flutter/material.dart';
import '../../../data/models_cloud.dart';
import '../../../data/drive_service.dart';

class MangaPickerSheet extends StatefulWidget {
  const MangaPickerSheet({super.key});

  @override
  State<MangaPickerSheet> createState() => _MangaPickerSheetState();
}

class _MangaPickerSheetState extends State<MangaPickerSheet> {
  late Future<List<CloudManga>> _mangasFuture;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _mangasFuture = DriveService.instance.getMangas();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: FutureBuilder<List<CloudManga>>(
            future: _mangasFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Lỗi: ${snapshot.error}'));
              }

              final allMangas = snapshot.data ?? [];
              final filteredMangas = allMangas.where((m) {
                final q = _searchQuery.trim().toLowerCase();
                return m.title.toLowerCase().contains(q) ||
                    m.author.toLowerCase().contains(q);
              }).toList();

              return Column(
                children: [
                  const SizedBox(height: 16),
                  const Text(
                    'Chọn truyện chia sẻ',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Tìm kiếm tên truyện hoặc tác giả...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                  ),
                  if (allMangas.isEmpty)
                    const Expanded(
                      child: Center(child: Text('Không có truyện nào')),
                    )
                  else if (filteredMangas.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text('Không tìm thấy truyện phù hợp'),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: filteredMangas.length,
                        itemBuilder: (context, index) {
                          final manga = filteredMangas[index];
                          final coverUrl = DriveService.instance
                              .getThumbnailLink(manga.coverFileId);
                          return ListTile(
                            leading: Image.network(
                              coverUrl,
                              width: 50,
                              height: 50,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.error),
                            ),
                            title: Text(manga.title),
                            subtitle: Text(manga.author),
                            onTap: () {
                              Navigator.of(context).pop(manga);
                            },
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
