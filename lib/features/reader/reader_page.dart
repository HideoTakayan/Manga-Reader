import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/database_helper.dart';
import '../../data/models.dart';
import '../../data/models_cloud.dart';
import '../catalog/catalog_cache_service.dart';
import '../../features/shared/drive_image.dart';
import '../../services/sync_service.dart';
import '../../services/folder_service.dart';
import '../../services/permission_service.dart';
import '../../services/level_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'novel_reader_widget.dart';
import 'pdf_reader_view.dart';
import 'reader_provider.dart';

class ReaderPage extends ConsumerStatefulWidget {
  final String chapterId;
  final String? mangaId;
  final int? initialPageIndex;
  const ReaderPage({
    super.key,
    required this.chapterId,
    this.mangaId,
    this.initialPageIndex,
  });

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
  final GlobalKey<PdfReaderViewState> _pdfReaderKey =
      GlobalKey<PdfReaderViewState>();

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
  double _autoScrollSpeedMultiplier = 1.0;
  int _autoPageTurnRunId = 0;
  double? _lastVerticalProgressSaveOffset;
  int? _lastVerticalProgressSavePage;
  static const double _autoScrollPixelsPerSecond = 132.0;
  static const double _verticalProgressSaveDelta = 160.0;
  static const Duration _autoPageTurnInterval = Duration(
    milliseconds: 1380,
  ); // Giảm tốc độ đọc 15% cho truyện tranh CBZ/ZIP (1200ms -> 1380ms)
  static const Duration _pdfAutoPageTurnInterval = Duration(
    milliseconds: 3200,
  ); // Tăng tốc độ đọc 1.25x cho PDF (4000ms -> 3200ms)
  static const Duration _holdDuration = Duration(milliseconds: 1500);

  late AnimationController _holdProgressController;
  final ValueNotifier<int> _currentPageNotifier = ValueNotifier<int>(0);
  final Map<int, GlobalKey> _pageKeys = {};
  int? _scrubbingPageIndex;

  DateTime? _lastChapterChange;
  static const Duration _chapterChangeCooldown = Duration(seconds: 2);
  bool _isChapterTransitionLocked = false;
  String? _restoredScrollChapterId;

  static const double _nextChapterThreshold = 100.0;
  static const double _prevChapterThreshold = -60.0;

  StreamSubscription<ClaimExpResult>? _levelUpSub;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _scrollController = ScrollController();

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

    _holdProgressController = AnimationController(
      vsync: this,
      duration: _holdDuration,
    );

    _scrollController.addListener(_onVerticalScroll);

    WakelockPlus.enable();

    // Kích hoạt chế độ toàn màn hình
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(readerProvider.notifier)
          .init(
            widget.chapterId,
            mangaId: widget.mangaId,
            initialPageIndex: widget.initialPageIndex,
          );
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
    int estimatedPage = _currentPageNotifier.value;

    if (pageCount > 0 && state.readingMode == ReadingMode.vertical) {
      final viewportRender = _scrollController
          .position
          .context
          .notificationContext
          ?.findRenderObject();
      if (viewportRender is RenderBox && mounted) {
        final centerTarget = viewportRender.size.height / 2;
        double? bestDistance;
        bool foundExact = false;

        // Ưu tiên kiểm tra các trang lân cận trước (O(1) cho 99% trường hợp cuộn mượt)
        final current = _currentPageNotifier.value;
        final neighborIndices = <int>[
          current,
          if (current + 1 < pageCount) current + 1,
          if (current - 1 >= 0) current - 1,
          if (current + 2 < pageCount) current + 2,
          if (current - 2 >= 0) current - 2,
        ];

        for (final index in neighborIndices) {
          final key = _pageKeys[index];
          final ctx = key?.currentContext;
          if (ctx != null) {
            final renderObj = ctx.findRenderObject();
            if (renderObj is RenderBox) {
              final position = renderObj.localToGlobal(
                Offset.zero,
                ancestor: viewportRender,
              );
              final itemTop = position.dy;
              final itemBottom = itemTop + renderObj.size.height;

              if (itemTop <= centerTarget && itemBottom >= centerTarget) {
                estimatedPage = index;
                foundExact = true;
                break;
              }

              final itemCenter = itemTop + (renderObj.size.height / 2);
              final distance = (itemCenter - centerTarget).abs();
              if (bestDistance == null || distance < bestDistance) {
                bestDistance = distance;
                estimatedPage = index;
              }
            }
          }
        }

        // Nếu chưa tìm thấy trang phủ qua tâm trong nhóm lân cận (ví dụ vừa nhảy xa)
        if (!foundExact) {
          final neighborSet = neighborIndices.toSet();
          for (final entry in _pageKeys.entries) {
            if (neighborSet.contains(entry.key)) continue;
            final ctx = entry.value.currentContext;
            if (ctx != null) {
              final renderObj = ctx.findRenderObject();
              if (renderObj is RenderBox) {
                final position = renderObj.localToGlobal(
                  Offset.zero,
                  ancestor: viewportRender,
                );
                final itemTop = position.dy;
                final itemBottom = itemTop + renderObj.size.height;

                if (itemTop <= centerTarget && itemBottom >= centerTarget) {
                  estimatedPage = entry.key;
                  break;
                }

                final itemCenter = itemTop + (renderObj.size.height / 2);
                final distance = (itemCenter - centerTarget).abs();
                if (bestDistance == null || distance < bestDistance) {
                  bestDistance = distance;
                  estimatedPage = entry.key;
                }
              }
            }
          }
        }
      }
    } else if (pageCount > 0 && state.readingMode == ReadingMode.horizontal) {
      // Dự phòng cho chế độ ngang nếu lọt vào đây (dù horizontal dùng onPageChanged)
      estimatedPage = _currentPageNotifier.value;
    }
    if (_currentPageNotifier.value != estimatedPage) {
      _currentPageNotifier.value = estimatedPage;
      _precacheNearbyPages(state, targetIndex: estimatedPage);
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
    
    // Nếu là PDF chế độ ngang: dùng hẹn giờ lật từng trang
    if (state.isPdf && state.readingMode == ReadingMode.horizontal) {
      _autoPageTurnRunId++;
      setState(() => _isAutoScrolling = true);
      _schedulePdfAutoPageTurn(_autoPageTurnRunId);
      return;
    }

    // Nếu là truyện thường chế độ ngang: dùng hẹn giờ lật từng trang
    if (!state.isPdf && state.readingMode == ReadingMode.horizontal) {
      if (!_pageController.hasClients) return;
      setState(() => _isAutoScrolling = true);
      _autoScrollTicker?.dispose();
      _autoScrollTicker = null;
      _lastAutoScrollTick = null;
      _autoPageTurnRunId++;
      _scheduleHorizontalAutoPageTurn(_autoPageTurnRunId);
      return;
    }

    // Chế độ dọc: Dùng Ticker tự cuộn màn hình mượt mà liên tục (cho CẢ TRUYỆN TRANH CBZ VÀ PDF)
    if (!state.isPdf && !_scrollController.hasClients) {
      return;
    }

    setState(() => _isAutoScrolling = true);
    _autoScrollTicker?.dispose();
    _autoScrollTicker = null;
    _lastAutoScrollTick = null;
    _autoPageTurnRunId++;

    _autoScrollTicker = createTicker((elapsed) {
      if (!mounted) {
        _stopAutoScroll();
        return;
      }

      final lastTick = _lastAutoScrollTick;
      _lastAutoScrollTick = elapsed;
      if (lastTick == null) return;

      final deltaSeconds =
          (elapsed - lastTick).inMicroseconds / Duration.microsecondsPerSecond;
      final safeDeltaSeconds = deltaSeconds.clamp(0.0, 0.05).toDouble();
      final deltaPixels = _autoScrollPixelsPerSecond * _autoScrollSpeedMultiplier * safeDeltaSeconds;

      if (state.isPdf) {
        // PDF cuộn dọc mượt mà từng pixel qua PdfReaderView
        final canContinue =
            _pdfReaderKey.currentState?.scrollBy(deltaPixels) ?? false;
        if (!canContinue) {
          _stopAutoScroll();
        }
      } else {
        // Truyện tranh CBZ / ZIP cuộn dọc qua ScrollController
        if (!_scrollController.hasClients) {
          _stopAutoScroll();
          return;
        }
        final position = _scrollController.position;
        if (position.pixels >= position.maxScrollExtent) {
          _stopAutoScroll();
          return;
        }
        final nextOffset = position.pixels + deltaPixels;
        _scrollController.jumpTo(
          nextOffset.clamp(0.0, position.maxScrollExtent),
        );
      }
    });
    _autoScrollTicker?.start();
  }

  void _schedulePdfAutoPageTurn(int runId) {
    if (!_isAutoScrolling || runId != _autoPageTurnRunId) return;
    final durationMs = (_pdfAutoPageTurnInterval.inMilliseconds / _autoScrollSpeedMultiplier).round();
    Future.delayed(Duration(milliseconds: durationMs.clamp(500, 10000)), () {
      if (!mounted) return;
      _advancePdfAutoPage(runId);
    });
  }

  Future<void> _advancePdfAutoPage(int runId) async {
    if (!_isAutoScrolling || runId != _autoPageTurnRunId) return;
    
    _pdfReaderKey.currentState?.autoScrollNext();
    
    _schedulePdfAutoPageTurn(runId);
  }

  void _scheduleHorizontalAutoPageTurn(int runId) {
    final durationMs = (_autoPageTurnInterval.inMilliseconds / _autoScrollSpeedMultiplier).round();
    Future.delayed(Duration(milliseconds: durationMs.clamp(300, 10000)), () async {
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
    if (state.readingMode != ReadingMode.horizontal && !state.isPdf) {
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
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Hủy Theo Dõi?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'Bạn có chắc chắn muốn hủy theo dõi truyện này?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Đồng ý'),
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
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _levelUpSub?.cancel();
    _scrollController.removeListener(_onVerticalScroll);
    _cancelHoldTimer();
    _progressSaveTimer?.cancel();
    _autoScrollTicker?.dispose();
    _holdProgressController.dispose();
    _currentPageNotifier.dispose();
    _pageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    // Tự động đẩy lịch sử đọc lên Firestore khi thoát chế độ đọc (bỏ qua nếu đang đọc Ẩn danh)
    if (!ref.read(readerProvider).isIncognito) {
      SyncService.instance.syncPendingHistory();
    }
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event, ReaderState state) {
    if (event is! KeyDownEvent) return;

    final isRtl = state.direction == ReaderDirection.rtl;
    final isVolDown = event.logicalKey == LogicalKeyboardKey.audioVolumeDown;
    final isVolUp = event.logicalKey == LogicalKeyboardKey.audioVolumeUp;

    // Nếu là phím âm lượng nhưng tính năng Volume Page Turn đang tắt thì bỏ qua
    if ((isVolDown || isVolUp) && !state.volumePageTurn) return;

    bool isNextKey = false;
    bool isPrevKey = false;

    if (isVolDown || isVolUp) {
      HapticFeedback.selectionClick();
      if (state.invertVolumeKeys) {
        isNextKey = isVolUp;
        isPrevKey = isVolDown;
      } else {
        isNextKey = isVolDown;
        isPrevKey = isVolUp;
      }
    } else {
      isNextKey = event.logicalKey == LogicalKeyboardKey.arrowDown ||
          (isRtl
              ? event.logicalKey == LogicalKeyboardKey.arrowLeft
              : event.logicalKey == LogicalKeyboardKey.arrowRight) ||
          event.logicalKey == LogicalKeyboardKey.space ||
          event.logicalKey == LogicalKeyboardKey.pageDown;

      isPrevKey = event.logicalKey == LogicalKeyboardKey.arrowUp ||
          (isRtl
              ? event.logicalKey == LogicalKeyboardKey.arrowRight
              : event.logicalKey == LogicalKeyboardKey.arrowLeft) ||
          event.logicalKey == LogicalKeyboardKey.pageUp;
    }

    if (isNextKey) {
      if (state.readingMode == ReadingMode.horizontal) {
        if (!_pageController.hasClients) return;
        if (state.currentPageIndex < state.pages.length - 1) {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
        } else {
          _triggerNextChapter();
        }
      } else {
        if (!_scrollController.hasClients) return;
        final currentOffset = _scrollController.offset;
        final maxScroll = _scrollController.position.maxScrollExtent;
        _scrollController.animateTo(
          (currentOffset + 500).clamp(0.0, maxScroll),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      }
    } else if (isPrevKey) {
      if (state.readingMode == ReadingMode.horizontal) {
        if (!_pageController.hasClients) return;
        if (state.currentPageIndex > 0) {
          _pageController.previousPage(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
        } else {
          _triggerPrevChapter();
        }
      } else {
        if (!_scrollController.hasClients) return;
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
    } else {
      final key = event.logicalKey;
      final notifier = ref.read(readerProvider.notifier);
      if (key == LogicalKeyboardKey.keyM) {
        notifier.toggleControls();
      } else if (key == LogicalKeyboardKey.keyB) {
        notifier.toggleBookmark();
      } else if (key == LogicalKeyboardKey.keyA) {
        _toggleAutoScroll();
      } else if (key == LogicalKeyboardKey.keyF) {
        _toggleFollowWithFeedback(state, notifier);
      } else if (key == LogicalKeyboardKey.bracketLeft) {
        final prevId = notifier.getPrevChapterId();
        if (prevId != null) {
          context.pushReplacement(_readerRoute(prevId, state.mangaId));
        }
      } else if (key == LogicalKeyboardKey.bracketRight) {
        final nextId = notifier.getNextChapterId();
        if (nextId != null) {
          context.pushReplacement(_readerRoute(nextId, state.mangaId));
        }
      } else if (key == LogicalKeyboardKey.equal ||
          key == LogicalKeyboardKey.add ||
          key == LogicalKeyboardKey.numpadAdd) {
        _increaseAutoScrollSpeed();
      } else if (key == LogicalKeyboardKey.minus ||
          key == LogicalKeyboardKey.numpadSubtract) {
        _decreaseAutoScrollSpeed();
      } else if (key == LogicalKeyboardKey.home) {
        _jumpToPage(0);
      } else if (key == LogicalKeyboardKey.end) {
        final pageCount = state.isPdf ? state.pdfPageCount : state.pages.length;
        if (pageCount > 0) _jumpToPage(pageCount - 1);
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
        final spreads = _calculateSpreads(state.pages.length, state.dualPageMode);
        final spreadIndex = spreads.indexWhere((s) => s.contains(target));
        final targetSpread = spreadIndex != -1 ? spreadIndex : target;
        _pageController.animateToPage(
          targetSpread,
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
      case ReaderBackground.sepia:
        return const Color(0xFF1E1712);
      case ReaderBackground.white:
        return Colors.white;
    }
  }

  String _readerRoute(String chapterId, String? mangaId, {int? page}) {
    final params = <String, String>{};
    if (mangaId != null && mangaId.isNotEmpty) params['mangaId'] = mangaId;
    if (page != null && page >= 0) params['page'] = page.toString();
    if (params.isEmpty) return '/reader/$chapterId';
    return '/reader/$chapterId?${Uri(queryParameters: params).query}';
  }

  void _readerPageForward(ReaderState state) {
    if (state.readingMode == ReadingMode.horizontal && !state.isPdf) {
      if (state.direction == ReaderDirection.rtl) {
        if (state.currentPageIndex < state.pages.length - 1) {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
        } else {
          _triggerNextChapter();
        }
      } else {
        if (state.currentPageIndex < state.pages.length - 1) {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
        } else {
          _triggerNextChapter();
        }
      }
    } else if (state.readingMode == ReadingMode.vertical) {
      if (_scrollController.hasClients) {
        final currentOffset = _scrollController.offset;
        final screenHeight = MediaQuery.of(context).size.height;
        _scrollController.animateTo(
          (currentOffset + (screenHeight * 0.65)).clamp(
            0.0,
            _scrollController.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  void _readerPageBackward(ReaderState state) {
    if (state.readingMode == ReadingMode.horizontal && !state.isPdf) {
      if (state.currentPageIndex > 0) {
        _pageController.previousPage(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      } else {
        _triggerPrevChapter();
      }
    } else if (state.readingMode == ReadingMode.vertical) {
      if (_scrollController.hasClients) {
        final currentOffset = _scrollController.offset;
        final screenHeight = MediaQuery.of(context).size.height;
        _scrollController.animateTo(
          (currentOffset - (screenHeight * 0.65)).clamp(
            0.0,
            _scrollController.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  String _tapZoneDescription(ReaderTapZone zone) {
    switch (zone) {
      case ReaderTapZone.default3Cols:
        return 'Trái: Lùi, Giữa: Menu, Phải: Tiến (hoặc ngược lại nếu đọc RTL)';
      case ReaderTapZone.oneHanded:
        return 'Nửa dưới: Tiến (thuận ngón cái), Đỉnh: Lùi, Giữa: Menu';
      case ReaderTapZone.leftHanded:
        return 'Trái: Tiến (thuận tay trái), Phải: Lùi, Giữa: Menu';
      case ReaderTapZone.swipeOnly:
        return 'Chạm mọi nơi chỉ để bật/tắt Menu. Lật trang bằng cách vuốt';
    }
  }

  void _handleReaderTap(
    TapUpDetails details,
    ReaderState state,
    ReaderNotifier notifier,
  ) {
    if (state.isPdf) {
      notifier.toggleControls();
      return;
    }

    final size = MediaQuery.of(context).size;
    final screenWidth = size.width;
    final screenHeight = size.height;
    final tapX = details.globalPosition.dx;
    final tapY = details.globalPosition.dy;

    // 1. Chế độ chỉ vuốt
    if (state.tapZone == ReaderTapZone.swipeOnly) {
      notifier.toggleControls();
      return;
    }

    // 2. Chế độ Đọc 1 tay (One-Handed / L-Shape)
    if (state.tapZone == ReaderTapZone.oneHanded) {
      // Đỉnh màn hình (18%) -> Lùi trang
      if (tapY < screenHeight * 0.18) {
        if (state.direction == ReaderDirection.rtl) {
          _readerPageForward(state);
        } else {
          _readerPageBackward(state);
        }
        return;
      }
      // Vùng tâm màn hình (Menu controls)
      if (tapX >= screenWidth * 0.25 &&
          tapX <= screenWidth * 0.75 &&
          tapY >= screenHeight * 0.25 &&
          tapY <= screenHeight * 0.55) {
        notifier.toggleControls();
        return;
      }
      // Toàn bộ vùng còn lại (60% dưới + hai bên lề dưới) -> Tiến trang
      if (state.direction == ReaderDirection.rtl) {
        _readerPageBackward(state);
      } else {
        _readerPageForward(state);
      }
      return;
    }

    // 3. Chế độ Thuận tay trái (Left-Handed)
    if (state.tapZone == ReaderTapZone.leftHanded) {
      // 40% Bên trái màn hình -> Tiến trang (dễ chạm nhất cho ngón cái tay trái)
      if (tapX < screenWidth * 0.40) {
        if (state.direction == ReaderDirection.rtl) {
          _readerPageBackward(state);
        } else {
          _readerPageForward(state);
        }
      }
      // 40% Bên phải màn hình -> Lùi trang
      else if (tapX > screenWidth * 0.60) {
        if (state.direction == ReaderDirection.rtl) {
          _readerPageForward(state);
        } else {
          _readerPageBackward(state);
        }
      }
      // 20% Giữa màn hình -> Menu controls
      else {
        notifier.toggleControls();
      }
      return;
    }

    // 4. Chế độ 3 Cột Mặc định (Default 3-Cols)
    // 35% Bên trái màn hình
    if (tapX < screenWidth * 0.35) {
      if (state.direction == ReaderDirection.rtl) {
        _readerPageForward(state);
      } else {
        _readerPageBackward(state);
      }
    }
    // 35% Bên phải màn hình
    else if (tapX > screenWidth * 0.65) {
      if (state.direction == ReaderDirection.rtl) {
        _readerPageBackward(state);
      } else {
        _readerPageForward(state);
      }
    }
    // 30% Vùng giữa màn hình -> Bật/Tắt thanh công cụ
    else {
      notifier.toggleControls();
    }
  }

  void _reloadCurrentChapter(ReaderNotifier notifier) {
    final state = ref.read(readerProvider);
    final chapterId = state.currentChapter?.id ?? widget.chapterId;
    final mangaId = state.mangaId ?? widget.mangaId;
    notifier.init(chapterId, mangaId: mangaId);
  }

  void _precacheNearbyPages(ReaderState state, {int? targetIndex}) {
    if (!mounted || state.pages.isEmpty) return;
    final current = targetIndex ?? state.currentPageIndex;
    final isVertical = state.readingMode == ReadingMode.vertical;
    final forwardWindow = isVertical ? 5 : 2;
    final backwardWindow = isVertical ? 2 : 2;
    final start = (current - backwardWindow).clamp(0, state.pages.length - 1);
    final end = (current + forwardWindow).clamp(0, state.pages.length - 1);
    for (var i = start; i <= end; i++) {
      try {
        final filePath = state.pages[i];
        if (filePath.isNotEmpty) {
          final file = File(filePath);
          if (file.existsSync()) {
            precacheImage(FileImage(file), context);
          }
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readerProvider);
    final notifier = ref.read(readerProvider.notifier);

    if (!state.isLoading && state.isNovel && state.localFilePath != null) {
      return NovelReaderWidget(
        epubPath: state.localFilePath!,
        storageKey: [
          state.mangaId,
          state.currentChapter?.id,
        ].whereType<String>().where((value) => value.isNotEmpty).join('_'),
        title:
            state.currentChapter?.title ?? state.manga?.title ?? 'Truyện chữ',
        realMangaId: state.mangaId,
        realChapterId: state.currentChapter?.id,
      );
    }

    ref.listen<ReaderState>(readerProvider, (prev, next) {
      if (_isAutoScrolling &&
          (false ||
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

      // Xử lý khi chuyển đổi giữa chế độ dọc và ngang
      if (prev != null && prev.readingMode != next.readingMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          if (next.readingMode == ReadingMode.horizontal) {
            if (_pageController.hasClients &&
                _pageController.page?.round() != next.currentPageIndex) {
              _pageController.jumpToPage(next.currentPageIndex);
            }
          } else if (next.readingMode == ReadingMode.vertical) {
            if (_scrollController.hasClients && next.pages.length > 1) {
              final maxScroll = _scrollController.position.maxScrollExtent;
              final targetOffset =
                  maxScroll * (next.currentPageIndex / (next.pages.length - 1));
              _scrollController.jumpTo(targetOffset.clamp(0.0, maxScroll));
            }
          }
        });
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
                  // Nội dung ảnh manga (áp dụng bộ lọc đảo màu trực tiếp lên trang truyện nếu bật)
                  state.invertColors
                      ? ColorFiltered(
                          colorFilter: const ColorFilter.matrix([
                            // Ma trận đảo màu (Invert): đảo RGB, giữ nguyên alpha
                            -1,  0,  0, 0, 255,
                             0, -1,  0, 0, 255,
                             0,  0, -1, 0, 255,
                             0,  0,  0, 1,   0,
                          ]),
                          child: GestureDetector(
                            onTapUp: (details) => _handleReaderTap(details, state, notifier),
                            child: state.isPdf && state.localFilePath != null
                                ? PdfReaderView(
                                    key: _pdfReaderKey,
                                    scrollDirection:
                                        state.readingMode == ReadingMode.horizontal
                                        ? Axis.horizontal
                                        : Axis.vertical,
                                    pdfPath: state.localFilePath!,
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
                        )
                      : GestureDetector(
                          onTapUp: (details) => _handleReaderTap(details, state, notifier),
                          child: state.isPdf && state.localFilePath != null
                              ? PdfReaderView(
                                  key: _pdfReaderKey,
                                  scrollDirection:
                                      state.readingMode == ReadingMode.horizontal
                                      ? Axis.horizontal
                                      : Axis.vertical,
                                  pdfPath: state.localFilePath!,
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

                  // ===== BỘ LỌC ẢNH BAN ĐÊM – các lớp phủ ảnh (IgnorePointer – không chặn touch) =====
                  // Lớp giảm sáng (Dim)
                  if (state.dimLevel > 0)
                    IgnorePointer(
                      child: Container(
                        color: Colors.black.withValues(
                          alpha: state.dimLevel,
                        ),
                      ),
                    ),

                  // Lớp lọc ánh sáng xanh: phủ màu vàng/cam nhẹ lên toàn bộ màn hình
                  if (state.tintLevel > 0)
                    IgnorePointer(
                      child: Container(
                        color: const Color(0xFFFF9500).withValues(
                          alpha: state.tintLevel,
                        ),
                      ),
                    ),

                  if (state.showControls)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,

                      child: ClipRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: EdgeInsets.fromLTRB(
                              10,
                              MediaQuery.of(context).padding.top + 5,
                              10,
                              10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.1),
                                ),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                        borderRadius: BorderRadius.circular(16),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.15,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.list,
                                                color: Colors.white,
                                                size: 14,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                state.currentChapter?.title ??
                                                    'Chương ?',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              const Icon(
                                                Icons.keyboard_arrow_down,
                                                color: Colors.white,
                                                size: 14,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Nút Lưu ảnh trang về máy
                                if (!state.isPdf && !state.isNovel && state.pages.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.download_rounded,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                    tooltip: 'Lưu ảnh trang này về Thư viện',
                                    onPressed: () => _saveCurrentPageImage(state),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                if (!state.isPdf && !state.isNovel && state.pages.isNotEmpty)
                                  const SizedBox(width: 10),
                                // Nút Menu (Ngăn kéo)
                                if (!state
                                    .isPdf) // Ẩn Thumbnail grid khi đọc PDF
                                  IconButton(
                                    icon: const Icon(
                                      Icons.grid_view,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                    tooltip: 'Danh sách trang',
                                    onPressed: () =>
                                        _showPageThumbnailSheet(state),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                // Nút Chế độ Ẩn danh (Incognito)
                                IconButton(
                                  icon: Icon(
                                    state.isIncognito
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_outlined,
                                    color: state.isIncognito
                                        ? Colors.purpleAccent
                                        : Colors.white,
                                    size: 24,
                                  ),
                                  tooltip: state.isIncognito
                                      ? 'Đang bật Chế độ ẩn danh'
                                      : 'Bật Chế độ ẩn danh',
                                  onPressed: () {
                                    HapticFeedback.mediumImpact();
                                    notifier.toggleIncognito();
                                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Row(
                                          children: [
                                            Icon(
                                              !state.isIncognito
                                                  ? Icons.visibility_off_rounded
                                                  : Icons.visibility_outlined,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                !state.isIncognito
                                                    ? 'Đã bật Chế độ ẩn danh (Không lưu lịch sử & tiến độ)'
                                                    : 'Đã tắt Chế độ ẩn danh (Tiến trình sẽ được lưu)',
                                              ),
                                            ),
                                          ],
                                        ),
                                        backgroundColor: !state.isIncognito
                                            ? Colors.deepPurple
                                            : Colors.grey[850],
                                        behavior: SnackBarBehavior.floating,
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                const SizedBox(width: 10),
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
                                  onPressed: () => _showReaderSettings(
                                    context,
                                    state,
                                    notifier,
                                  ),
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
                      ),
                    ),

                  // POPUP XEM TRƯỚC THUMBNAIL KHI TRƯỢT SLIDER
                  if (_scrubbingPageIndex != null &&
                      !state.isPdf &&
                      !state.isNovel &&
                      state.pages.isNotEmpty)
                    Positioned(
                      bottom: 145 + MediaQuery.of(context).padding.bottom,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: _buildScrubberThumbnailPreview(state),
                      ),
                    ),

                  // LỚP PHỦ DƯỚI CÙNG
                  if (state.showControls)
                    Positioned(
                      bottom: 16 + MediaQuery.of(context).padding.bottom,
                      left: 16,
                      right: 16,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ValueListenableBuilder<int>(
                                  valueListenable: _currentPageNotifier,
                                  builder: (context, currentPage, _) =>
                                      _buildPageSlider(state, currentPage),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.arrow_back_ios,
                                        color: Colors.white,
                                      ),
                                      onPressed:
                                          notifier.getPrevChapterId() != null
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
                                          _toggleFollowWithFeedback(
                                            state,
                                            notifier,
                                          ),
                                    ),
                                    Tooltip(
                                      message: state.isCurrentPageBookmarked
                                          ? 'Đã bookmark (Nhấn giữ để sửa ghi chú)'
                                          : 'Bookmark trang này (Nhấn giữ để thêm ghi chú)',
                                      child: GestureDetector(
                                        onLongPress: () =>
                                            _showBookmarkNoteDialog(state, notifier),
                                        child: IconButton(
                                          icon: Icon(
                                            state.isCurrentPageBookmarked
                                                ? Icons.bookmark
                                                : Icons.bookmark_border,
                                            color: state.isCurrentPageBookmarked
                                                ? Colors.amber
                                                : Colors.white,
                                          ),
                                          onPressed: () async {
                                            HapticFeedback.lightImpact();
                                            final added = await notifier
                                                .toggleBookmark();
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(
                                              context,
                                            ).hideCurrentSnackBar();
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  added
                                                      ? 'Đã thêm bookmark. Nhấn giữ để thêm ghi chú!'
                                                      : 'Đã bỏ bookmark',
                                                ),
                                                behavior: SnackBarBehavior.floating,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: _isAutoScrolling
                                          ? 'Tắt tự động đọc'
                                          : state.readingMode ==
                                                ReadingMode.horizontal
                                          ? 'Tự lật trang'
                                          : 'Tự cuộn',
                                      icon: Icon(
                                        _isAutoScrolling
                                            ? Icons.pause_circle
                                            : Icons.play_circle,
                                        color: Colors.white,
                                      ),
                                      onPressed: _toggleAutoScroll,
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.arrow_forward_ios,
                                        color: Colors.white,
                                      ),
                                      onPressed:
                                          notifier.getNextChapterId() != null
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
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Mini HUD hiển thị giờ & trang khi ẩn thanh công cụ
                  if (!state.showControls && state.showBatteryAndClock && !state.isNovel && !_isAutoScrolling)
                    Positioned(
                      bottom: MediaQuery.of(context).padding.bottom + 8,
                      right: 14,
                      child: ValueListenableBuilder<int>(
                        valueListenable: _currentPageNotifier,
                        builder: (context, currentPage, _) => _MiniReaderHud(
                          currentPage: currentPage,
                          totalPages: state.isPdf ? state.pdfPageCount : state.pages.length,
                        ),
                      ),
                    ),
                  // Thanh tinh chỉnh tốc độ tự cuộn
                  if (_isAutoScrolling)
                    Positioned(
                      bottom: (state.showControls ? 120 : 32) + MediaQuery.of(context).padding.bottom,
                      right: 16,
                      child: _buildAutoScrollControlBar(),
                    ),
                ],
              ),
      ),
    );
  }

  void _increaseAutoScrollSpeed() {
    HapticFeedback.lightImpact();
    setState(() {
      _autoScrollSpeedMultiplier = (_autoScrollSpeedMultiplier + 0.25).clamp(0.5, 4.0);
    });
  }

  void _decreaseAutoScrollSpeed() {
    HapticFeedback.lightImpact();
    setState(() {
      _autoScrollSpeedMultiplier = (_autoScrollSpeedMultiplier - 0.25).clamp(0.5, 4.0);
    });
  }

  Widget _buildAutoScrollControlBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Giảm tốc độ',
                icon: const Icon(Icons.remove, color: Colors.white70, size: 18),
                onPressed: _decreaseAutoScrollSpeed,
              ),
              const SizedBox(width: 4),
              Text(
                '${_autoScrollSpeedMultiplier.toStringAsFixed(2)}x',
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Tăng tốc độ',
                icon: const Icon(Icons.add, color: Colors.white70, size: 18),
                onPressed: _increaseAutoScrollSpeed,
              ),
              const SizedBox(width: 6),
              Container(width: 1, height: 16, color: Colors.white24),
              const SizedBox(width: 6),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Dừng tự cuộn',
                icon: const Icon(Icons.pause_circle_filled, color: Colors.redAccent, size: 22),
                onPressed: _stopAutoScroll,
              ),
            ],
          ),
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
    final clampedPage = currentPage.clamp(0, pageCount > 0 ? pageCount - 1 : 0);
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
                if (state.readingMode == ReadingMode.horizontal)
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      final newDirection =
                          state.direction == ReaderDirection.rtl
                              ? ReaderDirection.ltr
                              : ReaderDirection.rtl;
                      ref.read(readerProvider.notifier).setDirection(newDirection);
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            newDirection == ReaderDirection.rtl
                                ? 'Hướng đọc: Phải qua trái (Manga Nhật)'
                                : 'Hướng đọc: Trái qua phải (Manhwa/Comic)',
                          ),
                          duration: const Duration(milliseconds: 1500),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.blueAccent.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            state.direction == ReaderDirection.rtl
                                ? Icons.arrow_back
                                : Icons.arrow_forward,
                            color: Colors.blueAccent,
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            state.direction == ReaderDirection.rtl
                                ? 'Ngang (RTL)'
                                : 'Ngang (LTR)',
                            style: const TextStyle(
                              color: Colors.blueAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Text(
                    'Cuộn dọc',
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
                value: hasMultiplePages
                    ? (_scrubbingPageIndex ?? clampedPage).toDouble().clamp(0.0, (pageCount - 1).toDouble())
                    : 0,
                min: 0,
                max: hasMultiplePages ? (pageCount - 1).toDouble() : 1,
                divisions: hasMultiplePages ? pageCount - 1 : null,
                activeColor: Colors.blueAccent,
                inactiveColor: Colors.white24,
                onChangeStart: hasMultiplePages
                    ? (value) {
                        if (!state.isPdf && !state.isNovel && state.pages.isNotEmpty) {
                          setState(() => _scrubbingPageIndex = value.round());
                        }
                      }
                    : null,
                onChangeEnd: hasMultiplePages
                    ? (value) {
                        final newPage = value.round();
                        _jumpToPage(newPage);
                        if (_scrubbingPageIndex != null) {
                          setState(() => _scrubbingPageIndex = null);
                        }
                      }
                    : null,
                onChanged: hasMultiplePages
                    ? (value) {
                        final newPage = value.round();
                        if (newPage != (_scrubbingPageIndex ?? clampedPage)) {
                          HapticFeedback.selectionClick();
                        }
                        if (_scrubbingPageIndex != null) {
                          setState(() => _scrubbingPageIndex = newPage);
                        } else {
                          _jumpToPage(newPage);
                        }
                      }
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrubberThumbnailPreview(ReaderState state) {
    final target = (_scrubbingPageIndex ?? 0).clamp(0, state.pages.length - 1);
    final filePath = state.pages[target];

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.blueAccent.withValues(alpha: 0.7),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  File(filePath),
                  width: 95,
                  height: 140,
                  fit: BoxFit.cover,
                  cacheWidth: 250,
                  errorBuilder: (_, __, ___) => Container(
                    width: 95,
                    height: 140,
                    color: Colors.white10,
                    child: const Center(
                      child: Icon(Icons.broken_image, color: Colors.white38),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.blueAccent.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  'Trang ${target + 1} / ${state.pages.length}',
                  style: const TextStyle(
                    color: Colors.blueAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReaderError(String message, ReaderNotifier notifier) {
    return SafeArea(
      child: Stack(
        children: [
          Positioned(
            top: 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          Center(
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
                      Icons.error_outline_rounded,
                      color: Colors.redAccent,
                      size: 52,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Không mở được chương',
                    textAlign: TextAlign.center,
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
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: const Text('Quay lại'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _reloadCurrentChapter(notifier),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Thử lại'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
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
    final readerType = state.isNovel
        ? 'novel'
        : state.isPdf
        ? 'pdf'
        : 'manga';

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text(
                'Báo lỗi chương',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                      dropdownColor: Theme.of(ctx).cardColor,
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
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Theme.of(ctx).cardColor,
                        border: const OutlineInputBorder(),
                        hintText: 'Nhập mô tả chi tiết...',
                        hintStyle: const TextStyle(color: Colors.white30),
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
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
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
      backgroundColor: Theme.of(context).cardColor,
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
                        onSelectionChanged: (values) {
                          HapticFeedback.selectionClick();
                          notifier.setReadingMode(values.first);
                        },
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
                        onSelectionChanged: (values) {
                          HapticFeedback.selectionClick();
                          notifier.setDirection(values.first);
                        },
                      ),
                      if (current.readingMode == ReadingMode.horizontal) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Chế độ hiển thị trang (Ngang/Tablet)',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<ReaderDualPageMode>(
                          segments: const [
                            ButtonSegment(
                              value: ReaderDualPageMode.off,
                              icon: Icon(Icons.portrait),
                              label: Text('Trang đơn'),
                            ),
                            ButtonSegment(
                              value: ReaderDualPageMode.dual,
                              icon: Icon(Icons.auto_stories),
                              label: Text('Trang đôi'),
                            ),
                            ButtonSegment(
                              value: ReaderDualPageMode.dualCover,
                              icon: Icon(Icons.menu_book),
                              label: Text('Bìa đơn + Đôi'),
                            ),
                          ],
                          selected: {current.dualPageMode},
                          onSelectionChanged: (values) {
                            HapticFeedback.selectionClick();
                            notifier.setDualPageMode(values.first);
                          },
                        ),
                      ],
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
                        onSelectionChanged: (values) {
                          HapticFeedback.selectionClick();
                          notifier.setImageFit(values.first);
                        },
                      ),
                      const SizedBox(height: 16),

                      // Cắt viền trắng thông minh (Smart Margin Crop)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: current.cropBorders
                                ? Colors.orangeAccent.withValues(alpha: 0.45)
                                : Colors.white12,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.crop_free_rounded,
                              color: current.cropBorders
                                  ? Colors.orangeAccent
                                  : Colors.white70,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Cắt viền trắng (Smart Crop)',
                                    style: TextStyle(
                                      color: current.cropBorders
                                          ? Colors.orangeAccent
                                          : Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Tự động loại bỏ lề giấy trắng thừa giúp tranh tràn toàn màn hình',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: current.cropBorders,
                              activeTrackColor: Colors.orangeAccent,
                              activeThumbColor: Colors.orangeAccent,
                              onChanged: (val) {
                                HapticFeedback.selectionClick();
                                notifier.setCropBorders(val);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Mini HUD Đồng hồ & Pin khi đọc toàn màn hình
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: current.showBatteryAndClock
                                ? Colors.orangeAccent.withValues(alpha: 0.45)
                                : Colors.white12,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              color: current.showBatteryAndClock
                                  ? Colors.orangeAccent
                                  : Colors.white70,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Đồng hồ & Trang góc màn hình',
                                    style: TextStyle(
                                      color: current.showBatteryAndClock
                                          ? Colors.orangeAccent
                                          : Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Hiển thị giờ và số trang tinh tế khi ẩn thanh công cụ',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: current.showBatteryAndClock,
                              activeTrackColor: Colors.orangeAccent,
                              activeThumbColor: Colors.orangeAccent,
                              onChanged: (val) {
                                HapticFeedback.selectionClick();
                                notifier.setShowBatteryAndClock(val);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Chế độ đọc Ẩn danh (Incognito Mode)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: current.isIncognito
                              ? Colors.purple.withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: current.isIncognito
                                ? Colors.purpleAccent.withValues(alpha: 0.6)
                                : Colors.white12,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              current.isIncognito
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_outlined,
                              color: current.isIncognito
                                  ? Colors.purpleAccent
                                  : Colors.white70,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Chế độ đọc Ẩn danh (Incognito)',
                                    style: TextStyle(
                                      color: current.isIncognito
                                          ? Colors.purpleAccent
                                          : Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Không lưu lịch sử, tiến trình đọc và không đồng bộ Cloud',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: current.isIncognito,
                              activeTrackColor: Colors.purpleAccent,
                              activeThumbColor: Colors.purpleAccent,
                              onChanged: (val) {
                                HapticFeedback.selectionClick();
                                notifier.setIncognito(val);
                              },
                            ),
                          ],
                        ),
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
                            value: ReaderBackground.sepia,
                            icon: Icon(Icons.wb_twilight),
                            label: Text('Giấy ấm'),
                          ),
                          ButtonSegment(
                            value: ReaderBackground.white,
                            icon: Icon(Icons.light_mode),
                            label: Text('Trắng'),
                          ),
                        ],
                        selected: {current.background},
                        onSelectionChanged: (values) {
                          HapticFeedback.selectionClick();
                          notifier.setBackground(values.first);
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Sơ đồ vùng chạm lật trang',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<ReaderTapZone>(
                        segments: const [
                          ButtonSegment(
                            value: ReaderTapZone.default3Cols,
                            icon: Icon(Icons.view_column_rounded),
                            label: Text('3 Cột'),
                          ),
                          ButtonSegment(
                            value: ReaderTapZone.oneHanded,
                            icon: Icon(Icons.touch_app_rounded),
                            label: Text('1 Tay (L)'),
                          ),
                          ButtonSegment(
                            value: ReaderTapZone.leftHanded,
                            icon: Icon(Icons.pan_tool_alt_rounded),
                            label: Text('Tay trái'),
                          ),
                          ButtonSegment(
                            value: ReaderTapZone.swipeOnly,
                            icon: Icon(Icons.swipe_rounded),
                            label: Text('Chỉ vuốt'),
                          ),
                        ],
                        selected: {current.tapZone},
                        onSelectionChanged: (values) {
                          HapticFeedback.selectionClick();
                          notifier.setTapZone(values.first);
                        },
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _tapZoneDescription(current.tapZone),
                        style: const TextStyle(color: Colors.white54, fontSize: 11, fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: 16),

                      // ===== BỘ LỌC ẢNH BAN ĐÊM =====
                      const Divider(color: Colors.white12, height: 24),
                      Row(
                        children: [
                          const Icon(
                            Icons.bedtime_outlined,
                            color: Colors.amber,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Bộ lọc ban đêm',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Quick Eye-care Presets
                      Row(
                        children: [
                          Expanded(
                            child: _EyeCarePresetBtn(
                              label: 'Chuẩn',
                              icon: Icons.brightness_auto,
                              isSelected: current.dimLevel == 0.0 && current.tintLevel == 0.0 && !current.invertColors,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                ref.read(readerProvider.notifier).setDimLevel(0.0);
                                ref.read(readerProvider.notifier).setTintLevel(0.0);
                                ref.read(readerProvider.notifier).setInvertColors(false);
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _EyeCarePresetBtn(
                              label: 'Ấm áp',
                              icon: Icons.wb_twilight,
                              isSelected: current.tintLevel > 0.1 && !current.invertColors,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                ref.read(readerProvider.notifier).setDimLevel(0.0);
                                ref.read(readerProvider.notifier).setTintLevel(0.25);
                                ref.read(readerProvider.notifier).setInvertColors(false);
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _EyeCarePresetBtn(
                              label: 'Đảo màu',
                              icon: Icons.invert_colors,
                              isSelected: current.invertColors,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                ref.read(readerProvider.notifier).setInvertColors(!current.invertColors);
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _EyeCarePresetBtn(
                              label: 'Dịu mắt',
                              icon: Icons.nightlight_round,
                              isSelected: current.dimLevel > 0.2 && !current.invertColors,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                ref.read(readerProvider.notifier).setDimLevel(0.35);
                                ref.read(readerProvider.notifier).setTintLevel(0.15);
                                ref.read(readerProvider.notifier).setInvertColors(false);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Thanh giảm sáng
                      Row(
                        children: [
                          const Icon(Icons.brightness_4, color: Colors.white54, size: 16),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Giảm sáng',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ),
                          Text(
                            '${(current.dimLevel * 100).round()}%',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2.5,
                          activeTrackColor: Colors.white70,
                          inactiveTrackColor: Colors.white12,
                          thumbColor: Colors.white,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                        ),
                        child: Slider(
                          value: current.dimLevel,
                          min: 0.0,
                          max: 0.85,
                          onChanged: (v) =>
                              ref.read(readerProvider.notifier).setDimLevel(v),
                        ),
                      ),

                      const SizedBox(height: 4),

                      // Thanh lọc ánh sáng xanh
                      Row(
                        children: [
                          const Icon(Icons.filter_vintage, color: Colors.orangeAccent, size: 16),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Lọc ánh sáng xanh',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ),
                          Text(
                            '${(current.tintLevel * 200).round()}%',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2.5,
                          activeTrackColor: Colors.orangeAccent,
                          inactiveTrackColor: Colors.white12,
                          thumbColor: Colors.orange,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                        ),
                        child: Slider(
                          value: current.tintLevel,
                          min: 0.0,
                          max: 0.5,
                          onChanged: (v) =>
                              ref.read(readerProvider.notifier).setTintLevel(v),
                        ),
                      ),

                      const SizedBox(height: 4),

                      // Switch đảo màu
                      Row(
                        children: [
                          const Icon(Icons.invert_colors, color: Colors.purpleAccent, size: 16),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Đảo màu ảnh (Invert)',
                                  style: TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                                Text(
                                  'Tốt cho manga nền trắng khi đọc đêm',
                                  style: TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: current.invertColors,
                            activeThumbColor: Colors.purpleAccent,
                            activeTrackColor: Colors.purpleAccent.withValues(alpha: 0.4),
                            onChanged: (v) =>
                                ref.read(readerProvider.notifier).setInvertColors(v),
                          ),
                        ],
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
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.currentChapter?.title ?? 'Danh sách trang',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tổng cộng ${state.pages.length} trang • Chạm để nhảy trang',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orangeAccent.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        'Trang ${state.currentPageIndex + 1}/${state.pages.length}',
                        style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
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
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          Navigator.of(context).pop();
                          _jumpToPage(index);
                        },
                        onLongPress: () {
                          HapticFeedback.mediumImpact();
                          _saveCurrentPageImage(state, pageIndex: index);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? Colors.orangeAccent
                                  : Colors.white12,
                              width: selected ? 2.5 : 1,
                            ),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: Colors.orangeAccent.withValues(
                                        alpha: 0.35,
                                      ),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(state.pages[index]),
                                  fit: BoxFit.cover,
                                  cacheWidth: 300,
                                  gaplessPlayback: true,
                                ),
                              ),
                              if (selected)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orangeAccent,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Đang đọc',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                              Positioned(
                                left: 4,
                                bottom: 4,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.78),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.orangeAccent
                                            : Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
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

  /// Lưu ảnh của trang truyện hiện tại vào Thư viện máy (Pictures/MangaReader)
  Future<void> _saveCurrentPageImage(ReaderState state, {int? pageIndex}) async {
    final targetIndex = pageIndex ?? _currentPageNotifier.value;
    if (state.pages.isEmpty || targetIndex < 0 || targetIndex >= state.pages.length) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không có ảnh trang để lưu'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    final hasPerm = await PermissionService.hasStoragePermission();
    if (!hasPerm) {
      final granted = await PermissionService.requestStoragePermission();
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cần cấp quyền truy cập bộ nhớ để lưu ảnh vào Thư viện'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    final imagePath = state.pages[targetIndex];
    final mangaTitle = state.manga?.title ?? state.mangaId ?? 'Manga';
    final chapterTitle = state.currentChapter?.title ?? 'Chapter';

    final savedPath = await FolderService.savePageImageToGallery(
      sourceImagePath: imagePath,
      mangaTitle: mangaTitle,
      chapterTitle: chapterTitle,
      pageIndex: targetIndex,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (savedPath != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Đã lưu ảnh trang ${targetIndex + 1} vào Thư viện máy (Pictures/MangaReader)',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: const Color(0xFF1E293B),
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể lưu ảnh. Vui lòng thử lại!'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  /// Mở hộp thoại nhập / chỉnh sửa ghi chú cá nhân cho bookmark trang hiện tại
  Future<void> _showBookmarkNoteDialog(
    ReaderState state,
    ReaderNotifier notifier,
  ) async {
    HapticFeedback.lightImpact();
    final existingBookmark = await notifier.getCurrentPageBookmark();
    final textController = TextEditingController(text: existingBookmark?.note ?? '');

    if (!mounted) return;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Theme.of(dialogCtx).dialogTheme.backgroundColor ?? Theme.of(dialogCtx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.edit_note_rounded, color: Colors.amber, size: 24),
            const SizedBox(width: 8),
            Text(
              'Ghi chú Bookmark (Trang ${state.currentPageIndex + 1})',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Thêm ghi chú để dễ nhớ lý do bạn đánh dấu trang này:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              autofocus: true,
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Ví dụ: Đoạn đánh nhau hay, manh mối cốt truyện, wallpaper đẹp...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          if (existingBookmark?.note != null && existingBookmark!.note!.isNotEmpty)
            TextButton(
              onPressed: () {
                textController.clear();
                Navigator.pop(dialogCtx, true);
              },
              child: const Text('Xóa ghi chú', style: TextStyle(color: Colors.redAccent)),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Lưu ghi chú', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    final note = textController.text.trim();
    textController.dispose();

    if (save == true) {
      await notifier.saveBookmarkWithNote(note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            note.isEmpty
                ? 'Đã lưu bookmark (không ghi chú)'
                : 'Đã lưu ghi chú cho trang ${state.currentPageIndex + 1}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  List<List<int>> _calculateSpreads(int totalPages, ReaderDualPageMode mode) {
    if (totalPages <= 0) return [];
    if (mode == ReaderDualPageMode.off) {
      return List.generate(totalPages, (i) => [i]);
    }

    final spreads = <List<int>>[];
    int startIndex = 0;

    if (mode == ReaderDualPageMode.dualCover) {
      // Trang 0 đứng riêng làm bìa đơn
      spreads.add([0]);
      startIndex = 1;
    }

    for (int i = startIndex; i < totalPages; i += 2) {
      if (i + 1 < totalPages) {
        spreads.add([i, i + 1]);
      } else {
        spreads.add([i]);
      }
    }

    return spreads;
  }

  Widget _buildHorizontalView(ReaderState state, ReaderNotifier notifier) {
    final spreads = _calculateSpreads(state.pages.length, state.dualPageMode);
    final isRtl = state.direction == ReaderDirection.rtl;

    return PhotoViewGallery.builder(
      scrollPhysics: const BouncingScrollPhysics(),
      builder: (context, index) {
        if (index == spreads.length) {
          return PhotoViewGalleryPageOptions.customChild(
            child: Center(
              child: _buildHorizontalChapterTransitionFooter(state, notifier),
            ),
            initialScale: PhotoViewComputedScale.contained,
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.contained,
          );
        }

        final pageIndices = spreads[index];
        if (pageIndices.length == 1) {
          final pageIdx = pageIndices[0];
          if (state.cropBorders) {
            return PhotoViewGalleryPageOptions.customChild(
              child: ClipRect(
                child: Transform.scale(
                  scale: 1.08,
                  alignment: Alignment.center,
                  child: Image.file(
                    File(state.pages[pageIdx]),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              initialScale: PhotoViewComputedScale.contained,
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 3,
            );
          }

          return PhotoViewGalleryPageOptions(
            imageProvider: ResizeImage(
              FileImage(File(state.pages[pageIdx])),
              width: (MediaQuery.of(context).size.width *
                      MediaQuery.of(context).devicePixelRatio)
                  .toInt(),
            ),
            initialScale: _initialPhotoScale(state.imageFit),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 3,
          );
        }

        // Trang đôi (2 trang ghép cạnh nhau)
        final leftIdx = isRtl ? pageIndices[1] : pageIndices[0];
        final rightIdx = isRtl ? pageIndices[0] : pageIndices[1];

        Widget dualRow = Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Image.file(
                File(state.pages[leftIdx]),
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Image.file(
                File(state.pages[rightIdx]),
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
          ],
        );

        if (state.cropBorders) {
          dualRow = ClipRect(
            child: Transform.scale(
              scale: 1.08,
              alignment: Alignment.center,
              child: dualRow,
            ),
          );
        }

        return PhotoViewGalleryPageOptions.customChild(
          child: dualRow,
          initialScale: PhotoViewComputedScale.contained,
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
        );
      },
      itemCount: spreads.length + 1,
      pageController: _pageController,
      reverse: isRtl,
      onPageChanged: (index) {
        if (index < spreads.length) {
          final primaryPageIndex = spreads[index][0];
          notifier.onPageChanged(primaryPageIndex);
          HapticFeedback.selectionClick();
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

  // Chế độ đọc DỌC: ListView cuộn liên tục thuần túy, mượt mà 60/120fps, không bị can thiệp gesture
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
        final key = _pageKeys.putIfAbsent(pageIndex, () => GlobalKey());

        Widget imageWidget = Image.file(
          File(state.pages[pageIndex]),
          fit: _verticalImageFit(state.imageFit),
          width: double.infinity,
          alignment: Alignment.topCenter,
          cacheWidth:
              (MediaQuery.of(context).size.width *
                      MediaQuery.of(context).devicePixelRatio)
                  .toInt(),
          filterQuality: FilterQuality.none, // Khử anti-aliasing
          errorBuilder: (_, __, ___) => Container(
            height: 200,
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.broken_image_rounded, size: 36, color: Colors.white38),
                  const SizedBox(height: 8),
                  Text(
                    'Không thể tải trang ${pageIndex + 1}',
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        );

        if (state.cropBorders) {
          imageWidget = ClipRect(
            child: Transform.scale(
              scale: 1.08,
              alignment: Alignment.center,
              child: imageWidget,
            ),
          );
        }

        return Container(
          key: key,
          child: Transform.translate(
            offset: const Offset(0, -0.5), // Khử hở viền 1px
            child: imageWidget,
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

  Widget _buildDrawer(ReaderState state, ReaderNotifier notifier) {
    return _ReaderDrawerContent(
      state: state,
      notifier: notifier,
      onNavigateChapter: (chapterId, mangaId, {int? page}) {
        context.pushReplacement(_readerRoute(chapterId, mangaId, page: page));
      },
      onJumpToPage: _jumpToPage,
      onReloadChapter: _reloadCurrentChapter,
    );
  }
}

class _ReaderDrawerContent extends ConsumerStatefulWidget {
  final ReaderState state;
  final ReaderNotifier notifier;
  final Function(String chapterId, String? mangaId, {int? page}) onNavigateChapter;
  final Function(int pageIndex) onJumpToPage;
  final Function(ReaderNotifier notifier) onReloadChapter;

  const _ReaderDrawerContent({
    required this.state,
    required this.notifier,
    required this.onNavigateChapter,
    required this.onJumpToPage,
    required this.onReloadChapter,
  });

  @override
  ConsumerState<_ReaderDrawerContent> createState() => _ReaderDrawerContentState();
}

class _ReaderDrawerContentState extends ConsumerState<_ReaderDrawerContent>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _chapterSearchController = TextEditingController();
  final ScrollController _chapterScrollController = ScrollController();
  String _chapterSearchQuery = '';
  Timer? _searchDebounce;
  bool _isSortReversed = false;
  bool _hasAutoScrolled = false;
  Set<String> _readChapterIds = {};
  List<ReaderBookmark> _bookmarks = [];
  bool _isLoadingBookmarks = true;
  bool _filterOnlyCurrentChapter = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadInitialData();
  }

  @override
  void didUpdateWidget(covariant _ReaderDrawerContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.mangaId != oldWidget.state.mangaId ||
        widget.state.currentChapter?.id != oldWidget.state.currentChapter?.id) {
      _loadInitialData();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _chapterSearchController.dispose();
    _chapterScrollController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final mangaId = widget.state.mangaId;
    if (mangaId != null && mangaId.isNotEmpty) {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      final readIds = await DatabaseHelper.instance.getReadChapterIds(
        mangaId,
        userId: userId,
      );
      final prefs = await SharedPreferences.getInstance();
      final reversed =
          prefs.getBool('manga_sort_reversed_$mangaId') ?? false;
      if (mounted) {
        setState(() {
          _readChapterIds = readIds;
          _isSortReversed = reversed;
        });
      }
    }
    await _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    final mangaId = widget.state.mangaId;
    if (mangaId == null || mangaId.isEmpty) {
      if (mounted) setState(() => _isLoadingBookmarks = false);
      return;
    }
    try {
      final list = await DatabaseHelper.instance.getBookmarksForManga(mangaId);
      if (mounted) {
        setState(() {
          _bookmarks = list;
          _isLoadingBookmarks = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingBookmarks = false);
    }
  }

  String _getChapterTitle(String chapterId) {
    for (final c in widget.state.chapters) {
      if (c.id == chapterId) return c.title;
    }
    return 'Chương $chapterId';
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min';
  }

  Future<void> _deleteBookmark(ReaderBookmark bookmark) async {
    HapticFeedback.lightImpact();
    await widget.notifier.deleteBookmark(bookmark.id);
    await _loadBookmarks();
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã xóa bookmark Trang ${bookmark.pageIndex + 1}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _editBookmarkNote(ReaderBookmark bookmark) async {
    HapticFeedback.lightImpact();
    final textController = TextEditingController(text: bookmark.note ?? '');
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Theme.of(dialogCtx).dialogTheme.backgroundColor ?? Theme.of(dialogCtx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.edit_note_rounded, color: Colors.amber, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Ghi chú (Trang ${bookmark.pageIndex + 1})',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getChapterTitle(bookmark.chapterId),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              autofocus: true,
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Nhập ghi chú cá nhân...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          if (bookmark.note != null && bookmark.note!.isNotEmpty)
            TextButton(
              onPressed: () {
                textController.clear();
                Navigator.pop(dialogCtx, true);
              },
              child: const Text('Xóa ghi chú', style: TextStyle(color: Colors.redAccent)),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Lưu', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    final note = textController.text.trim();
    textController.dispose();

    if (save == true) {
      await widget.notifier.updateBookmarkNote(bookmark.id, note);
      await _loadBookmarks();
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            note.isEmpty
                ? 'Đã lưu (không ghi chú)'
                : 'Đã cập nhật ghi chú cho Trang ${bookmark.pageIndex + 1}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readerProvider);
    final notifier = ref.read(readerProvider.notifier);
    final currentChapter = state.currentChapter;

    // Filter chapters
    final seen = <String>{};
    final normalizedSearch = CatalogCacheService.instance.normalize(_chapterSearchQuery);
    final rawChapters = state.chapters
        .where((c) => seen.add(c.id))
        .where((c) {
          if (normalizedSearch.isEmpty) return true;
          final normTitle = CatalogCacheService.instance.normalize(c.title);
          return normTitle.contains(normalizedSearch);
        })
        .toList();
    final filteredChapters = _isSortReversed ? rawChapters.reversed.toList() : rawChapters;

    // Auto-scroll to current chapter
    if (!_hasAutoScrolled && currentChapter != null) {
      final selectedIndex = filteredChapters.indexWhere((c) => c.id == currentChapter.id);
      if (selectedIndex > 0) {
        _hasAutoScrolled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_chapterScrollController.hasClients) {
            final targetOffset = (selectedIndex * 56.0) - 100.0;
            _chapterScrollController.jumpTo(
              targetOffset.clamp(0.0, _chapterScrollController.position.maxScrollExtent),
            );
          }
        });
      }
    }

    // Filter bookmarks
    final currentChapterId = currentChapter?.id;
    final displayBookmarks = _filterOnlyCurrentChapter && currentChapterId != null
        ? _bookmarks.where((b) => b.chapterId == currentChapterId).toList()
        : _bookmarks;

    final currentChapterBookmarkCount = currentChapterId == null
        ? 0
        : _bookmarks.where((b) => b.chapterId == currentChapterId).length;

    return Drawer(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            // 1. Drawer Header (Manga summary & Tabs)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: const Border(
                  bottom: BorderSide(color: Colors.white12, width: 1),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (state.manga != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: DriveImage(
                            fileId: state.manga!.coverFileId,
                            width: 36,
                            height: 52,
                            fit: BoxFit.cover,
                          ),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.manga?.title ?? 'Đang đọc',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              state.currentChapter?.title ?? '',
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                        tooltip: 'Đóng',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.orangeAccent,
                    indicatorWeight: 3,
                    labelColor: Colors.orangeAccent,
                    unselectedLabelColor: Colors.white60,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.format_list_numbered_rounded, size: 16),
                            const SizedBox(width: 6),
                            Text('Chương (${state.chapters.length})'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.bookmarks_rounded, size: 16),
                            const SizedBox(width: 6),
                            Text('Đánh dấu (${_bookmarks.length})'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 2. TabBarView Body
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // TAB 1: Danh sách Chương
                  Column(
                    children: [
                      // Search & Sort bar
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _chapterSearchController,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                textInputAction: TextInputAction.search,
                                decoration: InputDecoration(
                                  hintText: 'Tìm số chương...',
                                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                                  prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 16),
                                  suffixIcon: _chapterSearchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear, color: Colors.white54, size: 14),
                                          onPressed: () {
                                            _chapterSearchController.clear();
                                            setState(() => _chapterSearchQuery = '');
                                          },
                                        )
                                      : null,
                                  filled: true,
                                  fillColor: Colors.white.withValues(alpha: 0.08),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                onChanged: (val) {
                                  if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
                                  _searchDebounce = Timer(const Duration(milliseconds: 150), () {
                                    if (mounted) setState(() => _chapterSearchQuery = val);
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              icon: Icon(
                                Icons.swap_vert_rounded,
                                color: _isSortReversed ? Colors.orangeAccent : Colors.white70,
                                size: 22,
                              ),
                              tooltip: _isSortReversed ? 'Mới nhất trước' : 'Cũ nhất trước',
                              onPressed: () async {
                                HapticFeedback.selectionClick();
                                setState(() => _isSortReversed = !_isSortReversed);
                                if (widget.state.mangaId != null && widget.state.mangaId!.isNotEmpty) {
                                  final prefs = await SharedPreferences.getInstance();
                                  await prefs.setBool('manga_sort_reversed_${widget.state.mangaId}', _isSortReversed);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      // Chapter ListView
                      Expanded(
                        child: filteredChapters.isEmpty
                            ? const Center(
                                child: Text('Không tìm thấy chương nào', style: TextStyle(color: Colors.white54)),
                              )
                            : ListView.builder(
                                controller: _chapterScrollController,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                itemCount: filteredChapters.length,
                                itemBuilder: (context, index) {
                                  final chapter = filteredChapters[index];
                                  final isCurrent = chapter.id == currentChapter?.id;
                                  final isRead = _readChapterIds.contains(chapter.id);

                                  return Container(
                                    margin: const EdgeInsets.symmetric(vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isCurrent
                                          ? Colors.orangeAccent.withValues(alpha: 0.14)
                                          : Colors.white.withValues(alpha: 0.04),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isCurrent
                                            ? Colors.orangeAccent.withValues(alpha: 0.7)
                                            : Colors.white.withValues(alpha: 0.08),
                                        width: isCurrent ? 1.5 : 1,
                                      ),
                                    ),
                                    child: ListTile(
                                      dense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                      leading: Icon(
                                        isCurrent
                                            ? Icons.play_circle_filled_rounded
                                            : isRead
                                                ? Icons.check_circle_rounded
                                                : Icons.radio_button_unchecked,
                                        color: isCurrent
                                            ? Colors.orangeAccent
                                            : isRead
                                                ? Colors.greenAccent
                                                : Colors.white24,
                                        size: 20,
                                      ),
                                      title: Text(
                                        chapter.title,
                                        style: TextStyle(
                                          color: isCurrent
                                              ? Colors.orangeAccent
                                              : isRead
                                                  ? Colors.white60
                                                  : Colors.white,
                                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                          fontSize: 13,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: isCurrent
                                          ? Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.orangeAccent,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                'Đang đọc',
                                                style: TextStyle(
                                                  color: Colors.black,
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            )
                                          : null,
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        Navigator.pop(context);
                                        if (!isCurrent) {
                                          widget.onNavigateChapter(chapter.id, widget.state.mangaId);
                                        }
                                      },
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),

                  // TAB 2: Danh sách Đánh dấu & Ghi chú
                  Column(
                    children: [
                      // Filter chips (Tất cả / Chương này)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: Text('Tất cả (${_bookmarks.length})', style: const TextStyle(fontSize: 11.5)),
                              selected: !_filterOnlyCurrentChapter,
                              selectedColor: Colors.orangeAccent,
                              labelStyle: TextStyle(
                                color: !_filterOnlyCurrentChapter ? Colors.black : Colors.white70,
                                fontWeight: !_filterOnlyCurrentChapter ? FontWeight.bold : FontWeight.normal,
                              ),
                              backgroundColor: Colors.white.withValues(alpha: 0.08),
                              onSelected: (val) {
                                if (val) setState(() => _filterOnlyCurrentChapter = false);
                              },
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: Text('Chương này ($currentChapterBookmarkCount)', style: const TextStyle(fontSize: 11.5)),
                              selected: _filterOnlyCurrentChapter,
                              selectedColor: Colors.orangeAccent,
                              labelStyle: TextStyle(
                                color: _filterOnlyCurrentChapter ? Colors.black : Colors.white70,
                                fontWeight: _filterOnlyCurrentChapter ? FontWeight.bold : FontWeight.normal,
                              ),
                              backgroundColor: Colors.white.withValues(alpha: 0.08),
                              onSelected: (val) {
                                if (val) setState(() => _filterOnlyCurrentChapter = true);
                              },
                            ),
                          ],
                        ),
                      ),

                      // Bookmark List
                      Expanded(
                        child: _isLoadingBookmarks
                            ? const Center(child: CircularProgressIndicator())
                            : displayBookmarks.isEmpty
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.bookmark_border_rounded,
                                            size: 48,
                                            color: Colors.white.withValues(alpha: 0.25),
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            _filterOnlyCurrentChapter
                                                ? 'Chưa có bookmark nào trong chương này'
                                                : 'Chưa có trang đánh dấu nào',
                                            style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 6),
                                          const Text(
                                            'Chạm vào biểu tượng Bookmark trên thanh điều khiển khi đọc để lưu lại trang yêu thích!',
                                            style: TextStyle(color: Colors.white38, fontSize: 12),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    itemCount: displayBookmarks.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final bookmark = displayBookmarks[index];
                                      final chapterTitle = _getChapterTitle(bookmark.chapterId);
                                      final isSameChapter = bookmark.chapterId == currentChapter?.id;

                                      return InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          Navigator.pop(context);
                                          if (isSameChapter) {
                                            widget.onJumpToPage(bookmark.pageIndex);
                                          } else {
                                            widget.onNavigateChapter(
                                              bookmark.chapterId,
                                              widget.state.mangaId,
                                              page: bookmark.pageIndex,
                                            );
                                          }
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.05),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: isSameChapter
                                                  ? Colors.amber.withValues(alpha: 0.4)
                                                  : Colors.white12,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: Colors.amber.withValues(alpha: 0.2),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        const Icon(Icons.bookmark_rounded, color: Colors.amber, size: 12),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          'Trang ${bookmark.pageIndex + 1}',
                                                          style: const TextStyle(
                                                            color: Colors.amber,
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      chapterTitle,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 13,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (bookmark.note != null && bookmark.note!.isNotEmpty) ...[
                                                const SizedBox(height: 8),
                                                Container(
                                                  width: double.infinity,
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: Colors.amber.withValues(alpha: 0.08),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: const Border(
                                                      left: BorderSide(color: Colors.amber, width: 3),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      const Icon(Icons.format_quote_rounded, color: Colors.amber, size: 14),
                                                      const SizedBox(width: 6),
                                                      Expanded(
                                                        child: Text(
                                                          bookmark.note!,
                                                          style: const TextStyle(
                                                            color: Colors.white70,
                                                            fontSize: 12,
                                                            fontStyle: FontStyle.italic,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(height: 6),
                                              Row(
                                                children: [
                                                  Text(
                                                    _formatDateTime(bookmark.updatedAt),
                                                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                                                  ),
                                                  const Spacer(),
                                                  IconButton(
                                                    visualDensity: VisualDensity.compact,
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                                    icon: const Icon(Icons.edit_note_rounded, color: Colors.amberAccent, size: 18),
                                                    tooltip: 'Sửa ghi chú',
                                                    onPressed: () => _editBookmarkNote(bookmark),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  IconButton(
                                                    visualDensity: VisualDensity.compact,
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                                    tooltip: 'Xóa bookmark',
                                                    onPressed: () => _deleteBookmark(bookmark),
                                                  ),
                                                ],
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
                ],
              ),
            ),

            // 3. Drawer Quick Action Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: const Border(
                  top: BorderSide(color: Colors.white12, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: Icon(
                        state.readingMode == ReadingMode.horizontal ? Icons.swap_vert : Icons.swap_horiz,
                        size: 16,
                      ),
                      label: Text(
                        state.readingMode == ReadingMode.horizontal ? 'Đọc Dọc' : 'Đọc Ngang',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        notifier.setReadingMode(
                          state.readingMode == ReadingMode.horizontal
                              ? ReadingMode.vertical
                              : ReadingMode.horizontal,
                        );
                        Navigator.pop(context);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Tải lại', style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onReloadChapter(notifier);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;
  Set<String> _readChapterIds = {};
  bool _isSortReversed = false;
  bool _hasAutoScrolled = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    if (widget.mangaId != null && widget.mangaId!.isNotEmpty) {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      final readIds = await DatabaseHelper.instance.getReadChapterIds(
        widget.mangaId!,
        userId: userId,
      );
      final prefs = await SharedPreferences.getInstance();
      final reversed =
          prefs.getBool('manga_sort_reversed_${widget.mangaId}') ?? false;
      if (mounted) {
        setState(() {
          _readChapterIds = readIds;
          _isSortReversed = reversed;
        });
      }
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
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
        final seen = <String>{};
        final normalizedSearch =
            CatalogCacheService.instance.normalize(_searchQuery);
        final rawChapters = widget.chapters
            .where((c) => seen.add(c.id))
            .where((c) {
              if (normalizedSearch.isEmpty) return true;
              final normTitle = CatalogCacheService.instance.normalize(c.title);
              return normTitle.contains(normalizedSearch);
            })
            .toList();
        final filteredChapters =
            _isSortReversed ? rawChapters.reversed.toList() : rawChapters;

        if (!_hasAutoScrolled && widget.currentChapter != null) {
          final selectedIndex = filteredChapters.indexWhere(
            (c) => c.id == widget.currentChapter!.id,
          );
          if (selectedIndex > 0) {
            _hasAutoScrolled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (scrollController.hasClients) {
                final targetOffset = (selectedIndex * 52.0) - 100.0;
                scrollController.jumpTo(
                  targetOffset.clamp(0.0, scrollController.position.maxScrollExtent),
                );
              }
            });
          }
        }

        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
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
                        // Nút đảo chiều thứ tự chương
                        IconButton(
                          icon: Icon(
                            Icons.swap_vert_rounded,
                            color: _isSortReversed
                                ? Colors.orangeAccent
                                : Colors.white,
                          ),
                          tooltip: _isSortReversed
                              ? 'Đang xếp: Mới nhất trước'
                              : 'Đang xếp: Cũ nhất trước',
                          onPressed: () async {
                            HapticFeedback.selectionClick();
                            setState(() => _isSortReversed = !_isSortReversed);
                            if (widget.mangaId != null &&
                                widget.mangaId!.isNotEmpty) {
                              final prefs =
                                  await SharedPreferences.getInstance();
                              await prefs.setBool(
                                'manga_sort_reversed_${widget.mangaId}',
                                _isSortReversed,
                              );
                            }
                          },
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
                            HapticFeedback.lightImpact();
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
                            Icons.unfold_more_rounded,
                            color: Colors.white,
                          ),
                          tooltip: 'Phóng to/Thu nhỏ',
                          onPressed: _toggleSize,
                        ),
                      ],
                    );
                  },
                ),
              ),

              // Thanh tìm kiếm nhanh chương
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Tìm nhanh số chương (vd: 12, Chapter 50)...',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                    prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white54, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
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

              // Danh sách
              Expanded(
                child: filteredChapters.isEmpty
                    ? const Center(
                        child: Text(
                          'Không tìm thấy chương phù hợp',
                          style: TextStyle(color: Colors.white38),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: filteredChapters.length,
                        itemBuilder: (context, index) {
                          final chapter = filteredChapters[index];
                          final isSelected =
                              chapter.id == widget.currentChapter?.id;
                          final isRead = _readChapterIds.contains(chapter.id);

                          final date =
                              "${chapter.uploadedAt.day}/${chapter.uploadedAt.month}/${chapter.uploadedAt.year}";

                          return InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              Navigator.pop(context); // Đóng cửa sổ
                              if (!isSelected) {
                                final mangaQuery =
                                    widget.mangaId == null ||
                                            widget.mangaId!.isEmpty
                                        ? ''
                                        : '?mangaId=${Uri.encodeComponent(widget.mangaId!)}';
                                context.pushReplacement(
                                  '/reader/${chapter.id}$mangaQuery',
                                );
                              }
                            },
                            child: Container(
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : null,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  if (!isRead && !isSelected) ...[
                                    Container(
                                      width: 6,
                                      height: 6,
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                  Expanded(
                                    child: Text(
                                      chapter.title,
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.blueAccent
                                            : isRead
                                                ? Colors.white38
                                                : Colors.white,
                                        fontWeight: isSelected || !isRead
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    date,
                                    style: TextStyle(
                                      color: isRead
                                          ? Colors.white24
                                          : Colors.grey,
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

class _EyeCarePresetBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _EyeCarePresetBtn({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = label == 'Đảo màu'
        ? Colors.purpleAccent
        : (label == 'Ấm áp' ? Colors.orangeAccent : (label == 'Dịu mắt' ? Colors.amberAccent : Colors.white));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor : Colors.white12,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? activeColor : Colors.white70,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? activeColor : Colors.white70,
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Mini HUD hiển thị góc màn hình khi đọc truyện toàn màn hình (Ẩn thanh công cụ)
class _MiniReaderHud extends StatefulWidget {
  final int currentPage;
  final int totalPages;

  const _MiniReaderHud({
    required this.currentPage,
    required this.totalPages,
  });

  @override
  State<_MiniReaderHud> createState() => _MiniReaderHudState();
}

class _MiniReaderHudState extends State<_MiniReaderHud> {
  Timer? _timer;
  String _timeString = '';

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _updateTime());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateTime() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    if (mounted) {
      setState(() => _timeString = '$h:$m');
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.access_time_rounded, size: 11.5, color: Colors.white70),
            const SizedBox(width: 4),
            Text(
              _timeString,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            if (widget.totalPages > 0) ...[
              const SizedBox(width: 6),
              Container(
                width: 3,
                height: 3,
                decoration: const BoxDecoration(
                  color: Colors.white38,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${widget.currentPage + 1}/${widget.totalPages}',
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


