import 'package:flutter/material.dart';

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
          GestureDetector(
            onTap: () {
              setState(() {
                _isDescriptionExpanded = !_isDescriptionExpanded;
              });
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.4,
                    color: Colors.white70,
                  ),
                  maxLines: _isDescriptionExpanded ? null : 4,
                  overflow: _isDescriptionExpanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                ),
                if (widget.description.length > 150)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _isDescriptionExpanded ? 'Rút gọn' : 'Xem thêm...',
                      style: TextStyle(
                        color: theme.primaryColor,
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
