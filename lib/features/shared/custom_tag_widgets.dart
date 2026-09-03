import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/library_status_service.dart';

class TagPreset {
  final String label;
  final IconData icon;
  final Color color;

  const TagPreset({
    required this.label,
    required this.icon,
    required this.color,
  });
}

class CustomTagHelper {
  static const List<TagPreset> presets = [
    TagPreset(
      label: 'Ưu tiên đọc',
      icon: Icons.local_fire_department_rounded,
      color: Colors.deepOrangeAccent,
    ),
    TagPreset(
      label: 'Đã xem Anime',
      icon: Icons.tv_rounded,
      color: Colors.cyanAccent,
    ),
    TagPreset(
      label: 'Chờ tích chap',
      icon: Icons.hourglass_bottom_rounded,
      color: Colors.amberAccent,
    ),
    TagPreset(
      label: 'Siêu phẩm',
      icon: Icons.star_rounded,
      color: Colors.purpleAccent,
    ),
    TagPreset(
      label: 'Bản dịch chuẩn',
      icon: Icons.verified_rounded,
      color: Colors.greenAccent,
    ),
    TagPreset(
      label: 'Tạm ngưng',
      icon: Icons.pause_circle_filled_rounded,
      color: Colors.blueGrey,
    ),
  ];

  static Color getColorForTag(String tag) {
    final match = presets.where((p) => p.label.toLowerCase() == tag.toLowerCase()).firstOrNull;
    if (match != null) return match.color;

    // Stable color based on string hash
    final hash = tag.codeUnits.fold(0, (prev, elem) => prev + elem);
    const colors = [
      Colors.pinkAccent,
      Colors.tealAccent,
      Colors.indigoAccent,
      Colors.limeAccent,
      Colors.deepOrangeAccent,
      Colors.purpleAccent,
      Colors.lightBlueAccent,
    ];
    return colors[hash % colors.length];
  }

  static IconData getIconForTag(String tag) {
    final match = presets.where((p) => p.label.toLowerCase() == tag.toLowerCase()).firstOrNull;
    if (match != null) return match.icon;
    return Icons.label_outline_rounded;
  }
}

class CustomTagBadge extends StatelessWidget {
  final String tag;
  final VoidCallback? onTap;
  final VoidCallback? onDeleted;
  final bool isSmall;

  const CustomTagBadge({
    super.key,
    required this.tag,
    this.onTap,
    this.onDeleted,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = CustomTagHelper.getColorForTag(tag);
    final icon = CustomTagHelper.getIconForTag(tag);

    return Container(
      margin: EdgeInsets.only(right: isSmall ? 4 : 6, bottom: isSmall ? 2 : 4),
      padding: EdgeInsets.symmetric(
        horizontal: isSmall ? 6 : 10,
        vertical: isSmall ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(isSmall ? 6 : 10),
        border: Border.all(
          color: color.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: isSmall ? 10 : 13,
            color: color,
          ),
          SizedBox(width: isSmall ? 3 : 5),
          Text(
            tag,
            style: TextStyle(
              color: color,
              fontSize: isSmall ? 10 : 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (onDeleted != null) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: onDeleted,
              child: Icon(
                Icons.close_rounded,
                size: isSmall ? 12 : 15,
                color: color.withValues(alpha: 0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class CustomTagManagerDialog extends StatefulWidget {
  final String mangaId;
  final List<String> currentTags;

  const CustomTagManagerDialog({
    super.key,
    required this.mangaId,
    required this.currentTags,
  });

  static Future<List<String>?> show(
    BuildContext context, {
    required String mangaId,
    required List<String> currentTags,
  }) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CustomTagManagerDialog(
        mangaId: mangaId,
        currentTags: currentTags,
      ),
    );
  }

  @override
  State<CustomTagManagerDialog> createState() => _CustomTagManagerDialogState();
}

class _CustomTagManagerDialogState extends State<CustomTagManagerDialog> {
  late Set<String> _tags;
  final TextEditingController _customTagController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tags = Set<String>.from(widget.currentTags);
  }

  @override
  void dispose() {
    _customTagController.dispose();
    super.dispose();
  }

  void _togglePreset(TagPreset preset) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_tags.contains(preset.label)) {
        _tags.remove(preset.label);
      } else {
        _tags.add(preset.label);
      }
    });
  }

  void _addCustomTag() {
    final text = _customTagController.text.trim();
    if (text.isEmpty) return;

    HapticFeedback.lightImpact();
    setState(() {
      _tags.add(text);
      _customTagController.clear();
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    try {
      final list = _tags.toList();
      await LibraryStatusService.instance.setTags(widget.mangaId, list);
      if (mounted) {
        Navigator.pop(context, list);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi lưu nhãn: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle Bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.bookmarks_rounded,
                      color: Colors.orangeAccent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nhãn Đọc Tùy Chỉnh',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Gắn nhãn để phân loại và lọc truyện dễ dàng',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.white12, height: 1),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Active tags
                    const Text(
                      'Nhãn đang áp dụng:',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_tags.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: const Text(
                          'Chưa có nhãn nào. Chọn từ gợi ý bên dưới hoặc tự thêm nhãn mới.',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _tags.map((t) {
                          return CustomTagBadge(
                            tag: t,
                            onDeleted: () {
                              HapticFeedback.selectionClick();
                              setState(() => _tags.remove(t));
                            },
                          );
                        }).toList(),
                      ),

                    const SizedBox(height: 20),

                    // Quick presets
                    const Text(
                      'Gợi ý nhãn nhanh:',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: CustomTagHelper.presets.map((preset) {
                        final isSelected = _tags.contains(preset.label);
                        return FilterChip(
                          avatar: Icon(
                            preset.icon,
                            size: 16,
                            color: isSelected ? Colors.white : preset.color,
                          ),
                          label: Text(preset.label),
                          selected: isSelected,
                          selectedColor: preset.color.withValues(alpha: 0.8),
                          backgroundColor: preset.color.withValues(alpha: 0.12),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : preset.color,
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          ),
                          side: BorderSide(
                            color: isSelected
                                ? Colors.transparent
                                : preset.color.withValues(alpha: 0.4),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          onSelected: (_) => _togglePreset(preset),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 20),

                    // Add Custom Tag
                    const Text(
                      'Tự tạo nhãn riêng:',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _customTagController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              hintText: 'Nhập tên nhãn mới...',
                              hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.05),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onSubmitted: (_) => _addCustomTag(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _addCustomTag,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white12,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Thêm', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Footer Save Action
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'LƯU NHÃN',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
