import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MangaDescriptionSection extends StatefulWidget {
  final String description;

  const MangaDescriptionSection({super.key, required this.description});

  @override
  State<MangaDescriptionSection> createState() =>
      _MangaDescriptionSectionState();
}

class _MangaDescriptionSectionState extends State<MangaDescriptionSection> {
  bool _isDescriptionExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = widget.description.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Giới Thiệu',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          if (text.isEmpty)
            Text(
              'Chưa có phần giới thiệu cho bộ truyện này.',
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.4,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
                fontStyle: FontStyle.italic,
              ),
            )
          else
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _isDescriptionExpanded = !_isDescriptionExpanded;
                });
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: Text(
                      text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.4,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                      ),
                      maxLines: _isDescriptionExpanded ? null : 4,
                      overflow: _isDescriptionExpanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                    ),
                  ),
                  if (text.length > 150)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _isDescriptionExpanded ? 'Rút gọn' : 'Xem thêm...',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
