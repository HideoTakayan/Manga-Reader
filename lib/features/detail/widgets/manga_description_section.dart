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
  void didUpdateWidget(covariant MangaDescriptionSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.description != widget.description) {
      _isDescriptionExpanded = false;
    }
  }

  bool _doesTextExceedMaxLines(
    String text,
    TextStyle? style,
    double maxWidth,
    TextDirection textDirection,
    TextScaler textScaler,
  ) {
    final textSpan = TextSpan(text: text, style: style);
    final textPainter = TextPainter(
      text: textSpan,
      maxLines: 4,
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);
    final didExceed = textPainter.didExceedMaxLines;
    textPainter.dispose();
    return didExceed;
  }

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
            LayoutBuilder(
              builder: (context, constraints) {
                final textStyle = theme.textTheme.bodyMedium?.copyWith(
                  height: 1.4,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                );
                final maxWidth = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : MediaQuery.sizeOf(context).width - 32;
                final canExpand = _doesTextExceedMaxLines(
                  text,
                  textStyle,
                  maxWidth > 0 ? maxWidth : 300,
                  Directionality.of(context),
                  MediaQuery.textScalerOf(context),
                );

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: (canExpand || _isDescriptionExpanded)
                        ? () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _isDescriptionExpanded = !_isDescriptionExpanded;
                            });
                          }
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedSize(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                            alignment: Alignment.topLeft,
                            child: Text(
                              text,
                              style: textStyle,
                              maxLines: _isDescriptionExpanded ? null : 4,
                              overflow: _isDescriptionExpanded
                                  ? TextOverflow.visible
                                  : TextOverflow.ellipsis,
                            ),
                          ),
                          if (canExpand || _isDescriptionExpanded)
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
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
