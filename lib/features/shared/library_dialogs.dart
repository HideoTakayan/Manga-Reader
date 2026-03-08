import 'package:flutter/material.dart';
import '../../services/library_service.dart';

// Class chứa các dialog dùng chung liên quan đến thư viện cá nhân.
// Tách ra file riêng để nhiều màn hình cùng dùng mà không bị lặp code.
class LibraryDialogs {
  // Hiện dialog chọn danh mục cho một hoặc nhiều bộ truyện cùng lúc.
  // Trả về true nếu người dùng bấm "Lưu", null nếu bấm "Hủy" hoặc đóng dialog.
  //
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
                              // Mỗi danh mục là một CheckboxListTile
                              // tick → thêm vào tempSelected, bỏ tick → xóa khỏi tempSelected
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
                        // Ghi danh mục mới vào SQLite cho từng truyện trong batch
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
