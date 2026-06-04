import 'package:flutter/material.dart';
import 'epub_models.dart';

class EpubPaginator {
  static List<EpubPage> paginate({
    required EpubChapter chapter,
    required Size viewportSize,
    required TextStyle baseTextStyle,
    required double blockSpacing,
  }) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) {
      return const [EpubPage(blocks: [])];
    }

    final pages = <EpubPage>[];
    List<EpubBlock> currentPageBlocks = [];
    double currentHeight = 0;

    for (final block in chapter.blocks) {
      if (block.type == EpubBlockType.image) {
        // Image breaks the page, so flush current blocks to a new page
        if (currentPageBlocks.isNotEmpty) {
          pages.add(EpubPage(blocks: currentPageBlocks));
          currentPageBlocks = [];
          currentHeight = 0;
        }
        // Image occupies its own full page
        pages.add(EpubPage(blocks: [block]));
      } else if (block.type == EpubBlockType.divider) {
        // Divider has a fixed visual height + padding (approx 32 logical pixels)
        const dividerHeight = 32.0;
        if (currentHeight + dividerHeight + blockSpacing >
                viewportSize.height &&
            currentPageBlocks.isNotEmpty) {
          pages.add(EpubPage(blocks: currentPageBlocks));
          currentPageBlocks = [];
          currentHeight = 0;
        }
        currentPageBlocks.add(block);
        currentHeight += dividerHeight + blockSpacing;
      } else {
        // Text blocks (Heading, Paragraph, Quote)
        final TextStyle blockStyle = _getStyleForBlock(
          block.type,
          baseTextStyle,
        );

        // Work on plain text for measurement; spans will be re-sliced after split
        final List<EpubSpan> remainingSpans = List.from(
          block.spans ?? [EpubSpan(text: '')],
        );

        while (remainingSpans.isNotEmpty) {
          final plainText = remainingSpans.map((s) => s.text).join();
          if (plainText.trim().isEmpty) break;

          final textPainter = _createTextPainter(remainingSpans, blockStyle);
          textPainter.layout(maxWidth: viewportSize.width);

          final blockRenderHeight = textPainter.height + blockSpacing;

          // Fits entirely on current page
          if (currentHeight + blockRenderHeight <= viewportSize.height) {
            currentPageBlocks.add(
              EpubBlock(type: block.type, spans: remainingSpans),
            );
            currentHeight += blockRenderHeight;
            break;
          }

          // Need to split
          final availableHeight = viewportSize.height - currentHeight;

          // Binary search to find character split index in plainText
          int low = 0;
          int high = plainText.length;
          int splitCharIndex = 0;

          // Only split if there's enough room for at least something
          if (availableHeight > blockSpacing) {
            while (low <= high) {
              final mid = (low + high) ~/ 2;
              final testSpans = _sliceSpans(remainingSpans, 0, mid);
              final testPainter = _createTextPainter(testSpans, blockStyle);
              testPainter.layout(maxWidth: viewportSize.width);
              if (testPainter.height + blockSpacing <= availableHeight) {
                splitCharIndex = mid;
                low = mid + 1;
              } else {
                high = mid - 1;
              }
            }

            // Backtrack to word boundary
            if (splitCharIndex > 0 && splitCharIndex < plainText.length) {
              final spaceIdx = plainText.lastIndexOf(
                RegExp(r'\s'),
                splitCharIndex,
              );
              if (spaceIdx > 0) splitCharIndex = spaceIdx;
            }
          }

          if (splitCharIndex == 0) {
            if (currentPageBlocks.isNotEmpty) {
              // Push current to page and retry on fresh page
              pages.add(EpubPage(blocks: currentPageBlocks));
              currentPageBlocks = [];
              currentHeight = 0;
            } else {
              // Force at least one word to avoid infinite loop
              int nextSpace = plainText.indexOf(RegExp(r'\s'));
              if (nextSpace == -1) nextSpace = plainText.length;
              if (nextSpace == 0) nextSpace = 1;
              final forced = _sliceSpans(remainingSpans, 0, nextSpace);
              final rest = _sliceSpans(
                remainingSpans,
                nextSpace,
                plainText.length,
              );
              if (forced.isNotEmpty) {
                pages.add(
                  EpubPage(
                    blocks: [EpubBlock(type: block.type, spans: forced)],
                  ),
                );
              }
              remainingSpans.clear();
              remainingSpans.addAll(_trimLeadingSpans(rest));
            }
            continue;
          }

          // Split into fit and remainder
          final fitSpans = _sliceSpans(remainingSpans, 0, splitCharIndex);
          final restSpans = _sliceSpans(
            remainingSpans,
            splitCharIndex,
            plainText.length,
          );

          if (fitSpans.isNotEmpty) {
            currentPageBlocks.add(EpubBlock(type: block.type, spans: fitSpans));
          }
          pages.add(EpubPage(blocks: currentPageBlocks));
          currentPageBlocks = [];
          currentHeight = 0;

          remainingSpans.clear();
          remainingSpans.addAll(_trimLeadingSpans(restSpans));
        }
      }
    }

    if (currentPageBlocks.isNotEmpty) {
      pages.add(EpubPage(blocks: currentPageBlocks));
    }

    if (pages.isEmpty) {
      pages.add(const EpubPage(blocks: []));
    }

    return pages;
  }

  static TextSpan buildTextSpan(EpubBlock block, TextStyle baseStyle) {
    return _buildSpanTree(block.spans ?? const [], baseStyle);
  }

  static TextPainter _createTextPainter(
    List<EpubSpan> spans,
    TextStyle baseStyle,
  ) {
    return TextPainter(
      text: _buildSpanTree(spans, baseStyle),
      textDirection: TextDirection.ltr,
    );
  }

  static TextSpan _buildSpanTree(List<EpubSpan> spans, TextStyle baseStyle) {
    if (spans.isEmpty) return TextSpan(style: baseStyle);
    if (spans.length == 1 && spans.first.isPlain) {
      return TextSpan(text: spans.first.text, style: baseStyle);
    }
    return TextSpan(
      style: baseStyle,
      children: spans.map((span) {
        return TextSpan(
          text: span.text,
          style: baseStyle.copyWith(
            fontWeight: span.bold ? FontWeight.bold : baseStyle.fontWeight,
            fontStyle: span.italic ? FontStyle.italic : baseStyle.fontStyle,
            decoration: span.underline
                ? TextDecoration.underline
                : baseStyle.decoration,
          ),
        );
      }).toList(),
    );
  }

  /// Slice a flat list of spans to cover chars [start, end) in the joined text.
  static List<EpubSpan> _sliceSpans(List<EpubSpan> spans, int start, int end) {
    final result = <EpubSpan>[];
    int pos = 0;
    for (final span in spans) {
      final spanEnd = pos + span.text.length;
      if (spanEnd <= start) {
        pos = spanEnd;
        continue;
      }
      if (pos >= end) break;

      final sliceStart = (start - pos).clamp(0, span.text.length);
      final sliceEnd = (end - pos).clamp(0, span.text.length);
      final sliced = span.text.substring(sliceStart, sliceEnd);
      if (sliced.isNotEmpty) {
        result.add(
          EpubSpan(
            text: sliced,
            bold: span.bold,
            italic: span.italic,
            underline: span.underline,
          ),
        );
      }
      pos = spanEnd;
    }
    return result;
  }

  /// Remove leading whitespace-only spans and trim first span's leading whitespace.
  static List<EpubSpan> _trimLeadingSpans(List<EpubSpan> spans) {
    final result = <EpubSpan>[];
    bool trimming = true;
    for (final span in spans) {
      if (trimming) {
        final trimmed = span.text.trimLeft();
        if (trimmed.isNotEmpty) {
          result.add(
            EpubSpan(
              text: trimmed,
              bold: span.bold,
              italic: span.italic,
              underline: span.underline,
            ),
          );
          trimming = false;
        }
      } else {
        result.add(span);
      }
    }
    return result;
  }

  static TextStyle _getStyleForBlock(EpubBlockType type, TextStyle baseStyle) {
    switch (type) {
      case EpubBlockType.heading:
        return baseStyle.copyWith(
          fontSize: (baseStyle.fontSize ?? 16.0) * 1.5,
          fontWeight: FontWeight.bold,
        );
      case EpubBlockType.quote:
        return baseStyle.copyWith(fontStyle: FontStyle.italic);
      default:
        return baseStyle;
    }
  }
}
