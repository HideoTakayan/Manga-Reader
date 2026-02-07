import 'package:flutter/material.dart';
import '../../services/library_service.dart';

class LibraryDialogs {
  static Future<bool?> showSetCategoryDialog(
    BuildContext context,
    List<String> mangaIds,
    List<String> currentSelected,
  ) {
    List<String> tempSelected = List.from(currentSelected);

    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StreamBuilder<List<String>>(
          stream: LibraryService.instance.streamCategories(),
          builder: (context, snapshot) {
            final categories = snapshot.data ?? ['Mặc định'];

            return StatefulBuilder(
              builder: (context, setDialogState) {
                return AlertDialog(
                  backgroundColor: const Color(0xFF212121),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: const Text(
                    'Đặt danh mục',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  content: SizedBox(
                    width: double.maxFinite,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: categories.length,
                            itemBuilder: (context, index) {
                              final cat = categories[index];
                              final isChecked = tempSelected.contains(cat);
                              return CheckboxListTile(
                                title: Text(
                                  cat,
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                value: isChecked,
                                activeColor: Colors.redAccent,
                                checkColor: Colors.white,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                onChanged: (val) {
                                  setDialogState(() {
                                    if (val == true) {
                                      tempSelected.add(cat);
                                    } else {
                                      tempSelected.remove(cat);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'Hủy',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        for (final id in mangaIds) {
                          await LibraryService.instance.setMangaCategories(
                            id,
                            tempSelected,
                          );
                        }
                        if (context.mounted) Navigator.pop(ctx, true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Lưu'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
