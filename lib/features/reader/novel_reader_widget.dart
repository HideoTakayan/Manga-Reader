import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import '../../data/database_helper.dart';
import '../../data/models.dart';

class NovelReaderWidget extends StatefulWidget {
  final Uint8List epubBytes;
  final String title;
  final String storageKey;

  const NovelReaderWidget({
    super.key,
    required this.epubBytes,
    required this.title,
    String? storageKey,
  }) : storageKey = storageKey ?? title;

  @override
  State<NovelReaderWidget> createState() => _NovelReaderWidgetState();
}

class _NovelReaderWidgetState extends State<NovelReaderWidget> {
  final _tts = FlutterTts();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _verticalController = ScrollController();
  final _pageController = PageController();
  final Map<int, GlobalKey> _chapterSectionKeys = {};

  _ParsedEpub? _book;
  bool _isLoading = true;
  String? _errorMessage;
  int _chapterIndex = 0;
  int _horizontalPageIndex = 0;
  int _fontSize = 18;
  int _bgColor = 0xFF1C1C1E;
  int _textColor = 0xFFFFFFFF;
  int _flowType = 0; // 0: horizontal pages, 1: vertical scroll

  bool _showTtsPanel = false;
  bool _isTtsPlaying = false;
  bool _isTtsFromSelection = false;
  double _ttsRate = 0.5;
  double _ttsPitch = 1.0;
  String _ttsLang = 'vi-VN';
  List<Map<String, String>> _availableVoices = [];
  Map<String, String>? _selectedVoice;
  String? _lastTtsText;
  List<String> _ttsChunks = [];
  int _ttsChunkIndex = 0;

  Timer? _progressTimer;
  Timer? _ttsSettingsTimer;
  Timer? _sleepTimer;
  int _sleepTimeMinutes = 0;
  bool _isCurrentBookmark = false;

  static const _supportedLangs = [
    ('vi-VN', 'Tiếng Việt'),
    ('en-US', 'English'),
    ('ja-JP', 'Nhật'),
    ('zh-CN', 'Trung'),
    ('ko-KR', 'Hàn'),
  ];

  String get _rawStorageKey =>
      widget.storageKey.isEmpty ? widget.title : widget.storageKey;

  String get _bookKey => _rawStorageKey
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  int get _stableKeyHash => _rawStorageKey.codeUnits.fold<int>(
    0,
    (hash, codeUnit) => (hash * 31 + codeUnit) & 0x7fffffff,
  );

  String get _resolvedBookKey =>
      _bookKey.isEmpty ? _stableKeyHash.toString() : _bookKey;

  String get _mangaId => 'epub_$_resolvedBookKey';

  String get _chapterId => 'epub_${_resolvedBookKey}_chapter_$_chapterIndex';

  String get _progressPrefsKey => 'epub_flutter_progress_$_mangaId';

  _EpubChapter get _currentChapter =>
      _book!.chapters[_chapterIndex.clamp(0, _book!.chapters.length - 1)];

  // --- Phase 2: Horizontal Window State ---
  int _windowCenterChapter = -1;
  List<String> _windowPages = [];
  int _pagesBeforeCenter = 0;
  final Map<int, List<String>> _chapterPagesCache = {};



  List<String> _getPagesForChapter(int chapterIndex) {
    if (_book == null || chapterIndex < 0 || chapterIndex >= _book!.chapters.length) {
      return [];
    }
    if (_chapterPagesCache.containsKey(chapterIndex)) {
      return _chapterPagesCache[chapterIndex]!;
    }
    final text = _formatChapterText(_book!.chapters[chapterIndex]);
    final pages = _splitIntoPages(text, max(900, _fontSize * 55));
    _chapterPagesCache[chapterIndex] = pages;
    return pages;
  }

  void _updateHorizontalWindow(int centerChapter) {
    if (_book == null) return;
    
    final chapters = _book!.chapters;
    final int prev = centerChapter - 1;
    final int next = centerChapter + 1;
    
    final List<String> newPages = [];
    int beforeCenterCount = 0;
    
    if (prev >= 0) {
      final prevPages = _getPagesForChapter(prev);
      newPages.addAll(prevPages);
      beforeCenterCount = prevPages.length;
    }
    
    final centerPages = _getPagesForChapter(centerChapter);
    newPages.addAll(centerPages);
    
    if (next < chapters.length) {
      final nextPages = _getPagesForChapter(next);
      newPages.addAll(nextPages);
    }
    
    _windowCenterChapter = centerChapter;
    _windowPages = newPages;
    _pagesBeforeCenter = beforeCenterCount;
  }
  // ----------------------------------------

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _init();
  }

  @override
  void didUpdateWidget(covariant NovelReaderWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.epubBytes != widget.epubBytes ||
        oldWidget.storageKey != widget.storageKey ||
        oldWidget.title != widget.title) {
      _resetForNewBook();
      _init();
    }
  }

  Future<void> _init() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      _fontSize = prefs.getInt('epub_font_size') ?? 18;
      _bgColor = prefs.getInt('epub_bg_color') ?? 0xFF1C1C1E;
      _textColor = prefs.getInt('epub_text_color') ?? 0xFFFFFFFF;
      _flowType = prefs.getInt('epub_flow_type') ?? 1;
      await _loadTtsSettings(prefs);

      final book = _parseEpub(widget.epubBytes);
      final saved = await _loadSavedPosition(prefs, book.chapters.length);
      if (!mounted) return;
      setState(() {
        _book = book;
        _chapterIndex = saved.$1;
        _horizontalPageIndex = saved.$2;
        _isLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_flowType == 1) {
          _jumpVerticalToChapter(saved.$1, offsetRatio: saved.$3);
        } else {
          _updateHorizontalWindow(saved.$1);
          final centerPagesCount = _getPagesForChapter(saved.$1).length;
          
          // Backward compatibility: if saved.$2 >= centerPagesCount, it's an old global index 
          // or an invalid out-of-bounds index. Fallback to 0 safely.
          final pageWithinChapter = saved.$2 >= centerPagesCount ? 0 : saved.$2;
          final initialIndex = _pagesBeforeCenter + pageWithinChapter;
          
          setState(() => _horizontalPageIndex = initialIndex);
          
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pageController.hasClients) {
              _pageController.jumpToPage(initialIndex);
            }
          });
        }
      });
      await _refreshBookmarkState();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Không đọc được EPUB: $e';
      });
    }
  }

  void _resetForNewBook() {
    _progressTimer?.cancel();
    _ttsSettingsTimer?.cancel();
    _sleepTimer?.cancel();
    _tts.stop();
    _verticalController.jumpTo(0);
    _lastTtsText = null;
    _ttsChunks = [];
    _ttsChunkIndex = 0;
    _book = null;
    _chapterIndex = 0;
    _horizontalPageIndex = 0;
    _isCurrentBookmark = false;
    _isTtsPlaying = false;
    _isTtsFromSelection = false;
    _chapterSectionKeys.clear();
    _chapterPagesCache.clear();
    _windowCenterChapter = -1;
    _windowPages.clear();
  }

  Future<void> _loadTtsSettings(SharedPreferences prefs) async {
    final prefix = 'tts_book_$_resolvedBookKey';
    _ttsRate =
        prefs.getDouble('${prefix}_rate') ?? prefs.getDouble('tts_rate') ?? 0.5;
    _ttsPitch =
        prefs.getDouble('${prefix}_pitch') ??
        prefs.getDouble('tts_pitch') ??
        1.0;
    _ttsLang =
        prefs.getString('${prefix}_lang') ??
        prefs.getString('tts_lang') ??
        'vi-VN';
    await _applyTtsSettings(restartIfPlaying: false);

    _tts.setCompletionHandler(() => unawaited(_playNextTtsChunk()));
    _tts.setErrorHandler((msg) {
      debugPrint('TTS Error: $msg');
      _ttsChunks = [];
      _ttsChunkIndex = 0;
      if (mounted) {
        setState(() => _isTtsPlaying = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('TTS lỗi: $msg')));
      }
    });
    await _loadVoicesForLang(_ttsLang);
  }

  Future<(int, int, double)> _loadSavedPosition(
    SharedPreferences prefs,
    int chapterCount,
  ) async {
    final raw = prefs.getString(_progressPrefsKey);
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return (
          (map['chapter'] as num? ?? 0).toInt().clamp(0, chapterCount - 1),
          max(0, (map['page'] as num? ?? 0).toInt()),
          max<double>(0, (map['offset'] as num? ?? 0).toDouble()),
        );
      } catch (_) {}
    }

    final progress = await DatabaseHelper.instance.getReaderProgress(_mangaId);
    final cfi = progress?.epubCfi ?? prefs.getString('epub_cfi_$_mangaId');
    final parsed = _decodePosition(cfi);
    if (parsed != null) {
      return (
        parsed.$1.clamp(0, chapterCount - 1),
        max(0, parsed.$2),
        max<double>(0, parsed.$3),
      );
    }
    return (0, 0, 0.0);
  }

  (int, int, double)? _decodePosition(String? value) {
    if (value == null || !value.startsWith('flutter:')) return null;
    final parts = value.substring('flutter:'.length).split(':');
    if (parts.length != 3) return null;
    return (
      int.tryParse(parts[0]) ?? 0,
      int.tryParse(parts[1]) ?? 0,
      double.tryParse(parts[2]) ?? 0,
    );
  }

  String _encodePosition() {
    double ratio = 0.0;
    int pageWithinChapter = 0;
    if (_flowType == 1) {
      final key = _chapterSectionKeys[_chapterIndex];
      if (key?.currentContext != null) {
        final box = key!.currentContext!.findRenderObject() as RenderBox?;
        if (box != null && box.attached) {
          // dy is relative to screen top. If we scrolled down past the chapter top, dy is negative.
          final top = box.localToGlobal(Offset.zero).dy;
          final height = box.size.height;
          if (height > 0) {
            ratio = (max(0.0, -top) / height).clamp(0.0, 1.0);
          }
        }
      }
    } else {
      // For horizontal mode, encode pageIndexWithinChapter
      pageWithinChapter = _pageWithinCurrentChapter();
      ratio = pageWithinChapter.toDouble();
    }
    return 'flutter:$_chapterIndex:$pageWithinChapter:${ratio.toStringAsFixed(4)}';
  }

  int _pageWithinCurrentChapter() {
    if (_windowPages.isEmpty) return 0;
    int page = 0;
    if (_chapterIndex < _windowCenterChapter) {
      page = _horizontalPageIndex;
    } else if (_chapterIndex == _windowCenterChapter) {
      page = _horizontalPageIndex - _pagesBeforeCenter;
    } else {
      final centerPages = _getPagesForChapter(_windowCenterChapter);
      page = _horizontalPageIndex - (_pagesBeforeCenter + centerPages.length);
    }
    final targetPagesCount = _getPagesForChapter(_chapterIndex).length;
    return page.clamp(0, max(0, targetPagesCount - 1)).toInt();
  }

  void _scheduleProgressSave() {
    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(milliseconds: 500), _saveProgress);
  }

  Future<void> _saveProgress() async {
    final position = _encodePosition();
    // Get the parts directly from encodePosition to save in DB
    final parts = position.substring('flutter:'.length).split(':');
    final pageWithinChapter = parts.length == 3 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final ratio = parts.length == 3 ? (double.tryParse(parts[2]) ?? 0.0) : 0.0;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _progressPrefsKey,
      jsonEncode({
        'chapter': _chapterIndex,
        'page': pageWithinChapter,
        'offset': ratio, // Save ratio instead of pixel offset
      }),
    );
    await DatabaseHelper.instance.saveReaderProgress(
      ReaderProgress(
        mangaId: _mangaId,
        chapterId: _chapterId,
        pageIndex: _flowType == 0 ? pageWithinChapter : _chapterIndex,
        scrollOffset: ratio, // Store ratio in DB
        progressPercent: _book == null || _book!.chapters.isEmpty
            ? 0
            : _chapterIndex /
                  max<double>(1, (_book!.chapters.length - 1).toDouble()),
        epubCfi: position,
        updatedAt: DateTime.now(),
      ),
    );
    await _refreshBookmarkState();
  }

  _ParsedEpub _parseEpub(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = {
      for (final file in archive.files) file.name.replaceAll('\\', '/'): file,
    };

    final container = _readArchiveText(files, 'META-INF/container.xml');
    final containerXml = XmlDocument.parse(container);
    final opfPath = containerXml
        .findAllElements('rootfile')
        .first
        .getAttribute('full-path');
    if (opfPath == null || opfPath.isEmpty) {
      throw const FormatException('EPUB thiếu rootfile OPF.');
    }

    final opf = _readArchiveText(files, opfPath);
    final opfXml = XmlDocument.parse(opf);
    final opfDir = _dirname(opfPath);

    final manifest = <String, _ManifestItem>{};
    for (final item in opfXml.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null) continue;
      manifest[id] = _ManifestItem(
        id: id,
        href: _normalizePath(_joinPath(opfDir, href)),
        mediaType: item.getAttribute('media-type') ?? '',
      );
    }

    final navTitles = _readNavTitles(files, manifest);
    final chapters = <_EpubChapter>[];
    var index = 1;
    for (final itemref in opfXml.findAllElements('itemref')) {
      final idref = itemref.getAttribute('idref');
      final item = idref == null ? null : manifest[idref];
      if (item == null || !_isHtmlItem(item)) continue;

      final html = _readArchiveText(files, item.href);
      final title =
          navTitles[item.href] ?? _extractTitle(html) ?? 'Chương $index';
      final text = _htmlToText(html);
      if (text.trim().isEmpty) continue;
      chapters.add(_EpubChapter(title: title, text: text));
      index++;
    }

    if (chapters.isEmpty) {
      throw const FormatException('Không tìm thấy nội dung text trong EPUB.');
    }
    return _ParsedEpub(title: widget.title, chapters: chapters);
  }

  Map<String, String> _readNavTitles(
    Map<String, ArchiveFile> files,
    Map<String, _ManifestItem> manifest,
  ) {
    final navItem = manifest.values.firstWhereOrNull(
      (item) =>
          item.mediaType.contains('nav') ||
          item.href.toLowerCase().endsWith('toc.xhtml') ||
          item.href.toLowerCase().endsWith('nav.xhtml'),
    );
    if (navItem == null || !files.containsKey(navItem.href)) return {};
    try {
      final doc = XmlDocument.parse(_readArchiveText(files, navItem.href));
      final navDir = _dirname(navItem.href);
      final result = <String, String>{};
      for (final a in doc.findAllElements('a')) {
        final href = a.getAttribute('href');
        final title = a.innerText.trim();
        if (href == null || title.isEmpty) continue;
        final cleanHref = href.split('#').first;
        result[_normalizePath(_joinPath(navDir, cleanHref))] = title;
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  bool _isHtmlItem(_ManifestItem item) {
    final lower = item.href.toLowerCase();
    return item.mediaType.contains('html') ||
        lower.endsWith('.xhtml') ||
        lower.endsWith('.html') ||
        lower.endsWith('.htm');
  }

  String _readArchiveText(Map<String, ArchiveFile> files, String path) {
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

  String? _extractTitle(String html) {
    try {
      final doc = XmlDocument.parse(html);
      return doc.findAllElements('title').firstOrNull?.innerText.trim();
    } catch (_) {
      return null;
    }
  }

  String _htmlToText(String html) {
    final normalized = html
        .replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(
            r'</\s*(p|div|h[1-6]|li|section|article|tr)\s*>',
            caseSensitive: false,
          ),
          '\n\n',
        );
    try {
      final doc = XmlDocument.parse(normalized);
      return _cleanText(doc.rootElement.innerText);
    } catch (_) {
      final stripped = normalized.replaceAll(RegExp(r'<[^>]+>'), ' ');
      return _cleanText(stripped);
    }
  }

  String _cleanText(String value) {
    return value
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n')
        .trim();
  }

  String _formatChapterText(_EpubChapter chapter) {
    final title = chapter.title.trim();
    final text = chapter.text.trim();
    if (title.isEmpty) return text;
    if (text.startsWith(title)) return text;
    return '$title\n\n$text';
  }

  List<String> _splitIntoPages(String text, int targetChars) {
    final paragraphs = text.split(RegExp(r'\n\s*\n'));
    final pages = <String>[];
    final buffer = StringBuffer();
    for (final paragraph in paragraphs) {
      if (buffer.length + paragraph.length > targetChars && buffer.isNotEmpty) {
        pages.add(buffer.toString().trim());
        buffer.clear();
      }
      buffer.writeln(paragraph.trim());
      buffer.writeln();
    }
    if (buffer.toString().trim().isNotEmpty) {
      pages.add(buffer.toString().trim());
    }
    return pages.isEmpty ? [text] : pages;
  }

  String _dirname(String path) {
    final normalized = _normalizePath(path);
    final index = normalized.lastIndexOf('/');
    return index == -1 ? '' : normalized.substring(0, index);
  }

  String _joinPath(String base, String child) {
    if (base.isEmpty) return child;
    return '$base/$child';
  }

  String _normalizePath(String path) {
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

  Future<void> _setFontSize(int value) async {
    final next = value.clamp(12, 40);
    if (!mounted) return;
    
    double progressRatio = 0.0;
    if (_flowType == 0 && _windowPages.isNotEmpty) {
       final oldCenterPagesCount = _getPagesForChapter(_chapterIndex).length;
       final pageWithinChapter = _pageWithinCurrentChapter();
       if (oldCenterPagesCount > 0) {
          progressRatio = pageWithinChapter / oldCenterPagesCount;
       }
    }
    
    setState(() {
       _fontSize = next;
       _chapterPagesCache.clear();
       if (_flowType == 0) {
          _updateHorizontalWindow(_chapterIndex);
          final newCenterPagesCount = _getPagesForChapter(_chapterIndex).length;
          final newPageWithinChapter = (progressRatio * newCenterPagesCount).floor().clamp(0, max(0, newCenterPagesCount - 1)).toInt();
          _horizontalPageIndex = _pagesBeforeCenter + newPageWithinChapter;
       }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('epub_font_size', next);
    _scheduleProgressSave();
    
    if (_flowType == 0) {
       WidgetsBinding.instance.addPostFrameCallback((_) {
         if (mounted && _pageController.hasClients) {
            _pageController.jumpToPage(_horizontalPageIndex);
         }
       });
    }
  }

  Future<void> _setFlowType(int value) async {
    final next = value == 1 ? 1 : 0;
    if (!mounted || _flowType == next) return;
    
    final targetChapter = _chapterIndex;
    double targetRatio = 0.0;
    
    if (_flowType == 1 && next == 0) {
       // Vertical -> Horizontal: get vertical ratio
       final position = _encodePosition();
       final parts = position.substring('flutter:'.length).split(':');
       targetRatio = parts.length == 3 ? (double.tryParse(parts[2]) ?? 0.0) : 0.0;
    } else if (_flowType == 0 && next == 1) {
       // Horizontal -> Vertical: calculate horizontal ratio
       final centerPagesCount = _getPagesForChapter(targetChapter).length;
       if (centerPagesCount > 0) {
          targetRatio = _pageWithinCurrentChapter() / centerPagesCount;
       }
    }
    
    if (next == 0) {
       _updateHorizontalWindow(targetChapter);
    }
    
    setState(() {
      _flowType = next;
      if (next == 0) {
         final centerPagesCount = _getPagesForChapter(targetChapter).length;
         final newPageWithinChapter = (targetRatio * centerPagesCount).floor().clamp(0, max(0, centerPagesCount - 1)).toInt();
         _horizontalPageIndex = _pagesBeforeCenter + newPageWithinChapter;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_flowType == 1) {
        _jumpVerticalToChapter(targetChapter, offsetRatio: targetRatio);
      } else {
        if (_pageController.hasClients) {
           _pageController.jumpToPage(_horizontalPageIndex);
        }
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('epub_flow_type', next);
    _scheduleProgressSave();
  }

  Future<void> _setBgColor(int color) async {
    if (!mounted) return;
    setState(() => _bgColor = color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('epub_bg_color', color);
  }

  Future<void> _setTextColor(int color) async {
    if (!mounted) return;
    setState(() => _textColor = color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('epub_text_color', color);
  }

  Future<void> _jumpToChapter(int index) async {
    Navigator.pop(context);
    await _jumpChapterWithoutDrawer(index);
  }



  void _jumpVerticalToChapter(int index, {double offsetRatio = 0.0}) {
    // Try GlobalKey first (accurate, works when item is mounted by ListView)
    final key = _chapterSectionKeys[index];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        alignment: 0.0,
        duration: Duration.zero,
      );
      // Legacy progress records saved offset as an absolute pixel value (> 1.0).
      // We safely ignore them and fallback to the top of the chapter (offsetRatio = 0.0).
      if (offsetRatio > 0 && offsetRatio <= 1.0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_verticalController.hasClients) return;
          final box = key.currentContext?.findRenderObject() as RenderBox?;
          if (box != null && box.attached) {
             final height = box.size.height;
             _verticalController.jumpTo(_verticalController.offset + height * offsetRatio);
          }
        });
      }
      return;
    }
    // Fallback: estimate position using chapter index ratio when item not yet mounted
    if (!_verticalController.hasClients || _book == null) return;
    final chapters = _book!.chapters;
    if (chapters.isEmpty) return;
    
    // Very rough estimate based on chapter index instead of char length to decouple from _fullBookText
    final ratio = index / chapters.length;
    final maxExtent = _verticalController.position.maxScrollExtent;
    _verticalController.jumpTo((ratio * maxExtent).clamp(0.0, maxExtent));
    
    // After ListView builds the item, refine with GlobalKey (retry up to 10 frames)
    int retryCount = 0;
    void tryRefine() {
      if (!mounted) return;
      final newKey = _chapterSectionKeys[index];
      if (newKey?.currentContext != null) {
        Scrollable.ensureVisible(
          newKey!.currentContext!,
          alignment: 0.0,
          duration: Duration.zero,
        );
        // Same check for the fallback route
        if (offsetRatio > 0 && offsetRatio <= 1.0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_verticalController.hasClients) return;
            final box = newKey.currentContext?.findRenderObject() as RenderBox?;
            if (box != null && box.attached) {
               final height = box.size.height;
               _verticalController.jumpTo(_verticalController.offset + height * offsetRatio);
            }
          });
        }
      } else if (retryCount < 10) {
        retryCount++;
        WidgetsBinding.instance.addPostFrameCallback((_) => tryRefine());
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => tryRefine());
  }

  void _pruneChapterSectionKeys(int activeIndex) {
    // Keep keys only for a small window around the active index to prevent memory bloat
    _chapterSectionKeys.removeWhere((key, value) => (key - activeIndex).abs() > 3);
  }



  /// New GlobalKey-based sync for ListView.builder vertical reader.
  /// Finds the chapter whose top edge is closest to (but still above) the
  /// viewport top. Falls back gracefully if no key is mounted yet.
  void _syncChapterFromVerticalKeys() {
    if (_book == null) return;
    int? best;
    double bestTop = double.negativeInfinity;

    for (final entry in _chapterSectionKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final topInViewport = box.localToGlobal(Offset.zero).dy;
      // Find chapter whose top is just above or at the screen top area
      if (topInViewport <= 100 && topInViewport > bestTop) {
        bestTop = topInViewport;
        best = entry.key;
      }
    }

    if (best != null && best != _chapterIndex && mounted) {
      setState(() => _chapterIndex = best!);
      _pruneChapterSectionKeys(_chapterIndex);
    }
  }

  Future<void> _jumpChapterWithoutDrawer(int index) async {
    if (_book == null) return;
    final next = index.clamp(0, _book!.chapters.length - 1);
    
    setState(() {
      _chapterIndex = next;
    });
    
    if (_flowType == 1) {
       _jumpVerticalToChapter(next);
    } else {
       _updateHorizontalWindow(next);
       setState(() {
          _horizontalPageIndex = _pagesBeforeCenter;
       });
       WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageController.hasClients) {
             _pageController.jumpToPage(_pagesBeforeCenter);
          }
       });
    }
    
    await _saveProgress();
  }

  Future<void> _nextChapter() async {
    if (_book == null || _chapterIndex >= _book!.chapters.length - 1) return;
    await _jumpChapterWithoutDrawer(_chapterIndex + 1);
  }

  Future<void> _prevChapter() async {
    if (_book == null || _chapterIndex <= 0) return;
    await _jumpChapterWithoutDrawer(_chapterIndex - 1);
  }

  Future<void> _refreshBookmarkState() async {
    final position = _encodePosition();
    final bookmarks = await DatabaseHelper.instance.getBookmarksForManga(
      _mangaId,
    );
    final bookmarked = bookmarks.any(
      (bookmark) => bookmark.epubCfi == position,
    );
    if (mounted) setState(() => _isCurrentBookmark = bookmarked);
  }

  Future<void> _toggleBookmark() async {
    final position = _encodePosition();
    final bookmarks = await DatabaseHelper.instance.getBookmarksForManga(
      _mangaId,
    );
    final existing = bookmarks.firstWhereOrNull(
      (bookmark) => bookmark.epubCfi == position,
    );
    if (existing != null) {
      await DatabaseHelper.instance.deleteBookmark(existing.id);
      if (mounted) setState(() => _isCurrentBookmark = false);
      return;
    }

    final now = DateTime.now();
    await DatabaseHelper.instance.saveBookmark(
      ReaderBookmark(
        id: '$_mangaId-$_chapterId-${position.hashCode}',
        mangaId: _mangaId,
        chapterId: _chapterId,
        pageIndex: _flowType == 0 ? _pageWithinCurrentChapter() : _chapterIndex,
        scrollOffset: _verticalController.hasClients
            ? _verticalController.offset
            : 0,
        epubCfi: position,
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (mounted) setState(() => _isCurrentBookmark = true);
  }

  Future<void> _loadVoicesForLang(String lang) async {
    try {
      final voices = await _tts.getVoices;
      if (voices == null || !mounted) return;
      final parsed = <Map<String, String>>[];
      for (final voice in voices) {
        if (voice is! Map) continue;
        final locale = voice['locale']?.toString() ?? '';
        final name = voice['name']?.toString() ?? '';
        if (locale.toLowerCase().contains(lang.toLowerCase()) ||
            lang.toLowerCase().contains(locale.toLowerCase())) {
          parsed.add({'name': name, 'locale': locale});
        }
      }
      setState(() {
        _availableVoices = parsed;
        _selectedVoice = parsed.firstOrNull;
      });
      if (_selectedVoice != null) {
        await _tts.setVoice({
          'name': _selectedVoice!['name']!,
          'locale': _selectedVoice!['locale']!,
        });
      }
    } catch (e) {
      debugPrint('TTS getVoices error: $e');
    }
  }

  Future<void> _setTtsVoice(Map<String, String> voice) async {
    setState(() => _selectedVoice = voice);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'tts_book_${_resolvedBookKey}_voice_name_$_ttsLang',
      voice['name']!,
    );
    _scheduleTtsSettingsApply(restartIfPlaying: true);
  }

  Future<void> _setTtsRate(double value) async {
    if (!mounted) return;
    setState(() => _ttsRate = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('tts_book_${_resolvedBookKey}_rate', value);
    _scheduleTtsSettingsApply(restartIfPlaying: true);
  }

  Future<void> _setTtsPitch(double value) async {
    if (!mounted) return;
    setState(() => _ttsPitch = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('tts_book_${_resolvedBookKey}_pitch', value);
    _scheduleTtsSettingsApply(restartIfPlaying: true);
  }

  Future<void> _setTtsLang(String lang) async {
    if (!mounted) return;
    setState(() => _ttsLang = lang);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tts_book_${_resolvedBookKey}_lang', lang);
    await _loadVoicesForLang(lang);
    _scheduleTtsSettingsApply(restartIfPlaying: true);
  }

  void _scheduleTtsSettingsApply({required bool restartIfPlaying}) {
    _ttsSettingsTimer?.cancel();
    _ttsSettingsTimer = Timer(const Duration(milliseconds: 250), () {
      _applyTtsSettings(restartIfPlaying: restartIfPlaying);
    });
  }

  Future<void> _applyTtsSettings({required bool restartIfPlaying}) async {
    final text = _lastTtsText;
    final shouldRestart = restartIfPlaying && _isTtsPlaying && text != null;
    final restartChunkIndex = _ttsChunkIndex;
    if (shouldRestart) {
      _isTtsPlaying = false;
      await _tts.stop();
    }
    await _tts.setLanguage(_ttsLang);
    await _tts.setSpeechRate(_ttsRate);
    await _tts.setPitch(_ttsPitch);
    if (_selectedVoice != null) {
      await _tts.setVoice({
        'name': _selectedVoice!['name']!,
        'locale': _selectedVoice!['locale']!,
      });
    }
    if (shouldRestart && mounted) {
      await _startTts(text, startChunkIndex: restartChunkIndex);
    }
  }

  Future<void> _toggleTts() async {
    if (_isTtsPlaying) {
      await _tts.stop();
      _ttsChunks = [];
      _ttsChunkIndex = 0;
      _isTtsFromSelection = false;
      if (mounted) {
        setState(() => _isTtsPlaying = false);
      }
      return;
    }

    if (_flowType == 0 && _windowPages.isEmpty) return;

    final text = _flowType == 0
        ? _windowPages[_horizontalPageIndex.clamp(
            0,
            _windowPages.length - 1,
          )]
        : _formatChapterText(_currentChapter);
    if (text.trim().isEmpty) return;
    await _startTts(text);
  }

  Future<void> _startTts(String text, {int startChunkIndex = 0}) async {
    final chunks = _splitTtsChunks(text);
    if (chunks.isEmpty) return;
    _lastTtsText = text;
    _ttsChunks = chunks;
    _ttsChunkIndex = startChunkIndex.clamp(0, chunks.length - 1).toInt();
    await _applyTtsSettings(restartIfPlaying: false);
    if (!mounted) return;
    setState(() => _isTtsPlaying = true);
    await _speakCurrentTtsChunk();
  }

  Future<void> _speakCurrentTtsChunk() async {
    if (!_isTtsPlaying || _ttsChunks.isEmpty) return;
    final chunk = _ttsChunks[_ttsChunkIndex].trim();
    if (chunk.isEmpty) {
      await _playNextTtsChunk();
      return;
    }
    await _tts.speak(chunk);
  }

  Future<void> _playNextTtsChunk() async {
    if (!_isTtsPlaying || _ttsChunks.isEmpty) return;
    _ttsChunkIndex++;
    if (_ttsChunkIndex >= _ttsChunks.length) {
      _ttsChunks = [];
      _ttsChunkIndex = 0;
      if (mounted) {
        setState(() => _isTtsPlaying = false);
      }

      if (_isTtsFromSelection && _flowType == 1) {
        _isTtsFromSelection = false;
        final oldChapter = _chapterIndex;
        await _nextChapter();

        if (_chapterIndex != oldChapter) {
          if (mounted) {
            final nextText = _formatChapterText(_currentChapter);
            if (nextText.trim().isNotEmpty) {
              await _startTts(nextText);
            }
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đã đọc hết sách')),
            );
          }
        }
      }
      return;
    }
    await _speakCurrentTtsChunk();
  }

  List<String> _splitTtsChunks(String text) {
    const maxChars = 2800;
    final source = text
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (source.isEmpty) return const [];

    final chunks = <String>[];
    final buffer = StringBuffer();
    final pieces = source.split(RegExp(r'(?<=[.!?。！？…])\s+|\n\s*\n'));
    for (final rawPiece in pieces) {
      final piece = rawPiece.trim();
      if (piece.isEmpty) continue;
      if (piece.length > maxChars) {
        if (buffer.isNotEmpty) {
          chunks.add(buffer.toString().trim());
          buffer.clear();
        }
        for (var i = 0; i < piece.length; i += maxChars) {
          chunks.add(piece.substring(i, min(i + maxChars, piece.length)));
        }
        continue;
      }
      if (buffer.length + piece.length + 1 > maxChars && buffer.isNotEmpty) {
        chunks.add(buffer.toString().trim());
        buffer.clear();
      }
      buffer.writeln(piece);
    }
    if (buffer.toString().trim().isNotEmpty) {
      chunks.add(buffer.toString().trim());
    }
    return chunks;
  }

  Future<void> _startTtsFromSelection(
    String sourceText,
    TextSelection selection,
  ) async {
    if (!selection.isValid || sourceText.isEmpty) return;
    final start = selection.start.clamp(0, sourceText.length);
    if (start >= sourceText.length) return;
    final text = sourceText.substring(start).trim();
    if (text.isEmpty) return;
    _isTtsFromSelection = true;
    await _startTts(text);
  }

  Future<void> _startTtsForSelectionOnly(
    String sourceText,
    TextSelection selection,
  ) async {
    if (!selection.isValid || sourceText.isEmpty) return;
    final start = selection.start.clamp(0, sourceText.length);
    final end = selection.end.clamp(0, sourceText.length);
    if (start >= end) return;
    final text = sourceText.substring(start, end).trim();
    if (text.isEmpty) return;
    _isTtsFromSelection = false;
    await _startTts(text);
  }

  void _setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    setState(() => _sleepTimeMinutes = minutes);
    if (minutes <= 0) return;
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      _tts.stop();
      _ttsChunks = [];
      _ttsChunkIndex = 0;
      if (mounted) {
        setState(() {
          _isTtsPlaying = false;
          _sleepTimeMinutes = 0;
        });
      }
    });
  }

  void _showColorSettings() {
    final bgColors = [
      0xFF1C1C1E,
      0xFFFFFFFF,
      0xFFF4ECD8,
      0xFF000000,
      0xFF112233,
    ];
    final textColors = [
      0xFFFFFFFF,
      0xFF000000,
      0xFF5B4636,
      0xFFDDDDDD,
      0xFFFFD700,
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2C2C2E),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Màu nền', style: TextStyle(color: Colors.white)),
            const SizedBox(height: 12),
            _buildColorRow(bgColors, _bgColor, _setBgColor),
            const SizedBox(height: 24),
            const Text('Màu chữ', style: TextStyle(color: Colors.white)),
            const SizedBox(height: 12),
            _buildColorRow(textColors, _textColor, _setTextColor),
          ],
        ),
      ),
    );
  }

  Widget _buildColorRow(
    List<int> colors,
    int selected,
    Future<void> Function(int) onSelected,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: colors
          .map(
            (color) => GestureDetector(
              onTap: () => onSelected(color),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Color(color),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected == color
                        ? Colors.blueAccent
                        : Colors.white24,
                    width: selected == color ? 3 : 1,
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  void _showReaderSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2C2C2E),
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Cài đặt đọc',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
                Text(
                  'Cỡ chữ $_fontSize',
                  style: const TextStyle(color: Colors.white),
                ),
                Slider(
                  value: _fontSize.toDouble(),
                  min: 12,
                  max: 40,
                  divisions: 14,
                  activeColor: Colors.blueAccent,
                  onChanged: (value) async {
                    await _setFontSize(value.round());
                    setModalState(() {});
                  },
                ),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      icon: Icon(Icons.swap_horiz),
                      label: Text('Ngang'),
                    ),
                    ButtonSegment(
                      value: 1,
                      icon: Icon(Icons.swap_vert),
                      label: Text('Dọc'),
                    ),
                  ],
                  selected: {_flowType},
                  onSelectionChanged: (values) async {
                    await _setFlowType(values.first);
                    setModalState(() {});
                  },
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Màu nền/chữ',
                    style: TextStyle(color: Colors.white),
                  ),
                  leading: const Icon(Icons.palette, color: Colors.white54),
                  onTap: _showColorSettings,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _showTtsPanel,
                  onChanged: (value) {
                    setState(() => _showTtsPanel = value);
                    setModalState(() {});
                  },
                  title: const Text(
                    'Mở bảng TTS',
                    style: TextStyle(color: Colors.white),
                  ),
                  secondary: const Icon(
                    Icons.record_voice_over,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _progressTimer?.cancel();
    _ttsSettingsTimer?.cancel();
    _sleepTimer?.cancel();
    _tts.stop();
    _verticalController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.redAccent)),
      );
    }
    if (_errorMessage != null || _book == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _errorMessage ?? 'Không mở được EPUB',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Color(_bgColor),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2C2C2E),
        title: Text(
          _currentChapter.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book),
            tooltip: 'Mục lục',
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
          IconButton(
            icon: Icon(
              _isCurrentBookmark ? Icons.bookmark : Icons.bookmark_border,
              color: _isCurrentBookmark ? Colors.amber : Colors.white,
            ),
            tooltip: 'Bookmark',
            onPressed: _toggleBookmark,
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Cài đặt',
            onPressed: _showReaderSettings,
          ),
        ],
      ),
      endDrawer: _buildTocDrawer(),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: _showTtsPanel ? 220 : 72),
        child: FloatingActionButton.small(
          heroTag: 'epub-reader-settings-${widget.storageKey}',
          backgroundColor: const Color(0xFF2C2C2E),
          foregroundColor: Colors.white,
          onPressed: _showReaderSettings,
          child: const Icon(Icons.tune),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _flowType == 1
                ? _buildVerticalReader()
                : _buildHorizontalReader(),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: _buildTtsBar()),
        ],
      ),
    );
  }

  Widget _buildTocDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF1C1C1E),
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Mục lục',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _book!.chapters.length,
                itemBuilder: (context, index) {
                  final chapter = _book!.chapters[index];
                  return ListTile(
                    selected: index == _chapterIndex,
                    selectedTileColor: Colors.white10,
                    title: Text(
                      chapter.title,
                      style: TextStyle(
                        color: index == _chapterIndex
                            ? Colors.white
                            : Colors.white70,
                      ),
                    ),
                    onTap: () => _jumpToChapter(index),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalReader() {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification ||
            notification is ScrollEndNotification) {
          _syncChapterFromVerticalKeys();
          _scheduleProgressSave();
        }
        return false;
      },
      child: ListView.builder(
        controller: _verticalController,
        padding: EdgeInsets.fromLTRB(22, 24, 22, _showTtsPanel ? 270 : 110),
        itemCount: _book?.chapters.length ?? 0,
        itemBuilder: (context, index) {
          final isNear = (index - _chapterIndex).abs() <= 3;
          if (!isNear) {
            _chapterSectionKeys.remove(index);
          } else {
            _chapterSectionKeys[index] ??= GlobalKey();
          }
          final chapterText = _formatChapterText(_book!.chapters[index]);
          return Container(
            key: isNear ? _chapterSectionKeys[index] : null,
            padding: const EdgeInsets.only(bottom: 48),
            child: SelectableText(
              chapterText,
              style: TextStyle(
                color: Color(_textColor),
                fontSize: _fontSize.toDouble(),
                height: 1.65,
              ),
              contextMenuBuilder: (context, editableTextState) {
                final buttonItems =
                    editableTextState.contextMenuButtonItems;
                final text = editableTextState.textEditingValue.text;
                final selection =
                    editableTextState.textEditingValue.selection;

                buttonItems.insert(0, ContextMenuButtonItem(
                  label: 'Đọc từ đây',
                  onPressed: () {
                    ContextMenuController.removeAny();
                    _startTtsFromSelection(text, selection);
                  },
                ));
                buttonItems.insert(1, ContextMenuButtonItem(
                  label: 'Đọc đoạn này',
                  onPressed: () {
                    ContextMenuController.removeAny();
                    _startTtsForSelectionOnly(text, selection);
                  },
                ));

                return AdaptiveTextSelectionToolbar.buttonItems(
                  anchors: editableTextState.contextMenuAnchors,
                  buttonItems: buttonItems,
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildHorizontalReader() {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification) {
          if (_chapterIndex != _windowCenterChapter) {
            // Shift the window!
            final centerPages = _getPagesForChapter(_windowCenterChapter);
            int pageWithinChapter = 0;
            if (_chapterIndex < _windowCenterChapter) {
              pageWithinChapter = _horizontalPageIndex; // We are in prev chapter
            } else {
              pageWithinChapter = _horizontalPageIndex - (_pagesBeforeCenter + centerPages.length);
            }
            
            _updateHorizontalWindow(_chapterIndex);
            final newIndex = (_pagesBeforeCenter + pageWithinChapter).clamp(0, max(0, _windowPages.length - 1)).toInt();
            setState(() => _horizontalPageIndex = newIndex);
            WidgetsBinding.instance.addPostFrameCallback((_) {
               if (mounted && _pageController.hasClients) {
                  _pageController.jumpToPage(newIndex);
               }
            });
          }
        }
        return false;
      },
      child: PageView.builder(
        controller: _pageController,
        itemCount: _windowPages.length,
        onPageChanged: (index) {
          setState(() => _horizontalPageIndex = index);
          
          if (_windowPages.isNotEmpty) {
             if (index < _pagesBeforeCenter) {
                final prevChapter = _windowCenterChapter - 1;
                if (prevChapter >= 0 && mounted) {
                   setState(() => _chapterIndex = prevChapter);
                }
             } else {
                final centerPages = _getPagesForChapter(_windowCenterChapter);
                if (index >= _pagesBeforeCenter + centerPages.length) {
                   final nextChapter = _windowCenterChapter + 1;
                   if (nextChapter < _book!.chapters.length && mounted) {
                      setState(() => _chapterIndex = nextChapter);
                   }
                } else {
                   if (mounted && _chapterIndex != _windowCenterChapter) {
                      setState(() => _chapterIndex = _windowCenterChapter);
                   }
                }
             }
          }
          _scheduleProgressSave();
        },
        itemBuilder: (context, index) {
          return Padding(
            padding: EdgeInsets.fromLTRB(22, 24, 22, _showTtsPanel ? 270 : 110),
            child: SingleChildScrollView(
              child: SelectableText(
                _windowPages[index],
              style: TextStyle(
                color: Color(_textColor),
                fontSize: _fontSize.toDouble(),
                height: 1.65,
              ),
              contextMenuBuilder: (context, editableTextState) {
                final buttonItems = editableTextState.contextMenuButtonItems;
                final text = editableTextState.textEditingValue.text;
                final selection = editableTextState.textEditingValue.selection;

                buttonItems.insert(0, ContextMenuButtonItem(
                  label: 'Đọc từ đây',
                  onPressed: () {
                    ContextMenuController.removeAny();
                    _startTtsFromSelection(text, selection);
                  },
                ));
                buttonItems.insert(1, ContextMenuButtonItem(
                  label: 'Đọc đoạn này',
                  onPressed: () {
                    ContextMenuController.removeAny();
                    _startTtsForSelectionOnly(text, selection);
                  },
                ));

                return AdaptiveTextSelectionToolbar.buttonItems(
                  anchors: editableTextState.contextMenuAnchors,
                  buttonItems: buttonItems,
                );
              },
            ),
          ),
        );
      },
      ),
    );
  }

  Widget _buildTtsSlider({
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.white54),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: color,
          inactiveColor: Colors.white12,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildTtsBar() {
    final selectedVoice = _selectedVoice == null
        ? null
        : _availableVoices.firstWhereOrNull(
            (voice) =>
                voice['name'] == _selectedVoice!['name'] &&
                voice['locale'] == _selectedVoice!['locale'],
          );

    if (!_showTtsPanel) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: _flowType == 1 ? 'Cuộn dọc' : 'Vuốt ngang',
                      icon: Icon(
                        _flowType == 1 ? Icons.swap_vert : Icons.swap_horiz,
                        color: Colors.white,
                      ),
                      onPressed: () => _setFlowType(_flowType == 1 ? 0 : 1),
                    ),
                    IconButton(
                      tooltip: 'Chương trước',
                      icon: const Icon(Icons.chevron_left, color: Colors.white),
                      onPressed: _prevChapter,
                    ),
                    _TtsButton(
                      icon: _isTtsPlaying
                          ? Icons.stop_rounded
                          : Icons.volume_up_rounded,
                      label: _isTtsPlaying ? 'Dừng' : 'Đọc',
                      color: _isTtsPlaying
                          ? Colors.redAccent
                          : Colors.blueAccent,
                      onTap: _toggleTts,
                    ),
                    IconButton(
                      tooltip: 'Chương sau',
                      icon: const Icon(
                        Icons.chevron_right,
                        color: Colors.white,
                      ),
                      onPressed: _nextChapter,
                    ),
                    IconButton(
                      tooltip: 'Mở TTS',
                      icon: const Icon(
                        Icons.keyboard_arrow_up,
                        color: Colors.white,
                      ),
                      onPressed: () => setState(() => _showTtsPanel = true),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _showTtsPanel = false),
              child: const Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Icon(Icons.keyboard_arrow_down, color: Colors.white54),
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    _flowType == 1 ? Icons.swap_vert : Icons.swap_horiz,
                    color: Colors.white,
                  ),
                  onPressed: () => _setFlowType(_flowType == 1 ? 0 : 1),
                ),
                _TtsButton(
                  icon: _isTtsPlaying
                      ? Icons.stop_rounded
                      : Icons.volume_up_rounded,
                  label: _isTtsPlaying ? 'Dừng' : 'Đọc',
                  color: _isTtsPlaying ? Colors.redAccent : Colors.blueAccent,
                  onTap: _toggleTts,
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: 'Ngôn ngữ',
                  icon: const Icon(Icons.language, color: Colors.white54),
                  color: const Color(0xFF3A3A3C),
                  onSelected: _setTtsLang,
                  itemBuilder: (_) => _supportedLangs
                      .map(
                        (entry) => PopupMenuItem<String>(
                          value: entry.$1,
                          child: Row(
                            children: [
                              Text(entry.$2),
                              if (_ttsLang == entry.$1) ...const [
                                SizedBox(width: 8),
                                Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.blueAccent,
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
            _buildTtsSlider(
              icon: Icons.speed,
              label: 'Tốc độ: ${_ttsRate.toStringAsFixed(1)}x',
              value: _ttsRate,
              min: 0.2,
              max: 1.0,
              divisions: 8,
              color: Colors.blueAccent,
              onChanged: _setTtsRate,
            ),
            _buildTtsSlider(
              icon: Icons.music_note,
              label: 'Cao độ: ${_ttsPitch.toStringAsFixed(1)}',
              value: _ttsPitch,
              min: 0.5,
              max: 2.0,
              divisions: 15,
              color: Colors.purpleAccent,
              onChanged: _setTtsPitch,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<Map<String, String>>(
                      isExpanded: true,
                      dropdownColor: const Color(0xFF3A3A3C),
                      value: selectedVoice,
                      hint: const Text(
                        'Chọn giọng',
                        style: TextStyle(color: Colors.white54),
                      ),
                      items: _availableVoices
                          .map(
                            (voice) => DropdownMenuItem<Map<String, String>>(
                              value: voice,
                              child: Text(
                                voice['name'] ?? 'Giọng mặc định',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (voice) {
                        if (voice != null) _setTtsVoice(voice);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PopupMenuButton<int>(
                    tooltip: 'Hẹn giờ tắt',
                    color: const Color(0xFF3A3A3C),
                    onSelected: _setSleepTimer,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 0, child: Text('Không hẹn giờ')),
                      PopupMenuItem(value: 15, child: Text('15 phút')),
                      PopupMenuItem(value: 30, child: Text('30 phút')),
                      PopupMenuItem(value: 60, child: Text('60 phút')),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3A3A3C),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _sleepTimeMinutes > 0 ? '$_sleepTimeMinutes p' : 'Tắt',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ParsedEpub {
  final String title;
  final List<_EpubChapter> chapters;

  const _ParsedEpub({required this.title, required this.chapters});
}

class _EpubChapter {
  final String title;
  final String text;

  const _EpubChapter({required this.title, required this.text});
}

class _ManifestItem {
  final String id;
  final String href;
  final String mediaType;

  const _ManifestItem({
    required this.id,
    required this.href,
    required this.mediaType,
  });
}

class _TtsButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _TtsButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
