import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../services/library_service.dart';

/// Trang quản lý và chỉnh sửa danh mục thư viện truyện.
/// Hỗ trợ thêm mới, đổi tên, xóa, kéo thả thay đổi thứ tự sắp xếp theo thời gian thực.
class EditCategoriesPage extends StatefulWidget {
  final Stream<List<String>>? categoriesStream;
  const EditCategoriesPage({super.key, this.categoriesStream});

  @override
  State<EditCategoriesPage> createState() => _EditCategoriesPageState();
}

class _EditCategoriesPageState extends State<EditCategoriesPage> {
  late final Stream<List<String>> _categoriesStream;

  @override
  void initState() {
    super.initState();
    _categoriesStream =
        widget.categoriesStream ?? LibraryService.instance.streamCategories();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return StreamBuilder<List<String>>(
      initialData: LibraryService.instance.currentCategories.isNotEmpty
          ? LibraryService.instance.currentCategories
          : null,
      stream: _categoriesStream,
      builder: (context, snapshot) {
        final categories = snapshot.data ?? [];
        final count = categories.length;

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            centerTitle: true,
            elevation: 0,
            backgroundColor: theme.scaffoldBackgroundColor,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Quay lại',
              onPressed: () {
                HapticFeedback.lightImpact();
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/my-library');
                }
              },
            ),
            title: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Quản lý danh mục',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (count > 0)
                  Text(
                    '$count danh mục',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
              ],
            ),
          ),
          body: (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData)
              ? const Center(child: CircularProgressIndicator())
              : categories.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.category_outlined,
                            size: 64,
                            color: cs.onSurface.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Chưa có danh mục nào',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () =>
                                _showAddDialog(context, categories),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Tạo danh mục mới'),
                          ),
                        ],
                      ),
                    )
                  : CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      slivers: [
                        // Banner hướng dẫn kéo thả sắp xếp
                        SliverToBoxAdapter(
                          child: Padding(
                            padding:
                                const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: cs.primary.withValues(alpha: 0.2),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.swap_vert_rounded,
                                    size: 20,
                                    color: cs.primary,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Kéo thả biểu tượng ☰ để thay đổi thứ tự tab trên Thư viện',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: cs.onSurface
                                            .withValues(alpha: 0.85),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Danh sách kéo thả Reorderable
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                          sliver: SliverReorderableList(
                            itemCount: categories.length,
                            onReorder: (oldIndex, newIndex) {
                              HapticFeedback.selectionClick();
                              if (newIndex > oldIndex) newIndex -= 1;
                              final items = List<String>.from(categories);
                              final item = items.removeAt(oldIndex);
                              items.insert(newIndex, item);
                              LibraryService.instance.reorderCategories(items);
                            },
                            proxyDecorator: (child, index, animation) {
                              return Material(
                                elevation: 8,
                                shadowColor:
                                    Colors.black.withValues(alpha: 0.4),
                                color: theme.cardColor,
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color:
                                          cs.primary.withValues(alpha: 0.6),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: child,
                                ),
                              );
                            },
                            itemBuilder: (context, index) {
                              final cat = categories[index];
                              final isDefault = cat == 'Mặc định';

                              return ReorderableDelayedDragStartListener(
                                key: ValueKey(cat),
                                index: index,
                                child: _CategoryCard(
                                  key: ValueKey('card_$cat'),
                                  name: cat,
                                  isDefault: isDefault,
                                  dragIndex: index,
                                  allCategories: categories,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'fab_edit_categories',
            elevation: 4,
            highlightElevation: 8,
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
            icon: const Icon(Icons.add_rounded),
            label: const Text(
              'Thêm danh mục',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            onPressed: () {
              HapticFeedback.mediumImpact();
              _showAddDialog(context, categories);
            },
          ),
        );
      },
    );
  }

  /// Dialog thêm danh mục mới với xác thực trực tiếp và UX trực quan
  static void _showAddDialog(BuildContext context, List<String> existing) {
    showDialog(
      context: context,
      builder: (_) => _AddCategoryDialog(existing: existing),
    );
  }
}

class _AddCategoryDialog extends StatefulWidget {
  final List<String> existing;
  const _AddCategoryDialog({required this.existing});

  @override
  State<_AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<_AddCategoryDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final newName = _controller.text.trim();
    if (newName.isEmpty) {
      setState(() => _errorText = 'Tên danh mục không được để trống');
      return;
    }
    if (newName.toLowerCase() == 'mặc định' ||
        widget.existing.any((c) => c.toLowerCase() == newName.toLowerCase())) {
      setState(() => _errorText = 'Danh mục "$newName" đã tồn tại');
      return;
    }

    HapticFeedback.lightImpact();
    LibraryService.instance.addCategory(newName);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Text('Đã thêm danh mục "$newName"'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AlertDialog(
      backgroundColor: theme.dialogTheme.backgroundColor ?? theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.create_new_folder_rounded,
              color: cs.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Thêm danh mục',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_errorText != null) {
                setState(() => _errorText = null);
              }
            },
            onSubmitted: (_) => _submit(),
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(
              hintText: 'Nhập tên danh mục...',
              hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.4)),
              errorText: _errorText,
              filled: true,
              fillColor: cs.onSurface.withValues(alpha: 0.05),
              prefixIcon: Icon(
                Icons.label_outline_rounded,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _errorText = null);
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: cs.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Hủy',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.6),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: const Text('Thêm', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

/// Card hiển thị 1 danh mục với icon, số lượng truyện, tay cầm kéo thả và các nút thao tác
class _CategoryCard extends StatelessWidget {
  final String name;
  final bool isDefault;
  final int dragIndex;
  final List<String> allCategories;

  const _CategoryCard({
    super.key,
    required this.name,
    required this.isDefault,
    required this.dragIndex,
    required this.allCategories,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.onSurface.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Handle kéo thả
            ReorderableDragStartListener(
              index: dragIndex,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.drag_indicator_rounded,
                  color: cs.onSurface.withValues(alpha: 0.45),
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Icon biểu trưng danh mục
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: (isDefault ? Colors.amber : cs.primary)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isDefault
                    ? Icons.bookmark_rounded
                    : Icons.folder_rounded,
                color: isDefault ? Colors.amber : cs.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),

            // Tên danh mục và số lượng truyện
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  StreamBuilder<int>(
                    stream: LibraryService.instance.streamMangaCountInCategory(name),
                    builder: (context, snapshot) {
                      final count = snapshot.data ?? 0;
                      return Text(
                        count > 0 ? '$count bộ truyện' : 'Chưa có truyện',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.45),
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Nút thao tác bên phải
            if (isDefault)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 14,
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Mặc định',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.edit_outlined,
                      size: 20,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                    tooltip: 'Đổi tên',
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _showEditDialog(context);
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: cs.error.withValues(alpha: 0.8),
                    ),
                    tooltip: 'Xóa',
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      _showDeleteDialog(context);
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Dialog chỉnh sửa tên danh mục
  void _showEditDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _EditCategoryDialog(
        currentName: name,
        allCategories: allCategories,
      ),
    );
  }

  /// Dialog xác nhận xóa danh mục
  void _showDeleteDialog(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: theme.dialogTheme.backgroundColor ?? theme.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.delete_outline_rounded,
                color: cs.error,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Xóa danh mục?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Tất cả truyện trong mục "$name" sẽ được gỡ khỏi danh mục này. Truyện trong thư viện của bạn sẽ không bị mất.',
          style: TextStyle(
            fontSize: 14.5,
            height: 1.45,
            color: cs.onSurface.withValues(alpha: 0.75),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              'Hủy',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FilledButton(
            onPressed: () async {
              HapticFeedback.mediumImpact();
              await LibraryService.instance.removeCategory(name);
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    content: Text('Đã xóa danh mục "$name"'),
                    backgroundColor: cs.error,
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 10,
              ),
            ),
            child: const Text(
              'Xóa',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog chỉnh sửa tên danh mục với xác thực an toàn và quản lý controller độc lập
class _EditCategoryDialog extends StatefulWidget {
  final String currentName;
  final List<String> allCategories;

  const _EditCategoryDialog({
    required this.currentName,
    required this.allCategories,
  });

  @override
  State<_EditCategoryDialog> createState() => _EditCategoryDialogState();
}

class _EditCategoryDialogState extends State<_EditCategoryDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final newName = _controller.text.trim();
    if (newName.isEmpty) {
      setState(() => _errorText = 'Tên danh mục không được để trống');
      return;
    }

    if (newName != widget.currentName) {
      if (newName.toLowerCase() == 'mặc định' ||
          widget.allCategories.any((c) =>
              c.toLowerCase() == newName.toLowerCase() &&
              c.toLowerCase() != widget.currentName.toLowerCase())) {
        setState(() => _errorText = 'Danh mục "$newName" đã tồn tại');
        return;
      }
    }

    HapticFeedback.lightImpact();
    await LibraryService.instance.updateCategory(widget.currentName, newName);
    if (!mounted) return;
    Navigator.pop(context);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        content: Text('Đã đổi tên thành "$newName"'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AlertDialog(
      backgroundColor: theme.dialogTheme.backgroundColor ?? theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.drive_file_rename_outline_rounded,
              color: cs.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Đổi tên danh mục',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_errorText != null) {
                setState(() => _errorText = null);
              }
            },
            onSubmitted: (_) => _submit(),
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(
              hintText: 'Nhập tên mới...',
              hintStyle: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.4),
              ),
              errorText: _errorText,
              filled: true,
              fillColor: cs.onSurface.withValues(alpha: 0.05),
              prefixIcon: Icon(
                Icons.label_outline_rounded,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _errorText = null);
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: cs.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Hủy',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.6),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 10,
            ),
          ),
          child: const Text(
            'Lưu',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
