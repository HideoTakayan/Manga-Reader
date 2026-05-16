import 'package:flutter/material.dart';
import '../../services/library_service.dart';

// Trang quản lý danh mục thư viện: thêm, sửa tên, xóa, kéo thả sắp xếp lại thứ tự.
// Mọi thay đổi ghi thẳng lên Firestore qua LibraryService — UI tự cập nhật qua Stream.
class EditCategoriesPage extends StatefulWidget {
  const EditCategoriesPage({super.key});

  @override
  State<EditCategoriesPage> createState() => _EditCategoriesPageState();
}

class _EditCategoriesPageState extends State<EditCategoriesPage> {
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
        stream: LibraryService.instance.streamCategories(),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context),
        label: const Text('Thêm'),
        icon: const Icon(Icons.add),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
    );
  }

  // Dialog thêm danh mục mới — chỉ gọi addCategory nếu tên không rỗng
  void _showAddDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm danh mục'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Tên danh mục'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                LibraryService.instance.addCategory(controller.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
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
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: const Icon(
          Icons.menu,
          color: Colors.white54,
        ), // Handle kéo thả
        title: Text(name, style: const TextStyle(color: Colors.white)),
        trailing: Row(
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

  // Pre-fill tên cũ vào TextField — chỉ gọi updateCategory nếu tên mới không rỗng
  void _showEditDialog(BuildContext context) {
    final controller = TextEditingController(text: name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sửa danh mục'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Tên mới'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                LibraryService.instance.updateCategory(name, controller.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  // Xóa danh mục: tất cả truyện trong mục này bị gỡ bỏ khỏi mục (không xóa truyện)
  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa danh mục?'),
        content: Text(
          'Tất cả truyện trong mục "$name" sẽ bị gỡ bỏ khỏi mục này.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              LibraryService.instance.removeCategory(name);
              Navigator.pop(ctx);
            },
            child: const Text('Xóa', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}
