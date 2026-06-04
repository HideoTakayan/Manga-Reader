import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/database_helper.dart';
import '../../data/models_cloud.dart';
import '../../features/shared/drive_image.dart';
import '../../services/history_service.dart';
import 'novel_reader_widget.dart';
import 'pdf_reader_view.dart';
import 'reader_provider.dart';

class ReaderPage extends ConsumerStatefulWidget {
  final String chapterId;
  final String? mangaId;
  const ReaderPage({super.key, required this.chapterId, this.mangaId});

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

// SingleTickerProviderStateMixin: cung cấp vsync cho AnimationController
// → tiết kiệm tài nguyên, chỉ dùng khi có đúng 1 AnimationController
class _ReaderPageState extends ConsumerState<ReaderPage>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late ScrollController _scrollController;
  final FocusNode _focusNode = FocusNode();

  // ==== HỆ THỐNG HOLD-TO-LOAD (chuyển chương bằng cách giữ ở vùng biên) ====
  // Tránh chuyển chương vô tình khi cuộn quá đà — phải giữ 1.5 giây mới chuyển

  bool _isInNextChapterZone = false; // Đang trong vùng dưới (gần hết chương)
  bool _isInPrevChapterZone = false; // Đang trong vùng trên (overscroll ngược)
  bool _isHoldingForNextChapter = false; // Đang đếm ngược để sang chương sau
  bool _isHoldingForPrevChapter = false; // Đang đếm ngược để về chương trước

  Timer? _holdTimer;
  Timer? _progressSaveTimer;
  Ticker? _autoScrollTicker;
  Duration? _lastAutoScrollTick;
  bool _isAutoScrolling = false;
  int _autoPageTurnRunId = 0;
  double? _lastVerticalProgressSaveOffset;
  int? _lastVerticalProgressSavePage;
  static const double _autoScrollPixelsPerSecond = 132.0;
  static const double _verticalProgressSaveDelta = 160.0;
  static const Duration _autoPageTurnInterval = Duration(
    milliseconds: 1200,
  ); // Đợi 1200ms + 280ms anim = ~1.5s
  static const Duration _holdDuration = Duration(milliseconds: 1500);

  late AnimationController _holdProgressController;
  final ValueNotifier<int> _currentPageNotifier = ValueNotifier<int>(0);

  DateTime? _lastChapterChange;
  static const Duration _chapterChangeCooldown = Duration(seconds: 2);
  bool _isChapterTransitionLocked = false;
  String? _restoredScrollChapterId;

  static const double _nextChapterThreshold = 100.0;
  static const double _prevChapterThreshold = -60.0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _scrollController = ScrollController();

    _holdProgressController = AnimationController(
      vsync: this,
      duration: _holdDuration,
    );

    _scrollController.addListener(_onVerticalScroll);

    // Kích hoạt chế độ toàn màn hình
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(readerProvider.notifier)
          .init(widget.chapterId, mangaId: widget.mangaId);
    });
  }

  void _onVerticalScroll() {
    final state = ref.read(readerProvider);

    if (state.readingMode != ReadingMode.vertical) return;
    if (!_scrollController.hasClients) return;

    final pixels = _scrollController.position.pixels;
    final maxExtent = _scrollController.position.maxScrollExtent;

    final isNearEnd = pixels >= maxExtent - _nextChapterThreshold;

    final isOverscrollTop = pixels < _prevChapterThreshold;

    if (isNearEnd && !_isInNextChapterZone) {
      _enterNextChapterZone();
    } else if (!isNearEnd && _isInNextChapterZone) {
      _exitNextChapterZone();
    }
    if (isOverscrollTop && !_isInPrevChapterZone) {
      _enterPrevChapterZone();
    } else if (!isOverscrollTop && _isInPrevChapterZone) {
      _exitPrevChapterZone();
    }

    final pageCount = state.pages.length;
    final estimatedPage = pageCount <= 1 || maxExtent <= 0
        ? 0
        : ((pixels / maxExtent) * (pageCount - 1)).round().clamp(
            0,
            pageCount - 1,
          );
          
    if (_currentPageNotifier.value != estimatedPage) {
      _currentPageNotifier.value = estimatedPage;
    }
    
    _scheduleVerticalProgressSaveIfNeeded(pixels, estimatedPage);
  }

  void _scheduleVerticalProgressSaveIfNeeded(double offset, int pageIndex) {
    final previousOffset = _lastVerticalProgressSaveOffset;
    final previousPage = _lastVerticalProgressSavePage;
    final movedEnough =
        previousOffset == null ||
        (offset - previousOffset).abs() >= _verticalProgressSaveDelta;
    final pageChanged = previousPage == null || previousPage != pageIndex;

    if (!movedEnough && !pageChanged) return;

    _lastVerticalProgressSaveOffset = offset;
    _lastVerticalProgressSavePage = pageIndex;
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      ref
          .read(readerProvider.notifier)
          .saveScrollProgress(offset, pageIndex: pageIndex);
    });
  }

  void _toggleAutoScroll() {
    if (_isAutoScrolling) {
      _stopAutoScroll();
    } else {
      _startAutoScroll();
    }
  }

  void _startAutoScroll() {
    final state = ref.read(readerProvider);
    if (state.isPdf) return;
    if (state.readingMode == ReadingMode.vertical &&
        !_scrollController.hasClients) {
      return;
    }
    if (state.readingMode == ReadingMode.horizontal &&
        !_pageController.hasClients) {
      return;
    }

    setState(() => _isAutoScrolling = true);
    _autoScrollTicker?.dispose();
    _autoScrollTicker = null;
    _lastAutoScrollTick = null;
    _autoPageTurnRunId++;

    if (state.readingMode == ReadingMode.horizontal) {
      _scheduleHorizontalAutoPageTurn(_autoPageTurnRunId);
      return;
    }

    _autoScrollTicker = createTicker((elapsed) {
      if (!mounted || !_scrollController.hasClients) {
        _stopAutoScroll();
        return;
      }

      final lastTick = _lastAutoScrollTick;
      _lastAutoScrollTick = elapsed;
      if (lastTick == null) return;

      final position = _scrollController.position;
      if (position.pixels >= position.maxScrollExtent) {
        _stopAutoScroll();
        return;
      }

      final deltaSeconds =
          (elapsed - lastTick).inMicroseconds / Duration.microsecondsPerSecond;
      final safeDeltaSeconds = deltaSeconds.clamp(0.0, 0.05).toDouble();
      final nextOffset =
          position.pixels + (_autoScrollPixelsPerSecond * safeDeltaSeconds);
      _scrollController.jumpTo(nextOffset.clamp(0.0, position.maxScrollExtent));
    });
    _autoScrollTicker?.start();
  }

  void _scheduleHorizontalAutoPageTurn(int runId) {
    Future.delayed(_autoPageTurnInterval, () async {
      if (!mounted || !_isAutoScrolling || runId != _autoPageTurnRunId) {
        return;
      }
      await _advanceHorizontalAutoPage(runId);
    });
  }

  Future<void> _advanceHorizontalAutoPage(int runId) async {
    if (!mounted || !_pageController.hasClients) {
      _stopAutoScroll();
      return;
    }

    final state = ref.read(readerProvider);
    final notifier = ref.read(readerProvider.notifier);
    if (state.readingMode != ReadingMode.horizontal || state.isPdf) {
      _stopAutoScroll();
      return;
    }

    final pageCount = state.pages.length;
    if (pageCount <= 0) {
      _stopAutoScroll();
      return;
    }
    if (state.isLoadingNextChapter) {
      _scheduleHorizontalAutoPageTurn(runId);
      return;
    }

    final currentPage = state.currentPageIndex.clamp(0, pageCount - 1);
    if (currentPage < pageCount - 1) {
      await _pageController.animateToPage(
        currentPage + 1,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      if (mounted && _isAutoScrolling && runId == _autoPageTurnRunId) {
        _scheduleHorizontalAutoPageTurn(runId);
      }
      return;
    }

    if (notifier.getNextChapterId() != null && !_isChapterTransitionLocked) {
      final changedChapter = await _triggerNextChapter(
        resumeHorizontalAuto: true,
      );
      if (!changedChapter &&
          mounted &&
          _isAutoScrolling &&
          runId == _autoPageTurnRunId) {
        _scheduleHorizontalAutoPageTurn(runId);
      }
      return;
    }

    _stopAutoScroll();
  }

  void _stopAutoScroll() {
    _autoScrollTicker?.dispose();
    _autoScrollTicker = null;
    _lastAutoScrollTick = null;
    _autoPageTurnRunId++;
    if (mounted && _isAutoScrolling) {
      setState(() => _isAutoScrolling = false);
    } else {
      _isAutoScrolling = false;
    }
  }

  Future<void> _toggleFollowWithFeedback(
    ReaderState state,
    ReaderNotifier notifier,
  ) async {
    if (state.isFollowed) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          title: const Text(
            'Hủy Theo Dõi?',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Bạn có chắc chắn muốn hủy theo dõi truyện này?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Đồng ý',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    try {
      final isNowFollowed = await notifier.toggleFollow();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isNowFollowed ? 'Đã theo dõi thành công!' : 'Đã hủy theo dõi',
          ),
          backgroundColor: isNowFollowed ? Colors.green : null,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _enterNextChapterZone() {
    final notifier = ref.read(readerProvider.notifier);
    if (notifier.getNextChapterId() == null) return;
    if (_isChapterTransitionLocked) return;

    setState(() {
      _isInNextChapterZone = true;
      _isHoldingForNextChapter = true;
    });

    _holdProgressController.forward(from: 0);
    _holdTimer = Timer(_holdDuration, () {
      _triggerNextChapter();
    });
  }

  void _exitNextChapterZone() {
    setState(() {
      _isInNextChapterZone = false;
      _isHoldingForNextChapter = false;
    });
    _cancelHoldTimer();
  }

  void _enterPrevChapterZone() {
    final notifier = ref.read(readerProvider.notifier);
    if (notifier.getPrevChapterId() == null) return;
    if (_isChapterTransitionLocked) return;

    setState(() {
      _isInPrevChapterZone = true;
      _isHoldingForPrevChapter = true;
    });

    _holdProgressController.forward(from: 0);
    _holdTimer = Timer(_holdDuration, () {
      _triggerPrevChapter();
    });
  }

  void _exitPrevChapterZone() {
    setState(() {
      _isInPrevChapterZone = false;
      _isHoldingForPrevChapter = false;
    });
    _cancelHoldTimer();
  }

  void _cancelHoldTimer() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdProgressController.stop();
    _holdProgressController.reset();
  }

  Future<bool> _triggerNextChapter({bool resumeHorizontalAuto = false}) async {
    if (_isChapterTransitionLocked) return false;
    if (_lastChapterChange != null &&
        DateTime.now().difference(_lastChapterChange!) <
            _chapterChangeCooldown) {
      return false;
    }

    final previousChapterId = ref.read(readerProvider).currentChapter?.id;
    setState(() {
      _isChapterTransitionLocked = true;
      _isHoldingForNextChapter = false;
    });
    _lastChapterChange = DateTime.now();
    HapticFeedback.mediumImpact();

    var changedChapter = false;
    try {
      await ref.read(readerProvider.notifier).loadNextChapter();
      if (!mounted) return false;

      final nextState = ref.read(readerProvider);
      changedChapter =
          previousChapterId != null &&
          previousChapterId != nextState.currentChapter?.id;

      if (nextState.readingMode == ReadingMode.vertical &&
          _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      } else if (nextState.readingMode == ReadingMode.horizontal) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_pageController.hasClients) {
            _pageController.jumpToPage(0);
          }
          if (resumeHorizontalAuto &&
              _isAutoScrolling &&
              changedChapter &&
              ref.read(readerProvider).readingMode == ReadingMode.horizontal &&
              !ref.read(readerProvider).isPdf) {
            _scheduleHorizontalAutoPageTurn(_autoPageTurnRunId);
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isChapterTransitionLocked = false;
          _isInNextChapterZone = false;
        });
        _cancelHoldTimer();
      }
    }

    return changedChapter;
  }

  Future<void> _triggerPrevChapter() async {
    if (_isChapterTransitionLocked) return;

    if (_lastChapterChange != null &&
        DateTime.now().difference(_lastChapterChange!) <
            _chapterChangeCooldown) {
      return;
    }

    setState(() {
      _isChapterTransitionLocked = true;
      _isHoldingForPrevChapter = false;
    });

    _lastChapterChange = DateTime.now();

    HapticFeedback.mediumImpact();

    try {
      await ref.read(readerProvider.notifier).loadPrevChapter();
    } finally {
      if (mounted) {
        setState(() {
          _isChapterTransitionLocked = false;
          _isInPrevChapterZone = false;
        });
        _cancelHoldTimer();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final nextState = ref.read(readerProvider);
          if (nextState.readingMode == ReadingMode.vertical &&
              _scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent - 200,
            );
          } else if (nextState.readingMode == ReadingMode.horizontal &&
              _pageController.hasClients &&
              nextState.pages.isNotEmpty) {
            _pageController.jumpToPage(nextState.pages.length - 1);
          }
        });
      }
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _scrollController.removeListener(_onVerticalScroll);
    _cancelHoldTimer();
    _progressSaveTimer?.cancel();
    _autoScrollTicker?.dispose();
    _holdProgressController.dispose();
    _pageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event, ReaderState state) {
    if (state.isPdf) return;
    if (event is! KeyDownEvent) return;

    if (event.logicalKey == LogicalKeyboardKey.audioVolumeDown ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (state.readingMode == ReadingMode.horizontal) {
        if (state.currentPageIndex < state.pages.length - 1) {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
        } else {
          _triggerNextChapter();
        }
      } else {
        final currentOffset = _scrollController.offset;
        final maxScroll = _scrollController.position.maxScrollExtent;
        _scrollController.animateTo(
          (currentOffset + 500).clamp(0.0, maxScroll),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      }
    } else if (event.logicalKey == LogicalKeyboardKey.audioVolumeUp ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (state.readingMode == ReadingMode.horizontal) {
        if (state.currentPageIndex > 0) {
          _pageController.previousPage(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
        } else {
          _triggerPrevChapter();
        }
      } else {
        final currentOffset = _scrollController.offset;
        _scrollController.animateTo(
          (currentOffset - 500).clamp(
            0.0,
            _scrollController.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  void _jumpToPage(int pageIndex) {
    final state = ref.read(readerProvider);
    if (!state.isPdf && state.pages.isEmpty) return;

    final pageCount = state.isPdf ? state.pdfPageCount : state.pages.length;
    if (pageCount <= 0) return;

    final target = pageIndex.clamp(0, pageCount - 1);
    ref.read(readerProvider.notifier).onPageChanged(target);

    // PDF handles jumping via initialPage passing to PdfReaderView
    if (state.isPdf) return;

    if (state.readingMode == ReadingMode.horizontal) {
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
      return;
    }

    if (_scrollController.hasClients && state.pages.length > 1) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final offset = maxScroll * (target / (state.pages.length - 1));
      _scrollController.animateTo(
        offset.clamp(0.0, maxScroll),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  Object _initialPhotoScale(ReaderImageFit fit) {
    switch (fit) {
      case ReaderImageFit.width:
        return PhotoViewComputedScale.covered;
      case ReaderImageFit.screen:
        return PhotoViewComputedScale.contained;
      case ReaderImageFit.original:
        return 1.0;
    }
  }

  BoxFit _verticalImageFit(ReaderImageFit fit) {
    switch (fit) {
      case ReaderImageFit.width:
        return BoxFit.fitWidth;
      case ReaderImageFit.screen:
        return BoxFit.contain;
      case ReaderImageFit.original:
        return BoxFit.none;
    }
  }

  Color _readerBackgroundColor(ReaderBackground background) {
    switch (background) {
      case ReaderBackground.black:
        return Colors.black;
      case ReaderBackground.gray:
        return const Color(0xFF2B2B2B);
      case ReaderBackground.white:
        return Colors.white;
    }
  }

  String _readerRoute(String chapterId, String? mangaId) {
    if (mangaId == null || mangaId.isEmpty) return '/reader/$chapterId';
    return '/reader/$chapterId?mangaId=${Uri.encodeComponent(mangaId)}';
  }

  void _reloadCurrentChapter(ReaderNotifier notifier) {
    final state = ref.read(readerProvider);
    final chapterId = state.currentChapter?.id ?? widget.chapterId;
    final mangaId = state.mangaId ?? widget.mangaId;
    notifier.init(chapterId, mangaId: mangaId);
  }

  void _precacheNearbyPages(ReaderState state) {
    if (!mounted || state.pages.isEmpty) return;
    final start = (state.currentPageIndex - 2).clamp(0, state.pages.length - 1);
    final end = (state.currentPageIndex + 2).clamp(0, state.pages.length - 1);
    for (var i = start; i <= end; i++) {
      precacheImage(FileImage(File(state.pages[i])), context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readerProvider);
    final notifier = ref.read(readerProvider.notifier);

    if (!state.isLoading && state.isNovel && state.epubBytes != null) {
      return NovelReaderWidget(
        epubBytes: state.epubBytes!,
        storageKey: [
          state.mangaId,
          state.currentChapter?.id,
        ].whereType<String>().where((value) => value.isNotEmpty).join('_'),
        title:
            state.currentChapter?.title ?? state.manga?.title ?? 'Truyện chữ',
      );
    }

    ref.listen<ReaderState>(readerProvider, (prev, next) {
      if (_isAutoScrolling &&
          (next.isPdf ||
              (prev?.currentChapter?.id != next.currentChapter?.id &&
                  next.readingMode != ReadingMode.horizontal))) {
        _stopAutoScroll();
      }

      if (prev?.currentPageIndex != next.currentPageIndex ||
          prev?.pages.length != next.pages.length) {
        _precacheNearbyPages(next);
        if (next.currentPageIndex != _currentPageNotifier.value) {
          _currentPageNotifier.value = next.currentPageIndex;
        }
      }

      if (prev?.currentPageIndex != next.currentPageIndex &&
          next.readingMode == ReadingMode.horizontal) {
        if (_pageController.hasClients &&
            _pageController.page?.round() != next.currentPageIndex) {
          _pageController.jumpToPage(next.currentPageIndex);
        }
      }

      final chapterId = next.currentChapter?.id;
      if (!next.isLoading &&
          next.readingMode == ReadingMode.vertical &&
          chapterId != null &&
          _restoredScrollChapterId != chapterId &&
          next.scrollOffset > 0) {
        _restoredScrollChapterId = chapterId;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          final maxScroll = _scrollController.position.maxScrollExtent;
          _scrollController.jumpTo(next.scrollOffset.clamp(0.0, maxScroll));
        });
      }
    });

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) => _handleKeyEvent(event, state),
      child: Scaffold(
        backgroundColor: _readerBackgroundColor(state.background),
        drawer: _buildDrawer(state, notifier),
        body: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : state.errorMessage != null
            ? _buildReaderError(state.errorMessage!, notifier)
            : Stack(
                children: [
                  // Nội dung
                  GestureDetector(
                    onTapUp: (details) {
                      final screenWidth = MediaQuery.of(context).size.width;
                      final tapX = details.globalPosition.dx;

                      if (state.readingMode == ReadingMode.horizontal &&
                          !state.isPdf) {
                        if (tapX < screenWidth * 0.3) {
                          if (state.direction == ReaderDirection.rtl) {
                            if (state.currentPageIndex <
                                state.pages.length - 1) {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeInOut,
                              );
                            } else {
                              _triggerNextChapter();
                            }
                          } else {
                            if (state.currentPageIndex > 0) {
                              _pageController.previousPage(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeInOut,
                              );
                            } else {
                              _triggerPrevChapter();
                            }
                          }
                        } else if (tapX > screenWidth * 0.7) {
                          if (state.direction == ReaderDirection.rtl) {
                            if (state.currentPageIndex > 0) {
                              _pageController.previousPage(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeInOut,
                              );
                            } else {
                              _triggerPrevChapter();
                            }
                          } else {
                            if (state.currentPageIndex <
                                state.pages.length - 1) {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeInOut,
                              );
                            } else {
                              _triggerNextChapter();
                            }
                          }
                        } else {
                          // Tap Center 40% -> Toggle menu
                          notifier.toggleControls();
                        }
                      } else {
                        // Vertical mode or PDF: Tap Center = menu, otherwise menu (for now keep simple)
                        notifier.toggleControls();
                      }
                    },
                    child: state.isPdf && state.pdfBytes != null
                        ? PdfReaderView(
                            pdfBytes: state.pdfBytes!,
                            initialPage: state.currentPageIndex,
                            onDocumentLoaded: (pageCount) {
                              notifier.setPdfPageCount(pageCount);
                            },
                            onPageChanged: (pageIndex) {
                              notifier.onPageChanged(pageIndex);
                              _scheduleVerticalProgressSaveIfNeeded(
                                0.0,
                                pageIndex,
                              );
                            },
                            onToggleControls: notifier.toggleControls,
                          )
                        : state.readingMode == ReadingMode.horizontal
                        ? _buildHorizontalView(state, notifier)
                        : _buildVerticalView(state, notifier),
                  ),

                  if (state.showControls)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: EdgeInsets.fromLTRB(
                          10,
                          MediaQuery.of(context).padding.top + 5,
                          10,
                          10,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.9),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Nút quay lại
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back,
                                color: Colors.white,
                                size: 24,
                              ),
                              onPressed: () => context.pop(),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 10),

                            // Ảnh bìa
                            if (state.manga != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: DriveImage(
                                  fileId: state.manga!.coverFileId,
                                  width: 40,
                                  height: 60,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            const SizedBox(width: 10),

                            // Thông tin & Chọn chương
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    state.manga?.title ?? 'Đang tải...',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (state.manga?.author != null)
                                    Text(
                                      state.manga!.author,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  const SizedBox(height: 4),

                                  // Nút chọn chương
                                  InkWell(
                                    onTap: () => _showChapterListModal(
                                      context,
                                      state.chapters,
                                      state.currentChapter,
                                      state.mangaId,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.list,
                                            color: Colors.white70,
                                            size: 14,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            state.currentChapter?.title ??
                                                'Chương ?',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.keyboard_arrow_down,
                                            color: Colors.white70,
                                            size: 14,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Nút Menu (Ngăn kéo)
                            if (!state.isPdf) // Ẩn Thumbnail grid khi đọc PDF
                              IconButton(
                                icon: const Icon(
                                  Icons.grid_view,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                tooltip: 'Danh sách trang',
                                onPressed: () => _showPageThumbnailSheet(state),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            IconButton(
                              icon: const Icon(
                                Icons.report_problem,
                                color: Colors.orangeAccent,
                                size: 24,
                              ),
                              tooltip: 'Báo lỗi',
                              onPressed: () => _showReportDialog(state),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              icon: const Icon(
                                Icons.tune,
                                color: Colors.white,
                                size: 24,
                              ),
                              tooltip: 'Cài đặt đọc',
                              onPressed: () =>
                                  _showReaderSettings(context, state, notifier),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 10),
                            Builder(
                              builder: (context) => IconButton(
                                icon: const Icon(
                                  Icons.menu,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                onPressed: () =>
                                    Scaffold.of(context).openDrawer(),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // LỚP PHỦ DƯỚI CÙNG
                  if (state.showControls)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 96,
                      child: ValueListenableBuilder<int>(
                        valueListenable: _currentPageNotifier,
                        builder: (context, currentPage, _) =>
                            _buildPageSlider(state, currentPage),
                      ),
                    ),

                  if (state.showControls)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 30,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.9),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back_ios,
                                color: Colors.white,
                              ),
                              onPressed: notifier.getPrevChapterId() != null
                                  ? () => context.pushReplacement(
                                      _readerRoute(
                                        notifier.getPrevChapterId()!,
                                        state.mangaId,
                                      ),
                                    )
                                  : null,
                            ),
                            IconButton(
                              icon: Icon(
                                state.isFollowed
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: state.isFollowed
                                    ? Colors.red
                                    : Colors.white,
                              ),
                              onPressed: () =>
                                  _toggleFollowWithFeedback(state, notifier),
                            ),

                            IconButton(
                              tooltip: state.isCurrentPageBookmarked
                                  ? 'Bỏ bookmark'
                                  : 'Bookmark trang này',
                              icon: Icon(
                                state.isCurrentPageBookmarked
                                    ? Icons.bookmark
                                    : Icons.bookmark_border,
                                color: state.isCurrentPageBookmarked
                                    ? Colors.amber
                                    : Colors.white,
                              ),
                              onPressed: () async {
                                final added = await notifier.toggleBookmark();
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      added
                                          ? 'Đã thêm bookmark'
                                          : 'Đã bỏ bookmark',
                                    ),
                                  ),
                                );
                              },
                            ),

                            IconButton(
                              tooltip: _isAutoScrolling
                                  ? 'Tắt tự động đọc'
                                  : state.readingMode == ReadingMode.horizontal
                                  ? 'Tự lật trang'
                                  : 'Tự cuộn',
                              icon: Icon(
                                _isAutoScrolling
                                    ? Icons.pause_circle
                                    : Icons.play_circle,
                                color: state.isPdf
                                    ? Colors.white30
                                    : Colors.white,
                              ),
                              onPressed: state.isPdf ? null : _toggleAutoScroll,
                            ),

                            IconButton(
                              icon: const Icon(
                                Icons.arrow_forward_ios,
                                color: Colors.white,
                              ),
                              onPressed: notifier.getNextChapterId() != null
                                  ? () => context.pushReplacement(
                                      _readerRoute(
                                        notifier.getNextChapterId()!,
                                        state.mangaId,
                                      ),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  // Chế độ đọc NGANG: PhotoViewGallery — swipe trái/phải giữa các trang
  // MemoryImage(Uint8List): ảnh đã decode (unzip .cbz) sẵn trong provider
  // PhotoViewComputedScale.contained: hiện đủ cả trang trong màn hình
  // maxScale: covered * 2 → zoom tối đa 2x
  Widget _buildPageSlider(ReaderState state, int currentPage) {
    final pageCount = state.isPdf ? state.pdfPageCount : state.pages.length;
    if (pageCount <= 0) return const SizedBox.shrink();
    final hasMultiplePages = pageCount > 1;
    final clampedPage = currentPage.clamp(
      0,
      pageCount > 0 ? pageCount - 1 : 0,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'Trang ${clampedPage + 1}/$pageCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  state.readingMode == ReadingMode.vertical
                      ? 'Cuộn dọc'
                      : 'Vuốt ngang',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.0,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 6.0,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 14.0,
                ),
              ),
              child: Slider(
                value: hasMultiplePages ? clampedPage.toDouble() : 0,
                min: 0,
                max: hasMultiplePages ? (pageCount - 1).toDouble() : 1,
                divisions: hasMultiplePages ? pageCount - 1 : null,
                activeColor: Colors.blueAccent,
                inactiveColor: Colors.white24,
                onChanged: hasMultiplePages
                    ? (value) => _jumpToPage(value.round())
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReaderError(String message, ReaderNotifier notifier) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Không mở được chương',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _reloadCurrentChapter(notifier),
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }

  void _showReportDialog(ReaderState state) {
    if (state.mangaId == null || state.manga == null) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bạn cần đăng nhập để báo lỗi.')),
      );
      return;
    }

    String selectedReason = 'Lỗi ảnh';
    final descController = TextEditingController();
    final pageCount = state.isPdf ? state.pdfPageCount : state.pages.length;
    final currentPage = pageCount <= 0
        ? 0
        : state.currentPageIndex.clamp(0, pageCount - 1);
    final readerType = state.isPdf ? 'pdf' : 'manga';

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1C1C1E),
              title: const Text(
                'Báo lỗi chương',
                style: TextStyle(color: Colors.white),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Loại lỗi:',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<String>(
                      value: selectedReason,
                      dropdownColor: const Color(0xFF2C2C2E),
                      style: const TextStyle(color: Colors.white),
                      isExpanded: true,
                      items: ['Lỗi ảnh', 'Sai chương', 'Thiếu trang', 'Khác']
                          .map(
                            (r) => DropdownMenuItem(value: r, child: Text(r)),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setDialogState(() => selectedReason = v!),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Mô tả thêm (Tùy chọn):',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 3,
                      decoration: const InputDecoration(
                        filled: true,
                        fillColor: Color(0xFF2C2C2E),
                        border: OutlineInputBorder(),
                        hintText: 'Nhập mô tả chi tiết...',
                        hintStyle: TextStyle(color: Colors.white30),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Hủy',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final description = descController.text.trim();
                    Navigator.pop(ctx);
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      final doc = FirebaseFirestore.instance
                          .collection('reports')
                          .doc();
                      await doc.set(
                        Report(
                          id: doc.id,
                          mangaId: state.mangaId!,
                          mangaTitle: state.manga!.title,
                          chapterId:
                              state.currentChapter?.id ?? widget.chapterId,
                          chapterTitle: state.currentChapter?.title ?? '',
                          userId: uid,
                          reason: selectedReason,
                          description: description,
                          readerType: readerType,
                          pageIndex: currentPage,
                          totalPages: pageCount,
                          createdAt: DateTime.now(),
                        ).toMap(),
                      );

                      if (mounted) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Cảm ơn bạn đã báo lỗi!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Lỗi: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                  ),
                  child: const Text(
                    'Gửi',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(descController.dispose);
  }

  void _showReaderSettings(
    BuildContext context,
    ReaderState state,
    ReaderNotifier notifier,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      showDragHandle: true,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final current = ref.watch(readerProvider);
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cài đặt đọc truyện tranh',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Chế độ đọc',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<ReadingMode>(
                        segments: const [
                          ButtonSegment(
                            value: ReadingMode.vertical,
                            icon: Icon(Icons.swap_vert),
                            label: Text('Dọc'),
                          ),
                          ButtonSegment(
                            value: ReadingMode.horizontal,
                            icon: Icon(Icons.swap_horiz),
                            label: Text('Ngang'),
                          ),
                        ],
                        selected: {current.readingMode},
                        onSelectionChanged: (values) =>
                            notifier.setReadingMode(values.first),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Hướng đọc ngang',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<ReaderDirection>(
                        segments: const [
                          ButtonSegment(
                            value: ReaderDirection.ltr,
                            icon: Icon(Icons.arrow_forward),
                            label: Text('Trái qua phải'),
                          ),
                          ButtonSegment(
                            value: ReaderDirection.rtl,
                            icon: Icon(Icons.arrow_back),
                            label: Text('Phải qua trái'),
                          ),
                        ],
                        selected: {current.direction},
                        onSelectionChanged: (values) =>
                            notifier.setDirection(values.first),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Fit ảnh',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<ReaderImageFit>(
                        segments: const [
                          ButtonSegment(
                            value: ReaderImageFit.width,
                            icon: Icon(Icons.fit_screen),
                            label: Text('Rộng'),
                          ),
                          ButtonSegment(
                            value: ReaderImageFit.screen,
                            icon: Icon(Icons.fullscreen),
                            label: Text('Màn hình'),
                          ),
                          ButtonSegment(
                            value: ReaderImageFit.original,
                            icon: Icon(Icons.image),
                            label: Text('Gốc'),
                          ),
                        ],
                        selected: {current.imageFit},
                        onSelectionChanged: (values) =>
                            notifier.setImageFit(values.first),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Màu nền',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<ReaderBackground>(
                        segments: const [
                          ButtonSegment(
                            value: ReaderBackground.black,
                            icon: Icon(Icons.dark_mode),
                            label: Text('Đen'),
                          ),
                          ButtonSegment(
                            value: ReaderBackground.gray,
                            icon: Icon(Icons.contrast),
                            label: Text('Xám'),
                          ),
                          ButtonSegment(
                            value: ReaderBackground.white,
                            icon: Icon(Icons.light_mode),
                            label: Text('Trắng'),
                          ),
                        ],
                        selected: {current.background},
                        onSelectionChanged: (values) =>
                            notifier.setBackground(values.first),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showPageThumbnailSheet(ReaderState state) {
    if (state.pages.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Danh sách trang',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      '${state.pages.length} trang',
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView.builder(
                    itemCount: state.pages.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.68,
                        ),
                    itemBuilder: (context, index) {
                      final selected = index == state.currentPageIndex;
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          Navigator.of(context).pop();
                          _jumpToPage(index);
                        },
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selected
                                  ? Colors.blueAccent
                                  : Colors.white12,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(7),
                                child: Image.file(
                                  File(state.pages[index]),
                                  fit: BoxFit.cover,
                                  cacheWidth: 300,
                                  gaplessPlayback: true,
                                ),
                              ),
                              Positioned(
                                left: 4,
                                bottom: 4,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.72),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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

  Widget _buildHorizontalView(ReaderState state, ReaderNotifier notifier) {
    return PhotoViewGallery.builder(
      scrollPhysics: const BouncingScrollPhysics(),
      builder: (context, index) {
        if (index == state.pages.length) {
          return PhotoViewGalleryPageOptions.customChild(
            child: Center(
              child: _buildHorizontalChapterTransitionFooter(state, notifier),
            ),
            initialScale: PhotoViewComputedScale.contained,
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.contained,
          );
        }

        return PhotoViewGalleryPageOptions(
          imageProvider: ResizeImage(
            FileImage(File(state.pages[index])),
            width:
                (MediaQuery.of(context).size.width *
                        MediaQuery.of(context).devicePixelRatio)
                    .toInt(),
          ),
          initialScale: _initialPhotoScale(state.imageFit),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
        );
      },
      itemCount: state.pages.length + 1,
      pageController: _pageController,
      reverse: state.direction == ReaderDirection.rtl,
      onPageChanged: (index) {
        if (index < state.pages.length) {
          notifier.onPageChanged(index);
        }
      },
      loadingBuilder: (context, event) =>
          const Center(child: CircularProgressIndicator()),
      backgroundDecoration: BoxDecoration(
        color: _readerBackgroundColor(state.background),
      ),
    );
  }

  Widget _buildHorizontalChapterTransitionFooter(
    ReaderState state,
    ReaderNotifier notifier,
  ) {
    final hasNextChapter = notifier.getNextChapterId() != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.keyboard_double_arrow_right,
            color: Colors.white54,
            size: 40,
          ),
          const SizedBox(height: 16),
          Text(
            'Hết ${state.currentChapter?.title ?? 'chương'}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 20),
          if (state.isLoadingNextChapter)
            const Column(
              children: [
                CircularProgressIndicator(strokeWidth: 2),
                SizedBox(height: 12),
                Text(
                  'Đang tải chương tiếp theo...',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            )
          else if (hasNextChapter)
            FilledButton.icon(
              onPressed: _isChapterTransitionLocked
                  ? null
                  : () => _triggerNextChapter(),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Đọc chương tiếp'),
            )
          else
            const Column(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.green, size: 32),
                SizedBox(height: 8),
                Text(
                  'Đây là chương cuối cùng',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // Chế độ đọc DỌC: ListView cuộn liên tục
  // Cấu trúc item: [header] [trang 0] [trang 1] ... [trang N] [footer]
  // BouncingScrollPhysics: cho phép overscroll ở đầu → kích hoạt prev chapter zone
  Widget _buildVerticalView(ReaderState state, ReaderNotifier notifier) {
    final itemCount = state.pages.length + 2; // +2 = header + footer

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      physics: const BouncingScrollPhysics(),
      itemCount: itemCount,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemBuilder: (context, index) {
        if (index == 0) return _buildChapterTransitionHeader(state, notifier);
        if (index == itemCount - 1) {
          return _buildChapterTransitionFooter(state, notifier);
        }
        // pageIndex = index - 1 vì index 0 là header
        final pageIndex = index - 1;
        return Transform.translate(
          offset: const Offset(0, -0.5), // Khử hở viền 1px
          child: Image.file(
            File(state.pages[pageIndex]),
            fit: _verticalImageFit(state.imageFit),
            width: double.infinity,
            alignment: Alignment.topCenter,
            cacheWidth:
                (MediaQuery.of(context).size.width *
                        MediaQuery.of(context).devicePixelRatio)
                    .toInt(),
            filterQuality: FilterQuality.none, // Khử anti-aliasing
            errorBuilder: (_, __, ___) => const SizedBox(
              height: 200,
              child: Icon(Icons.broken_image, color: Colors.white),
            ),
          ),
        );
      },
    );
  }

  // Tiêu đề chuyển chương (cho chương trước) với vòng tròn giữ để tải
  Widget _buildChapterTransitionHeader(
    ReaderState state,
    ReaderNotifier notifier,
  ) {
    final hasPrevChapter = notifier.getPrevChapterId() != null;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 40),

          // Đang tải, đang giữ, hoặc chỉ báo chương trước
          if (state.isLoadingPrevChapter)
            const Column(
              children: [
                CircularProgressIndicator(strokeWidth: 2),
                SizedBox(height: 12),
                Text(
                  'Đang tải chương trước...',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            )
          else if (_isHoldingForPrevChapter && hasPrevChapter)
            // Hiển thị vòng tròn tiến trình khi đang giữ
            Column(
              children: [
                const SizedBox(height: 20),
                SizedBox(
                  width: 60,
                  height: 60,
                  child: AnimatedBuilder(
                    animation: _holdProgressController,
                    builder: (context, child) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          // Vòng tròn nền
                          CircularProgressIndicator(
                            value: 1.0,
                            strokeWidth: 4,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          // Vòng tròn tiến trình
                          CircularProgressIndicator(
                            value: _holdProgressController.value,
                            strokeWidth: 4,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.blueAccent,
                            ),
                          ),
                          // Biểu tượng mũi tên lên
                          Icon(
                            Icons.arrow_upward,
                            color: Colors.blueAccent.withValues(
                              alpha:
                                  0.5 + (_holdProgressController.value * 0.5),
                            ),
                            size: 24,
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Giữ để đọc chương trước...',
                  style: TextStyle(
                    color: Colors.blueAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            )
          else if (hasPrevChapter)
            Column(
              children: [
                const Icon(
                  Icons.keyboard_double_arrow_up,
                  color: Colors.white54,
                  size: 28,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Cuộn thêm để đọc chương trước',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                // Nút nhấn thủ công
                OutlinedButton.icon(
                  onPressed: () => notifier.loadPrevChapter(),
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Chương trước'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                  ),
                ),
              ],
            )
          else
            Column(
              children: [
                const Icon(
                  Icons.first_page,
                  color: Colors.blueAccent,
                  size: 32,
                ),
                const SizedBox(height: 8),
                Text(
                  'Đây là chương đầu tiên',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

          const SizedBox(height: 20),

          // Đường chia mờ dần
          Container(
            height: 2,
            width: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.white.withValues(alpha: 0.2),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // Chân trang chuyển chương (cho chương sau) với vòng tròn giữ để tải
  Widget _buildChapterTransitionFooter(
    ReaderState state,
    ReaderNotifier notifier,
  ) {
    final hasNextChapter = notifier.getNextChapterId() != null;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Divider
          Container(
            height: 2,
            width: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.white.withValues(alpha: 0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Văn bản kết thúc chương
          Text(
            'Hết ${state.currentChapter?.title ?? 'chương'}',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 16),

          // Đang tải, đang giữ, hoặc chỉ báo chương tiếp theo
          if (state.isLoadingNextChapter)
            const Column(
              children: [
                CircularProgressIndicator(strokeWidth: 2),
                SizedBox(height: 12),
                Text(
                  'Đang tải chương tiếp theo...',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            )
          else if (_isHoldingForNextChapter && hasNextChapter)
            // Hiển thị chỉ báo tiến trình giữ
            Column(
              children: [
                SizedBox(
                  width: 60,
                  height: 60,
                  child: AnimatedBuilder(
                    animation: _holdProgressController,
                    builder: (context, child) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          // Vòng tròn nền
                          CircularProgressIndicator(
                            value: 1.0,
                            strokeWidth: 4,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          // Vòng tròn tiến trình
                          CircularProgressIndicator(
                            value: _holdProgressController.value,
                            strokeWidth: 4,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.blueAccent,
                            ),
                          ),
                          // Biểu tượng ở giữa
                          Icon(
                            Icons.arrow_downward,
                            color: Colors.blueAccent.withValues(
                              alpha:
                                  0.5 + (_holdProgressController.value * 0.5),
                            ),
                            size: 24,
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Giữ để đọc chương tiếp...',
                  style: TextStyle(
                    color: Colors.blueAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            )
          else if (hasNextChapter)
            Column(
              children: [
                const Icon(
                  Icons.keyboard_double_arrow_down,
                  color: Colors.white54,
                  size: 28,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Cuộn xuống và giữ để đọc chương tiếp',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                // Nút thủ công để dự phòng
                OutlinedButton.icon(
                  onPressed: _isChapterTransitionLocked
                      ? null
                      : () => _triggerNextChapter(),
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('Chương tiếp'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                  ),
                ),
              ],
            )
          else
            Column(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: Colors.green,
                  size: 32,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Bạn đã đọc hết truyện!',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Quay lại'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                  ),
                ),
              ],
            ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // Cửa sổ danh sách chương
  void _showChapterListModal(
    BuildContext context,
    List<CloudChapter> chapters,
    CloudChapter? currentChapter,
    String? mangaId,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor:
          Colors.transparent, // Trong suốt để DraggableSheet xử lý nền
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return _ChapterListModalContent(
          chapters: chapters,
          currentChapter: currentChapter,
          mangaId: mangaId,
        );
      },
    );
  }

  // Ngăn kéo (Menu)
  Future<void> _showBookmarkList(ReaderState state) async {
    final mangaId = state.mangaId;
    if (mangaId == null || mangaId.isEmpty) return;

    final bookmarks = await DatabaseHelper.instance.getBookmarksForManga(
      mangaId,
    );
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      builder: (context) {
        if (bookmarks.isEmpty) {
          return const SizedBox(
            height: 180,
            child: Center(
              child: Text(
                'Chưa có bookmark nào',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          );
        }

        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: bookmarks.length,
            separatorBuilder: (_, __) => const Divider(color: Colors.white12),
            itemBuilder: (context, index) {
              final bookmark = bookmarks[index];
              var chapterTitle = bookmark.chapterId;
              for (final chapter in state.chapters) {
                if (chapter.id == bookmark.chapterId) {
                  chapterTitle = chapter.title;
                  break;
                }
              }

              return ListTile(
                leading: const Icon(Icons.bookmark, color: Colors.amber),
                title: Text(
                  chapterTitle,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'Trang ${bookmark.pageIndex + 1}',
                  style: const TextStyle(color: Colors.white54),
                ),
                onTap: () {
                  Navigator.pop(context);
                  if (bookmark.chapterId != state.currentChapter?.id) {
                    context.pushReplacement(
                      _readerRoute(bookmark.chapterId, state.mangaId),
                    );
                    return;
                  }

                  ref
                      .read(readerProvider.notifier)
                      .onPageChanged(bookmark.pageIndex);
                  if (state.readingMode == ReadingMode.horizontal &&
                      _pageController.hasClients) {
                    _pageController.jumpToPage(bookmark.pageIndex);
                  } else if (_scrollController.hasClients) {
                    final maxScroll =
                        _scrollController.position.maxScrollExtent;
                    _scrollController.jumpTo(
                      bookmark.scrollOffset.clamp(0.0, maxScroll),
                    );
                  }
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildDrawer(ReaderState state, ReaderNotifier notifier) {
    return Drawer(
      backgroundColor: const Color(0xFF1E1E1E),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.black),
            child: Center(
              child: Text(
                'Cài đặt & Tùy chọn',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.refresh, color: Colors.white),
            title: const Text('Tải lại', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _reloadCurrentChapter(notifier);
            },
          ),
          ListTile(
            leading: Icon(
              state.readingMode == ReadingMode.horizontal
                  ? Icons.view_day
                  : Icons.view_array,
              color: Colors.white,
            ),
            title: Text(
              state.readingMode == ReadingMode.horizontal
                  ? 'Chuyển sang đọc dọc'
                  : 'Chuyển sang đọc ngang',
              style: const TextStyle(color: Colors.white),
            ),
            onTap: () {
              notifier.setReadingMode(
                state.readingMode == ReadingMode.horizontal
                    ? ReadingMode.vertical
                    : ReadingMode.horizontal,
              );
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(
              state.isCurrentPageBookmarked
                  ? Icons.bookmark
                  : Icons.bookmark_border,
              color: state.isCurrentPageBookmarked
                  ? Colors.amber
                  : Colors.white,
            ),
            title: Text(
              state.isCurrentPageBookmarked
                  ? 'Bỏ bookmark trang này'
                  : 'Bookmark trang này',
              style: const TextStyle(color: Colors.white),
            ),
            onTap: () async {
              final added = await notifier.toggleBookmark();
              if (!mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(added ? 'Đã thêm bookmark' : 'Đã bỏ bookmark'),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.bookmarks, color: Colors.white),
            title: const Text(
              'Danh sách bookmark',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(context);
              _showBookmarkList(state);
            },
          ),
          ListTile(
            leading: const Icon(Icons.history, color: Colors.white),
            title: const Text(
              'Xóa lịch sử đọc',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () async {
              final mangaId = state.mangaId;
              if (mangaId == null || mangaId.isEmpty) {
                Navigator.pop(context);
                return;
              }

              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid != null) {
                await DatabaseHelper.instance.deleteHistoryForManga(
                  uid,
                  mangaId,
                );
                await HistoryService.instance.deleteHistory(mangaId);
              }
              if (!mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đã xóa lịch sử đọc')),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ChapterListModalContent extends StatefulWidget {
  final List<CloudChapter> chapters;
  final CloudChapter? currentChapter;
  final String? mangaId;

  const _ChapterListModalContent({
    required this.chapters,
    required this.currentChapter,
    required this.mangaId,
  });

  @override
  State<_ChapterListModalContent> createState() =>
      _ChapterListModalContentState();
}

class _ChapterListModalContentState extends State<_ChapterListModalContent> {
  final DraggableScrollableController _controller =
      DraggableScrollableController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleSize() {
    if (_controller.size > 0.6) {
      _controller.animateTo(
        0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _controller.animateTo(
        1.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _controller,
      initialChildSize: 0.5,
      minChildSize: 0.5,
      maxChildSize: 1.0,
      expand: false,
      snap: true,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1C1C1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Tiêu đề
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.white12, width: 1),
                  ),
                ),
                child: Consumer(
                  builder: (context, ref, child) {
                    final state = ref.watch(readerProvider);
                    final notifier = ref.read(readerProvider.notifier);

                    return Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Expanded(
                          child: Text(
                            'DS Chương',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        // Biểu tượng theo dõi (Trái tim)
                        IconButton(
                          icon: Icon(
                            state.isFollowed
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: state.isFollowed ? Colors.red : Colors.white,
                          ),
                          onPressed: () async {
                            try {
                              final isNowFollowed = await notifier
                                  .toggleFollow();
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    isNowFollowed
                                        ? 'Đã theo dõi thành công!'
                                        : 'Đã hủy theo dõi',
                                  ),
                                  backgroundColor: isNowFollowed
                                      ? Colors.green
                                      : null,
                                ),
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    e.toString().replaceFirst(
                                      'Exception: ',
                                      '',
                                    ),
                                  ),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          },
                        ),

                        // Biểu tượng đổi kích thước
                        IconButton(
                          icon: const Icon(
                            Icons.swap_vert,
                            color: Colors.white,
                          ),
                          onPressed: _toggleSize,
                        ),
                      ],
                    );
                  },
                ),
              ),

              // Danh sách
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  // Dedup bằng Set.add() — trả về false nếu id đã tồn tại
                  // Đây là biện pháp phòng ngừa nếu server trả về chapter trùng id
                  itemCount: () {
                    final seen = <String>{};
                    return widget.chapters.where((c) => seen.add(c.id)).length;
                  }(),
                  itemBuilder: (context, index) {
                    // Recompute uniqueChapters mỗi lần — kém hiệu quả nhưng đảm bảo đúng 100%
                    // Tối ưu hơn: tính 1 lần ở initState/build, truyền vào widget
                    final seen = <String>{};
                    final uniqueChapters = widget.chapters
                        .where((c) => seen.add(c.id))
                        .toList();

                    if (index >= uniqueChapters.length) return const SizedBox();

                    final chapter = uniqueChapters[index];
                    final isSelected = chapter.id == widget.currentChapter?.id;

                    // Định dạng ngày: dd/MM/yyyy
                    final date =
                        "${chapter.uploadedAt.day}/${chapter.uploadedAt.month}/${chapter.uploadedAt.year}";

                    return InkWell(
                      onTap: () {
                        Navigator.pop(context); // Đóng cửa sổ
                        if (!isSelected) {
                          // Điều hướng đến chương đã chọn
                          final mangaQuery =
                              widget.mangaId == null || widget.mangaId!.isEmpty
                              ? ''
                              : '?mangaId=${Uri.encodeComponent(widget.mangaId!)}';
                          context.pushReplacement(
                            '/reader/${chapter.id}$mangaQuery',
                          );
                        }
                      },
                      child: Container(
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.05)
                            : null,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                chapter.title,
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.blueAccent
                                      : Colors.white70,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            Text(
                              date,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
