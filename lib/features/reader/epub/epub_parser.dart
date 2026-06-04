import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';
import 'package:html/parser.dart' show parseFragment;
import 'package:html/dom.dart' as html_dom;

import 'epub_models.dart';

class EpubParseArgs {
  final Uint8List bytes;
  final String title;

  const EpubParseArgs({required this.bytes, required this.title});
}

class EpubChapterParseArgs {
  final Uint8List bytes;
  final EpubChapterReference chapter;

  const EpubChapterParseArgs({required this.bytes, required this.chapter});
}

class EpubParser {
  static ParsedEpub parse(EpubParseArgs args) {
    final stopwatch = Stopwatch()..start();

    // 1. Unzip
    final archive = ZipDecoder().decodeBytes(args.bytes);
    final files = <String, ArchiveFile>{};
    for (final file in archive) {
      files[_normalizePath(file.name)] = file;
    }
    debugPrint(
      '[EpubParser] Unzip completed in ${stopwatch.elapsedMilliseconds}ms',
    );
    stopwatch.reset();

    try {
      // 2. Read container.xml to find OPF
      final container = _readArchiveText(files, 'META-INF/container.xml');
      final containerXml = XmlDocument.parse(container);
      final opfPath = containerXml
          .findAllElements('rootfile')
          .first
          .getAttribute('full-path');
      if (opfPath == null) {
        throw const FormatException('Không tìm thấy OPF path');
      }

      final opf = _readArchiveText(files, opfPath);
      final opfXml = XmlDocument.parse(opf);
      final opfDir = _dirname(opfPath);

      // 3. Build Manifest
      final manifest = <String, ManifestItem>{};
      for (final item in opfXml.findAllElements('item')) {
        final id = item.getAttribute('id');
        final href = item.getAttribute('href');
        if (id == null || href == null) continue;
        manifest[id] = ManifestItem(
          id: id,
          href: _normalizePath(_joinPath(opfDir, href)),
          mediaType: item.getAttribute('media-type') ?? '',
          properties: item.getAttribute('properties') ?? '',
        );
      }
      debugPrint(
        '[EpubParser] Metadata & Manifest parsed in ${stopwatch.elapsedMilliseconds}ms',
      );

      // 4. Extract Navigation Titles
      final navTitles = _readNavTitles(files, manifest);

      // 5. Build Spine (Chapters)
      final chapters = <EpubChapter>[];
      var index = 1;
      for (final itemref in opfXml.findAllElements('itemref')) {
        final idref = itemref.getAttribute('idref');
        final item = idref == null ? null : manifest[idref];
        if (item == null || !_isHtmlItem(item)) continue;

        final html = _readArchiveText(files, item.href);
        final title =
            navTitles[item.href] ?? _extractTitle(html) ?? 'Chương $index';
        final blocks = _parseBlocks(html, item.href, files);

        if (blocks.isEmpty) continue;

        if (title.isNotEmpty) {
          final firstTextBlock = blocks.firstWhereOrNull(
            (b) => b.text != null && b.text!.trim().isNotEmpty,
          );
          if (firstTextBlock == null ||
              !firstTextBlock.text!.trim().startsWith(title)) {
            blocks.insert(
              0,
              EpubBlock.plainText(type: EpubBlockType.heading, text: title),
            );
          }
        }

        chapters.add(EpubChapter(title: title, blocks: blocks));
        index++;
      }

      if (chapters.isEmpty) {
        throw const FormatException('Không tìm thấy nội dung text trong EPUB.');
      }

      debugPrint(
        '[EpubParser] Total EPUB parsing completed in ${stopwatch.elapsedMilliseconds}ms. Chapters: ${chapters.length}',
      );
      stopwatch.stop();

      return ParsedEpub(title: args.title, chapters: chapters);
    } catch (e) {
      debugPrint('[EpubParser] Lỗi parse EPUB: $e');
      rethrow;
    }
  }

  /// Parses only EPUB metadata, spine and TOC. Chapter XHTML remains
  /// compressed until [parseChapter] requests a specific entry.
  static ParsedEpubIndex parseIndex(EpubParseArgs args) {
    final files = decodeFiles(args.bytes);
    final package = _readPackage(files);
    final navTitles = _readNavTitles(files, package.manifest);
    final chapters = <EpubChapterReference>[];
    var index = 1;

    for (final itemref in package.opf.findAllElements('itemref')) {
      final idref = itemref.getAttribute('idref');
      final item = idref == null ? null : package.manifest[idref];
      if (item == null || !_isHtmlItem(item)) continue;
      chapters.add(
        EpubChapterReference(
          title: navTitles[item.href] ?? 'Chương $index',
          href: item.href,
        ),
      );
      index++;
    }

    if (chapters.isEmpty) {
      throw const FormatException('Không tìm thấy chapter trong EPUB.');
    }
    return ParsedEpubIndex(title: args.title, chapters: chapters);
  }

  /// Parses one chapter on demand. The archive package keeps individual ZIP
  /// entries compressed until their [ArchiveFile.content] is accessed.
  static EpubChapter parseChapter(EpubChapterParseArgs args) {
    final files = decodeFiles(args.bytes);
    return buildChapter(files, args.chapter);
  }

  static Map<String, ArchiveFile> decodeFiles(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    return {for (final file in archive) _normalizePath(file.name): file};
  }

  static _EpubPackage _readPackage(Map<String, ArchiveFile> files) {
    final container = _readArchiveText(files, 'META-INF/container.xml');
    final containerXml = XmlDocument.parse(container);
    final opfPath = containerXml
        .findAllElements('rootfile')
        .first
        .getAttribute('full-path');
    if (opfPath == null) {
      throw const FormatException('Không tìm thấy OPF path');
    }

    final opf = XmlDocument.parse(_readArchiveText(files, opfPath));
    final opfDir = _dirname(opfPath);
    final manifest = <String, ManifestItem>{};
    for (final item in opf.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null) continue;
      manifest[id] = ManifestItem(
        id: id,
        href: _normalizePath(_joinPath(opfDir, href)),
        mediaType: item.getAttribute('media-type') ?? '',
        properties: item.getAttribute('properties') ?? '',
      );
    }
    return _EpubPackage(opf: opf, manifest: manifest);
  }

  static EpubChapter buildChapter(
    Map<String, ArchiveFile> files,
    EpubChapterReference chapter,
  ) {
    final html = _readArchiveText(files, chapter.href);
    final extractedTitle = _extractTitle(html);
    final title = chapter.title.isNotEmpty
        ? chapter.title
        : extractedTitle ?? 'Chương';
    final blocks = _parseBlocks(html, chapter.href, files);
    if (title.isNotEmpty) {
      final firstTextBlock = blocks.firstWhereOrNull(
        (block) => block.text != null && block.text!.trim().isNotEmpty,
      );
      if (firstTextBlock == null ||
          !firstTextBlock.text!.trim().startsWith(title)) {
        blocks.insert(
          0,
          EpubBlock.plainText(type: EpubBlockType.heading, text: title),
        );
      }
    }
    return EpubChapter(title: title, blocks: blocks);
  }

  static Map<String, String> _readNavTitles(
    Map<String, ArchiveFile> files,
    Map<String, ManifestItem> manifest,
  ) {
    final navItem =
        manifest.values.firstWhereOrNull((item) => item.isNav) ??
        manifest.values.firstWhereOrNull(
          (item) =>
              item.mediaType.contains('nav') ||
              item.href.toLowerCase().endsWith('toc.xhtml') ||
              item.href.toLowerCase().endsWith('nav.xhtml'),
        );

    if (navItem != null && files.containsKey(navItem.href)) {
      try {
        final doc = XmlDocument.parse(_readArchiveText(files, navItem.href));
        final navDir = _dirname(navItem.href);
        final result = <String, String>{};

        final navTocs = doc
            .findAllElements('nav')
            .where(
              (e) =>
                  e.getAttribute('epub:type') == 'toc' ||
                  e.getAttribute('type') == 'toc',
            );

        Iterable<XmlElement> linkElements;
        if (navTocs.isNotEmpty) {
          linkElements = navTocs.first.findAllElements('a');
        } else {
          linkElements = doc.findAllElements('a');
        }

        for (final a in linkElements) {
          final href = a.getAttribute('href');
          final title = a.innerText.trim();
          if (href == null || title.isEmpty) continue;
          final cleanHref = href.split('#').first;
          result[_normalizePath(_joinPath(navDir, cleanHref))] = title;
        }
        if (result.isNotEmpty) return result;
      } catch (e) {
        debugPrint('[EpubParser] Lỗi parse nav.xhtml: $e');
      }
    }

    final ncxItem = manifest.values.firstWhereOrNull(
      (item) =>
          item.mediaType == 'application/x-dtbncx+xml' ||
          item.href.toLowerCase().endsWith('.ncx'),
    );

    if (ncxItem != null && files.containsKey(ncxItem.href)) {
      try {
        final doc = XmlDocument.parse(_readArchiveText(files, ncxItem.href));
        final navDir = _dirname(ncxItem.href);
        final result = <String, String>{};
        for (final navPoint in doc.findAllElements('navPoint')) {
          final textNode = navPoint.findAllElements('text').firstOrNull;
          final contentNode = navPoint.findAllElements('content').firstOrNull;

          final title = textNode?.innerText.trim();
          final src = contentNode?.getAttribute('src');

          if (title != null &&
              title.isNotEmpty &&
              src != null &&
              src.isNotEmpty) {
            final cleanHref = src.split('#').first;
            result[_normalizePath(_joinPath(navDir, cleanHref))] = title;
          }
        }
        return result;
      } catch (e) {
        debugPrint('[EpubParser] Lỗi parse toc.ncx: $e');
      }
    }

    return {};
  }

  static bool _isHtmlItem(ManifestItem item) {
    final lower = item.href.toLowerCase();
    return item.mediaType.contains('html') ||
        lower.endsWith('.xhtml') ||
        lower.endsWith('.html') ||
        lower.endsWith('.htm');
  }

  static String _readArchiveText(Map<String, ArchiveFile> files, String path) {
    final normalized = _normalizePath(path);
    final file = files[normalized];
    if (file == null || !file.isFile) {
      throw FormatException('Không tìm thấy file EPUB: $normalized');
    }
    final content = file.content;
    final bytes = content is Uint8List
        ? content
        : content is List<int>
        ? Uint8List.fromList(content)
        : Uint8List(0);
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String? _extractTitle(String html) {
    try {
      final doc = XmlDocument.parse(html);
      return doc.findAllElements('title').firstOrNull?.innerText.trim();
    } catch (_) {
      return null;
    }
  }

  static String _cleanHtml(String html) {
    var cleanedHtml = html.replaceAll(
      RegExp(r'<head[^>]*>.*?</head>', caseSensitive: false, dotAll: true),
      '',
    );
    cleanedHtml = cleanedHtml.replaceAll(
      RegExp(r'<style[^>]*>.*?</style>', caseSensitive: false, dotAll: true),
      '',
    );
    cleanedHtml = cleanedHtml.replaceAll(
      RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false, dotAll: true),
      '',
    );
    return cleanedHtml;
  }

  static List<EpubBlock> _parseBlocks(
    String htmlContent,
    String htmlPath,
    Map<String, ArchiveFile> files,
  ) {
    final blocks = <EpubBlock>[];
    final cleanedHtml = _cleanHtml(htmlContent);
    final document = parseFragment(cleanedHtml);

    List<EpubSpan> currentSpans = [];
    EpubBlockType currentType = EpubBlockType.paragraph;

    void flushSpans() {
      if (currentSpans.isEmpty) return;
      // Merge adjacent spans with the same style (just concatenate, no added spaces)
      final merged = <EpubSpan>[];
      for (final span in currentSpans) {
        if (span.text.isEmpty) continue;
        if (merged.isNotEmpty &&
            merged.last.bold == span.bold &&
            merged.last.italic == span.italic &&
            merged.last.underline == span.underline) {
          final last = merged.removeLast();
          merged.add(
            EpubSpan(
              text: last.text + span.text,
              bold: last.bold,
              italic: last.italic,
              underline: last.underline,
            ),
          );
        } else {
          merged.add(span);
        }
      }
      // Clean whitespace at block level: trim start/end of the whole block
      // by adjusting first and last spans
      if (merged.isEmpty) {
        currentSpans = [];
        currentType = EpubBlockType.paragraph;
        return;
      }
      // Trim leading whitespace from the first span
      final first = merged.first;
      if (first.text.trimLeft().isEmpty && merged.length == 1) {
        currentSpans = [];
        currentType = EpubBlockType.paragraph;
        return;
      }
      merged[0] = EpubSpan(
        text: first.text.trimLeft(),
        bold: first.bold,
        italic: first.italic,
        underline: first.underline,
      );
      // Trim trailing whitespace from the last span
      final last = merged.last;
      merged[merged.length - 1] = EpubSpan(
        text: last.text.trimRight(),
        bold: last.bold,
        italic: last.italic,
        underline: last.underline,
      );
      // Remove empty spans after trimming
      final cleaned = merged.where((s) => s.text.isNotEmpty).toList();
      if (cleaned.isNotEmpty) {
        blocks.add(EpubBlock(type: currentType, spans: cleaned));
      }
      currentSpans = [];
      currentType = EpubBlockType.paragraph;
    }

    void traverseInline(
      html_dom.Node node,
      bool bold,
      bool italic,
      bool underline,
    ) {
      if (node is html_dom.Text) {
        final raw = node.text.replaceAll(RegExp(r'[ \t]+'), ' ');
        if (raw.isNotEmpty) {
          currentSpans.add(
            EpubSpan(
              text: raw,
              bold: bold,
              italic: italic,
              underline: underline,
            ),
          );
        }
      } else if (node is html_dom.Element) {
        final name = node.localName?.toLowerCase();
        if (name == 'br') {
          currentSpans.add(
            EpubSpan(
              text: '\n',
              bold: bold,
              italic: italic,
              underline: underline,
            ),
          );
          return;
        }
        bool nextBold = bold;
        bool nextItalic = italic;
        bool nextUnderline = underline;
        if (name == 'b' || name == 'strong') nextBold = true;
        if (name == 'i' || name == 'em') nextItalic = true;
        if (name == 'u') nextUnderline = true;
        for (final child in node.nodes) {
          traverseInline(child, nextBold, nextItalic, nextUnderline);
        }
      }
    }

    void traverse(
      html_dom.Node node,
      EpubBlockType inheritedType,
      bool bold,
      bool italic,
      bool underline,
    ) {
      if (node is html_dom.Text) {
        traverseInline(node, bold, italic, underline);
      } else if (node is html_dom.Element) {
        final name = node.localName?.toLowerCase();

        if (name == 'br') {
          currentSpans.add(EpubSpan(text: '\n'));
          return;
        }

        final isInlineTag = [
          'b',
          'i',
          'em',
          'strong',
          'u',
          'span',
          'a',
          'sup',
          'sub',
          'small',
          'mark',
        ].contains(name);
        if (isInlineTag) {
          bool nextBold = bold || (name == 'b' || name == 'strong');
          bool nextItalic = italic || (name == 'i' || name == 'em');
          bool nextUnderline = underline || (name == 'u');
          for (final child in node.nodes) {
            traverse(child, inheritedType, nextBold, nextItalic, nextUnderline);
          }
          return;
        }

        // Block element — flush current spans first
        flushSpans();

        if (name == 'img' || name == 'image') {
          final src =
              node.attributes['src'] ??
              node.attributes['href'] ??
              node.attributes['xlink:href'];
          if (src != null && src.isNotEmpty) {
            final cleanSrc = src.split('#').first.split('?').first;
            final imgPath = _normalizePath(
              _joinPath(_dirname(htmlPath), cleanSrc),
            );
            final imgFile = files[imgPath];
            if (imgFile != null && imgFile.isFile) {
              final content = imgFile.content;
              if (content is Uint8List) {
                blocks.add(
                  EpubBlock(type: EpubBlockType.image, image: content),
                );
              } else if (content is List<int>) {
                blocks.add(
                  EpubBlock(
                    type: EpubBlockType.image,
                    image: Uint8List.fromList(content),
                  ),
                );
              }
            }
          }
        } else if (name == 'hr') {
          blocks.add(const EpubBlock(type: EpubBlockType.divider));
        } else {
          EpubBlockType nextType = inheritedType;
          if (name == 'h1' ||
              name == 'h2' ||
              name == 'h3' ||
              name == 'h4' ||
              name == 'h5' ||
              name == 'h6') {
            nextType = EpubBlockType.heading;
          } else if (name == 'blockquote') {
            nextType = EpubBlockType.quote;
          } else if (name == 'p' || name == 'div' || name == 'li') {
            if (inheritedType != EpubBlockType.quote) {
              nextType = EpubBlockType.paragraph;
            }
          }
          currentType = nextType;
          for (final child in node.nodes) {
            traverse(child, nextType, bold, italic, underline);
          }
          flushSpans();
        }
      }
    }

    for (final node in document.nodes) {
      traverse(node, EpubBlockType.paragraph, false, false, false);
    }
    flushSpans();

    return blocks;
  }

  static String formatChapterText(EpubChapter chapter) {
    final title = chapter.title.trim();
    final text = chapter.text.trim();
    if (title.isEmpty) return text;
    if (text.startsWith(title)) return text;
    return '$title\n\n$text';
  }

  static String _dirname(String path) {
    final normalized = _normalizePath(path);
    final index = normalized.lastIndexOf('/');
    return index == -1 ? '' : normalized.substring(0, index);
  }

  static String _joinPath(String base, String child) {
    if (base.isEmpty) return child;
    return '$base/$child';
  }

  static String _normalizePath(String path) {
    final parts = <String>[];
    for (final part in Uri.decodeFull(path).replaceAll('\\', '/').split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else {
        parts.add(part);
      }
    }
    return parts.join('/');
  }
}

class _EpubPackage {
  final XmlDocument opf;
  final Map<String, ManifestItem> manifest;

  const _EpubPackage({required this.opf, required this.manifest});
}
