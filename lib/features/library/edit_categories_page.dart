import 'package:flutter/material.dart';
import '../../services/library_service.dart';

// Trang quản lý danh mục thư viện: thêm, sửa tên, xóa, kéo thả sắp xếp lại thứ tự.
// Mọi thay đổi ghi thẳng lên Firestore qua LibraryService — UI tự cập nhật qua Stream.
class EditCategoriesPage extends StatefulWidget {
  const EditCategoriesPage({super.key});

  @override
  State<EditCategoriesPage> createState() => _EditCategoriesPageState();
}

InputDecoration _inputDeco(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white54),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.05),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Colors.orange, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
  );
}

class _EditCategoriesPageState extends State<EditCategoriesPage> {
  late Stream<List<String>> _categoriesStream;

  @override
  void initState() {
    super.initState();
    _categoriesStream = LibraryService.instance.streamCategories();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chỉnh sửa danh mục'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      // StreamBuilder: danh sách categories realtime từ Firestore
      // Mỗi khi thêm/xóa/sửa/reorder → stream phát → list tự cập nhật
      body: StreamBuilder<List<String>>(
        stream: _categoriesStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final categories = snapshot.data!;

          // ReorderableListView: kéo thả sắp xếp thứ tự danh mục
          // Cần ValueKey duy nhất cho mỗi item để Flutter track vị trí khi kéo
          return ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: categories.length,
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex -= 1;
              final items = List<String>.from(categories);
              final item = items.removeAt(oldIndex);
              items.insert(newIndex, item);
              LibraryService.instance.reorderCategories(
                items,
              ); // Ghi thứ tự mới lên Firestore
            },
            itemBuilder: (context, index) {
              final cat = categories[index];
              return _CategoryItem(
                key: ValueKey(cat),
                name: cat,
                isDefault:
                    cat == 'Mặc định', // Danh mục Mặc định không được xóa
              );
            },
          );
        },
      ),
      floatingActionButton: StreamBuilder<List<String>>(
        stream: _categoriesStream,
        builder: (context, snapshot) {
          final categories = snapshot.data ?? [];
          return FloatingActionButton.extended(
            onPressed: () => _showAddDialog(context, categories),
            label: const Text('Thêm'),
            icon: const Icon(Icons.add),
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          );
        },
      ),
    );
  }

  // Dialog thêm danh mục mới — kiểm tra tên không rỗng & không trùng
  void _showAddDialog(BuildContext context, List<String> existingCategories) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Thêm danh mục', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: StatefulBuilder(
          builder: (context, _) {
            void submit() {
              final newName = controller.text.trim();
              if (newName.isEmpty) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tên danh mục không được để trống')),
                );
                return;
              }
              if (newName.toLowerCase() == 'mặc định' ||
                  existingCategories.any(
                    (c) => c.toLowerCase() == newName.toLowerCase(),
                  )) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Danh mục "$newName" đã tồn tại')),
                );
                return;
              }
              LibraryService.instance.addCategory(newName);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Đã thêm danh mục "$newName"')),
              );
            }

            return TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => submit(),
              style: const TextStyle(color: Colors.white),
              decoration: _inputDeco('Tên danh mục'),
            );
          },
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isEmpty) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tên danh mục không được để trống')),
                );
                return;
              }
              if (newName.toLowerCase() == 'mặc định' ||
                  existingCategories.any(
                    (c) => c.toLowerCase() == newName.toLowerCase(),
                  )) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Danh mục "$newName" đã tồn tại')),
                );
                return;
              }
              LibraryService.instance.addCategory(newName);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Đã thêm danh mục "$newName"')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Thêm', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }
}

// Card 1 danh mục: icon kéo thả bên trái, tên, nút sửa + xóa bên phải.
// isDefault = true → không cho xóa (danh mục "Mặc định" luôn tồn tại)
class _CategoryItem extends StatelessWidget {
  final String name;
  final bool isDefault;
  const _CategoryItem({super.key, required this.name, this.isDefault = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: const Icon(
          Icons.menu,
          color: Colors.white54,
        ), // Handle kéo thả
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white),
        ),
        trailing: isDefault
            ? const SizedBox.shrink()
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: Colors.white70),
                    onPressed: () => _showEditDialog(context),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white70),
                    onPressed: () => _showDeleteDialog(context),
                  ),
                ],
              ),
      ),
    );
  }

  // Pre-fill tên cũ vào TextField — kiểm tra tên mới không rỗng & không trùng
  void _showEditDialog(BuildContext context) {
    final controller = TextEditingController(text: name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Sửa danh mục', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: StatefulBuilder(
          builder: (context, _) {
            Future<void> submit() async {
              final newName = controller.text.trim();
              if (newName.isEmpty) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tên danh mục không được để trống')),
                );
                return;
              }
              if (newName != name) {
                final existingCategories =
                    await LibraryService.instance.getCategories();
                if (newName.toLowerCase() == 'mặc định' ||
                    existingCategories.any(
                      (c) => c.toLowerCase() == newName.toLowerCase(),
                    )) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Danh mục "$newName" đã tồn tại')),
                    );
                  }
                  return;
                }
              }
              LibraryService.instance.updateCategory(name, newName);
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Đã đổi tên danh mục thành "$newName"')),
                );
              }
            }

            return TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => submit(),
              style: const TextStyle(color: Colors.white),
              decoration: _inputDeco('Tên mới'),
            );
          },
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tên danh mục không được để trống')),
                );
                return;
              }
              if (newName != name) {
                final existingCategories =
                    await LibraryService.instance.getCategories();
                if (newName.toLowerCase() == 'mặc định' ||
                    existingCategories.any(
                      (c) => c.toLowerCase() == newName.toLowerCase(),
                    )) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Danh mục "$newName" đã tồn tại')),
                    );
                  }
                  return;
                }
              }
              LibraryService.instance.updateCategory(name, newName);
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Đã đổi tên danh mục thành "$newName"')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Lưu', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  // Xóa danh mục: tất cả truyện trong mục này bị gỡ bỏ khỏi mục (không xóa truyện)
  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Xóa danh mục?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Tất cả truyện trong mục "$name" sẽ bị gỡ bỏ khỏi mục này.',
          style: const TextStyle(color: Colors.white70),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              LibraryService.instance.removeCategory(name);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Đã xóa danh mục "$name"')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Xóa', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
