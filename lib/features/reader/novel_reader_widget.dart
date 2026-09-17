import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'epub/epub_models.dart';
import 'epub/epub_parser.dart';
import 'epub/epub_paginator.dart';
import 'epub/epub_lazy_chapter_loader.dart';

import '../../data/database_helper.dart';
import '../../data/models.dart';
import '../../services/tts_service.dart';
import '../../services/glossary_service.dart';
import '../../services/community_glossary_service.dart';
import '../../services/level_service.dart';
import '../catalog/catalog_cache_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class NovelReaderWidget extends StatefulWidget {
  final String epubPath;
  final String title;
  final String storageKey;
  final String? realMangaId;
  final String? realChapterId;

  const NovelReaderWidget({
    super.key,
    required this.epubPath,
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

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _verticalViewportKey = GlobalKey();
  final _verticalItemController = ItemScrollController();
  final _verticalOffsetController = ScrollOffsetController();
  final _verticalPositionsListener = ItemPositionsListener.create();
  int _verticalJumpGeneration = 0;
  final _pageController = PageController();
  final _focusNode = FocusNode();
  final Map<int, GlobalKey> _chapterSectionKeys = {};
  final Map<int, Map<int, GlobalKey>> _blockKeys = {};
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
  double? _pendingTargetRatio;

  bool _showTtsPanel = false;
  bool _showControls = true;
  bool _isTtsPlaying = false;
  double _ttsRate = 0.5;
  double _ttsPitch = 1.0;
  String _ttsLang = 'vi-VN';
  List<Map<String, String>> _availableVoices = [];
  Map<String, String>? _selectedVoice;

  Timer? _progressTimer;
  Timer? _ttsSettingsTimer;
  Timer? _bookSearchTimer;
  int _searchSessionId = 0;
  int _sleepTimeMinutes = 0;
  bool _isCurrentBookmark = false;
  bool _isIncognito = false;
  bool _volumePageTurn = true;
  bool _invertVolumeKeys = false;
  String _currentSelection = '';

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

  String get _mangaId => widget.realMangaId ?? 'epub_$_resolvedBookKey';

  String get _chapterId => widget.realChapterId ?? 'epub_${_resolvedBookKey}_chapter_$_chapterIndex';

  String get _progressPrefsKey => 'epub_flutter_progress_$_mangaId';
  double get _horizontalBlockSpacing => _fontSize.toDouble() * _lineHeight;

  int get _chapterCount => _book?.chapters.length ?? 0;

  EpubChapter _chapterAt(int chapterIndex) {
    final index = chapterIndex.clamp(0, _chapterCount - 1);
    return _lazyChapterLoader?.peek(index) ?? _book!.chapters[index];
  }

  EpubChapter get _currentChapter => _chapterAt(_chapterIndex);

  double get _readerBottomPadding => 24;


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

    final processedChapter = chapter.applyReplacements(
      (text) => GlossaryService.instance.applyReplacements(text, mangaId: widget.storageKey),
    );

    final pages = EpubPaginator.paginate(
      chapter: processedChapter,
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

  StreamSubscription<ClaimExpResult>? _levelUpSub;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _syncTtsState();
    TtsService.instance.addListener(_onTtsServiceChanged);
    GlossaryService.instance.addListener(_onGlossaryChanged);
    _levelUpSub = LevelService.instance.onLevelUp.listen((result) {
      if (mounted) {
        final title = LevelService.levelTitles[
            (result.newLevel - 1).clamp(0, LevelService.levelTitles.length - 1)];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            backgroundColor: const Color(0xFF1E1E2C),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFFFD700), width: 1.2),
            ),
            content: Row(
              children: [
                const Text('🎉', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'THĂNG CẤP ĐỘC GIẢ! (Lv. ${result.newLevel})',
                        style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'Danh hiệu: $title (+10 EXP)',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
    });
    TtsService.instance.onNextChapterRequested = () async {
      if (mounted) {
        final old = _chapterIndex;
        await _nextChapter();
        if (_chapterIndex != old && mounted) {
          final curChapter = await _loadChapter(_chapterIndex);
          final nextText = EpubParser.formatChapterText(curChapter);
          if (nextText.trim().isNotEmpty) {
            final nextBlockTexts = curChapter.blocks
                .map((b) => (b.text != null && b.type != EpubBlockType.divider) ? b.text! : '')
                .toList();
            await _startTts(nextText, blockTexts: nextBlockTexts);
            return true;
          }
        }
      }
      return false;
    };
    TtsService.instance.onPrevChapterRequested = () async {
      if (mounted && _chapterIndex > 0) {
        final old = _chapterIndex;
        await _prevChapter();
        if (_chapterIndex != old && mounted) {
          final curChapter = await _loadChapter(_chapterIndex);
          final prevText = EpubParser.formatChapterText(curChapter);
          if (prevText.trim().isNotEmpty) {
            final prevBlockTexts = curChapter.blocks
                .map((b) => (b.text != null && b.type != EpubBlockType.divider) ? b.text! : '')
                .toList();
            final chunks = TtsService.instance.splitTtsChunks(
              prevText,
              blockTexts: prevBlockTexts,
              mangaId: _mangaId,
            );
            final lastChunkIndex = max(0, chunks.length - 1);
            await _startTts(prevText, blockTexts: prevBlockTexts, startChunkIndex: lastChunkIndex);
            return true;
          }
        }
      }
      return false;
    };
    _init();
  }

  int _lastScrolledChunkIndex = -1;

  void _onTtsServiceChanged() {
    if (!mounted) return;
    final tts = TtsService.instance;
    final chunkChanged = _lastScrolledChunkIndex != tts.chunkIndex;
    final playingChanged = _isTtsPlaying != tts.isPlaying;
    final rateChanged = (_ttsRate - tts.rate).abs() > 0.01;
    final pitchChanged = (_ttsPitch - tts.pitch).abs() > 0.01;
    final sleepChanged = _sleepTimeMinutes != tts.sleepMinutesRemaining;

    // Chỉ rebuild khi câu đổi, trạng thái phát đổi, hoặc cài đặt đổi (tránh rebuild trên mỗi 100ms)
    if (chunkChanged || playingChanged || rateChanged || pitchChanged || sleepChanged) {
      setState(() {
        _syncTtsState();
      });
    }

    if (chunkChanged && (_isTtsPlaying || tts.isVisible)) {
      _lastScrolledChunkIndex = tts.chunkIndex;
      _scrollToActiveTtsChunkIfNeeded();
    }
  }

  void _scrollToActiveTtsChunkIfNeeded() {
    if (!_isTtsPlaying && !TtsService.instance.isVisible) return;
    // Không can thiệp cuộn nếu người dùng đang chạm hoặc vuốt màn hình
    if (_readerPointerStart != null) return;

    final currentChunk = TtsService.instance.currentChunk;
    if (currentChunk == null) return;

    // Chế độ lật trang ngang: tự động lật sang trang chứa câu đang đọc
    if (_flowType == 0) {
      _syncHorizontalPageWithTts(currentChunk);
      return;
    }

    final chapIdx = TtsService.instance.currentChapterIndex;
    final blockIdx = currentChunk.blockIndex;
    final key = _blockKeys[chapIdx]?[blockIdx];
    if (key == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _readerPointerStart != null) return;
      final ctx = key.currentContext;
      if (ctx == null || !ctx.mounted) return;

      final renderBox = ctx.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) return;

      final screenHeight = MediaQuery.of(context).size.height;
      final safeTop = MediaQuery.of(context).padding.top + 60; // buffer cho top bar
      final ttsPanelHeight = _showTtsPanel ? 250.0 : 88.0;
      final safeBottom = screenHeight - ttsPanelHeight;

      final pos = renderBox.localToGlobal(Offset.zero);
      final top = pos.dy;
      final blockHeight = renderBox.size.height;

      // Tính toạ độ Y ước tính của câu đang đọc trong block
      final chapter = (chapIdx >= 0 && chapIdx < _chapterCount)
          ? _chapterAt(chapIdx)
          : null;
      final blockTextLength = (chapter != null && blockIdx < chapter.blocks.length)
          ? (chapter.blocks[blockIdx].text?.length ?? 0)
          : 0;
      final progressInBlock = blockTextLength > 0
          ? (currentChunk.charStartInBlock / blockTextLength).clamp(0.0, 1.0)
          : 0.0;
      final sentenceEstimatedY = top + (blockHeight * progressInBlock);

      // Nếu câu đang đọc nằm an toàn trong khung nhìn thì không cần cuộn
      if (sentenceEstimatedY >= safeTop + 24 && sentenceEstimatedY <= safeBottom - 36) {
        return;
      }

      // Nếu block nhỏ hơn màn hình, cuộn đưa block về vị trí 28% từ đỉnh
      if (blockHeight <= (safeBottom - safeTop)) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.28,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOutCubic,
        );
      } else {
        // Nếu block dài (vượt màn hình), tính alignment tương ứng với vị trí của câu trong block
        final targetAlignment = (progressInBlock * 0.82).clamp(0.0, 0.95);
        Scrollable.ensureVisible(
          ctx,
          alignment: targetAlignment,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  void _syncHorizontalPageWithTts(TtsChunk currentChunk) {
    if (_windowPages.isEmpty || !_pageController.hasClients) return;
    final chapIdx = TtsService.instance.currentChapterIndex;
    if (chapIdx != _windowCenterChapter) return;

    final chunkSnippet = currentChunk.text.trim();
    if (chunkSnippet.isEmpty) return;

    final centerPages = _getPagesForChapter(chapIdx);
    final startIndex = _pagesBeforeCenter;
    final endIndex = (startIndex + centerPages.length).clamp(0, _windowPages.length);

    int matchedPageIndex = -1;
    final sample = chunkSnippet.length > 25 ? chunkSnippet.substring(0, 25) : chunkSnippet;
    for (int i = startIndex; i < endIndex; i++) {
      if (_windowPages[i].text.contains(sample)) {
        matchedPageIndex = i;
        break;
      }
    }

    if (matchedPageIndex != -1 && matchedPageIndex != _horizontalPageIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients || _readerPointerStart != null) return;
        _pageController.animateToPage(
          matchedPageIndex,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOutCubic,
        );
      });
    }
  }

  void _syncTtsState() {
    _isTtsPlaying = TtsService.instance.isPlaying;
    _ttsRate = TtsService.instance.rate;
    _ttsPitch = TtsService.instance.pitch;
    _ttsLang = TtsService.instance.lang;
    _availableVoices = TtsService.instance.availableVoices;
    _selectedVoice = TtsService.instance.selectedVoice;
    _sleepTimeMinutes = TtsService.instance.sleepMinutesRemaining;
  }

  @override
  void didUpdateWidget(covariant NovelReaderWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.epubPath != widget.epubPath ||
        oldWidget.storageKey != widget.storageKey ||
        oldWidget.title != widget.title ||
        oldWidget.realChapterId != widget.realChapterId) {
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
      _volumePageTurn = prefs.getBool('reader_volume_page_turn') ?? true;
      _invertVolumeKeys = prefs.getBool('reader_invert_volume_keys') ?? false;
      await _loadTtsSettings(prefs);

      late final ParsedEpub book;
      final fileLength = await File(widget.epubPath).length();
      if (fileLength >= _lazyLoadingThresholdBytes) {
        final index = await compute(
          EpubParser.parseIndex,
          EpubParseArgs(path: widget.epubPath, title: widget.title),
        );
        final loader = EpubLazyChapterLoader(
          index: index,
          path: widget.epubPath,
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
          EpubParseArgs(path: widget.epubPath, title: widget.title),
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
          _jumpVerticalToChapter(saved.$1, offsetRatio: saved.$3, blockIndex: saved.$4);
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
    _bookSearchTimer?.cancel();
    if (_verticalItemController.isAttached) {
      _verticalItemController.jumpTo(index: 0);
    }
    _book = null;
    _lazyChapterLoader?.clear();
    _lazyChapterLoader = null;
    _chapterIndex = 0;
    _horizontalPageIndex = 0;
    _isCurrentBookmark = false;
    _chapterSectionKeys.clear();
    _chapterPagesCache.clear();
    _windowCenterChapter = -1;
    _windowPages.clear();
  }

  Future<void> _loadTtsSettings(SharedPreferences prefs) async {
    _syncTtsState();
  }

  Future<(int, int, double, int)> _loadSavedPosition(
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
          max(0, (map['blockIndex'] as num? ?? 0).toInt()),
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
        max(0, parsed.$4),
      );
    }
    return (0, 0, 0.0, 0);
  }

  (int, int, double, int)? _decodePosition(String? value) {
    if (value == null || !value.startsWith('flutter:')) return null;
    final parts = value.substring('flutter:'.length).split(':');
    if (parts.length < 3) return null;
    return (
      int.tryParse(parts[0]) ?? 0,
      int.tryParse(parts[1]) ?? 0,
      double.tryParse(parts[2]) ?? 0,
      parts.length > 3 ? (int.tryParse(parts[3]) ?? 0) : 0,
    );
  }

  String _encodePosition() {
    double ratio = 0.0;
    int pageWithinChapter = 0;
    int blockIndex = 0;
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
          
          final blocks = _blockKeys[_chapterIndex];
          if (blocks != null) {
            double minDistance = double.infinity;
            for (final entry in blocks.entries) {
              final bBox = entry.value.currentContext?.findRenderObject() as RenderBox?;
              if (bBox != null && bBox.attached) {
                final bTop = bBox.localToGlobal(Offset.zero).dy - viewportTop;
                if (bTop >= -100 && bTop < minDistance) {
                  minDistance = bTop;
                  blockIndex = entry.key;
                }
              }
            }
          }
        }
      }
    } else {
      // For horizontal mode, encode pageIndexWithinChapter
      pageWithinChapter = _pageWithinCurrentChapter();
      ratio = pageWithinChapter.toDouble();
    }
    return 'flutter:$_chapterIndex:$pageWithinChapter:${ratio.toStringAsFixed(4)}:$blockIndex';
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
    if (_isIncognito) return;
    final position = _encodePosition();
    // Get the parts directly from encodePosition to save in DB
    final parts = position.substring('flutter:'.length).split(':');
    final pageWithinChapter = parts.length >= 3
        ? (int.tryParse(parts[1]) ?? 0)
        : 0;
    final ratio = parts.length >= 3 ? (double.tryParse(parts[2]) ?? 0.0) : 0.0;
    final blockIndex = parts.length >= 4 ? (int.tryParse(parts[3]) ?? 0) : 0;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _progressPrefsKey,
      jsonEncode({
        'chapter': _chapterIndex,
        'page': pageWithinChapter,
        'offset': ratio, // Save ratio instead of pixel offset
        'blockIndex': blockIndex,
      }),
    );
    await DatabaseHelper.instance.saveReaderProgress(
      ReaderProgress(
        mangaId: _mangaId,
        chapterId: _chapterId,
        pageIndex: _flowType == 0 ? pageWithinChapter : _chapterIndex,
        blockIndex: blockIndex,
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

    if (widget.realMangaId != null) {
      final userId = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
      final chapterTitle = _book != null && _chapterIndex >= 0 && _chapterIndex < _book!.chapters.length
          ? _book!.chapters[_chapterIndex].title
          : widget.title;
      final history = ReadingHistory(
        userId: userId,
        mangaId: widget.realMangaId!,
        chapterId: _chapterId,
        chapterTitle: chapterTitle,
        lastPageIndex: _flowType == 0 ? pageWithinChapter : _chapterIndex,
        totalPages: _book?.chapters.length ?? 1,
        updatedAt: DateTime.now(),
      );
      await DatabaseHelper.instance.saveHistory(history);
      LevelService.instance.claimChapterExp(
        widget.realMangaId!,
        _chapterId,
        chapterTitle: chapterTitle,
      );
    } else {
      LevelService.instance.claimChapterExp(
        widget.storageKey,
        'ch_$_chapterIndex',
        chapterTitle: widget.title,
      );
    }

    await _refreshBookmarkState();
  }

  void _repaginate(void Function() configChange) {
    if (!mounted) return;

    double progressRatio = 0.0;
    if (_pendingTargetRatio != null) {
      progressRatio = _pendingTargetRatio!;
      _pendingTargetRatio = null;
    } else if (_flowType == 0 && _windowPages.isNotEmpty) {
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
      targetRatio = parts.length >= 3
          ? (double.tryParse(parts[2]) ?? 0.0)
          : 0.0;
      _pendingTargetRatio = targetRatio;
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

  void _jumpVerticalToChapter(int index, {double offsetRatio = 0.0, int blockIndex = 0}) {
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

      if (safeRatio <= 0 && blockIndex <= 0) return;

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

        RenderBox? box;
        final blockKey = _blockKeys[index]?[blockIndex];
        if (blockIndex > 0 && blockKey?.currentContext != null) {
          box = blockKey!.currentContext!.findRenderObject() as RenderBox?;
        } else {
          final context = _chapterSectionKeys[index]?.currentContext;
          box = context?.findRenderObject() as RenderBox?;
        }
        
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
        final desiredViewportTop = blockIndex > 0 ? 0.0 : -(box.size.height * safeRatio);
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
    _blockKeys.removeWhere(
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

  Future<void> _saveQuote(String quote) async {
    final position = _encodePosition();
    final now = DateTime.now();
    await DatabaseHelper.instance.saveBookmark(
      ReaderBookmark(
        id: '$_mangaId-$_chapterId-${position.hashCode}-${now.millisecondsSinceEpoch}',
        mangaId: _mangaId,
        chapterId: _chapterId,
        pageIndex: _flowType == 0 ? _pageWithinCurrentChapter() : _chapterIndex,
        scrollOffset: 0,
        epubCfi: position,
        note: quote,
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã lưu trích dẫn vào Bookmark', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
          backgroundColor: Theme.of(context).colorScheme.primary,
          action: SnackBarAction(
            label: 'Xem ngay',
            textColor: Theme.of(context).colorScheme.onPrimary,
            onPressed: _showBookmarks,
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
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
      backgroundColor: Theme.of(context).cardColor,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final theme = Theme.of(context);
        final onSurface = theme.colorScheme.onSurface;
        final divider = theme.dividerColor;

        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.68,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.bookmarks, color: Colors.amber),
                  title: Text(
                    'Danh sách bookmark & trích dẫn',
                    style: TextStyle(
                      color: onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: bookmarks.isEmpty
                      ? Center(
                          child: Text(
                            'Chưa có bookmark nào',
                            style: TextStyle(color: onSurface.withValues(alpha: 0.6)),
                          ),
                        )
                      : ListView.separated(
                          itemCount: bookmarks.length,
                          separatorBuilder: (_, _) =>
                              Divider(height: 1, color: divider),
                          itemBuilder: (context, index) {
                            final bookmark = bookmarks[index];
                            final isQuote = bookmark.note != null && bookmark.note!.isNotEmpty;
                            final parsed = _decodePosition(bookmark.epubCfi);
                            final bookChapters = _book?.chapters;
                            final chapterIndex = (parsed != null && bookChapters != null && bookChapters.isNotEmpty)
                                ? parsed.$1.clamp(0, bookChapters.length - 1)
                                : null;
                            final chapter = chapterIndex == null
                                ? null
                                : _chapterAt(chapterIndex);
                            return ListTile(
                              leading: Icon(
                                isQuote ? Icons.format_quote : Icons.bookmark,
                                color: isQuote ? Colors.cyanAccent : Colors.amber,
                              ),
                              title: Text(
                                isQuote ? '“${bookmark.note}”' : (chapter?.title ?? 'Vị trí đã lưu'),
                                style: TextStyle(
                                  color: onSurface,
                                  fontStyle: isQuote ? FontStyle.italic : FontStyle.normal,
                                  fontWeight: isQuote ? FontWeight.w500 : FontWeight.normal,
                                ),
                                maxLines: isQuote ? 3 : 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                isQuote
                                    ? (chapter?.title ?? 'Trích dẫn')
                                    : (chapter == null
                                        ? 'Không xác định được chương'
                                        : _chapterPreview(chapter)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: onSurface.withValues(alpha: 0.6), fontSize: 12),
                              ),
                              trailing: IconButton(
                                icon: Icon(Icons.delete_outline, color: onSurface.withValues(alpha: 0.38), size: 20),
                                onPressed: () async {
                                  await DatabaseHelper.instance.deleteBookmark(bookmark.id);
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    _showBookmarks();
                                  }
                                },
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
        );
      },
    );
  }

  Future<void> _showBookSearch() async {
    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final theme = Theme.of(context);
        final onSurface = theme.colorScheme.onSurface;
        final divider = theme.dividerColor;

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
                        style: TextStyle(color: onSurface),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Tìm trong sách',
                          hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.38)),
                          prefixIcon: Icon(Icons.search, color: onSurface.withValues(alpha: 0.54)),
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
                                style: TextStyle(color: onSurface.withValues(alpha: 0.6)),
                              ),
                            )
                          : ListView.separated(
                              itemCount: results.length,
                              separatorBuilder: (_, _) => Divider(
                                height: 1,
                                color: divider,
                              ),
                              itemBuilder: (context, index) {
                                final chapterIndex = results[index];
                                final chapter =
                                    resultChapters[chapterIndex] ??
                                    _chapterAt(chapterIndex);
                                return ListTile(
                                  leading: Icon(
                                    Icons.menu_book,
                                    color: onSurface.withValues(alpha: 0.7),
                                  ),
                                  title: Text(
                                    chapter.title,
                                    style: TextStyle(color: onSurface),
                                  ),
                                  subtitle: Text(
                                    _chapterPreview(chapter),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: onSurface.withValues(alpha: 0.6),
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
    final path = widget.epubPath;

    if (loader != null) {
      final result = await compute(_searchEpubLazyInIsolate, {
        'path': path,
        'chapters': loader.index.chapters,
        'query': normalizedQuery,
      });
      if (sessionId == _searchSessionId) {
        matches.addAll(result);
      }
    } else if (_book != null) {
      final result = await compute(_searchEpubInMemoryInIsolate, {
        'chapters': _book!.chapters,
        'query': normalizedQuery,
      });
      if (sessionId == _searchSessionId) {
        matches.addAll(result);
      }
    }

    loader?.retainAround(_chapterIndex);
    return matches;
  }

  static String _normalizeSearchText(String text) {
    const vietnameseMap = {
      'a': 'áàảãạăắằẳẵặâấầẩẫậ',
      'd': 'đ',
      'e': 'éèẻẽẹêếềểễệ',
      'i': 'íìỉĩị',
      'o': 'óòỏõọôốồổỗộơớờởỡợ',
      'u': 'úùủũụưứừửữự',
      'y': 'ýỳỷỹỵ',
    };
    var result = text.toLowerCase();
    for (final entry in vietnameseMap.entries) {
      for (final char in entry.value.split('')) {
        result = result.replaceAll(char, entry.key);
      }
    }
    return result;
  }

  // Static functions for isolate (must be static if inside class)
  static Map<int, EpubChapter> _searchEpubLazyInIsolate(
    Map<String, dynamic> args,
  ) {
    final path = args['path'] as String;
    final chapters = args['chapters'] as List<EpubChapterReference>;
    final query = args['query'] as String;
    final rawQuery = query.toLowerCase();
    final normalizedQuery = _normalizeSearchText(query);
    final matches = <int, EpubChapter>{};

    for (var index = 0; index < chapters.length; index++) {
      try {
        final chapterRef = chapters[index];
        final chapter = EpubParser.parseChapter(
          EpubChapterParseArgs(path: path, chapter: chapterRef),
        );
        final title = chapter.title;
        final body = EpubParser.formatChapterText(chapter);
        final combined = '$title $body';
        final rawCombined = combined.toLowerCase();
        final normCombined = _normalizeSearchText(combined);

        if (rawCombined.contains(rawQuery) ||
            normCombined.contains(normalizedQuery)) {
          matches[index] = chapter;
        }
      } catch (_) {}
    }
    return matches;
  }

  static Map<int, EpubChapter> _searchEpubInMemoryInIsolate(
    Map<String, dynamic> args,
  ) {
    final chapters = args['chapters'] as List<EpubChapter>;
    final query = args['query'] as String;
    final rawQuery = query.toLowerCase();
    final normalizedQuery = _normalizeSearchText(query);
    final matches = <int, EpubChapter>{};

    for (var index = 0; index < chapters.length; index++) {
      final chapter = chapters[index];
      final title = chapter.title;
      final body = EpubParser.formatChapterText(chapter);
      final combined = '$title $body';
      final rawCombined = combined.toLowerCase();
      final normCombined = _normalizeSearchText(combined);

      if (rawCombined.contains(rawQuery) ||
          normCombined.contains(normalizedQuery)) {
        matches[index] = chapter;
      }
    }
    return matches;
  }

  Future<void> _setTtsVoice(Map<String, String> voice) async {
    await TtsService.instance.setVoice(voice);
    _syncTtsState();
  }

  Future<void> _setTtsRate(double value, {bool restartIfPlaying = true}) async {
    await TtsService.instance.setRate(value, restartIfPlaying: restartIfPlaying);
    _syncTtsState();
  }

  Future<void> _setTtsPitch(double value, {bool restartIfPlaying = true}) async {
    await TtsService.instance.setPitch(value, restartIfPlaying: restartIfPlaying);
    _syncTtsState();
  }

  Future<void> _setTtsLang(String lang) async {
    await TtsService.instance.setLanguage(lang);
    _syncTtsState();
  }

  Future<void> _toggleTts() async {
    if (TtsService.instance.isPlaying) {
      await TtsService.instance.pause();
      return;
    }

    if (_flowType == 0 && _windowPages.isEmpty) return;

    final curChapter = await _loadChapter(_chapterIndex);
    final blockTexts = curChapter.blocks
        .map((b) => (b.text != null && b.type != EpubBlockType.divider) ? b.text! : '')
        .toList();

    final text = EpubParser.formatChapterText(curChapter);
    if (text.trim().isEmpty) return;

    int targetChunk = 0;
    if (_flowType == 1 && blockTexts.isNotEmpty) {
      final position = _encodePosition();
      final parts = position.substring('flutter:'.length).split(':');
      // blockIndex từ _encodePosition = full block index, nay chunk.blockIndex cũng = full index → khớp trực tiếp
      final fullBlockIndex = parts.length >= 4 ? (int.tryParse(parts[3]) ?? 0) : 0;

      final chunks = TtsService.instance.splitTtsChunks(
        text,
        blockTexts: blockTexts,
        mangaId: _mangaId,
      );
      targetChunk = chunks.indexWhere((c) => c.blockIndex >= fullBlockIndex);
      if (targetChunk == -1) targetChunk = 0;
    } else if (_flowType == 0 && _windowPages.isNotEmpty) {
      final currentPage = _windowPages[_horizontalPageIndex.clamp(0, _windowPages.length - 1)];
      final pageSnippet = currentPage.text.trim();
      final chunks = TtsService.instance.splitTtsChunks(
        text,
        blockTexts: blockTexts,
        mangaId: _mangaId,
      );
      if (pageSnippet.isNotEmpty) {
        final sample = pageSnippet.length > 25 ? pageSnippet.substring(0, 25) : pageSnippet;
        final idx = chunks.indexWhere((c) => c.text.contains(sample) || sample.contains(c.text.trim()));
        if (idx != -1) targetChunk = idx;
      }
    }

    await _startTts(
      text,
      blockTexts: blockTexts,
      startChunkIndex: targetChunk,
    );
  }

  Future<void> _startTts(
    String text, {
    List<String>? blockTexts,
    int startChunkIndex = 0,
  }) async {
    await TtsService.instance.startReading(
      mangaId: _mangaId,
      chapterId: _chapterId,
      chapterTitle: _currentChapter.title,
      mangaTitle: widget.title,
      epubPath: widget.epubPath,
      chapterIndex: _chapterIndex,
      text: text,
      blockTexts: blockTexts,
      startChunkIndex: startChunkIndex,
    );
  }

  int _findBestMatchingChunk(List<TtsChunk> chunks, String selectedText) {
    if (chunks.isEmpty) return 0;
    final cleanSelected = selectedText
        .replaceAll(RegExp(r'["“”‘’«»]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
    if (cleanSelected.isEmpty) return 0;

    // 1. Tìm các candidate có chứa chuỗi hoặc chuỗi chứa candidate
    final candidates = <int>[];
    for (var i = 0; i < chunks.length; i++) {
      final cleanChunk = chunks[i].text
          .replaceAll(RegExp(r'["“”‘’«»]'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim()
          .toLowerCase();
      if (cleanChunk == cleanSelected ||
          cleanChunk.contains(cleanSelected) ||
          cleanSelected.contains(cleanChunk)) {
        candidates.add(i);
      }
    }

    if (candidates.isEmpty) {
      // Thử tìm theo 3 từ đầu tiên của chuỗi chọn
      final words = cleanSelected.split(' ');
      if (words.length >= 3) {
        final prefix = words.take(3).join(' ');
        for (var i = 0; i < chunks.length; i++) {
          final cleanChunk = chunks[i].text.toLowerCase();
          if (cleanChunk.contains(prefix)) {
            candidates.add(i);
          }
        }
      }
    }

    if (candidates.isEmpty) {
      // Fallback: tìm theo từ đầu tiên dài hơn 3 ký tự
      final words = cleanSelected.split(' ').where((w) => w.length > 3).toList();
      if (words.isNotEmpty) {
        final keyWord = words.first;
        for (var i = 0; i < chunks.length; i++) {
          if (chunks[i].text.toLowerCase().contains(keyWord)) {
            candidates.add(i);
          }
        }
      }
    }

    if (candidates.isEmpty) return 0;
    if (candidates.length == 1) return candidates.first;

    // Ưu tiên candidate gần với vị trí đang hiển thị trên màn hình nhất
    int referenceBlockIndex = 0;
    if (_flowType == 1) {
      final position = _encodePosition();
      final parts = position.substring('flutter:'.length).split(':');
      referenceBlockIndex = parts.length >= 4 ? (int.tryParse(parts[3]) ?? 0) : 0;
    }
    candidates.sort((a, b) {
      final distA = (chunks[a].blockIndex - referenceBlockIndex).abs();
      final distB = (chunks[b].blockIndex - referenceBlockIndex).abs();
      return distA.compareTo(distB);
    });
    return candidates.first;
  }

  Future<void> _startTtsFromSelection(String selectedText) async {
    if (selectedText.trim().isEmpty) return;
    final chapter = await _loadChapter(_chapterIndex);
    final blockTexts = chapter.blocks
        .map((b) => (b.text != null && b.type != EpubBlockType.divider) ? b.text! : '')
        .toList();
    final fullText = EpubParser.formatChapterText(chapter);

    final tts = TtsService.instance;
    final isSameChapter = tts.currentChapterIndex == _chapterIndex &&
        tts.currentMangaId == _mangaId &&
        tts.totalChunks > 0;

    final chunks = isSameChapter
        ? tts.chunks
        : tts.splitTtsChunks(
            fullText,
            blockTexts: blockTexts,
            mangaId: _mangaId,
          );

    final targetChunk = _findBestMatchingChunk(chunks, selectedText);

    if (isSameChapter) {
      await tts.seekToChunk(targetChunk);
      if (!tts.isPlaying) {
        await tts.resume();
      }
    } else {
      await _startTts(
        fullText,
        blockTexts: blockTexts,
        startChunkIndex: targetChunk,
      );
    }
  }

  Future<void> _startTtsForSelectionOnly(String selectedText) async {
    if (selectedText.trim().isEmpty) return;
    await _startTts(selectedText.trim());
  }

  void _showChunkPickerBottomSheet() {
    final tts = TtsService.instance;
    final chunks = tts.chunks;
    if (chunks.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final onSurface = theme.colorScheme.onSurface;
        final divider = theme.dividerColor;

        var searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredChunks = searchQuery.isEmpty
                ? chunks.asMap().entries.toList()
                : chunks.asMap().entries.where((e) {
                    return e.value.text.toLowerCase().contains(searchQuery.toLowerCase());
                  }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.75,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: onSurface.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.format_list_numbered_rounded, color: theme.colorScheme.primary, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Chọn câu đọc (${chunks.length} câu)',
                                style: TextStyle(
                                  color: onSurface,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Đang ở câu ${tts.chunkIndex + 1}',
                            style: TextStyle(color: theme.colorScheme.primary, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: TextField(
                        style: TextStyle(color: onSurface, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Tìm kiếm câu trong chương...',
                          hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.38), fontSize: 13),
                          prefixIcon: Icon(Icons.search, color: onSurface.withValues(alpha: 0.54), size: 18),
                          filled: true,
                          fillColor: onSurface.withValues(alpha: 0.08),
                          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (val) {
                          setModalState(() => searchQuery = val);
                        },
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: ListView.separated(
                        controller: scrollController,
                        itemCount: filteredChunks.length,
                        separatorBuilder: (_, __) => Divider(color: divider, height: 1),
                        itemBuilder: (_, i) {
                          final entry = filteredChunks[i];
                          final chunkIdx = entry.key;
                          final chunk = entry.value;
                          final isCurrent = chunkIdx == tts.chunkIndex;

                          return ListTile(
                            tileColor: isCurrent ? theme.colorScheme.primary.withValues(alpha: 0.15) : null,
                            leading: Container(
                              width: 34,
                              height: 34,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isCurrent ? theme.colorScheme.primary : onSurface.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${chunkIdx + 1}',
                                style: TextStyle(
                                  color: isCurrent ? theme.colorScheme.onPrimary : onSurface.withValues(alpha: 0.7),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              chunk.text,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCurrent ? theme.colorScheme.primary : onSurface,
                                fontSize: 13,
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            trailing: isCurrent
                                ? Icon(Icons.graphic_eq_rounded, color: theme.colorScheme.primary, size: 18)
                                : null,
                            onTap: () {
                              Navigator.pop(ctx);
                              tts.seekToChunk(chunkIdx);
                              if (!tts.isPlaying) {
                                tts.resume();
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _setSleepTimer(int minutes) {
    TtsService.instance.setSleepTimer(minutes);
    setState(() => _sleepTimeMinutes = minutes);
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
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final onSurface = Theme.of(context).colorScheme.onSurface;
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Màu nền',
                style: TextStyle(
                  color: onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _buildColorRow(bgColors, _bgColor, _setBgColor),
              const SizedBox(height: 24),
              Text(
                'Màu chữ',
                style: TextStyle(
                  color: onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _buildColorRow(textColors, _textColor, _setTextColor),
            ],
          ),
        );
      },
    );
  }

  Widget _buildColorRow(
    List<int> colors,
    int selected,
    Future<void> Function(int) onSelected,
  ) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final divider = theme.dividerColor;

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
                        ? primary
                        : divider,
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
      (label: 'Sáng', bg: 0xFFFFFFFF, text: 0xFF1C1C1E),
      (label: 'Tối', bg: 0xFF1C1C1E, text: 0xFFFFFFFF),
      (label: 'Giấy cũ', bg: 0xFFF7F1E3, text: 0xFF2D241E),
      (label: 'Ấm áp', bg: 0xFFF8EED9, text: 0xFF4A3525),
      (label: 'E-Ink', bg: 0xFFECECEC, text: 0xFF1B1B1B),
      (label: 'Xanh dịu', bg: 0xFFD7ECE5, text: 0xFF1B3B2B),
      (label: 'Sepia', bg: 0xFFF4ECD8, text: 0xFF5B4636),
      (label: 'Gỗ mun', bg: 0xFF181512, text: 0xFFD5C7B7),
      (label: 'Mắt', bg: 0xFFC7EDCC, text: 0xFF333333),
      (label: 'AMOLED', bg: 0xFF000000, text: 0xFF888888),
    ];

    final totalChapters = _book?.chapters.length ?? 1;
    final progressPercent = totalChapters <= 1
        ? 0.0
        : _chapterIndex / (totalChapters - 1);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            color: Theme.of(context).cardColor.withValues(alpha: 0.85),
            child: StatefulBuilder(
        builder: (context, setModalState) {
          final theme = Theme.of(context);
          final primary = theme.colorScheme.primary;
          final onPrimary = theme.colorScheme.onPrimary;
          final onSurface = theme.colorScheme.onSurface;
          final divider = theme.dividerColor;

          return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Cài đặt đọc',
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: onSurface.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
                // Progress indicator
                Row(
                  children: [
                    Icon(
                      Icons.menu_book,
                      size: 14,
                      color: onSurface.withValues(alpha: 0.54),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Chương ${_chapterIndex + 1}/$totalChapters  •  ${(progressPercent * 100).round()}%',
                      style: TextStyle(
                        color: onSurface.withValues(alpha: 0.54),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: progressPercent,
                  backgroundColor: divider,
                  color: primary,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                ),
                const SizedBox(height: 16),
                // Font size
                Text(
                  'Cỡ chữ $_fontSize',
                  style: TextStyle(color: onSurface),
                ),
                Slider(
                  value: _fontSize.toDouble(),
                  min: 12,
                  max: 40,
                  divisions: 14,
                  activeColor: primary,
                  onChanged: (value) async {
                    await _setFontSize(value.round());
                    setModalState(() {});
                  },
                ),
                // Line height
                Text(
                  'Dãn dòng ${_lineHeight.toStringAsFixed(2)}',
                  style: TextStyle(color: onSurface),
                ),
                Slider(
                  value: _lineHeight,
                  min: 1.2,
                  max: 2.5,
                  divisions: 13,
                  activeColor: primary,
                  onChanged: (value) async {
                    await _setLineHeight(
                      double.parse(value.toStringAsFixed(2)),
                    );
                    setModalState(() {});
                  },
                ),
                Text(
                  'Lề ngang ${_pageHorizontalPadding.round()}',
                  style: TextStyle(color: onSurface),
                ),
                Slider(
                  value: _pageHorizontalPadding,
                  min: 12,
                  max: 48,
                  divisions: 12,
                  activeColor: primary,
                  onChanged: (value) async {
                    await _setPageHorizontalPadding(value);
                    setModalState(() {});
                  },
                ),
                const SizedBox(height: 4),
                // Font family
                Text('Font chữ', style: TextStyle(color: onSurface)),
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
                                  ? primary
                                  : onSurface.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: selected
                                    ? primary
                                    : divider,
                              ),
                            ),
                            child: Text(
                              option.label,
                              style: TextStyle(
                                color: selected ? onPrimary : onSurface.withValues(alpha: 0.7),
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
                Text(
                  'Theme nhanh',
                  style: TextStyle(color: onSurface),
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
                                    ? primary
                                    : divider,
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
                  title: Text(
                    'Màu nền/chữ tuỳ chỉnh',
                    style: TextStyle(color: onSurface),
                  ),
                  leading: Icon(Icons.palette, color: onSurface.withValues(alpha: 0.54)),
                  onTap: _showColorSettings,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _volumePageTurn,
                  activeTrackColor: primary,
                  activeThumbColor: primary,
                  onChanged: (value) async {
                    setState(() => _volumePageTurn = value);
                    setModalState(() {});
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('reader_volume_page_turn', value);
                  },
                  title: Text(
                    'Phím âm lượng chuyển trang',
                    style: TextStyle(color: onSurface),
                  ),
                  subtitle: Text(
                    'Dùng nút tăng/giảm âm lượng để lật trang/cuộn',
                    style: TextStyle(color: onSurface.withValues(alpha: 0.54), fontSize: 11),
                  ),
                  secondary: Icon(
                    Icons.volume_up_rounded,
                    color: onSurface.withValues(alpha: 0.54),
                  ),
                ),
                if (_volumePageTurn)
                  SwitchListTile(
                    contentPadding: const EdgeInsets.only(left: 32),
                    value: _invertVolumeKeys,
                    activeTrackColor: primary,
                    activeThumbColor: primary,
                    onChanged: (value) async {
                      setState(() => _invertVolumeKeys = value);
                      setModalState(() {});
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('reader_invert_volume_keys', value);
                    },
                    title: Text(
                      'Đảo ngược chiều phím',
                      style: TextStyle(color: onSurface.withValues(alpha: 0.7), fontSize: 13),
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isIncognito,
                  activeTrackColor: Colors.purpleAccent,
                  activeThumbColor: Colors.purpleAccent,
                  onChanged: (value) {
                    setState(() => _isIncognito = value);
                    setModalState(() {});
                  },
                  title: Text(
                    'Chế độ đọc ẩn danh (Incognito)',
                    style: TextStyle(color: onSurface),
                  ),
                  subtitle: Text(
                    'Không lưu lịch sử, tiến trình đọc và không đồng bộ Cloud',
                    style: TextStyle(color: onSurface.withValues(alpha: 0.54), fontSize: 11),
                  ),
                  secondary: Icon(
                    _isIncognito ? Icons.visibility_off_rounded : Icons.visibility_outlined,
                    color: _isIncognito ? Colors.purpleAccent : onSurface.withValues(alpha: 0.54),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Danh sách bookmark & trích dẫn',
                    style: TextStyle(color: onSurface),
                  ),
                  subtitle: Text(
                    'Xem, điều hướng hoặc xoá bookmark',
                    style: TextStyle(color: onSurface.withValues(alpha: 0.54), fontSize: 11),
                  ),
                  leading: const Icon(Icons.bookmarks_outlined, color: Colors.amber),
                  trailing: Icon(Icons.chevron_right, color: onSurface.withValues(alpha: 0.38)),
                  onTap: () {
                    Navigator.pop(context);
                    _showBookmarks();
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _showTtsPanel,
                  onChanged: (value) {
                    setState(() => _showTtsPanel = value);
                    setModalState(() {});
                  },
                  title: Text(
                    'Mở bảng TTS',
                    style: TextStyle(color: onSurface),
                  ),
                  secondary: Icon(
                    Icons.record_voice_over,
                    color: onSurface.withValues(alpha: 0.54),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Từ điển sửa từ ngữ hàng loạt',
                    style: TextStyle(color: onSurface),
                  ),
                  subtitle: Text(
                    'Sửa từ dịch sai/Hán hóa (VD: Nã Phá Luân ➔ Napoleon)',
                    style: TextStyle(color: onSurface.withValues(alpha: 0.54), fontSize: 11),
                  ),
                  leading: const Icon(
                    Icons.spellcheck_rounded,
                    color: Colors.purpleAccent,
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: onSurface.withValues(alpha: 0.38),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showGlossaryManagerSheet();
                  },
                ),
              ],
            ),
          ),
        );
      },
    ),
  ),
),
),
);
  }

  @override
  void dispose() {
    if (!TtsService.instance.isPlaying) {
      WakelockPlus.disable();
    }
    _levelUpSub?.cancel();
    _verticalJumpGeneration++;
    TtsService.instance.removeListener(_onTtsServiceChanged);
    GlossaryService.instance.removeListener(_onGlossaryChanged);
    TtsService.instance.onNextChapterRequested = null;
    TtsService.instance.onPrevChapterRequested = null;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _progressTimer?.cancel();
    _ttsSettingsTimer?.cancel();
    _bookSearchTimer?.cancel();
    _lazyChapterLoader?.clear();
    _pageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onGlossaryChanged() {
    if (mounted) {
      setState(() {
        _chapterPagesCache.clear();
        _updateHorizontalWindow(_chapterIndex);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      final theme = Theme.of(context);
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'Đang phân tích nội dung EPUB...',
                style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
      );
    }
    if (_errorMessage != null || _book == null) {
      final theme = Theme.of(context);
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            tooltip: 'Quay lại',
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.auto_stories_outlined,
                    size: 52,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Không thể tải nội dung EPUB',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage ?? 'Định dạng file EPUB không hợp lệ hoặc dữ liệu chương bị lỗi.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text('Quay lại'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.onSurface,
                        side: BorderSide(color: theme.dividerColor),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _init,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Thử lại', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is! KeyDownEvent) return;
        final key = event.logicalKey;
        final isVolDown = key == LogicalKeyboardKey.audioVolumeDown;
        final isVolUp = key == LogicalKeyboardKey.audioVolumeUp;

        if ((isVolDown || isVolUp) && !_volumePageTurn) return;

        bool isNext = false;
        bool isPrev = false;

        if (isVolDown || isVolUp) {
          HapticFeedback.selectionClick();
          if (_invertVolumeKeys) {
            isNext = isVolUp;
            isPrev = isVolDown;
          } else {
            isNext = isVolDown;
            isPrev = isVolUp;
          }
        } else {
          isNext = key == LogicalKeyboardKey.arrowRight ||
              key == LogicalKeyboardKey.arrowDown ||
              key == LogicalKeyboardKey.pageDown ||
              key == LogicalKeyboardKey.space;
          isPrev = key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.pageUp;
        }

        if (isNext) {
          if (_flowType == 0) {
            if (_pageController.hasClients && _horizontalPageIndex < _windowPages.length - 1) {
              _pageController.nextPage(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
              );
            } else {
              _nextChapter();
            }
          } else {
            _verticalOffsetController.animateScroll(
              offset: 500,
              duration: const Duration(milliseconds: 200),
            );
          }
        } else if (isPrev) {
          if (_flowType == 0) {
            if (_pageController.hasClients && _horizontalPageIndex > 0) {
              _pageController.previousPage(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
              );
            } else {
              _prevChapter();
            }
          } else {
            _verticalOffsetController.animateScroll(
              offset: -500,
              duration: const Duration(milliseconds: 200),
            );
          }
        } else if (key == LogicalKeyboardKey.equal ||
                   key == LogicalKeyboardKey.add ||
                   key == LogicalKeyboardKey.numpadAdd) {
          _setFontSize((_fontSize + 1).clamp(12, 36));
        } else if (key == LogicalKeyboardKey.minus ||
                   key == LogicalKeyboardKey.numpadSubtract) {
          _setFontSize((_fontSize - 1).clamp(12, 36));
        } else if (key == LogicalKeyboardKey.keyT) {
          _toggleTts();
        } else if (key == LogicalKeyboardKey.keyB) {
          _toggleBookmark();
        } else if (key == LogicalKeyboardKey.keyM) {
          setState(() => _showControls = !_showControls);
        } else if (key == LogicalKeyboardKey.bracketLeft && _chapterIndex > 0) {
          _jumpToChapter(_chapterIndex - 1);
        } else if (key == LogicalKeyboardKey.bracketRight &&
                   _book != null &&
                   _chapterIndex < _book!.chapters.length - 1) {
          _jumpToChapter(_chapterIndex + 1);
        } else if (key == LogicalKeyboardKey.home) {
          _jumpToChapter(0);
        } else if (key == LogicalKeyboardKey.end && _book != null && _book!.chapters.isNotEmpty) {
          _jumpToChapter(_book!.chapters.length - 1);
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Color(_bgColor),
        endDrawer: _buildTocDrawer(),
        body: Stack(
          children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _viewportSize ??= Size(constraints.maxWidth, constraints.maxHeight);
                return Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _handleReaderPointerDown,
                  onPointerUp: _handleReaderPointerUp,
                  onPointerCancel: _handleReaderPointerCancel,
                  child: SelectionArea(
                    onSelectionChanged: (content) => _currentSelection = content?.plainText ?? '',
                    contextMenuBuilder: _buildContextMenu,
                    child: _flowType == 1
                        ? _buildVerticalReader()
                        : _buildHorizontalReader(),
                  ),
                );
              },
            ),
          ),
          if (_showControls)
            Positioned(left: 0, right: 0, top: 0, child: _buildReaderTopBar()),

          if (_showControls || _isTtsPlaying || TtsService.instance.isVisible)
            Positioned(left: 0, right: 0, bottom: 0, child: _buildTtsBar()),
        ],
      ),
    ),
    );
  }

  Widget _buildReaderTopBar() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: Colors.black.withValues(alpha: 0.6),
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
                icon: const Icon(Icons.menu_book, color: Colors.white),
                tooltip: 'Mục lục',
                onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
              ),
              IconButton(
                icon: Icon(
                  _isCurrentBookmark ? Icons.bookmark : Icons.bookmark_border,
                  color: _isCurrentBookmark ? Colors.amber : Colors.white,
                ),
                tooltip: _isCurrentBookmark ? 'Xoá bookmark trang này' : 'Đánh dấu trang này',
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
    ),
  ),
);
  }

  Widget _buildTocDrawer() {
    // Guard: _book có thể null khi EPUB đang reload (didUpdateWidget)
    final chapters = _book?.chapters;
    if (chapters == null || chapters.isEmpty) {
      return const Drawer(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Drawer(
      backgroundColor: Theme.of(context).cardColor,
      child: _NovelTocDrawerContent(
        chapters: chapters,
        currentIndex: _chapterIndex,
        onSelectChapter: (index) => _jumpToChapter(index),
      ),
    );
  }

  Widget _buildContextMenu(
    BuildContext context,
    SelectableRegionState selectableRegionState,
  ) {
    final selectedText = _currentSelection.trim();

    // Lọc chỉ giữ lại các thao tác chuẩn (Sao chép, Chọn tất cả, Chia sẻ), loại bỏ các app rác từ OS
    final standardItems = selectableRegionState.contextMenuButtonItems.where((item) {
      return item.type == ContextMenuButtonType.copy ||
          item.type == ContextMenuButtonType.selectAll ||
          item.type == ContextMenuButtonType.share;
    }).toList();

    final customButtons = <ContextMenuButtonItem>[
      // 1. Lưu trích dẫn
      ContextMenuButtonItem(
        label: 'Lưu trích dẫn',
        onPressed: () async {
          selectableRegionState.hideToolbar();
          if (selectedText.isNotEmpty) {
            await _saveQuote(selectedText);
          }
        },
      ),
      // 2. Sửa từ trong truyện
      ContextMenuButtonItem(
        label: 'Sửa từ trong truyện',
        onPressed: () {
          selectableRegionState.hideToolbar();
          if (selectedText.isNotEmpty) {
            _showQuickAddGlossaryDialog(this.context, selectedText);
          }
        },
      ),
      // 3. Đọc từ đây
      ContextMenuButtonItem(
        label: 'Đọc từ đây',
        onPressed: () {
          selectableRegionState.hideToolbar();
          _startTtsFromSelection(selectedText);
        },
      ),
      // 4. Đọc đoạn này
      ContextMenuButtonItem(
        label: 'Đọc đoạn này',
        onPressed: () {
          selectableRegionState.hideToolbar();
          _startTtsForSelectionOnly(selectedText);
        },
      ),
      // 5. Dịch/Tra từ
      ContextMenuButtonItem(
        label: 'Dịch/Tra từ',
        onPressed: () async {
          selectableRegionState.hideToolbar();
          if (selectedText.isNotEmpty) {
            final url = Uri.parse(
              'https://translate.google.com/?sl=auto&tl=vi&text=${Uri.encodeComponent(selectedText)}',
            );
            final messenger = ScaffoldMessenger.of(context);
            try {
              final launched = await launchUrl(
                url,
                mode: LaunchMode.inAppBrowserView,
              );
              if (!launched) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            } catch (_) {
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(content: Text('Không thể mở liên kết dịch')),
                );
            }
          }
        },
      ),
      ...standardItems,
    ];

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: selectableRegionState.contextMenuAnchors,
      buttonItems: customButtons,
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
    final chapterText = GlossaryService.instance.applyReplacements(
      EpubParser.formatChapterText(chapter),
      mangaId: widget.storageKey,
    );
    return Container(
      key: isNear ? _chapterSectionKeys[index] : null,
      padding: const EdgeInsets.only(bottom: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (chapter.blocks.isNotEmpty)
            ...chapter.blocks.asMap().entries.map((entry) {
              final blockIndex = entry.key;
              final block = entry.value;

              _blockKeys[index] ??= {};
              final key = _blockKeys[index]![blockIndex] ??= GlobalKey();

              if (block.type == EpubBlockType.image && block.image != null) {
                return Container(
                  key: isNear ? key : null,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Image.memory(block.image!, fit: BoxFit.contain),
                );
              } else if (block.type == EpubBlockType.divider) {
                return Padding(
                  key: isNear ? key : null,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: const Divider(color: Colors.white24, thickness: 1),
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

                final isCurrentChapter = _isTtsPlaying &&
                    (TtsService.instance.currentChapterIndex == index);
                final currentChunk = isCurrentChapter ? TtsService.instance.currentChunk : null;
                final isActiveBlock = currentChunk != null && currentChunk.blockIndex == blockIndex;

                int? sentenceStart;
                int? sentenceEnd;

                if (isActiveBlock) {
                  sentenceStart = currentChunk.charStartInBlock;
                  sentenceEnd = currentChunk.charEndInBlock;
                }

                final processedBlock = block.applyReplacements(
                  (text) => GlossaryService.instance.applyReplacements(
                    text,
                    mangaId: widget.storageKey,
                  ),
                );

                Widget childText = isActiveBlock
                    ? ValueListenableBuilder<({int? start, int? end})>(
                        valueListenable: TtsService.instance.wordProgressNotifier,
                        builder: (context, wordProgress, child) {
                          int? dynamicWordStart;
                          int? dynamicWordEnd;
                          if (wordProgress.start != null && wordProgress.end != null) {
                            dynamicWordStart = sentenceStart! + wordProgress.start!;
                            dynamicWordEnd = sentenceStart + wordProgress.end!;
                          }
                          return Text.rich(
                            EpubPaginator.buildHighlightedTextSpan(
                              processedBlock,
                              baseStyle,
                              sentenceStart: sentenceStart,
                              sentenceEnd: sentenceEnd,
                              wordStart: dynamicWordStart,
                              wordEnd: dynamicWordEnd,
                              sentenceHighlightColor: const Color(0x333B82F6),
                              wordHighlightColor: const Color(0x993B82F6),
                            ),
                          );
                        },
                      )
                    : Text.rich(
                        EpubPaginator.buildTextSpan(
                          processedBlock,
                          baseStyle,
                        ),
                      );

                return Container(
                  key: isNear ? key : null,
                  margin: padding,
                  child: childText,
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
              Text(
                chapterText,
                style: TextStyle(
                  color: Color(_textColor),
                  fontSize: _fontSize.toDouble(),
                  height: _lineHeight,
                  fontFamily: _fontFamily == 'Default' ? null : _fontFamily,
                ),
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

                  final isCurrentChapter = _isTtsPlaying &&
                      (TtsService.instance.currentChapterIndex == _windowCenterChapter);
                  final currentChunk = isCurrentChapter ? TtsService.instance.currentChunk : null;
                  final chunkText = currentChunk?.text.trim() ?? '';
                  final rawBlockText = block.text ?? '';
                  final matchIndex = (chunkText.isNotEmpty && rawBlockText.isNotEmpty)
                      ? rawBlockText.indexOf(chunkText)
                      : -1;
                  final isActiveBlock = matchIndex != -1;

                  int? sentenceStart;
                  int? sentenceEnd;

                  if (isActiveBlock) {
                    sentenceStart = matchIndex;
                    sentenceEnd = matchIndex + chunkText.length;
                  }

                  final processedBlock = block.applyReplacements(
                    (text) => GlossaryService.instance.applyReplacements(
                      text,
                      mangaId: widget.storageKey,
                    ),
                  );

                  Widget childText = isActiveBlock
                      ? ValueListenableBuilder<({int? start, int? end})>(
                          valueListenable: TtsService.instance.wordProgressNotifier,
                          builder: (context, wordProgress, child) {
                            int? dynamicWordStart;
                            int? dynamicWordEnd;
                            if (wordProgress.start != null && wordProgress.end != null) {
                              dynamicWordStart = sentenceStart! + wordProgress.start!;
                              dynamicWordEnd = sentenceStart + wordProgress.end!;
                            }
                            return Text.rich(
                              EpubPaginator.buildHighlightedTextSpan(
                                processedBlock,
                                baseStyle,
                                sentenceStart: sentenceStart,
                                sentenceEnd: sentenceEnd,
                                wordStart: dynamicWordStart,
                                wordEnd: dynamicWordEnd,
                                sentenceHighlightColor: const Color(0x333B82F6),
                                wordHighlightColor: const Color(0x993B82F6),
                              ),
                            );
                          },
                        )
                      : Text.rich(
                          EpubPaginator.buildTextSpan(
                            processedBlock,
                            baseStyle,
                          ),
                        );

                  return Container(
                    margin: EdgeInsets.only(bottom: _horizontalBlockSpacing),
                    child: childText,
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
    ValueChanged<double>? onChangeEnd,
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
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          activeColor: color,
          inactiveColor: Colors.white12,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }

  Widget _buildTtsBar() {
    final tts = TtsService.instance;
    final selectedVoice = _selectedVoice == null
        ? null
        : _availableVoices.firstWhereOrNull(
            (voice) =>
                voice['name'] == _selectedVoice!['name'] &&
                voice['locale'] == _selectedVoice!['locale'],
          );

    final currentChunkNum = tts.totalChunks > 0 ? tts.chunkIndex + 1 : 0;
    final totalChunksNum = tts.totalChunks;
    final progressPct = (tts.progress * 100).toInt();

    if (!_showTtsPanel) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF141416).withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Thanh tiến độ mỏng hiển thị % đọc trong chương
                      if (totalChunksNum > 0)
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                          child: LinearProgressIndicator(
                            value: tts.progress.clamp(0.0, 1.0),
                            minHeight: 2.5,
                            backgroundColor: Colors.white12,
                            valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                          ),
                        ),
                      // Dòng header nhỏ: số câu và nút đóng
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 6, 8, 0),
                        child: Row(
                          children: [
                            Icon(
                              Icons.graphic_eq_rounded,
                              size: 14,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: InkWell(
                                onTap: _showChunkPickerBottomSheet,
                                child: Text(
                                  totalChunksNum > 0
                                      ? 'Câu $currentChunkNum/$totalChunksNum • $progressPct% • ${_currentChapter.title}'
                                      : _currentChapter.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                              icon: Icon(Icons.format_list_numbered_rounded, size: 16, color: Theme.of(context).colorScheme.primary),
                              tooltip: 'Chọn câu đọc',
                              onPressed: _showChunkPickerBottomSheet,
                            ),
                            const SizedBox(width: 2),
                            InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                HapticFeedback.lightImpact();
                                tts.stopAndHide();
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.close_rounded, size: 16, color: Colors.white54),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Cụm nút điều khiển chính
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              tooltip: _flowType == 1 ? 'Chuyển lật trang' : 'Chuyển cuộn dọc',
                              icon: Icon(
                                _flowType == 1 ? Icons.swap_vert_rounded : Icons.swap_horiz_rounded,
                                color: Colors.white70,
                                size: 20,
                              ),
                              onPressed: () => _setFlowType(_flowType == 1 ? 0 : 1),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              tooltip: 'Chương trước',
                              icon: const Icon(Icons.fast_rewind_rounded, color: Colors.white, size: 22),
                              onPressed: _prevChapter,
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              tooltip: 'Lùi 1 câu',
                              icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 24),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                tts.prevChunk();
                              },
                            ),
                            // Nút Phát / Tạm dừng nổi bật
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(26),
                                onTap: () {
                                  HapticFeedback.mediumImpact();
                                  _toggleTts();
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.all(11),
                                  decoration: BoxDecoration(
                                    color: _isTtsPlaying
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.white.withValues(alpha: 0.18),
                                    shape: BoxShape.circle,
                                    boxShadow: _isTtsPlaying
                                        ? [
                                            BoxShadow(
                                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                                              blurRadius: 12,
                                              spreadRadius: 2,
                                            )
                                          ]
                                        : null,
                                  ),
                                  child: Icon(
                                    _isTtsPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    color: _isTtsPlaying ? Theme.of(context).colorScheme.onPrimary : Colors.white,
                                    size: 26,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              tooltip: 'Tiến 1 câu',
                              icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 24),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                tts.nextChunk();
                              },
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              tooltip: 'Chương sau',
                              icon: const Icon(Icons.fast_forward_rounded, color: Colors.white, size: 22),
                              onPressed: _nextChapter,
                            ),
                            // Nút đổi nhanh tốc độ đọc
                            InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                tts.cycleSpeed();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Text(
                                  '${_ttsRate.toStringAsFixed(1)}x',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              tooltip: 'Mở rộng cài đặt',
                              icon: const Icon(
                                Icons.keyboard_arrow_up_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                              onPressed: () {
                                setState(() => _showTtsPanel = true);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF161618).withValues(alpha: 0.94),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Nút kéo xuống thu nhỏ
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    setState(() => _showTtsPanel = false);
                  },
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(24, 0, 24, 6),
                    child: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54, size: 26),
                  ),
                ),

                // Thông tin tiến độ câu & chương kèm nút chọn danh sách câu
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _currentChapter.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _showChunkPickerBottomSheet,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                totalChunksNum > 0
                                    ? 'Câu $currentChunkNum / $totalChunksNum ($progressPct%)'
                                    : '',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.format_list_numbered_rounded, size: 16, color: Theme.of(context).colorScheme.primary),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Slider tua câu mượt mà
                if (totalChunksNum > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 4),
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        trackHeight: 3,
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                        activeTrackColor: Theme.of(context).colorScheme.primary,
                        inactiveTrackColor: Colors.white12,
                        thumbColor: Theme.of(context).colorScheme.primary,
                      ),
                      child: Slider(
                        value: tts.chunkIndex.toDouble().clamp(0.0, (totalChunksNum - 1).toDouble()),
                        min: 0.0,
                        max: (totalChunksNum - 1).toDouble(),
                        divisions: max(1, totalChunksNum - 1),
                        onChanged: (val) {
                          tts.seekToChunk(val.round());
                        },
                      ),
                    ),
                  ),

                // Hàng điều khiển đa phương tiện đầy đủ
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      tooltip: _flowType == 1 ? 'Cuộn dọc' : 'Vuốt ngang',
                      icon: Icon(
                        _flowType == 1 ? Icons.swap_vert_rounded : Icons.swap_horiz_rounded,
                        color: Colors.white70,
                      ),
                      onPressed: () => _setFlowType(_flowType == 1 ? 0 : 1),
                    ),
                    IconButton(
                      tooltip: 'Chương trước',
                      icon: const Icon(Icons.fast_rewind_rounded, color: Colors.white, size: 26),
                      onPressed: _prevChapter,
                    ),
                    IconButton(
                      tooltip: 'Lùi 1 câu',
                      icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 28),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        tts.prevChunk();
                      },
                    ),
                    // Nút Play / Pause lớn trung tâm
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(32),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _toggleTts();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Theme.of(context).colorScheme.primary,
                                Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                              ],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                                blurRadius: 14,
                                spreadRadius: 2,
                              )
                            ],
                          ),
                          child: Icon(
                            _isTtsPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Theme.of(context).colorScheme.onPrimary,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tiến 1 câu',
                      icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 28),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        tts.nextChunk();
                      },
                    ),
                    IconButton(
                      tooltip: 'Chương sau',
                      icon: const Icon(Icons.fast_forward_rounded, color: Colors.white, size: 26),
                      onPressed: _nextChapter,
                    ),
                    IconButton(
                      tooltip: 'Tắt hoàn toàn TTS',
                      icon: const Icon(Icons.power_settings_new_rounded, color: Colors.redAccent),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        tts.stopAndHide();
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                // Slider Tốc độ đọc (Hỗ trợ từ 0.5x đến 3.0x theo yêu cầu)
                _buildTtsSlider(
                  icon: Icons.speed_rounded,
                  label: 'Tốc độ: ${_ttsRate.toStringAsFixed(2)}x',
                  value: _ttsRate.clamp(0.5, 3.0),
                  min: 0.5,
                  max: 3.0,
                  divisions: 25,
                  color: Theme.of(context).colorScheme.primary,
                  onChanged: (val) {
                    setState(() => _ttsRate = val);
                  },
                  onChangeEnd: (val) {
                    _setTtsRate(val, restartIfPlaying: true);
                  },
                ),

                // Slider Cao độ giọng
                _buildTtsSlider(
                  icon: Icons.music_note_rounded,
                  label: 'Cao độ: ${_ttsPitch.toStringAsFixed(2)}',
                  value: _ttsPitch.clamp(0.5, 2.0),
                  min: 0.5,
                  max: 2.0,
                  divisions: 15,
                  color: Colors.purpleAccent,
                  onChanged: (val) {
                    setState(() => _ttsPitch = val);
                  },
                  onChangeEnd: (val) {
                    _setTtsPitch(val, restartIfPlaying: true);
                  },
                ),

                const SizedBox(height: 8),

                // Hàng Voice, Ngôn ngữ, Hẹn giờ, Từ điển
                Row(
                  children: [
                    // Chọn giọng
                    Expanded(
                      flex: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<Map<String, String>>(
                            isExpanded: true,
                            dropdownColor: const Color(0xFF2C2C2E),
                            value: selectedVoice,
                            hint: const Text(
                              'Chọn giọng nói',
                              style: TextStyle(color: Colors.white54, fontSize: 12),
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
                    ),
                    const SizedBox(width: 8),

                    // Từ điển sửa từ
                    IconButton(
                      tooltip: 'Từ điển sửa từ',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.purpleAccent.withValues(alpha: 0.15),
                      ),
                      icon: const Icon(
                        Icons.spellcheck_rounded,
                        color: Colors.purpleAccent,
                        size: 20,
                      ),
                      onPressed: _showGlossaryManagerSheet,
                    ),
                    const SizedBox(width: 4),

                    // Ngôn ngữ
                    PopupMenuButton<String>(
                      tooltip: 'Ngôn ngữ',
                      icon: const Icon(Icons.language_rounded, color: Colors.white70, size: 20),
                      color: const Color(0xFF2C2C2E),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onSelected: _setTtsLang,
                      itemBuilder: (_) => _supportedLangs
                          .map(
                            (entry) => PopupMenuItem<String>(
                              value: entry.$1,
                              child: Row(
                                children: [
                                  Text(entry.$2, style: const TextStyle(color: Colors.white)),
                                  if (_ttsLang == entry.$1) ...[
                                    const SizedBox(width: 8),
                                    Icon(
                                      Icons.check,
                                      size: 16,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(width: 4),

                    // Hẹn giờ tắt
                    PopupMenuButton<int>(
                      tooltip: 'Hẹn giờ tắt',
                      color: const Color(0xFF2C2C2E),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onSelected: (val) {
                        if (val == -1) {
                          TtsService.instance.setStopAtEndOfChapter(true);
                          _setSleepTimer(0);
                        } else {
                          TtsService.instance.setStopAtEndOfChapter(false);
                          _setSleepTimer(val);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: -1, child: Text('Hết chương', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold))),
                        PopupMenuItem(value: 0, child: Text('Không hẹn giờ', style: TextStyle(color: Colors.white))),
                        PopupMenuItem(value: 15, child: Text('15 phút', style: TextStyle(color: Colors.white))),
                        PopupMenuItem(value: 30, child: Text('30 phút', style: TextStyle(color: Colors.white))),
                        PopupMenuItem(value: 45, child: Text('45 phút', style: TextStyle(color: Colors.white))),
                        PopupMenuItem(value: 60, child: Text('60 phút', style: TextStyle(color: Colors.white))),
                        PopupMenuItem(value: 90, child: Text('90 phút', style: TextStyle(color: Colors.white))),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: (tts.stopAtEndOfChapter || _sleepTimeMinutes > 0)
                              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: (tts.stopAtEndOfChapter || _sleepTimeMinutes > 0) ? Theme.of(context).colorScheme.primary : Colors.white12,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 15,
                              color: (tts.stopAtEndOfChapter || _sleepTimeMinutes > 0) ? Theme.of(context).colorScheme.primary : Colors.white70,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              tts.stopAtEndOfChapter
                                  ? 'Hết chương'
                                  : (_sleepTimeMinutes > 0 ? '$_sleepTimeMinutes p' : 'Hẹn giờ'),
                              style: TextStyle(
                                color: (tts.stopAtEndOfChapter || _sleepTimeMinutes > 0) ? Theme.of(context).colorScheme.primary : Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  Future<void> _showQuickAddGlossaryDialog(
    BuildContext context,
    String originalWord,
  ) async {
    await showDialog(
      context: context,
      builder: (ctx) => _QuickAddGlossaryDialog(
        originalWord: originalWord,
        storageKey: widget.storageKey,
      ),
    );
  }

  Future<void> _showGlossaryManagerSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GlossaryManagerSheet(
        mangaId: widget.storageKey,
        mangaTitle: widget.title,
      ),
    );
  }
}

class _GlossaryManagerSheet extends StatefulWidget {
  final String mangaId;
  final String mangaTitle;

  const _GlossaryManagerSheet({
    required this.mangaId,
    required this.mangaTitle,
  });

  @override
  State<_GlossaryManagerSheet> createState() => _GlossaryManagerSheetState();
}

class _GlossaryManagerSheetState extends State<_GlossaryManagerSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _communitySearchCtrl = TextEditingController();
  String _communitySearchQuery = '';
  String _communitySortBy = 'downloadsCount'; // 'downloadsCount' | 'createdAt' | 'likesCount'
  Stream<List<CommunityGlossaryPack>>? _communityPacksStream;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _updateStream();
  }

  void _updateStream() {
    _communityPacksStream = CommunityGlossaryService.instance.streamCommunityPacks(
      sortBy: _communitySortBy,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _communitySearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _showAddEditRuleDialog([GlossaryRule? existingRule, bool defaultMangaOnly = true]) async {
    await showDialog(
      context: context,
      builder: (ctx) => _AddEditRuleDialog(
        existingRule: existingRule,
        defaultMangaOnly: defaultMangaOnly,
        mangaId: widget.mangaId,
      ),
    );
  }

  Future<void> _showPublishPackDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng đăng nhập để chia sẻ gói từ điển')),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (ctx) => _PublishPackDialog(
        mangaId: widget.mangaId,
        mangaTitle: widget.mangaTitle,
      ),
    );
  }

  Future<void> _showPreviewPackDialog(CommunityGlossaryPack pack) async {
    await showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final onSurface = theme.colorScheme.onSurface;
        return AlertDialog(
          backgroundColor: theme.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              Icon(Icons.preview_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pack.title,
                  style: TextStyle(color: onSurface, fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tác giả: ${pack.authorName} • ${pack.rules.length} từ',
                  style: TextStyle(color: onSurface.withValues(alpha: 0.6), fontSize: 12),
                ),
                if (pack.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    pack.description,
                    style: TextStyle(color: onSurface.withValues(alpha: 0.7), fontSize: 13),
                  ),
                ],
                Divider(color: theme.dividerColor, height: 16),
                Expanded(
                  child: ListView.separated(
                    itemCount: pack.rules.length,
                    separatorBuilder: (_, __) => Divider(color: theme.dividerColor, height: 1),
                    itemBuilder: (ctx, idx) {
                      final r = pack.rules[idx];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                r.from,
                                style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                            Icon(Icons.arrow_forward_rounded, color: theme.colorScheme.primary, size: 14),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                r.to,
                                style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Đóng', style: TextStyle(color: onSurface.withValues(alpha: 0.6))),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _importPackDialog(pack);
              },
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Nhập gói này'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _importPackDialog(CommunityGlossaryPack pack) async {
    bool isMangaOnly = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final theme = Theme.of(ctx);
          final onSurface = theme.colorScheme.onSurface;
          return AlertDialog(
            backgroundColor: theme.cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                Icon(Icons.download_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Nhập Gói Từ Điển',
                  style: TextStyle(color: onSurface, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bạn muốn áp dụng ${pack.rules.length} từ trong gói "${pack.title}" vào đâu?',
                  style: TextStyle(color: onSurface.withValues(alpha: 0.7), fontSize: 13.5),
                ),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setDialogState(() => isMangaOnly = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isMangaOnly
                          ? theme.colorScheme.primary.withValues(alpha: 0.15)
                          : onSurface.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isMangaOnly ? theme.colorScheme.primary : theme.dividerColor,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isMangaOnly ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: isMangaOnly ? theme.colorScheme.primary : onSurface.withValues(alpha: 0.54),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Chỉ áp dụng cho truyện này (${widget.mangaTitle})',
                            style: TextStyle(
                              color: isMangaOnly ? onSurface : onSurface.withValues(alpha: 0.7),
                              fontSize: 13,
                              fontWeight: isMangaOnly ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setDialogState(() => isMangaOnly = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: !isMangaOnly
                          ? theme.colorScheme.primary.withValues(alpha: 0.15)
                          : onSurface.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: !isMangaOnly ? theme.colorScheme.primary : theme.dividerColor,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          !isMangaOnly ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: !isMangaOnly ? theme.colorScheme.primary : onSurface.withValues(alpha: 0.54),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Áp dụng toàn cầu (Tất cả các truyện)',
                            style: TextStyle(
                              color: !isMangaOnly ? onSurface : onSurface.withValues(alpha: 0.7),
                              fontSize: 13,
                              fontWeight: !isMangaOnly ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Hủy', style: TextStyle(color: onSurface.withValues(alpha: 0.6))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(ctx);
                  final count = await CommunityGlossaryService.instance.importPackToLocal(
                    pack,
                    targetMangaId: isMangaOnly ? widget.mangaId : null,
                  );
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('✅ Đã nhập thành công $count từ vào từ điển!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
                child: const Text('Xác nhận nhập'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GlossaryService.instance,
      builder: (context, _) {
        final allRules = GlossaryService.instance.rules;
        final mangaRules = allRules.where((r) => r.mangaId == widget.mangaId).toList();
        final globalRules = allRules.where((r) => r.mangaId == null).toList();

        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
                child: Row(
                  children: [
                    Icon(Icons.spellcheck_rounded, color: Theme.of(context).colorScheme.primary, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Từ Điển Sửa Từ Ngữ (Glossary)',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Tự động thay thế từ khi đọc & khi nghe TTS',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.cloud_upload_rounded, color: Theme.of(context).colorScheme.primary, size: 24),
                      tooltip: 'Đăng gói lên cộng đồng',
                      onPressed: _showPublishPackDialog,
                    ),
                    IconButton(
                      icon: Icon(Icons.add_circle, color: Theme.of(context).colorScheme.primary, size: 28),
                      tooltip: 'Thêm từ sửa mới',
                      onPressed: () => _showAddEditRuleDialog(null, _tabController.index == 0),
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabController,
                indicatorColor: Theme.of(context).colorScheme.primary,
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                tabs: [
                  Tab(text: 'Truyện này (${mangaRules.length})'),
                  Tab(text: 'Toàn cầu (${globalRules.length})'),
                  const Tab(text: 'Cộng đồng 🌐'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildRuleList(mangaRules, isMangaTab: true),
                    _buildRuleList(globalRules, isMangaTab: false),
                    _buildCommunityTab(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCommunityTab() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Column(
      children: [
        // Search and Sort bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: TextField(
                    controller: _communitySearchCtrl,
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                    decoration: InputDecoration(
                      hintText: 'Tìm gói theo tên truyện, tác giả, từ...',
                      hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38), fontSize: 12),
                      prefixIcon: Icon(Icons.search, size: 16, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38)),
                      suffixIcon: _communitySearchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, size: 14, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38)),
                              onPressed: () {
                                _communitySearchCtrl.clear();
                                setState(() => _communitySearchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (val) => setState(() => _communitySearchQuery = val),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'Sắp xếp',
                color: Theme.of(context).cardColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (val) {
                  setState(() {
                    _communitySortBy = val;
                    _updateStream();
                  });
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'downloadsCount', child: Text('Tải nhiều nhất 🔥')),
                  PopupMenuItem(value: 'createdAt', child: Text('Mới nhất ⏱️')),
                  PopupMenuItem(value: 'likesCount', child: Text('Yêu thích ❤️')),
                ],
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _communitySortBy == 'downloadsCount'
                            ? Icons.local_fire_department_rounded
                            : _communitySortBy == 'createdAt'
                                ? Icons.access_time_rounded
                                : Icons.favorite_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down, size: 18, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Packs Stream List
        Expanded(
          child: StreamBuilder<List<CommunityGlossaryPack>>(
            stream: _communityPacksStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary));
              }

              final allPacks = snapshot.data ?? [];
              var packs = allPacks;
              if (_communitySearchQuery.isNotEmpty) {
                final q = _communitySearchQuery.toLowerCase().trim();
                packs = packs.where((p) {
                  return p.title.toLowerCase().contains(q) ||
                      p.description.toLowerCase().contains(q) ||
                      (p.mangaTitle != null && p.mangaTitle!.toLowerCase().contains(q)) ||
                      p.authorName.toLowerCase().contains(q) ||
                      p.rules.any((r) => r.from.toLowerCase().contains(q) || r.to.toLowerCase().contains(q));
                }).toList();
              }
              if (packs.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_off_rounded, size: 48, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.24)),
                        const SizedBox(height: 12),
                        Text(
                          'Chưa có gói từ điển cộng đồng nào',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purpleAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _showPublishPackDialog,
                          icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                          label: const Text('Chia sẻ gói đầu tiên'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                itemCount: packs.length,
                itemBuilder: (context, index) {
                  final pack = packs[index];
                  final isLiked = currentUserId != null && pack.likedUserIds.contains(currentUserId);
                  final isAuthor = currentUserId != null && pack.authorId == currentUserId;

                  return Card(
                    color: Theme.of(context).cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: Colors.purpleAccent.withValues(alpha: 0.3),
                                backgroundImage: pack.authorAvatar.isNotEmpty
                                    ? NetworkImage(pack.authorAvatar)
                                    : null,
                                child: pack.authorAvatar.isEmpty
                                    ? Text(
                                        pack.authorName.isNotEmpty ? pack.authorName[0].toUpperCase() : 'U',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      pack.title,
                                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    Text(
                                      '${pack.authorName} • ${pack.rules.length} từ',
                                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              if (isAuthor)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        backgroundColor: Theme.of(ctx).cardColor,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        title: Text('Xóa gói từ điển?', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface, fontWeight: FontWeight.bold)),
                                        content: Text('Bạn có chắc muốn xóa gói "${pack.title}" khỏi cộng đồng?', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.7))),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Hủy', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6)))),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                                            onPressed: () => Navigator.pop(ctx, true),
                                            child: const Text('Xóa'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      await CommunityGlossaryService.instance.deletePack(pack.id);
                                    }
                                  },
                                ),
                            ],
                          ),
                          if (pack.description.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              pack.description,
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7), fontSize: 12.5),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 8),
                          // Preview pills of top 2 rules
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              ...pack.rules.take(2).map((r) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${r.from} ➔ ${r.to}',
                                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
                                    ),
                                  )),
                              if (pack.rules.length > 2)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.purpleAccent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '+${pack.rules.length - 2} từ',
                                    style: const TextStyle(fontSize: 11, color: Colors.purpleAccent, fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () => CommunityGlossaryService.instance.toggleLike(pack.id),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                      child: Row(
                                        children: [
                                          Icon(
                                            isLiked ? Icons.favorite : Icons.favorite_border,
                                            size: 15,
                                            color: isLiked ? Colors.redAccent : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                                          ),
                                          const SizedBox(width: 4),
                                          Text('${pack.likesCount}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Row(
                                    children: [
                                      Icon(Icons.download_rounded, size: 15, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)),
                                      const SizedBox(width: 4),
                                      Text('${pack.downloadsCount}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
                                    ],
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: () => _showPreviewPackDialog(pack),
                                    child: Text('Xem chi tiết', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
                                  ),
                                  const SizedBox(width: 4),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.purpleAccent,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () => _importPackDialog(pack),
                                    icon: const Icon(Icons.download_rounded, size: 14),
                                    label: const Text('Nhập gói', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRuleList(List<GlossaryRule> rules, {required bool isMangaTab}) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    if (rules.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.text_fields_rounded, size: 48, color: onSurface.withValues(alpha: 0.24)),
              const SizedBox(height: 12),
              Text(
                isMangaTab
                    ? 'Chưa có từ sửa đổi nào cho bộ truyện này'
                    : 'Chưa có từ sửa đổi toàn cầu nào',
                textAlign: TextAlign.center,
                style: TextStyle(color: onSurface.withValues(alpha: 0.6), fontSize: 14),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purpleAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _showAddEditRuleDialog(null, isMangaTab),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Thêm từ đầu tiên'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      itemCount: rules.length,
      itemBuilder: (context, index) {
        final rule = rules[index];
        return Card(
          color: theme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: theme.dividerColor),
          ),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    rule.from,
                    style: TextStyle(
                      color: rule.isEnabled ? Colors.orangeAccent : onSurface.withValues(alpha: 0.38),
                      fontWeight: FontWeight.bold,
                      decoration: rule.isEnabled ? null : TextDecoration.lineThrough,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward_rounded, color: Colors.purpleAccent, size: 16),
                ),
                Flexible(
                  child: Text(
                    rule.to,
                    style: TextStyle(
                      color: rule.isEnabled ? Colors.greenAccent : onSurface.withValues(alpha: 0.38),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: rule.isEnabled,
                  activeTrackColor: Colors.purpleAccent,
                  activeThumbColor: Colors.purpleAccent,
                  onChanged: (_) => GlossaryService.instance.toggleRule(rule.id),
                ),
                IconButton(
                  icon: Icon(Icons.edit_outlined, size: 20, color: onSurface.withValues(alpha: 0.6)),
                  onPressed: () => _showAddEditRuleDialog(rule, isMangaTab),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                  onPressed: () => GlossaryService.instance.deleteRule(rule.id),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NovelTocDrawerContent extends StatefulWidget {
  final List<EpubChapter> chapters;
  final int currentIndex;
  final ValueChanged<int> onSelectChapter;

  const _NovelTocDrawerContent({
    required this.chapters,
    required this.currentIndex,
    required this.onSelectChapter,
  });

  @override
  State<_NovelTocDrawerContent> createState() => _NovelTocDrawerContentState();
}

class _NovelTocDrawerContentState extends State<_NovelTocDrawerContent> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;
  bool _isSortReversed = false;
  bool _hasAutoScrolled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasAutoScrolled && mounted && _scrollController.hasClients && widget.currentIndex > 0) {
        _hasAutoScrolled = true;
        final targetOffset = (widget.currentIndex * 56.0 - 150.0).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.jumpTo(targetOffset);
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery =
        CatalogCacheService.instance.normalize(_searchQuery);
    final indexedChapters = widget.chapters.asMap().entries.toList();

    final filtered = normalizedQuery.isEmpty
        ? indexedChapters
        : indexedChapters.where((entry) {
            final normTitle =
                CatalogCacheService.instance.normalize(entry.value.title);
            final chapNum = '${entry.key + 1}';
            final normChap = 'chuong $chapNum';
            return normTitle.contains(normalizedQuery) ||
                chapNum.contains(normalizedQuery) ||
                normChap.contains(normalizedQuery);
          }).toList();

    final displayChapters =
        _isSortReversed ? filtered.reversed.toList() : filtered;

    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mục lục',
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.chapters.length} chương',
                        style: TextStyle(
                          color: onSurface.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: _isSortReversed ? 'Đảo thứ tự (Mới nhất)' : 'Đảo thứ tự (Cũ nhất)',
                  icon: Icon(
                    _isSortReversed ? Icons.arrow_downward : Icons.arrow_upward,
                    color: onSurface.withValues(alpha: 0.7),
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() => _isSortReversed = !_isSortReversed);
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: onSurface, fontSize: 13),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Tìm kiếm chương...',
                hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.38), fontSize: 13),
                prefixIcon: Icon(Icons.search, color: onSurface.withValues(alpha: 0.38), size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: onSurface.withValues(alpha: 0.38), size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: onSurface.withValues(alpha: 0.08),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) {
                if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 150), () {
                  if (mounted) setState(() => _searchQuery = val);
                });
              },
            ),
          ),
          const SizedBox(height: 4),
          Divider(height: 1, color: theme.dividerColor),
          Expanded(
            child: displayChapters.isEmpty
                ? Center(
                    child: Text(
                      'Không tìm thấy chương phù hợp',
                      style: TextStyle(color: onSurface.withValues(alpha: 0.38), fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: displayChapters.length,
                    itemBuilder: (context, i) {
                      final originalIndex = displayChapters[i].key;
                      final chapter = displayChapters[i].value;
                      final isCurrent = originalIndex == widget.currentIndex;

                      return ListTile(
                        selected: isCurrent,
                        selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                        leading: isCurrent
                            ? Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              )
                            : null,
                        title: Text(
                          chapter.title.isEmpty ? 'Chương ${originalIndex + 1}' : chapter.title,
                          style: TextStyle(
                            color: isCurrent
                                ? theme.colorScheme.primary
                                : onSurface.withValues(alpha: 0.75),
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          widget.onSelectChapter(originalIndex);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _QuickAddGlossaryDialog extends StatefulWidget {
  final String originalWord;
  final String? storageKey;

  const _QuickAddGlossaryDialog({
    required this.originalWord,
    this.storageKey,
  });

  @override
  State<_QuickAddGlossaryDialog> createState() => _QuickAddGlossaryDialogState();
}

class _QuickAddGlossaryDialogState extends State<_QuickAddGlossaryDialog> {
  late final TextEditingController _toController;
  bool _isMangaOnly = true;

  @override
  void initState() {
    super.initState();
    _toController = TextEditingController();
  }

  @override
  void dispose() {
    _toController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final target = _toController.text.trim();
    if (target.isEmpty) return;
    Navigator.pop(context);
    await GlossaryService.instance.addRule(
      from: widget.originalWord,
      to: target,
      mangaId: _isMangaOnly ? widget.storageKey : null,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã cập nhật quy tắc: "${widget.originalWord}" ➔ "$target"'),
          backgroundColor: Colors.purple,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return AlertDialog(
      backgroundColor: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Icon(Icons.spellcheck_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            'Sửa Từ Ngữ Hàng Loạt',
            style: TextStyle(
              color: onSurface,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Từ gốc trong truyện:',
            style: TextStyle(color: onSurface.withValues(alpha: 0.7), fontSize: 13),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: onSurface.withValues(alpha: 0.12)),
            ),
            child: Text(
              widget.originalWord,
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Thay thế thành (chuẩn hiển thị & TTS):',
            style: TextStyle(color: onSurface.withValues(alpha: 0.7), fontSize: 13),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _toController,
            autofocus: true,
            style: TextStyle(color: onSurface),
            decoration: InputDecoration(
              hintText: 'Ví dụ: Napoleon, Edison, 100%...',
              hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.38)),
              filled: true,
              fillColor: onSurface.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _isMangaOnly,
            activeTrackColor: theme.colorScheme.primary,
            activeThumbColor: theme.colorScheme.primary,
            onChanged: (val) => setState(() => _isMangaOnly = val),
            title: Text(
              'Chỉ áp dụng cho bộ truyện này',
              style: TextStyle(color: onSurface, fontSize: 13),
            ),
            subtitle: Text(
              _isMangaOnly
                  ? 'Chỉ sửa trong truyện hiện tại'
                  : 'Sửa trong tất cả các truyện trên máy',
              style: TextStyle(color: onSurface.withValues(alpha: 0.54), fontSize: 11),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Hủy', style: TextStyle(color: onSurface.withValues(alpha: 0.6))),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: _save,
          child: const Text('Lưu & Sửa ngay'),
        ),
      ],
    );
  }
}

class _AddEditRuleDialog extends StatefulWidget {
  final GlossaryRule? existingRule;
  final bool defaultMangaOnly;
  final String? mangaId;

  const _AddEditRuleDialog({
    this.existingRule,
    this.defaultMangaOnly = true,
    this.mangaId,
  });

  @override
  State<_AddEditRuleDialog> createState() => _AddEditRuleDialogState();
}

class _AddEditRuleDialogState extends State<_AddEditRuleDialog> {
  late final TextEditingController _fromController;
  late final TextEditingController _toController;
  late bool _isMangaOnly;

  @override
  void initState() {
    super.initState();
    _fromController = TextEditingController(text: widget.existingRule?.from ?? '');
    _toController = TextEditingController(text: widget.existingRule?.to ?? '');
    _isMangaOnly = widget.existingRule != null
        ? widget.existingRule!.mangaId != null
        : widget.defaultMangaOnly;
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final from = _fromController.text.trim();
    final to = _toController.text.trim();
    if (from.isEmpty) return;
    Navigator.pop(context);
    if (widget.existingRule != null) {
      await GlossaryService.instance.updateRule(
        GlossaryRule(
          id: widget.existingRule!.id,
          from: from,
          to: to,
          mangaId: _isMangaOnly ? widget.mangaId : null,
          isEnabled: widget.existingRule!.isEnabled,
          createdAt: widget.existingRule!.createdAt,
        ),
      );
    } else {
      await GlossaryService.instance.addRule(
        from: from,
        to: to,
        mangaId: _isMangaOnly ? widget.mangaId : null,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return AlertDialog(
      backgroundColor: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Icon(Icons.spellcheck_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            widget.existingRule == null ? 'Thêm Từ Sửa Đổi' : 'Chỉnh Sửa Từ',
            style: TextStyle(
              color: onSurface,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Từ gốc / Từ bị dịch sai:', style: TextStyle(color: onSurface.withValues(alpha: 0.7), fontSize: 13)),
          const SizedBox(height: 4),
          TextField(
            controller: _fromController,
            autofocus: widget.existingRule == null,
            style: TextStyle(color: onSurface),
            decoration: InputDecoration(
              hintText: 'Ví dụ: Nã Phá Luân, Ái Nhân Tôn...',
              hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.38)),
              filled: true,
              fillColor: onSurface.withValues(alpha: 0.06),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 12),
          Text('Thay thế thành:', style: TextStyle(color: onSurface.withValues(alpha: 0.7), fontSize: 13)),
          const SizedBox(height: 4),
          TextField(
            controller: _toController,
            style: TextStyle(color: onSurface),
            decoration: InputDecoration(
              hintText: 'Ví dụ: Napoleon, Edison...',
              hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.38)),
              filled: true,
              fillColor: onSurface.withValues(alpha: 0.06),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _isMangaOnly,
            activeTrackColor: theme.colorScheme.primary,
            activeThumbColor: theme.colorScheme.primary,
            onChanged: (val) => setState(() => _isMangaOnly = val),
            title: Text('Chỉ áp dụng cho truyện này', style: TextStyle(color: onSurface, fontSize: 13)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Hủy', style: TextStyle(color: onSurface.withValues(alpha: 0.6))),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _save,
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}

class _PublishPackDialog extends StatefulWidget {
  final String mangaId;
  final String mangaTitle;

  const _PublishPackDialog({
    required this.mangaId,
    required this.mangaTitle,
  });

  @override
  State<_PublishPackDialog> createState() => _PublishPackDialogState();
}

class _PublishPackDialogState extends State<_PublishPackDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late int _selectedScope;
  late final List<GlossaryRule> _allRules;
  late final List<GlossaryRule> _mangaRules;
  late final List<GlossaryRule> _globalRules;

  @override
  void initState() {
    super.initState();
    _allRules = GlossaryService.instance.rules;
    _mangaRules = _allRules.where((r) => r.mangaId == widget.mangaId).toList();
    _globalRules = _allRules.where((r) => r.mangaId == null).toList();
    _selectedScope = _mangaRules.isNotEmpty ? 0 : 1;
    _titleCtrl = TextEditingController(
      text: _selectedScope == 0
          ? 'Từ điển chuẩn hóa: ${widget.mangaTitle}'
          : 'Bộ từ điển Convert tiếng Trung phổ biến',
    );
    _descCtrl = TextEditingController(
      text: 'Chuẩn hóa tên nhân vật và địa danh bị dịch sai/Hán hóa.',
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  List<GlossaryRule> get _targetRules {
    if (_selectedScope == 0) return _mangaRules;
    if (_selectedScope == 1) return _globalRules;
    return _allRules;
  }

  Future<void> _publish() async {
    final title = _titleCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    if (title.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    try {
      await CommunityGlossaryService.instance.publishPack(
        title: title,
        description: desc,
        mangaTitle: _selectedScope == 0 ? widget.mangaTitle : null,
        rules: _targetRules,
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('🎉 Đã chia sẻ gói từ điển lên cộng đồng thành công!'),
          backgroundColor: Colors.purple,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Lỗi chia sẻ: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final targetRules = _targetRules;

    return AlertDialog(
      backgroundColor: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          const Icon(Icons.cloud_upload_rounded, color: Colors.purpleAccent),
          const SizedBox(width: 8),
          Text(
            'Đăng Gói Từ Điển Lên Cloud',
            style: TextStyle(color: onSurface, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chọn nguồn từ cần chia sẻ:', style: TextStyle(color: onSurface.withValues(alpha: 0.7), fontSize: 13)),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: _selectedScope,
              dropdownColor: theme.cardColor,
              decoration: InputDecoration(
                filled: true,
                fillColor: onSurface.withValues(alpha: 0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: [
                DropdownMenuItem(
                  value: 0,
                  child: Text('Chỉ từ của truyện này (${_mangaRules.length} từ)'),
                ),
                DropdownMenuItem(
                  value: 1,
                  child: Text('Chỉ từ toàn cầu (${_globalRules.length} từ)'),
                ),
                DropdownMenuItem(
                  value: 2,
                  child: Text('Tất cả từ trên máy (${_allRules.length} từ)'),
                ),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedScope = val;
                    _titleCtrl.text = _selectedScope == 0
                        ? 'Từ điển chuẩn hóa: ${widget.mangaTitle}'
                        : 'Bộ từ điển Convert tiếng Trung phổ biến';
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            Text('Tên gói từ điển:', style: TextStyle(color: onSurface.withValues(alpha: 0.7), fontSize: 13)),
            const SizedBox(height: 4),
            TextField(
              controller: _titleCtrl,
              style: TextStyle(color: onSurface),
              decoration: InputDecoration(
                hintText: 'Ví dụ: Chuẩn hóa Convert One Piece...',
                hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.38)),
                filled: true,
                fillColor: onSurface.withValues(alpha: 0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            Text('Mô tả ngắn gọn:', style: TextStyle(color: onSurface.withValues(alpha: 0.7), fontSize: 13)),
            const SizedBox(height: 4),
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              style: TextStyle(color: onSurface),
              decoration: InputDecoration(
                hintText: 'Tóm tắt nội dung gói từ điển...',
                hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.38)),
                filled: true,
                fillColor: onSurface.withValues(alpha: 0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sẽ tải lên ${targetRules.length} cặp từ sửa đổi.',
              style: TextStyle(color: theme.colorScheme.primary, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Hủy', style: TextStyle(color: onSurface.withValues(alpha: 0.6))),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: targetRules.isEmpty ? null : _publish,
          child: const Text('Đăng ngay'),
        ),
      ],
    );
  }
}

