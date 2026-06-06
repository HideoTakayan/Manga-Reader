import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'epub/epub_models.dart';
import 'epub/epub_parser.dart';
import 'epub/epub_paginator.dart';
import 'epub/epub_lazy_chapter_loader.dart';

import '../../data/database_helper.dart';
import '../../data/models.dart';

class NovelReaderWidget extends StatefulWidget {
  final Uint8List epubBytes;
  final String title;
  final String storageKey;
  final String? realMangaId;
  final String? realChapterId;

  const NovelReaderWidget({
    super.key,
    required this.epubBytes,
    required this.title,
    String? storageKey,
    this.realMangaId,
    this.realChapterId,
  }) : storageKey = storageKey ?? title;

  @override
  State<NovelReaderWidget> createState() => _NovelReaderWidgetState();
}

class _NovelReaderWidgetState extends State<NovelReaderWidget> {
  static const _supportedFontFamilies = {'Default', 'serif', 'monospace'};
  static const _lazyLoadingThresholdBytes = 8 * 1024 * 1024;

  final _tts = FlutterTts();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _verticalViewportKey = GlobalKey();
  final _verticalItemController = ItemScrollController();
  final _verticalOffsetController = ScrollOffsetController();
  final _verticalPositionsListener = ItemPositionsListener.create();
  int _verticalJumpGeneration = 0;
  final _pageController = PageController();
  final Map<int, GlobalKey> _chapterSectionKeys = {};
  Offset? _readerPointerStart;
  DateTime? _readerPointerStartTime;

  ParsedEpub? _book;
  EpubLazyChapterLoader? _lazyChapterLoader;
  bool _isLoading = true;
  String? _errorMessage;
  int _chapterIndex = 0;
  int _horizontalPageIndex = 0;
  int _fontSize = 18;
  int _bgColor = 0xFF1C1C1E;
  int _textColor = 0xFFFFFFFF;
  int _flowType = 0; // 0: horizontal pages, 1: vertical scroll
  double _lineHeight = 1.65;
  double _pageHorizontalPadding = 22;
  String _fontFamily = 'Default';
  Size? _viewportSize;

  bool _showTtsPanel = false;
  bool _showControls = true;
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
  Timer? _bookSearchTimer;
  int _searchSessionId = 0;
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
  double get _horizontalBlockSpacing => _fontSize.toDouble() * _lineHeight;

  int get _chapterCount => _book?.chapters.length ?? 0;

  EpubChapter _chapterAt(int chapterIndex) {
    final index = chapterIndex.clamp(0, _chapterCount - 1);
    return _lazyChapterLoader?.peek(index) ?? _book!.chapters[index];
  }

  EpubChapter get _currentChapter => _chapterAt(_chapterIndex);

  double get _readerBottomPadding => 24;

  double get _floatingActionBottomPadding {
    return _showTtsPanel ? 220 : 72;
  }

  // --- Phase 2: Horizontal Window State ---
  int _windowCenterChapter = -1;
  List<EpubPage> _windowPages = [];
  int _pagesBeforeCenter = 0;
  final Map<int, List<EpubPage>> _chapterPagesCache = {};

  List<EpubPage> _getPagesForChapter(int chapterIndex) {
    if (_book == null ||
        chapterIndex < 0 ||
        chapterIndex >= _book!.chapters.length) {
      return [];
    }
    if (_chapterPagesCache.containsKey(chapterIndex)) {
      return _chapterPagesCache[chapterIndex]!;
    }

    final chapter = _chapterAt(chapterIndex);

    if (_viewportSize == null) {
      // If layout hasn't built yet, we can't paginate accurately.
      // Return a temporary page. LayoutBuilder will trigger a real update.
      return const [EpubPage(blocks: [])];
    }

    final availableWidth = _viewportSize!.width - (_pageHorizontalPadding * 2);
    final availableHeight = _viewportSize!.height - 24 - _readerBottomPadding;
    final paddedViewport = Size(
      max(1, availableWidth),
      max(1, availableHeight),
    );

    final textStyle = TextStyle(
      color: Color(_textColor),
      fontSize: _fontSize.toDouble(),
      height: _lineHeight,
      fontFamily: _fontFamily == 'Default' ? null : _fontFamily,
    );

    final pages = EpubPaginator.paginate(
      chapter: chapter,
      viewportSize: paddedViewport,
      baseTextStyle: textStyle,
      blockSpacing: _horizontalBlockSpacing,
    );

    _chapterPagesCache[chapterIndex] = pages;
    return pages;
  }

  void _pruneChapterPagesCache(int centerChapter) {
    _chapterPagesCache.removeWhere(
      (chapterIndex, _) => (chapterIndex - centerChapter).abs() > 2,
    );
  }

  void _updateHorizontalWindow(int centerChapter) {
    if (_book == null) return;

    final chapters = _book!.chapters;
    final int prev = centerChapter - 1;
    final int next = centerChapter + 1;

    final List<EpubPage> newPages = [];
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
    _pruneChapterPagesCache(centerChapter);
  }

  Future<void> _loadLazyWindow(int centerChapter) async {
    final loader = _lazyChapterLoader;
    if (loader == null) return;
    await loader.preloadAround(centerChapter);
    loader.retainAround(centerChapter);
    _chapterPagesCache.removeWhere(
      (chapterIndex, _) => loader.peek(chapterIndex) == null,
    );
  }

  Future<EpubChapter> _loadChapter(int chapterIndex) async {
    final loader = _lazyChapterLoader;
    if (loader == null) return _book!.chapters[chapterIndex];
    final cached = loader.peek(chapterIndex);
    if (cached != null) return cached;
    final chapter = await loader.load(chapterIndex);
    if (mounted) {
      setState(() => _chapterPagesCache.remove(chapterIndex));
    }
    return chapter;
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
      _lineHeight = prefs.getDouble('epub_line_height') ?? 1.65;
      _pageHorizontalPadding =
          prefs.getDouble('epub_page_horizontal_padding') ?? 22;
      final savedFontFamily = prefs.getString('epub_font_family') ?? 'Default';
      _fontFamily = _supportedFontFamilies.contains(savedFontFamily)
          ? savedFontFamily
          : 'Default';
      await _loadTtsSettings(prefs);

      late final ParsedEpub book;
      if (widget.epubBytes.length >= _lazyLoadingThresholdBytes) {
        final index = await compute(
          EpubParser.parseIndex,
          EpubParseArgs(bytes: widget.epubBytes, title: widget.title),
        );
        final loader = EpubLazyChapterLoader(
          index: index,
          bytes: widget.epubBytes,
        );
        book = ParsedEpub(
          title: index.title,
          chapters: [
            for (final chapter in index.chapters)
              EpubChapter(
                title: chapter.title,
                blocks: [
                  EpubBlock.plainText(
                    type: EpubBlockType.heading,
                    text: chapter.title,
                  ),
                ],
              ),
          ],
        );
        _lazyChapterLoader = loader;
      } else {
        book = await compute(
          EpubParser.parse,
          EpubParseArgs(bytes: widget.epubBytes, title: widget.title),
        );
      }
      final saved = await _loadSavedPosition(prefs, book.chapters.length);
      await _loadLazyWindow(saved.$1);
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
      await _saveProgress();
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
    _bookSearchTimer?.cancel();
    _tts.stop();
    if (_verticalItemController.isAttached) {
      _verticalItemController.jumpTo(index: 0);
    }
    _lastTtsText = null;
    _ttsChunks = [];
    _ttsChunkIndex = 0;
    _book = null;
    _lazyChapterLoader?.clear();
    _lazyChapterLoader = null;
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
        final viewportBox =
            _verticalViewportKey.currentContext?.findRenderObject()
                as RenderBox?;
        if (box != null &&
            viewportBox != null &&
            box.attached &&
            viewportBox.attached) {
          final chapterTop = box.localToGlobal(Offset.zero).dy;
          final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
          final topInViewport = chapterTop - viewportTop;
          final height = box.size.height;
          if (height > 0) {
            ratio = (max(0.0, -topInViewport) / height).clamp(0.0, 1.0);
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
    final pageWithinChapter = parts.length == 3
        ? (int.tryParse(parts[1]) ?? 0)
        : 0;
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
    await DatabaseHelper.instance.saveReadingActivity(
      ReadingActivity.create(
        userId: FirebaseAuth.instance.currentUser?.uid ?? 'guest',
        mangaId: _mangaId,
        chapterId: _chapterId,
        chapterTitle:
            _book != null &&
                _chapterIndex >= 0 &&
                _chapterIndex < _book!.chapters.length
            ? _book!.chapters[_chapterIndex].title
            : null,
        pageIndex: _chapterIndex,
        totalPages: _book?.chapters.length ?? 1,
        progressPercent: _book == null || _book!.chapters.isEmpty
            ? 0
            : _chapterIndex /
                  max<double>(1, (_book!.chapters.length - 1).toDouble()),
      ),
    );

    if (widget.realMangaId != null && widget.realChapterId != null) {
      final userId = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
      final chapterTitle = _book != null && _chapterIndex >= 0 && _chapterIndex < _book!.chapters.length
          ? _book!.chapters[_chapterIndex].title
          : widget.title;
      final history = ReadingHistory(
        userId: userId,
        mangaId: widget.realMangaId!,
        chapterId: widget.realChapterId!,
        chapterTitle: chapterTitle,
        lastPageIndex: 0,
        totalPages: _book?.chapters.length ?? 1,
        updatedAt: DateTime.now(),
      );
      await DatabaseHelper.instance.saveHistory(history);
    }

    await _refreshBookmarkState();
  }

  void _repaginate(void Function() configChange) {
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
      configChange();
      if (_flowType == 0) {
        _chapterPagesCache.clear();
        _updateHorizontalWindow(_chapterIndex);
        final newCenterPagesCount = _getPagesForChapter(_chapterIndex).length;
        final newPageWithinChapter = (progressRatio * newCenterPagesCount)
            .floor()
            .clamp(0, max(0, newCenterPagesCount - 1))
            .toInt();
        _horizontalPageIndex = _pagesBeforeCenter + newPageWithinChapter;
      }
    });

    if (_flowType == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(_horizontalPageIndex);
        }
      });
    }
  }

  void _toggleControls() {
    if (!mounted) return;
    setState(() => _showControls = !_showControls);
  }

  void _handleReaderPointerDown(PointerDownEvent event) {
    _readerPointerStart = event.position;
    _readerPointerStartTime = DateTime.now();
  }

  void _handleReaderPointerUp(PointerUpEvent event) {
    final start = _readerPointerStart;
    final startTime = _readerPointerStartTime;
    _readerPointerStart = null;
    _readerPointerStartTime = null;
    if (start == null || startTime == null) return;

    final moved = (event.position - start).distance;
    final elapsed = DateTime.now().difference(startTime);
    if (moved <= 18 && elapsed <= const Duration(milliseconds: 450)) {
      _toggleControls();
    }
  }

  void _handleReaderPointerCancel(PointerCancelEvent event) {
    _readerPointerStart = null;
    _readerPointerStartTime = null;
  }

  Future<void> _setFontSize(int value) async {
    final next = value.clamp(12, 40);
    if (!mounted) return;
    _repaginate(() => _fontSize = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('epub_font_size', next);
    _scheduleProgressSave();
  }

  Future<void> _setLineHeight(double value) async {
    if (!mounted) return;
    _repaginate(() => _lineHeight = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('epub_line_height', value);
  }

  Future<void> _setPageHorizontalPadding(double value) async {
    if (!mounted) return;
    _repaginate(() => _pageHorizontalPadding = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('epub_page_horizontal_padding', value);
  }

  Future<void> _setFontFamily(String family) async {
    if (!mounted) return;
    _repaginate(() => _fontFamily = family);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('epub_font_family', family);
  }

  /// Apply a preset theme (bg + text color pair).
  Future<void> _applyThemePreset(int bg, int text) async {
    if (!mounted) return;
    setState(() {
      _bgColor = bg;
      _textColor = text;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('epub_bg_color', bg);
    await prefs.setInt('epub_text_color', text);
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
      targetRatio = parts.length == 3
          ? (double.tryParse(parts[2]) ?? 0.0)
          : 0.0;
    } else if (_flowType == 0 && next == 1) {
      // Horizontal -> Vertical: calculate horizontal ratio
      final centerPagesCount = _getPagesForChapter(targetChapter).length;
      if (centerPagesCount > 0) {
        targetRatio = _pageWithinCurrentChapter() / centerPagesCount;
      }
    }

    if (next == 0) {
      await _loadLazyWindow(targetChapter);
      _updateHorizontalWindow(targetChapter);
    }

    setState(() {
      _flowType = next;
      if (next == 0) {
        final centerPagesCount = _getPagesForChapter(targetChapter).length;
        final newPageWithinChapter = (targetRatio * centerPagesCount)
            .floor()
            .clamp(0, max(0, centerPagesCount - 1))
            .toInt();
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
    final generation = ++_verticalJumpGeneration;
    final safeRatio = offsetRatio.clamp(0.0, 1.0);

    Future<void> restorePosition() async {
      for (var retry = 0; retry < 12; retry++) {
        if (!mounted || generation != _verticalJumpGeneration) return;
        if (_verticalItemController.isAttached) {
          _verticalItemController.jumpTo(index: index, alignment: 0);
          break;
        }
        await WidgetsBinding.instance.endOfFrame;
      }

      if (safeRatio <= 0) return;

      const settleDelays = [
        Duration.zero,
        Duration(milliseconds: 80),
        Duration(milliseconds: 250),
        Duration(milliseconds: 700),
        Duration(milliseconds: 1500),
      ];
      for (final delay in settleDelays) {
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        if (!mounted || generation != _verticalJumpGeneration) return;
        await WidgetsBinding.instance.endOfFrame;

        final context = _chapterSectionKeys[index]?.currentContext;
        final box = context?.findRenderObject() as RenderBox?;
        final viewportBox =
            _verticalViewportKey.currentContext?.findRenderObject()
                as RenderBox?;
        if (box == null ||
            viewportBox == null ||
            !box.attached ||
            !viewportBox.attached ||
            box.size.height <= 0) {
          continue;
        }

        final currentGlobalTop = box.localToGlobal(Offset.zero).dy;
        final viewportGlobalTop = viewportBox.localToGlobal(Offset.zero).dy;
        final currentViewportTop = currentGlobalTop - viewportGlobalTop;
        final desiredViewportTop = -(box.size.height * safeRatio);
        final correction = currentViewportTop - desiredViewportTop;
        if (correction.abs() <= 1) continue;

        try {
          await _verticalOffsetController.animateScroll(
            offset: correction,
            duration: const Duration(milliseconds: 1),
          );
        } catch (_) {
          // The list may detach while switching reader modes or closing.
        }
      }
    }

    unawaited(restorePosition());
  }

  void _pruneChapterSectionKeys(int activeIndex) {
    // Keep keys only for a small window around the active index to prevent memory bloat
    _chapterSectionKeys.removeWhere(
      (key, value) => (key - activeIndex).abs() > 3,
    );
  }

  /// Tracks the chapter currently crossing the top of the viewport.
  void _syncChapterFromVerticalKeys() {
    if (_book == null) return;
    final positions = _verticalPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    final visible = positions.where(
      (position) => position.itemTrailingEdge > 0,
    );
    if (visible.isEmpty) return;
    final crossingTop = visible.where(
      (position) => position.itemLeadingEdge <= 0,
    );
    final best = crossingTop.isNotEmpty
        ? crossingTop.reduce(
            (current, candidate) =>
                candidate.itemLeadingEdge > current.itemLeadingEdge
                ? candidate
                : current,
          )
        : visible.reduce(
            (current, candidate) =>
                candidate.itemLeadingEdge < current.itemLeadingEdge
                ? candidate
                : current,
          );

    if (best.index != _chapterIndex && mounted) {
      setState(() => _chapterIndex = best.index);
      _pruneChapterSectionKeys(_chapterIndex);
    }
  }

  Future<void> _jumpChapterWithoutDrawer(
    int index, {
    int pageWithinChapter = 0,
    double verticalOffsetRatio = 0,
  }) async {
    if (_book == null) return;
    final next = index.clamp(0, _book!.chapters.length - 1);

    if (_flowType == 0) {
      try {
        await _loadLazyWindow(next);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Lỗi tải chương, vui lòng thử lại'),
              action: SnackBarAction(
                label: 'Thử lại',
                onPressed: () => _jumpChapterWithoutDrawer(
                  index,
                  pageWithinChapter: pageWithinChapter,
                  verticalOffsetRatio: verticalOffsetRatio,
                ),
              ),
            ),
          );
        }
        return;
      }
    }

    setState(() {
      _chapterIndex = next;
    });

    if (_flowType == 1) {
      _jumpVerticalToChapter(next, offsetRatio: verticalOffsetRatio);
    } else {
      _updateHorizontalWindow(next);
      final chapterPages = _getPagesForChapter(next);
      final targetPage = pageWithinChapter
          .clamp(0, max(0, chapterPages.length - 1))
          .toInt();
      setState(() {
        _horizontalPageIndex = _pagesBeforeCenter + targetPage;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(_horizontalPageIndex);
        }
      });
    }

    await _saveProgress();
  }

  Future<void> _jumpToEncodedPosition(String? position) async {
    final parsed = _decodePosition(position);
    if (parsed == null) return;
    await _jumpChapterWithoutDrawer(
      parsed.$1,
      pageWithinChapter: parsed.$2,
      verticalOffsetRatio: parsed.$3,
    );
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
        scrollOffset: 0,
        epubCfi: position,
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (mounted) setState(() => _isCurrentBookmark = true);
  }

  String _chapterPreview(EpubChapter chapter, {int maxLength = 110}) {
    final text = EpubParser.formatChapterText(
      chapter,
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength).trimRight()}...';
  }

  Future<void> _showBookmarks() async {
    final bookmarks = await DatabaseHelper.instance.getBookmarksForManga(
      _mangaId,
    );
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF2C2C2E),
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.68,
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.bookmarks, color: Colors.amber),
                title: Text(
                  'Danh sách bookmark',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: bookmarks.isEmpty
                    ? const Center(
                        child: Text(
                          'Chưa có bookmark nào',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : ListView.separated(
                        itemCount: bookmarks.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: Colors.white12),
                        itemBuilder: (context, index) {
                          final bookmark = bookmarks[index];
                          final parsed = _decodePosition(bookmark.epubCfi);
                          final chapterIndex = parsed?.$1.clamp(
                            0,
                            _book!.chapters.length - 1,
                          );
                          final chapter = chapterIndex == null
                              ? null
                              : _chapterAt(chapterIndex);
                          return ListTile(
                            leading: const Icon(
                              Icons.bookmark,
                              color: Colors.amber,
                            ),
                            title: Text(
                              chapter?.title ?? 'Vị trí đã lưu',
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              chapter == null
                                  ? 'Không xác định được chương'
                                  : _chapterPreview(chapter),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white60),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              unawaited(
                                _jumpToEncodedPosition(bookmark.epubCfi),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showBookSearch() async {
    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF2C2C2E),
      isScrollControlled: true,
      builder: (context) {
        var results = <int>[];
        var resultChapters = <int, EpubChapter>{};
        var isSearching = false;
        return StatefulBuilder(
          builder: (context, setModalState) => SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.72,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Tìm trong sách',
                          hintStyle: TextStyle(color: Colors.white54),
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (query) {
                          final normalized = query.trim().toLowerCase();
                          _bookSearchTimer?.cancel();
                          _searchSessionId++;
                          final currentSessionId = _searchSessionId;

                          if (normalized.isEmpty) {
                            setModalState(() {
                              results = [];
                              resultChapters = {};
                              isSearching = false;
                            });
                            return;
                          }
                          setModalState(() => isSearching = true);
                          _bookSearchTimer = Timer(
                            const Duration(milliseconds: 350),
                            () async {
                              final matches = await _searchChapters(
                                normalized,
                                currentSessionId,
                              );
                              if (!context.mounted ||
                                  currentSessionId != _searchSessionId) {
                                return;
                              }
                              setModalState(() {
                                resultChapters = matches;
                                results = matches.keys.toList();
                                isSearching = false;
                              });
                            },
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: isSearching
                          ? const Center(child: CircularProgressIndicator())
                          : results.isEmpty
                          ? Center(
                              child: Text(
                                controller.text.trim().isEmpty
                                    ? 'Nhập từ khóa để tìm kiếm'
                                    : 'Không tìm thấy nội dung phù hợp',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            )
                          : ListView.separated(
                              itemCount: results.length,
                              separatorBuilder: (_, _) => const Divider(
                                height: 1,
                                color: Colors.white12,
                              ),
                              itemBuilder: (context, index) {
                                final chapterIndex = results[index];
                                final chapter =
                                    resultChapters[chapterIndex] ??
                                    _chapterAt(chapterIndex);
                                return ListTile(
                                  leading: const Icon(
                                    Icons.menu_book,
                                    color: Colors.white70,
                                  ),
                                  title: Text(
                                    chapter.title,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  subtitle: Text(
                                    _chapterPreview(chapter),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white60,
                                    ),
                                  ),
                                  onTap: () {
                                    Navigator.pop(context);
                                    unawaited(
                                      _jumpChapterWithoutDrawer(chapterIndex),
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    _bookSearchTimer?.cancel();
    _searchSessionId++;
    controller.dispose();
  }

  Future<Map<int, EpubChapter>> _searchChapters(
    String normalizedQuery,
    int sessionId,
  ) async {
    final matches = <int, EpubChapter>{};
    final loader = _lazyChapterLoader;
    for (var index = 0; index < _chapterCount; index++) {
      if (sessionId != _searchSessionId) return matches;
      final chapter = loader == null
          ? _book!.chapters[index]
          : await loader.load(index);
      if (sessionId != _searchSessionId) return matches;
      if (EpubParser.formatChapterText(
        chapter,
      ).toLowerCase().contains(normalizedQuery)) {
        matches[index] = chapter;
      }
    }
    loader?.retainAround(_chapterIndex);
    return matches;
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
        ? _windowPages[_horizontalPageIndex.clamp(0, _windowPages.length - 1)]
              .text
        : EpubParser.formatChapterText(_currentChapter);
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
            final nextText = EpubParser.formatChapterText(_currentChapter);
            if (nextText.trim().isNotEmpty) {
              await _startTts(nextText);
            }
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Đã đọc hết sách')));
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
    final pieces = source.split(RegExp(r'(?<=[.!?…。！？])\s+|\n\s*\n'));
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
    const fontFamilies = [
      (label: 'Mặc định', family: 'Default'),
      (label: 'Serif', family: 'serif'),
      (label: 'Monospace', family: 'monospace'),
    ];
    const themePresets = [
      (label: 'Tối', bg: 0xFF1C1C1E, text: 0xFFFFFFFF),
      (label: 'Sáng', bg: 0xFFFFFFFF, text: 0xFF1C1C1E),
      (label: 'Sepia', bg: 0xFFF4ECD8, text: 0xFF5B4636),
      (label: 'Đêm', bg: 0xFF000000, text: 0xFFDDDDDD),
      (label: 'Biển', bg: 0xFF112233, text: 0xFFFFD700),
    ];

    final totalChapters = _book?.chapters.length ?? 1;
    final progressPercent = totalChapters <= 1
        ? 0.0
        : _chapterIndex / (totalChapters - 1);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2C2C2E),
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          top: false,
          child: SingleChildScrollView(
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
                // Progress indicator
                Row(
                  children: [
                    const Icon(
                      Icons.menu_book,
                      size: 14,
                      color: Colors.white54,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Chương ${_chapterIndex + 1}/$totalChapters  •  ${(progressPercent * 100).round()}%',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: progressPercent,
                  backgroundColor: Colors.white12,
                  color: Colors.blueAccent,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                ),
                const SizedBox(height: 16),
                // Font size
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
                // Line height
                Text(
                  'Dãn dòng ${_lineHeight.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white),
                ),
                Slider(
                  value: _lineHeight,
                  min: 1.2,
                  max: 2.5,
                  divisions: 13,
                  activeColor: Colors.blueAccent,
                  onChanged: (value) async {
                    await _setLineHeight(
                      double.parse(value.toStringAsFixed(2)),
                    );
                    setModalState(() {});
                  },
                ),
                Text(
                  'Lề ngang ${_pageHorizontalPadding.round()}',
                  style: const TextStyle(color: Colors.white),
                ),
                Slider(
                  value: _pageHorizontalPadding,
                  min: 12,
                  max: 48,
                  divisions: 12,
                  activeColor: Colors.blueAccent,
                  onChanged: (value) async {
                    await _setPageHorizontalPadding(value);
                    setModalState(() {});
                  },
                ),
                const SizedBox(height: 4),
                // Font family
                const Text('Font chữ', style: TextStyle(color: Colors.white)),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: fontFamilies.map((option) {
                      final selected = _fontFamily == option.family;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () async {
                            await _setFontFamily(option.family);
                            setModalState(() {});
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? Colors.blueAccent
                                  : const Color(0xFF3A3A3C),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: selected
                                    ? Colors.blueAccent
                                    : Colors.white24,
                              ),
                            ),
                            child: Text(
                              option.label,
                              style: TextStyle(
                                color: selected ? Colors.white : Colors.white70,
                                fontSize: 13,
                                fontFamily: option.family == 'Default'
                                    ? null
                                    : option.family,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                // Flow type
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
                const SizedBox(height: 16),
                // Theme presets
                const Text(
                  'Theme nhanh',
                  style: TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: themePresets.map((preset) {
                      final active =
                          _bgColor == preset.bg && _textColor == preset.text;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () async {
                            await _applyThemePreset(preset.bg, preset.text);
                            setModalState(() {});
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Color(preset.bg),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: active
                                    ? Colors.blueAccent
                                    : Colors.white24,
                                width: active ? 2 : 1,
                              ),
                            ),
                            child: Text(
                              preset.label,
                              style: TextStyle(
                                color: Color(preset.text),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Màu nền/chữ tuỳ chỉnh',
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
    _verticalJumpGeneration++;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _progressTimer?.cancel();
    _ttsSettingsTimer?.cancel();
    _sleepTimer?.cancel();
    _bookSearchTimer?.cancel();
    _tts.stop();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.redAccent),
              SizedBox(height: 16),
              Text(
                'Đang phân tích nội dung EPUB...',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
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
      endDrawer: _buildTocDrawer(),
      body: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _handleReaderPointerDown,
              onPointerUp: _handleReaderPointerUp,
              onPointerCancel: _handleReaderPointerCancel,
              child: _flowType == 1
                  ? _buildVerticalReader()
                  : _buildHorizontalReader(),
            ),
          ),
          if (_showControls)
            Positioned(left: 0, right: 0, top: 0, child: _buildReaderTopBar()),
          if (_showControls)
            Positioned(
              right: 16,
              bottom: _floatingActionBottomPadding,
              child: FloatingActionButton.small(
                heroTag: 'epub-reader-settings-${widget.storageKey}',
                backgroundColor: const Color(0xFF2C2C2E),
                foregroundColor: Colors.white,
                onPressed: _showReaderSettings,
                child: const Icon(Icons.tune),
              ),
            ),
          if (_showControls)
            Positioned(left: 0, right: 0, bottom: 0, child: _buildTtsBar()),
        ],
      ),
    );
  }

  Widget _buildReaderTopBar() {
    return Material(
      color: const Color(0xFF2C2C2E),
      elevation: 4,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                tooltip: 'Quay lại',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Text(
                  _currentChapter.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.search, color: Colors.white),
                tooltip: 'Tìm trong sách',
                onPressed: _showBookSearch,
              ),
              IconButton(
                icon: const Icon(Icons.bookmarks_outlined, color: Colors.white),
                tooltip: 'Danh sách bookmark',
                onPressed: _showBookmarks,
              ),
              IconButton(
                icon: const Icon(Icons.menu_book, color: Colors.white),
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
                icon: const Icon(Icons.tune, color: Colors.white),
                tooltip: 'Cài đặt',
                onPressed: _showReaderSettings,
              ),
            ],
          ),
        ),
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

  Widget _buildContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final buttonItems = editableTextState.contextMenuButtonItems;
    final text = editableTextState.textEditingValue.text;
    final selection = editableTextState.textEditingValue.selection;

    buttonItems.insert(
      0,
      ContextMenuButtonItem(
        label: 'Đọc từ đây',
        onPressed: () {
          ContextMenuController.removeAny();
          _startTtsFromSelection(text, selection);
        },
      ),
    );
    buttonItems.insert(
      1,
      ContextMenuButtonItem(
        label: 'Đọc đoạn này',
        onPressed: () {
          ContextMenuController.removeAny();
          _startTtsForSelectionOnly(text, selection);
        },
      ),
    );

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }

  Widget _buildVerticalReader() {
    final totalChapters = _book?.chapters.length ?? 0;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) {
          _verticalJumpGeneration++;
        }
        if (notification is ScrollUpdateNotification ||
            notification is ScrollEndNotification) {
          _syncChapterFromVerticalKeys();
          _scheduleProgressSave();
        }
        return false;
      },
      child: SizedBox.expand(
        key: _verticalViewportKey,
        child: ScrollablePositionedList.builder(
          itemScrollController: _verticalItemController,
          scrollOffsetController: _verticalOffsetController,
          itemPositionsListener: _verticalPositionsListener,
          padding: EdgeInsets.fromLTRB(
            _pageHorizontalPadding,
            24,
            _pageHorizontalPadding,
            _readerBottomPadding,
          ),
          itemCount: totalChapters,
          itemBuilder: (context, chapterIndex) {
            final isNear = (chapterIndex - _chapterIndex).abs() <= 3;
            if (!isNear) {
              _chapterSectionKeys.remove(chapterIndex);
            } else {
              _chapterSectionKeys[chapterIndex] ??= GlobalKey();
            }
            final loader = _lazyChapterLoader;
            if (loader == null) {
              return _buildVerticalChapter(
                chapterIndex,
                _book!.chapters[chapterIndex],
                isNear: isNear,
              );
            }
            return FutureBuilder<EpubChapter>(
              future: _loadChapter(chapterIndex),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Lỗi tải chương',
                            style: TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                // By calling setState, FutureBuilder will rebuild and recall _loadChapter
                              });
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Thử lại'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final chapter = snapshot.data;
                if (chapter == null) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return _buildVerticalChapter(
                  chapterIndex,
                  chapter,
                  isNear: isNear,
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildVerticalChapter(
    int index,
    EpubChapter chapter, {
    required bool isNear,
  }) {
    final chapterText = EpubParser.formatChapterText(chapter);
    return Container(
      key: isNear ? _chapterSectionKeys[index] : null,
      padding: const EdgeInsets.only(bottom: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (chapter.blocks.isNotEmpty)
            ...chapter.blocks.map((block) {
              if (block.type == EpubBlockType.image && block.image != null) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Image.memory(block.image!, fit: BoxFit.contain),
                );
              } else if (block.type == EpubBlockType.divider) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Divider(color: Colors.white24, thickness: 1),
                );
              } else {
                double fontSize = _fontSize.toDouble();
                EdgeInsets padding = const EdgeInsets.only(bottom: 16);
                if (block.type == EpubBlockType.heading) {
                  fontSize *= 1.4;
                  padding = const EdgeInsets.only(top: 16, bottom: 24);
                } else if (block.type == EpubBlockType.quote) {
                  padding = const EdgeInsets.only(left: 16, bottom: 16);
                }
                final baseStyle = TextStyle(
                  color: Color(_textColor),
                  fontSize: fontSize,
                  fontWeight: block.type == EpubBlockType.heading
                      ? FontWeight.bold
                      : FontWeight.normal,
                  fontStyle: block.type == EpubBlockType.quote
                      ? FontStyle.italic
                      : FontStyle.normal,
                  height: _lineHeight,
                  fontFamily: _fontFamily == 'Default' ? null : _fontFamily,
                );
                return Padding(
                  padding: padding,
                  child: SelectableText.rich(
                    EpubPaginator.buildTextSpan(block, baseStyle),
                    contextMenuBuilder: _buildContextMenu,
                  ),
                );
              }
            })
          else ...[
            if (chapter.images.isNotEmpty)
              ...chapter.images.map(
                (img) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Image.memory(img, fit: BoxFit.contain),
                ),
              ),
            if (chapterText.trim().isNotEmpty)
              SelectableText(
                chapterText,
                style: TextStyle(
                  color: Color(_textColor),
                  fontSize: _fontSize.toDouble(),
                  height: _lineHeight,
                  fontFamily: _fontFamily == 'Default' ? null : _fontFamily,
                ),
                contextMenuBuilder: _buildContextMenu,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildHorizontalReader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final currentSize = Size(constraints.maxWidth, constraints.maxHeight);

        if (_viewportSize != currentSize) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _repaginate(() {
                _viewportSize = currentSize;
              });
            }
          });
          return const Center(child: CircularProgressIndicator());
        }

        if (_windowPages.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollEndNotification) {
              if (_chapterIndex != _windowCenterChapter) {
                unawaited(_shiftHorizontalWindow());
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
              final page = _windowPages[index];

              if (page.blocks.length == 1 &&
                  page.blocks.first.type == EpubBlockType.image &&
                  page.blocks.first.image != null) {
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    _pageHorizontalPadding,
                    24,
                    _pageHorizontalPadding,
                    _readerBottomPadding,
                  ),
                  child: Center(
                    child: Image.memory(
                      page.blocks.first.image!,
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              }

              Widget child = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: page.blocks.map((block) {
                  if (block.type == EpubBlockType.image &&
                      block.image != null) {
                    return Center(
                      child: Image.memory(block.image!, fit: BoxFit.contain),
                    );
                  }
                  if (block.type == EpubBlockType.divider) {
                    return Padding(
                      padding: EdgeInsets.only(bottom: _horizontalBlockSpacing),
                      child: const Divider(height: 32),
                    );
                  }

                  final double blockFontSize =
                      block.type == EpubBlockType.heading
                      ? _fontSize.toDouble() * 1.5
                      : _fontSize.toDouble();
                  final baseStyle = TextStyle(
                    color: Color(_textColor),
                    fontSize: blockFontSize,
                    fontWeight: block.type == EpubBlockType.heading
                        ? FontWeight.bold
                        : FontWeight.normal,
                    fontStyle: block.type == EpubBlockType.quote
                        ? FontStyle.italic
                        : FontStyle.normal,
                    height: _lineHeight,
                    fontFamily: _fontFamily == 'Default' ? null : _fontFamily,
                  );

                  return Padding(
                    padding: EdgeInsets.only(bottom: _horizontalBlockSpacing),
                    child: SelectableText.rich(
                      EpubPaginator.buildTextSpan(block, baseStyle),
                      contextMenuBuilder: _buildContextMenu,
                    ),
                  );
                }).toList(),
              );

              return Padding(
                padding: EdgeInsets.fromLTRB(
                  _pageHorizontalPadding,
                  24,
                  _pageHorizontalPadding,
                  _readerBottomPadding,
                ),
                child: child,
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _shiftHorizontalWindow() async {
    final targetChapter = _chapterIndex;
    final centerPages = _getPagesForChapter(_windowCenterChapter);
    final pageWithinChapter = targetChapter < _windowCenterChapter
        ? _horizontalPageIndex
        : _horizontalPageIndex - (_pagesBeforeCenter + centerPages.length);

    try {
      await _loadLazyWindow(targetChapter);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Lỗi tải chương mới'),
            action: SnackBarAction(
              label: 'Thử lại',
              onPressed: () => _shiftHorizontalWindow(),
            ),
          ),
        );
      }
      return;
    }

    if (!mounted || targetChapter != _chapterIndex) return;
    _updateHorizontalWindow(targetChapter);
    final newIndex = (_pagesBeforeCenter + pageWithinChapter)
        .clamp(0, max(0, _windowPages.length - 1))
        .toInt();
    setState(() => _horizontalPageIndex = newIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _pageController.jumpToPage(newIndex);
      }
    });
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
                      onPressed: () {
                        setState(() => _showTtsPanel = true);
                      },
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
              onTap: () {
                setState(() => _showTtsPanel = false);
              },
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
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
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
