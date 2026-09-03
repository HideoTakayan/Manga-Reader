import 'dart:typed_data';

class ParsedEpub {
  final String title;
  final List<EpubChapter> chapters;

  const ParsedEpub({required this.title, required this.chapters});
}

class ParsedEpubIndex {
  final String title;
  final List<EpubChapterReference> chapters;

  const ParsedEpubIndex({required this.title, required this.chapters});
}

class EpubChapterReference {
  final String title;
  final String href;

  const EpubChapterReference({required this.title, required this.href});
}

enum EpubBlockType { heading, paragraph, quote, divider, image }

/// A single run of inline text with optional styling.
class EpubSpan {
  final String text;
  final bool bold;
  final bool italic;
  final bool underline;

  const EpubSpan({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.underline = false,
  });

  bool get isPlain => !bold && !italic && !underline;

  @override
  String toString() => text;
}

class EpubBlock {
  final EpubBlockType type;

  /// For rich inline text: list of styled spans.
  final List<EpubSpan>? spans;
  final Uint8List? image;

  const EpubBlock({required this.type, this.spans, this.image});

  /// Plain-text representation (for TTS, search, etc.)
  String? get text => spans?.map((s) => s.text).join();

  /// Convenience constructor for a plain-text block (backward compat)
  factory EpubBlock.plainText({
    required EpubBlockType type,
    required String text,
  }) {
    return EpubBlock(
      type: type,
      spans: [EpubSpan(text: text)],
    );
  }

  EpubBlock applyReplacements(String Function(String) transform) {
    if (spans == null) return this;
    final newSpans = spans!.map((s) => EpubSpan(
      text: transform(s.text),
      bold: s.bold,
      italic: s.italic,
      underline: s.underline,
    )).toList();
    return EpubBlock(type: type, spans: newSpans, image: image);
  }
}

class EpubChapter {
  final String title;
  final List<EpubBlock> blocks;

  const EpubChapter({required this.title, required this.blocks});

  // Backward compatibility & TTS
  String get text => blocks
      .where((b) => b.text != null && b.type != EpubBlockType.divider)
      .map((b) => b.text)
      .join('\n\n');

  List<Uint8List> get images => blocks
      .where((b) => b.type == EpubBlockType.image && b.image != null)
      .map((b) => b.image!)
      .toList();

  EpubChapter applyReplacements(String Function(String) transform) {
    final newTitle = transform(title);
    final newBlocks = blocks.map((b) => b.applyReplacements(transform)).toList();
    return EpubChapter(title: newTitle, blocks: newBlocks);
  }
}

class EpubPage {
  final List<EpubBlock> blocks;

  const EpubPage({required this.blocks});

  String get text => blocks
      .where((b) => b.text != null && b.type != EpubBlockType.divider)
      .map((b) => b.text)
      .join('\n\n');
}

class ManifestItem {
  final String id;
  final String href;
  final String mediaType;
  final String properties;

  const ManifestItem({
    required this.id,
    required this.href,
    required this.mediaType,
    this.properties = '',
  });

  bool get isNav => properties.split(RegExp(r'\s+')).contains('nav');
}
