import 'dart:ui';
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
import 'package:image_size_getter/image_size_getter.dart';
import 'package:image_size_getter/file_input.dart';
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
  Timer?
  _precacheDebounceTimer; // Debounce để tránh spam precacheImage khi cuộn nhanh
  final Set<String> _precachedPaths = {}; // Track file đã cache, tránh gọi lại
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

  final Map<String, Size> _imageSizeCache = {};

  Size? _getImageSize(String filePath) {
    if (_imageSizeCache.containsKey(filePath)) {
      return _imageSizeCache[filePath];
    }
    try {
      final size =
          ImageSizeGetter.getSizeResult(FileInput(File(filePath))).size;
      _imageSizeCache[filePath] = size;
      return size;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _scrollController = ScrollController();

    _levelUpSub = LevelService.instance.onLevelUp.listen((result) {
      if (mounted) {
        final title =
            LevelService.levelTitles[(result.newLevel - 1).clamp(
              0,
              LevelService.levelTitles.length - 1,
            )];
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
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
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
      // BUG-02 fix: reset so scroll-restore triggers correctly even on reload
      _restoredScrollChapterId = null;
      ref
          .read(readerProvider.notifier)
          .init(
            widget.chapterId,
            mangaId: widget.mangaId,
            initialPageIndex: widget.initialPageIndex,
          );

      _applyOrientation(ref.read(readerProvider).orientation);
    });
  }

  void _applyOrientation(ReaderOrientation orientation) {
    switch (orientation) {
      case ReaderOrientation.portrait:
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        break;
      case ReaderOrientation.landscape:
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        break;
      case ReaderOrientation.reversePortrait:
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitDown]);
        break;
      case ReaderOrientation.auto:
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        break;
    }
  }

  void _onVerticalScroll() {
    final state = ref.read(readerProvider);

    if (!state.isVerticalMode) return;
    if (!_scrollController.hasClients) return;

    final pixels = _scrollController.position.pixels;
    final maxExtent = _scrollController.position.maxScrollExtent;
    final readingMode =
        state.readingMode; // cache local để khỏi lấy lại nhiều lần

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

    if (pageCount > 0 && state.isVerticalMode) {
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
    } else if (pageCount > 0 && readingMode == ReadingMode.horizontal) {
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
      final deltaPixels =
          _autoScrollPixelsPerSecond *
          _autoScrollSpeedMultiplier *
          safeDeltaSeconds;

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
    final durationMs =
        (_pdfAutoPageTurnInterval.inMilliseconds / _autoScrollSpeedMultiplier)
            .round();
    Future.delayed(Duration(milliseconds: durationMs.clamp(500, 10000)), () {
      if (!mounted) return;
      _advancePdfAutoPage(runId);
    });
  }

  Future<void> _advancePdfAutoPage(int runId) async {
    if (!_isAutoScrolling || runId != _autoPageTurnRunId) return;

    final canContinue = _pdfReaderKey.currentState?.autoScrollNext() ?? false;
    if (!canContinue) {
      _stopAutoScroll();
      return;
    }

    _schedulePdfAutoPageTurn(runId);
  }

  void _scheduleHorizontalAutoPageTurn(int runId) {
    final durationMs =
        (_autoPageTurnInterval.inMilliseconds / _autoScrollSpeedMultiplier)
            .round();
    Future.delayed(
      Duration(milliseconds: durationMs.clamp(300, 10000)),
      () async {
        if (!mounted || !_isAutoScrolling || runId != _autoPageTurnRunId) {
          return;
        }
        await _advanceHorizontalAutoPage(runId);
      },
    );
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

    final spreads = _calculateSpreads(state.pages.length, state.dualPageMode);
    final currentSpread = _pageController.page?.round() ?? 0;

    if (currentSpread < spreads.length - 1) {
      if (!_pageController.hasClients) {
        _stopAutoScroll();
        return;
      }
      await _pageController.animateToPage(
        currentSpread + 1,
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
          backgroundColor:
              Theme.of(ctx).dialogTheme.backgroundColor ??
              Theme.of(ctx).cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
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

    // BUG-09 fix: stop any running animation before restarting
    _holdProgressController.stop();
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

    // BUG-09 fix: stop any running animation before restarting
    _holdProgressController.stop();
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

      if (nextState.isVerticalMode && _scrollController.hasClients) {
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
          if (nextState.isVerticalMode && _scrollController.hasClients) {
            // BUG-07 fix: use 50% of screen height instead of magic 200px
            final halfScreen = MediaQuery.of(context).size.height * 0.5;
            _scrollController.jumpTo(
              (_scrollController.position.maxScrollExtent - halfScreen).clamp(
                0.0,
                _scrollController.position.maxScrollExtent,
              ),
            );
          } else if (nextState.readingMode == ReadingMode.horizontal &&
              _pageController.hasClients &&
              nextState.pages.isNotEmpty) {
            final spreads = _calculateSpreads(
              nextState.pages.length,
              nextState.dualPageMode,
            );
            final targetSpread = spreads.isNotEmpty ? spreads.length - 1 : 0;
            _pageController.jumpToPage(targetSpread);
          }
        });
      }
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    _levelUpSub?.cancel();
    _scrollController.removeListener(_onVerticalScroll);
    _cancelHoldTimer();
    _progressSaveTimer?.cancel();
    _precacheDebounceTimer?.cancel();
    _precachedPaths.clear();
    _imageSizeCache.clear();
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
      isNextKey =
          event.logicalKey == LogicalKeyboardKey.arrowDown ||
          (isRtl
              ? event.logicalKey == LogicalKeyboardKey.arrowLeft
              : event.logicalKey == LogicalKeyboardKey.arrowRight) ||
          event.logicalKey == LogicalKeyboardKey.space ||
          event.logicalKey == LogicalKeyboardKey.pageDown;

      isPrevKey =
          event.logicalKey == LogicalKeyboardKey.arrowUp ||
          (isRtl
              ? event.logicalKey == LogicalKeyboardKey.arrowRight
              : event.logicalKey == LogicalKeyboardKey.arrowLeft) ||
          event.logicalKey == LogicalKeyboardKey.pageUp;
    }

    if (isNextKey) {
      _readerPageForward(state);
    } else if (isPrevKey) {
      _readerPageBackward(state);
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

    // PDF handles jumping via initialPage passing to PdfReaderView and direct controller jump
    if (state.isPdf) {
      _pdfReaderKey.currentState?.jumpToPage(target);
      return;
    }

    if (state.readingMode == ReadingMode.horizontal) {
      if (_pageController.hasClients) {
        final spreads = _calculateSpreads(
          state.pages.length,
          state.dualPageMode,
        );
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

      // BUG-04 fix: try exact position via RenderBox (pages may have unequal heights).
      // Fall back to linear estimate if the key hasn't laid out yet.
      final pageKey = _pageKeys[target];
      final ctx = pageKey?.currentContext;
      if (ctx != null) {
        final box = ctx.findRenderObject() as RenderBox?;
        if (box != null && box.attached) {
          final scrollPos = _scrollController.position;
          try {
            final viewport = scrollPos.context.storageContext;
            final vpBox = viewport.findRenderObject() as RenderBox?;
            if (vpBox != null && vpBox.attached) {
              final localTop = vpBox
                  .globalToLocal(box.localToGlobal(Offset.zero))
                  .dy;
              final absoluteOffset = (scrollPos.pixels + localTop).clamp(
                0.0,
                maxScroll,
              );
              _scrollController.animateTo(
                absoluteOffset,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
              );
              return;
            }
          } catch (_) {}
        }
      }

      // Linear fallback for pages not yet in the widget tree
      final offset = maxScroll * (target / (state.pages.length - 1));
      _scrollController.animateTo(
        offset.clamp(0.0, maxScroll),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  Object _initialPhotoScale(ReaderImageFit fit, {String? filePath}) {
    if (fit == ReaderImageFit.smart && filePath != null) {
      try {
        final size = ImageSizeGetter.getSizeResult(
          FileInput(File(filePath)),
        ).size;
        final imageRatio = size.width / size.height;
        final screenSize = MediaQuery.of(context).size;
        final screenRatio = screenSize.width / screenSize.height;

        // Nếu ảnh dài hơn màn hình nhiều (ví dụ webtoon) -> Fit width (covered)
        // Nếu ảnh ngang hoặc tỷ lệ gần bằng màn hình -> Fit screen (contained)
        if (imageRatio < screenRatio * 0.8) {
          return PhotoViewComputedScale.covered;
        } else {
          return PhotoViewComputedScale.contained;
        }
      } catch (_) {
        return PhotoViewComputedScale.contained;
      }
    }

    switch (fit) {
      case ReaderImageFit.smart: // Fallback
      case ReaderImageFit.width:
        return PhotoViewComputedScale.covered;
      case ReaderImageFit.height:
      case ReaderImageFit.screen:
        return PhotoViewComputedScale.contained;
      case ReaderImageFit.original:
        return 1.0;
    }
  }

  Alignment _getZoomAlignment(ReaderZoomStart zoomStart) {
    switch (zoomStart) {
      case ReaderZoomStart.left:
        return Alignment.centerLeft;
      case ReaderZoomStart.right:
        return Alignment.centerRight;
      case ReaderZoomStart.center:
        return Alignment.center;
      case ReaderZoomStart.auto:
        return Alignment.center;
    }
  }

  BoxFit _verticalImageFit(ReaderImageFit fit) {
    switch (fit) {
      case ReaderImageFit
          .smart: // Trong chế độ cuộn dọc, fitWidth là tối ưu nhất cho smart
      case ReaderImageFit.width:
        return BoxFit.fitWidth;
      case ReaderImageFit.height:
        return BoxFit.fitHeight;
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
    if (state.isPdf) {
      if (state.readingMode == ReadingMode.horizontal) {
        _pdfReaderKey.currentState?.nextPage();
      } else {
        final screenHeight = MediaQuery.of(context).size.height;
        _pdfReaderKey.currentState?.scrollBy(screenHeight * 0.65);
      }
      return;
    }

    if (state.readingMode == ReadingMode.horizontal) {
      final spreads = _calculateSpreads(state.pages.length, state.dualPageMode);
      final currentSpread = _pageController.hasClients
          ? _pageController.page?.round() ?? 0
          : 0;
      if (currentSpread < spreads.length - 1) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      } else {
        _triggerNextChapter();
      }
    } else if (state.isVerticalMode) {
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
    if (state.isPdf) {
      if (state.readingMode == ReadingMode.horizontal) {
        _pdfReaderKey.currentState?.previousPage();
      } else {
        final screenHeight = MediaQuery.of(context).size.height;
        _pdfReaderKey.currentState?.scrollBy(-(screenHeight * 0.65));
      }
      return;
    }

    if (state.readingMode == ReadingMode.horizontal) {
      final currentSpread = _pageController.hasClients
          ? _pageController.page?.round() ?? 0
          : 0;
      if (currentSpread > 0) {
        _pageController.previousPage(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      } else {
        _triggerPrevChapter();
      }
    } else if (state.isVerticalMode) {
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

  String _tapZoneDescription(ReaderTapZone zone, {bool isVertical = false}) {
    if (isVertical) {
      switch (zone) {
        case ReaderTapZone.default3Cols:
          return 'Chạm mép dưới: Cuộn xuống, Mép trên: Cuộn lên, Giữa: Menu';
        case ReaderTapZone.oneHanded:
          return 'Nửa dưới màn hình: Cuộn xuống (thuận ngón cái), Đỉnh: Cuộn lên, Giữa: Menu';
        case ReaderTapZone.leftHanded:
          return 'Mép trái: Cuộn xuống, Mép phải: Cuộn lên, Giữa: Menu';
        case ReaderTapZone.swipeOnly:
          return 'Chạm chỉ để bật/tắt Menu. Điều hướng cuộn hoàn toàn bằng cách vuốt tay';
        case ReaderTapZone.kindle:
          return 'Nửa phải: Cuộn xuống, Nửa trái: Cuộn lên, Chính giữa: Menu';
      }
    }
    switch (zone) {
      case ReaderTapZone.default3Cols:
        return 'Trái: Lùi, Giữa: Menu, Phải: Tiến (hoặc ngược lại nếu đọc RTL)';
      case ReaderTapZone.oneHanded:
        return 'Nửa dưới: Tiến (thuận ngón cái), Đỉnh: Lùi, Giữa: Menu';
      case ReaderTapZone.leftHanded:
        return 'Trái: Tiến (thuận tay trái), Phải: Lùi, Giữa: Menu';
      case ReaderTapZone.swipeOnly:
        return 'Chạm mọi nơi chỉ để bật/tắt Menu. Lật trang bằng cách vuốt';
      case ReaderTapZone.kindle:
        return 'Nửa phải: Tiến, Nửa trái: Lùi, Chính giữa: Menu';
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
    double tapX = details.globalPosition.dx;
    double tapY = details.globalPosition.dy;

    if (state.tapZoneInvert == ReaderTapZoneInvert.horizontal ||
        state.tapZoneInvert == ReaderTapZoneInvert.both) {
      tapX = screenWidth - tapX;
    }
    if (state.tapZoneInvert == ReaderTapZoneInvert.vertical ||
        state.tapZoneInvert == ReaderTapZoneInvert.both) {
      tapY = screenHeight - tapY;
    }

    // 1. Chế độ chỉ vuốt
    if (state.tapZone == ReaderTapZone.swipeOnly) {
      notifier.toggleControls();
      return;
    }

    // 1.5. Chế độ Kindle: Nửa phải tiến, nửa trái lùi. Chạm chính giữa mở menu
    if (state.tapZone == ReaderTapZone.kindle) {
      final midLeft = screenWidth * 0.3;
      final midRight = screenWidth * 0.7;
      if (tapX > midLeft && tapX < midRight) {
        notifier.toggleControls();
      } else if (tapX >= midRight) {
        if (state.direction == ReaderDirection.rtl && !state.isVerticalMode) {
          _readerPageBackward(state);
        } else {
          _readerPageForward(state);
        }
      } else {
        if (state.direction == ReaderDirection.rtl && !state.isVerticalMode) {
          _readerPageForward(state);
        } else {
          _readerPageBackward(state);
        }
      }
      return;
    }

    // 2. Chế độ Đọc 1 tay (One-Handed / L-Shape)
    // Thiết kế công thái học: Đỉnh màn hình luôn là LÙI, toàn bộ nửa dưới & hai lề dưới luôn là TIẾN
    if (state.tapZone == ReaderTapZone.oneHanded) {
      // Đỉnh màn hình (18%) -> Lùi trang / Cuộn lên
      if (tapY < screenHeight * 0.18) {
        _readerPageBackward(state);
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
      // Toàn bộ vùng còn lại (vừa tầm ngón cái) -> Tiến trang / Cuộn xuống
      _readerPageForward(state);
      return;
    }

    // 3. Chế độ Thuận tay trái (Left-Handed)
    // Thiết kế công thái học: Lề trái là nơi ngón cái tay trái đặt vào -> Luôn là TIẾN
    if (state.tapZone == ReaderTapZone.leftHanded) {
      if (state.isVerticalMode) {
        // Mép trái (40%) -> Cuộn xuống (Tiến)
        if (tapX < screenWidth * 0.40) {
          _readerPageForward(state);
        }
        // Mép phải (40%) -> Cuộn lên (Lùi)
        else if (tapX > screenWidth * 0.60) {
          _readerPageBackward(state);
        }
        // 20% Giữa màn hình -> Menu controls
        else {
          notifier.toggleControls();
        }
        return;
      }

      // Đọc ngang: 40% Bên trái màn hình -> Luôn TIẾN (dành cho ngón cái tay trái)
      if (tapX < screenWidth * 0.40) {
        _readerPageForward(state);
      }
      // 40% Bên phải màn hình -> Luôn LÙI
      else if (tapX > screenWidth * 0.60) {
        _readerPageBackward(state);
      }
      // 20% Giữa màn hình -> Menu controls
      else {
        notifier.toggleControls();
      }
      return;
    }

    // 4. Chế độ 3 Cột Mặc định (Default 3-Cols)
    if (state.isVerticalMode) {
      if (tapY < screenHeight * 0.35) {
        _readerPageBackward(state);
      } else if (tapY > screenHeight * 0.65) {
        _readerPageForward(state);
      } else {
        notifier.toggleControls();
      }
      return;
    }

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
    // BUG-02 fix: clear restore guard so scrollOffset re-fires after reload
    _restoredScrollChapterId = null;
    notifier.init(chapterId, mangaId: mangaId);
  }

  void _precacheNearbyPages(ReaderState state, {int? targetIndex}) {
    if (!mounted || state.pages.isEmpty) return;
    // Debounce: tránh spam precache khi cuộn liên tục
    _precacheDebounceTimer?.cancel();
    _precacheDebounceTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      final current = targetIndex ?? state.currentPageIndex;
      final isVertical = state.isVerticalMode;
      final forwardWindow = isVertical ? 5 : 2;
      final backwardWindow = isVertical ? 2 : 2;
      final start = (current - backwardWindow).clamp(0, state.pages.length - 1);
      final end = (current + forwardWindow).clamp(0, state.pages.length - 1);
      for (var i = start; i <= end; i++) {
        try {
          final filePath = state.pages[i];
          // Bỏ qua nếu đã cache rồi (tránh gọi precacheImage lặp lại)
          if (filePath.isEmpty || _precachedPaths.contains(filePath)) continue;
          final file = File(filePath);
          if (file.existsSync()) {
            _precachedPaths.add(filePath);
            precacheImage(FileImage(file), context);
          }
        } catch (_) {}
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readerProvider);
    final notifier = ref.read(readerProvider.notifier);

    // BUG FIX: ref.listen phải được gọi ở top-level trong build(), TRƯỚC mọi early-return,
    // để listener luôn active dù đang đọc EPUB hay Manga.
    ref.listen<ReaderState>(readerProvider, (prev, next) {
      if (prev?.currentChapter?.id != next.currentChapter?.id) {
        _precachedPaths.clear();
      }

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
        if (_pageController.hasClients) {
          final spreads = _calculateSpreads(
            next.pages.length,
            next.dualPageMode,
          );
          final maxSpread = spreads.isEmpty ? 0 : spreads.length - 1;
          final targetSpread = spreads.indexWhere(
            (s) => s.contains(next.currentPageIndex),
          );
          final safeSpread = targetSpread != -1
              ? targetSpread
              : next.currentPageIndex.clamp(0, maxSpread);
          if (_pageController.page?.round() != safeSpread) {
            _pageController.jumpToPage(safeSpread);
          }
        }
      }

      if (prev?.orientation != next.orientation) {
        _applyOrientation(next.orientation);
      }

      // Xử lý khi chuyển đổi giữa chế độ dọc và ngang
      if (prev != null && prev.readingMode != next.readingMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          if (next.readingMode == ReadingMode.horizontal) {
            if (_pageController.hasClients) {
              final spreads = _calculateSpreads(
                next.pages.length,
                next.dualPageMode,
              );
              final maxSpread = spreads.isEmpty ? 0 : spreads.length - 1;
              final targetSpread = spreads.indexWhere(
                (s) => s.contains(next.currentPageIndex),
              );
              final safeSpread = targetSpread != -1
                  ? targetSpread
                  : next.currentPageIndex.clamp(0, maxSpread);
              if (_pageController.page?.round() != safeSpread) {
                _pageController.jumpToPage(safeSpread);
              }
            }
          } else if (next.isVerticalMode) {
            _jumpToPage(next.currentPageIndex);
          }
        });
      }

      final chapterId = next.currentChapter?.id;
      if (!next.isLoading &&
          next.isVerticalMode &&
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

    // Early-return cho EPUB reader (sau khi ref.listen đã được đăng ký)
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
                  // Nội dung ảnh manga — chỉ rebuild khi page/mode/fit/filter thực sự thay đổi
                  Consumer(
                    builder: (context, ref, _) {
                      final contentState = ref.watch(
                        readerProvider.select(
                          (s) => (
                            pages: s.pages,
                            readingMode: s.readingMode,
                            isPdf: s.isPdf,
                            localFilePath: s.localFilePath,
                            currentPageIndex: s.currentPageIndex,
                            imageFit: s.imageFit,
                            background: s.background,
                            invertColors: s.invertColors,
                            cropBorders: s.cropBorders,
                            dualPageMode: s.dualPageMode,
                            direction: s.direction,
                            isNovel: s.isNovel,
                            currentChapter: s.currentChapter,
                          ),
                        ),
                      );
                      final contentNotifier = ref.read(readerProvider.notifier);
                      final contentFullState = ref.read(readerProvider);

                      Widget readerView = GestureDetector(
                        onTapUp: (details) => _handleReaderTap(
                          details,
                          contentFullState,
                          contentNotifier,
                        ),
                        child:
                            contentState.isPdf &&
                                contentState.localFilePath != null
                            ? PdfReaderView(
                                key: _pdfReaderKey,
                                scrollDirection:
                                    contentState.readingMode ==
                                        ReadingMode.horizontal
                                    ? Axis.horizontal
                                    : Axis.vertical,
                                pdfPath: contentState.localFilePath!,
                                initialPage: contentState.currentPageIndex,
                                onDocumentLoaded: (pageCount) {
                                  contentNotifier.setPdfPageCount(pageCount);
                                },
                                onPageChanged: (pageIndex) {
                                  contentNotifier.onPageChanged(pageIndex);
                                  _scheduleVerticalProgressSaveIfNeeded(
                                    0.0,
                                    pageIndex,
                                  );
                                },
                                onToggleControls:
                                    contentNotifier.toggleControls,
                              )
                            : contentState.readingMode == ReadingMode.horizontal
                            ? _buildHorizontalView(
                                contentFullState,
                                contentNotifier,
                              )
                            : _buildVerticalView(
                                contentFullState,
                                contentNotifier,
                              ),
                      );

                      return ColorFiltered(
                        colorFilter: contentState.invertColors
                            ? const ColorFilter.matrix([
                                -1,
                                0,
                                0,
                                0,
                                255,
                                0,
                                -1,
                                0,
                                0,
                                255,
                                0,
                                0,
                                -1,
                                0,
                                255,
                                0,
                                0,
                                0,
                                1,
                                0,
                              ])
                            : const ColorFilter.matrix([
                                1,
                                0,
                                0,
                                0,
                                0,
                                0,
                                1,
                                0,
                                0,
                                0,
                                0,
                                0,
                                1,
                                0,
                                0,
                                0,
                                0,
                                0,
                                1,
                                0,
                              ]),
                        child: readerView,
                      );
                    },
                  ),

                  // ===== BỘ LỌC ẢNH BAN ĐÊM – các lớp phủ ảnh (IgnorePointer – không chặn touch) =====
                  // Lớp giảm sáng (Dim)
                  if (state.dimLevel > 0)
                    IgnorePointer(
                      child: Container(
                        color: Colors.black.withValues(alpha: state.dimLevel),
                      ),
                    ),

                  // Lớp lọc ánh sáng xanh: phủ màu vàng/cam nhẹ lên toàn bộ màn hình
                  if (state.tintLevel > 0)
                    IgnorePointer(
                      child: Container(
                        color: const Color(
                          0xFFFF9500,
                        ).withValues(alpha: state.tintLevel),
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
                                  tooltip: 'Quay lại',
                                  onPressed: () => context.pop(),
                                ),
                                const SizedBox(width: 4),

                                // Thông tin & Chọn chương
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      InkWell(
                                        onTap: state.mangaId != null &&
                                                state.mangaId!.isNotEmpty
                                            ? () {
                                                HapticFeedback.selectionClick();
                                                context.push(
                                                  '/detail/${state.mangaId}',
                                                );
                                              }
                                            : null,
                                        borderRadius: BorderRadius.circular(6),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 2,
                                            horizontal: 2,
                                          ),
                                          child: Text(
                                            state.manga?.title ?? 'Đang tải...',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      // Nút chọn chương
                                      InkWell(
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          _showChapterListModal(
                                            context,
                                            state.chapters,
                                            state.currentChapter,
                                            state.mangaId,
                                          );
                                        },
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          constraints: const BoxConstraints(
                                            minHeight: 28,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: Colors.white.withValues(
                                                alpha: 0.15,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  state.currentChapter?.title ??
                                                      'Chương ?',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 3),
                                              const Icon(
                                                Icons.keyboard_arrow_down_rounded,
                                                color: Colors.white70,
                                                size: 16,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Nút Lưu ảnh trang về máy
                                if (!state.isPdf &&
                                    !state.isNovel &&
                                    state.pages.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.download_rounded,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                    tooltip: 'Lưu ảnh trang này về Thư viện',
                                    onPressed: () =>
                                        _saveCurrentPageImage(state),
                                    padding: const EdgeInsets.all(6),
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                  ),
                                if (!state.isPdf &&
                                    !state.isNovel &&
                                    state.pages.isNotEmpty)
                                  const SizedBox(width: 4),
                                // Nút Menu (Ngăn kéo)
                                if (!state
                                    .isPdf) // Ẩn Thumbnail grid khi đọc PDF
                                  IconButton(
                                    icon: const Icon(
                                      Icons.grid_view,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                    tooltip: 'Danh sách trang',
                                    onPressed: () =>
                                        _showPageThumbnailSheet(state),
                                    padding: const EdgeInsets.all(6),
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                  ),
                                if (!state.isPdf)
                                  const SizedBox(width: 4),
                                // Nút Chế độ Ẩn danh (Incognito)
                                IconButton(
                                  icon: Icon(
                                    state.isIncognito
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_outlined,
                                    color: state.isIncognito
                                        ? Colors.purpleAccent
                                        : Colors.white,
                                    size: 22,
                                  ),
                                  tooltip: state.isIncognito
                                      ? 'Đang bật Chế độ ẩn danh'
                                      : 'Bật Chế độ ẩn danh',
                                  onPressed: () {
                                    HapticFeedback.mediumImpact();
                                    notifier.toggleIncognito();
                                    ScaffoldMessenger.of(
                                      context,
                                    ).hideCurrentSnackBar();
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
                                  padding: const EdgeInsets.all(6),
                                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(
                                    Icons.tune,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                  tooltip: 'Cài đặt đọc',
                                  onPressed: () => _showReaderSettings(
                                    context,
                                    state,
                                    notifier,
                                  ),
                                  padding: const EdgeInsets.all(6),
                                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                ),
                                const SizedBox(width: 4),
                                Builder(
                                  builder: (context) => IconButton(
                                    icon: const Icon(
                                      Icons.menu,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                    onPressed: () =>
                                        Scaffold.of(context).openDrawer(),
                                    padding: const EdgeInsets.all(6),
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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
                                      icon: Icon(
                                        Icons.skip_previous_rounded,
                                        color:
                                            notifier.getPrevChapterId() != null
                                            ? Colors.white
                                            : Colors.white24,
                                        size: 26,
                                      ),
                                      tooltip:
                                          notifier.getPrevChapterId() != null
                                          ? 'Chương trước'
                                          : 'Đã là chương đầu tiên',
                                      onPressed:
                                          notifier.getPrevChapterId() != null
                                          ? () {
                                              HapticFeedback.selectionClick();
                                              context.pushReplacement(
                                                _readerRoute(
                                                  notifier.getPrevChapterId()!,
                                                  state.mangaId,
                                                ),
                                              );
                                            }
                                          : null,
                                    ),
                                    IconButton(
                                      tooltip: state.isFollowed
                                          ? 'Bỏ theo dõi truyện'
                                          : 'Theo dõi truyện',
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
                                      triggerMode: TooltipTriggerMode.manual,
                                      message: state.isCurrentPageBookmarked
                                          ? 'Đã bookmark (Nhấn giữ để sửa ghi chú)'
                                          : 'Bookmark trang này (Nhấn giữ để thêm ghi chú)',
                                      child: IconButton(
                                        icon: Icon(
                                          state.isCurrentPageBookmarked
                                              ? Icons.bookmark
                                              : Icons.bookmark_border,
                                          color: state.isCurrentPageBookmarked
                                              ? Colors.amber
                                              : Colors.white,
                                        ),
                                        onLongPress: () =>
                                            _showBookmarkNoteDialog(
                                              state,
                                              notifier,
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
                                              duration: const Duration(
                                                milliseconds: 1500,
                                              ),
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: _isAutoScrolling
                                          ? 'Dừng tự động đọc'
                                          : state.readingMode ==
                                                ReadingMode.horizontal
                                          ? 'Bật tự lật trang'
                                          : 'Bật tự cuộn',
                                      icon: Icon(
                                        _isAutoScrolling
                                            ? Icons.pause_circle_filled_rounded
                                            : Icons.play_circle_outline_rounded,
                                        color: _isAutoScrolling
                                            ? Theme.of(context).colorScheme.primary
                                            : Colors.white,
                                        size: 26,
                                      ),
                                      onPressed: _toggleAutoScroll,
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.skip_next_rounded,
                                        color:
                                            notifier.getNextChapterId() != null
                                            ? Colors.white
                                            : Colors.white24,
                                        size: 26,
                                      ),
                                      tooltip:
                                          notifier.getNextChapterId() != null
                                          ? 'Chương kế tiếp'
                                          : 'Đã là chương mới nhất',
                                      onPressed:
                                          notifier.getNextChapterId() != null
                                          ? () {
                                              HapticFeedback.selectionClick();
                                              context.pushReplacement(
                                                _readerRoute(
                                                  notifier.getNextChapterId()!,
                                                  state.mangaId,
                                                ),
                                              );
                                            }
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
                  if (!state.showControls &&
                      state.showBatteryAndClock &&
                      !state.isNovel)
                    Positioned(
                      bottom: MediaQuery.of(context).padding.bottom + 8,
                      right: _isAutoScrolling ? null : 14,
                      left: _isAutoScrolling ? 14 : null,
                      child: ValueListenableBuilder<int>(
                        valueListenable: _currentPageNotifier,
                        builder: (context, currentPage, _) => _MiniReaderHud(
                          currentPage: currentPage,
                          totalPages: state.isPdf
                              ? state.pdfPageCount
                              : state.pages.length,
                        ),
                      ),
                    ),
                  // Thanh tinh chỉnh tốc độ tự cuộn
                  if (_isAutoScrolling)
                    Positioned(
                      bottom:
                          (state.showControls ? 155 : 32) +
                          MediaQuery.of(context).padding.bottom,
                      right: 16,
                      child: _buildAutoScrollControlBar(),
                    ),
                ],
              ),
      ),
    );
  }

  void _increaseAutoScrollSpeed() {
    if (_autoScrollSpeedMultiplier >= 4.0) return;
    HapticFeedback.lightImpact();
    setState(() {
      _autoScrollSpeedMultiplier = (_autoScrollSpeedMultiplier + 0.25).clamp(
        0.5,
        4.0,
      );
    });
  }

  void _decreaseAutoScrollSpeed() {
    if (_autoScrollSpeedMultiplier <= 0.5) return;
    HapticFeedback.lightImpact();
    setState(() {
      _autoScrollSpeedMultiplier = (_autoScrollSpeedMultiplier - 0.25).clamp(
        0.5,
        4.0,
      );
    });
  }

  Widget _buildAutoScrollControlBar() {
    final speedText = _autoScrollSpeedMultiplier % 1 == 0
        ? '${_autoScrollSpeedMultiplier.toInt()}x'
        : '${_autoScrollSpeedMultiplier.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '')}x';

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                tooltip: _autoScrollSpeedMultiplier > 0.5
                    ? 'Giảm tốc độ'
                    : 'Đã đạt tốc độ tối thiểu (0.5x)',
                icon: Icon(
                  Icons.remove_rounded,
                  color: _autoScrollSpeedMultiplier > 0.5
                      ? Colors.white70
                      : Colors.white24,
                  size: 20,
                ),
                onPressed: _autoScrollSpeedMultiplier > 0.5
                    ? _decreaseAutoScrollSpeed
                    : null,
              ),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 38),
                child: Text(
                  speedText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.amberAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                tooltip: _autoScrollSpeedMultiplier < 4.0
                    ? 'Tăng tốc độ'
                    : 'Đã đạt tốc độ tối đa (4.0x)',
                icon: Icon(
                  Icons.add_rounded,
                  color: _autoScrollSpeedMultiplier < 4.0
                      ? Colors.white70
                      : Colors.white24,
                  size: 20,
                ),
                onPressed: _autoScrollSpeedMultiplier < 4.0
                    ? _increaseAutoScrollSpeed
                    : null,
              ),
              const SizedBox(width: 6),
              Container(width: 1, height: 18, color: Colors.white24),
              const SizedBox(width: 6),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                tooltip: 'Dừng tự cuộn',
                icon: const Icon(
                  Icons.pause_circle_filled_rounded,
                  color: Colors.redAccent,
                  size: 24,
                ),
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
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
                      ref
                          .read(readerProvider.notifier)
                          .setDirection(newDirection);
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
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            state.direction == ReaderDirection.rtl
                                ? Icons.arrow_back
                                : Icons.arrow_forward,
                            color: Theme.of(context).colorScheme.primary,
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            state.direction == ReaderDirection.rtl
                                ? 'Ngang (RTL)'
                                : 'Ngang (LTR)',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
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
            Directionality(
              textDirection: state.direction == ReaderDirection.rtl
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3.5,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8.0,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 18.0,
                  ),
                ),
                child: Slider(
                  value: hasMultiplePages
                      ? (_scrubbingPageIndex ?? clampedPage).toDouble().clamp(
                          0.0,
                          (pageCount - 1).toDouble(),
                        )
                      : 0,
                  min: 0,
                  max: hasMultiplePages ? (pageCount - 1).toDouble() : 1,
                  divisions: hasMultiplePages ? pageCount - 1 : null,
                  activeColor: Theme.of(context).colorScheme.primary,
                  inactiveColor: Colors.white24,
                  onChangeStart: hasMultiplePages
                      ? (value) {
                          if (!state.isPdf &&
                              !state.isNovel &&
                              state.pages.isNotEmpty) {
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
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
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
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  'Trang ${target + 1} / ${state.pages.length}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
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
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
              ),
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
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
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
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
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
              backgroundColor:
                  Theme.of(ctx).dialogTheme.backgroundColor ??
                  Theme.of(ctx).cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'Báo lỗi chương',
                style: TextStyle(
                  color: Theme.of(ctx).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Loại lỗi:',
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<String>(
                      value: selectedReason,
                      dropdownColor: Theme.of(ctx).cardColor,
                      style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface),
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
                    Text(
                      'Mô tả thêm (Tùy chọn):',
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descController,
                      style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface),
                      maxLines: 3,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Theme.of(ctx).cardColor,
                        border: const OutlineInputBorder(),
                        hintText: 'Nhập mô tả chi tiết...',
                        hintStyle: TextStyle(
                          color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.35),
                        ),
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
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
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
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final current = ref.watch(readerProvider);
            final theme = Theme.of(context);
            final primary = theme.colorScheme.primary;
            final onSurface = theme.colorScheme.onSurface;
            final divider = theme.dividerColor;
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.88,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Cài đặt đọc truyện tranh',
                                style: TextStyle(
                                  color: onSurface,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close, color: onSurface.withValues(alpha: 0.7)),
                              tooltip: 'Đóng',
                              onPressed: () => Navigator.pop(context),
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: current.isPerMangaSettings
                              ? primary.withValues(alpha: 0.15)
                              : onSurface.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: current.isPerMangaSettings
                                ? primary
                                : divider.withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                        child: SwitchListTile(
                          title: const Text(
                            'Lưu cài đặt riêng cho truyện này',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            'Ghi đè cài đặt chung. Bật để lưu chế độ đọc, hướng lật, v.v. riêng cho phần truyện này.',
                            style: TextStyle(
                              fontSize: 11,
                              color: onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                          value: current.isPerMangaSettings,
                          onChanged: (val) {
                            notifier.setPerMangaSettings(val);
                          },
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          dense: true,
                          activeTrackColor: primary.withValues(alpha: 0.5),
                          activeThumbColor: primary,
                        ),
                      ),
                      const _ReaderSheetSectionHeader('BỐ CỤC & HƯỚNG ĐỌC', Icons.auto_stories_rounded),
                      Text(
                        'Chế độ đọc',
                        style: TextStyle(color: onSurface.withValues(alpha: 0.7)),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<ReadingMode>(
                        showSelectedIcon: false,
                        style: ButtonStyle(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          padding: WidgetStateProperty.all(
                            const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          ),
                        ),
                        segments: const [
                          ButtonSegment(
                            value: ReadingMode.vertical,
                            icon: Icon(Icons.swap_vert, size: 15),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Dọc', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          ButtonSegment(
                            value: ReadingMode.verticalGap,
                            icon: Icon(Icons.format_line_spacing, size: 15),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Dọc (cách)', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          ButtonSegment(
                            value: ReadingMode.horizontal,
                            icon: Icon(Icons.swap_horiz, size: 15),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Ngang', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                        selected: {current.readingMode},
                        onSelectionChanged: (values) {
                          HapticFeedback.selectionClick();
                          notifier.setReadingMode(values.first);
                        },
                      ),
                      if (current.readingMode == ReadingMode.horizontal) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Hướng đọc (Trái ↔ Phải)',
                          style: TextStyle(color: onSurface.withValues(alpha: 0.7)),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<ReaderDirection>(
                          showSelectedIcon: false,
                          style: ButtonStyle(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            padding: WidgetStateProperty.all(
                              const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            ),
                          ),
                          segments: const [
                            ButtonSegment(
                              value: ReaderDirection.ltr,
                              icon: Icon(Icons.arrow_forward, size: 15),
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Trái qua phải', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              ),
                            ),
                            ButtonSegment(
                              value: ReaderDirection.rtl,
                              icon: Icon(Icons.arrow_back, size: 15),
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Phải qua trái', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ],
                          selected: {current.direction},
                          onSelectionChanged: (values) {
                            HapticFeedback.selectionClick();
                            notifier.setDirection(values.first);
                          },
                        ),

                        const SizedBox(height: 16),
                        Text(
                          'Chế độ hiển thị trang (Ngang/Tablet)',
                          style: TextStyle(color: onSurface.withValues(alpha: 0.7)),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<ReaderDualPageMode>(
                          showSelectedIcon: false,
                          style: ButtonStyle(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            padding: WidgetStateProperty.all(
                              const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                            ),
                          ),
                          segments: const [
                            ButtonSegment(
                              value: ReaderDualPageMode.off,
                              icon: Icon(Icons.portrait, size: 15),
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Trang đơn', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              ),
                            ),
                            ButtonSegment(
                              value: ReaderDualPageMode.dual,
                              icon: Icon(Icons.auto_stories, size: 15),
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Trang đôi', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              ),
                            ),
                            ButtonSegment(
                              value: ReaderDualPageMode.dualCover,
                              icon: Icon(Icons.menu_book, size: 15),
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Bìa đơn + Đôi', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              ),
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
                      Text(
                        'Fit ảnh',
                        style: TextStyle(color: onSurface.withValues(alpha: 0.7)),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<ReaderImageFit>(
                        showSelectedIcon: false,
                        style: ButtonStyle(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          padding: WidgetStateProperty.all(
                            const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                          ),
                        ),
                        segments: const [
                          ButtonSegment(
                            value: ReaderImageFit.smart,
                            icon: Icon(Icons.auto_awesome, size: 14),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Smart',
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          ButtonSegment(
                            value: ReaderImageFit.width,
                            icon: Icon(Icons.fit_screen, size: 14),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Rộng',
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          ButtonSegment(
                            value: ReaderImageFit.height,
                            icon: Icon(Icons.height, size: 14),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Dọc',
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          ButtonSegment(
                            value: ReaderImageFit.screen,
                            icon: Icon(Icons.fullscreen, size: 14),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Màn',
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          ButtonSegment(
                            value: ReaderImageFit.original,
                            icon: Icon(Icons.image, size: 14),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Gốc',
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ],
                        selected: {current.imageFit},
                        onSelectionChanged: (values) {
                          HapticFeedback.selectionClick();
                          notifier.setImageFit(values.first);
                        },
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Xoay màn hình',
                        style: TextStyle(color: onSurface.withValues(alpha: 0.7)),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<ReaderOrientation>(
                        showSelectedIcon: false,
                        style: ButtonStyle(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          padding: WidgetStateProperty.all(
                            const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          ),
                        ),
                        segments: const [
                          ButtonSegment(
                            value: ReaderOrientation.auto,
                            icon: Icon(Icons.screen_rotation, size: 15),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Tự do', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          ButtonSegment(
                            value: ReaderOrientation.portrait,
                            icon: Icon(Icons.screen_lock_portrait, size: 15),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Dọc', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          ButtonSegment(
                            value: ReaderOrientation.landscape,
                            icon: Icon(Icons.screen_lock_landscape, size: 15),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Ngang', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          ButtonSegment(
                            value: ReaderOrientation.reversePortrait,
                            icon: Icon(Icons.screen_lock_portrait, size: 15),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Ngược', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                        selected: {current.orientation},
                        onSelectionChanged: (values) {
                          HapticFeedback.selectionClick();
                          notifier.setOrientation(values.first);
                        },
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Vị trí bắt đầu phóng to',
                        style: TextStyle(color: onSurface.withValues(alpha: 0.7)),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<ReaderZoomStart>(
                        showSelectedIcon: false,
                        style: ButtonStyle(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          padding: WidgetStateProperty.all(
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                          ),
                        ),
                        segments: const [
                          ButtonSegment(
                            value: ReaderZoomStart.auto,
                            icon: Icon(Icons.auto_awesome, size: 15),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Tự động', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          ButtonSegment(
                            value: ReaderZoomStart.left,
                            icon: Icon(Icons.align_horizontal_left, size: 15),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Trái', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          ButtonSegment(
                            value: ReaderZoomStart.center,
                            icon: Icon(Icons.align_horizontal_center, size: 15),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Giữa', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          ButtonSegment(
                            value: ReaderZoomStart.right,
                            icon: Icon(Icons.align_horizontal_right, size: 15),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Phải', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                        selected: {current.zoomStart},
                        onSelectionChanged: (values) {
                          HapticFeedback.selectionClick();
                          notifier.setZoomStart(values.first);
                        },
                      ),
                      const _ReaderSheetSectionHeader('TIỆN ÍCH & TỰ ĐỘNG HÓA', Icons.tune_rounded),

                      // Cắt viền trắng thông minh (Smart Margin Crop)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: onSurface.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: current.cropBorders
                                ? primary.withValues(alpha: 0.45)
                                : divider.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.crop_free_rounded,
                              color: current.cropBorders
                                  ? primary
                                  : onSurface.withValues(alpha: 0.7),
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
                                          ? primary
                                          : onSurface,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Tự động loại bỏ lề giấy trắng thừa giúp tranh tràn toàn màn hình',
                                    style: TextStyle(
                                      color: onSurface.withValues(alpha: 0.6),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: current.cropBorders,
                              activeTrackColor: primary,
                              activeThumbColor: primary,
                              onChanged: (val) {
                                HapticFeedback.selectionClick();
                                notifier.setCropBorders(val);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Tự động xoay ảnh ngang (Rotate Landscape Images)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: onSurface.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: current.rotateLandscapeImages
                                ? primary.withValues(alpha: 0.45)
                                : divider.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.rotate_90_degrees_cw_rounded,
                              color: current.rotateLandscapeImages
                                  ? primary
                                  : onSurface.withValues(alpha: 0.7),
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Tự động xoay trang ngang',
                                    style: TextStyle(
                                      color: current.rotateLandscapeImages
                                          ? primary
                                          : onSurface,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Xoay 90° các trang ảnh khổ ngang để xem tràn toàn màn hình',
                                    style: TextStyle(
                                      color: onSurface.withValues(alpha: 0.6),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: current.rotateLandscapeImages,
                              activeTrackColor: primary,
                              activeThumbColor: primary,
                              onChanged: (val) {
                                HapticFeedback.selectionClick();
                                notifier.setRotateLandscapeImages(val);
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
                          color: onSurface.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: current.showBatteryAndClock
                                ? primary.withValues(alpha: 0.45)
                                : divider.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              color: current.showBatteryAndClock
                                  ? primary
                                  : onSurface.withValues(alpha: 0.7),
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
                                          ? primary
                                          : onSurface,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Hiển thị giờ và số trang tinh tế khi ẩn thanh công cụ',
                                    style: TextStyle(
                                      color: onSurface.withValues(alpha: 0.6),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: current.showBatteryAndClock,
                              activeTrackColor: primary,
                              activeThumbColor: primary,
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
                              : onSurface.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: current.isIncognito
                                ? Colors.purpleAccent.withValues(alpha: 0.6)
                                : divider.withValues(alpha: 0.2),
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
                                  : onSurface.withValues(alpha: 0.7),
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
                                          : onSurface,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Không lưu lịch sử, tiến trình đọc và không đồng bộ Cloud',
                                    style: TextStyle(
                                      color: onSurface.withValues(alpha: 0.6),
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
                      const _ReaderSheetSectionHeader('PHÍM CỨNG & CỬ CHỈ', Icons.touch_app_rounded),

                      // Phím âm lượng chuyển trang (Volume Page Turn)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: onSurface.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: current.volumePageTurn
                                ? primary.withValues(alpha: 0.45)
                                : divider.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.volume_up_rounded,
                                  color: current.volumePageTurn
                                      ? primary
                                      : onSurface.withValues(alpha: 0.7),
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Phím âm lượng chuyển trang',
                                        style: TextStyle(
                                          color: current.volumePageTurn
                                              ? primary
                                              : onSurface,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Dùng nút tăng/giảm âm lượng để lật trang hoặc cuộn đọc',
                                        style: TextStyle(
                                          color: onSurface.withValues(alpha: 0.6),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch.adaptive(
                                  value: current.volumePageTurn,
                                  activeTrackColor: primary,
                                  activeThumbColor: primary,
                                  onChanged: (val) {
                                    HapticFeedback.selectionClick();
                                    notifier.setVolumePageTurn(val);
                                  },
                                ),
                              ],
                            ),
                            if (current.volumePageTurn) ...[
                              Divider(color: divider, height: 16),
                              Row(
                                children: [
                                  const SizedBox(width: 34),
                                  Expanded(
                                    child: Text(
                                      'Đảo ngược chiều phím',
                                      style: TextStyle(
                                        color: onSurface.withValues(alpha: 0.75),
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                  Switch.adaptive(
                                    value: current.invertVolumeKeys,
                                    activeTrackColor: primary,
                                    activeThumbColor: primary,
                                    onChanged: (val) {
                                      HapticFeedback.selectionClick();
                                      notifier.setInvertVolumeKeys(val);
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const _ReaderSheetSectionHeader('MÀU NỀN & BẢO VỆ MẮT', Icons.palette_outlined),
                      Text(
                        'Màu nền',
                        style: TextStyle(color: onSurface.withValues(alpha: 0.7)),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<ReaderBackground>(
                        showSelectedIcon: true,
                        style: ButtonStyle(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          padding: WidgetStateProperty.all(
                            const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          ),
                        ),
                        segments: const [
                          ButtonSegment(
                            value: ReaderBackground.black,
                            icon: Icon(Icons.dark_mode, size: 15),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Đen', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          ButtonSegment(
                            value: ReaderBackground.gray,
                            icon: Icon(Icons.contrast, size: 15),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Xám', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          ButtonSegment(
                            value: ReaderBackground.sepia,
                            icon: Icon(Icons.wb_twilight, size: 15),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Giấy ấm', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          ButtonSegment(
                            value: ReaderBackground.white,
                            icon: Icon(Icons.light_mode, size: 15),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Trắng', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                        selected: {current.background},
                        onSelectionChanged: (values) {
                          HapticFeedback.selectionClick();
                          notifier.setBackground(values.first);
                        },
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Sơ đồ vùng chạm lật trang',
                        style: TextStyle(color: onSurface.withValues(alpha: 0.7)),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<ReaderTapZone>(
                        showSelectedIcon: false,
                        style: ButtonStyle(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          padding: WidgetStateProperty.all(
                            const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                          ),
                        ),
                        segments: const [
                          ButtonSegment(
                            value: ReaderTapZone.default3Cols,
                            icon: Icon(Icons.view_column_rounded, size: 14),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '3 Cột',
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          ButtonSegment(
                            value: ReaderTapZone.oneHanded,
                            icon: Icon(Icons.touch_app_rounded, size: 14),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '1 Tay',
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          ButtonSegment(
                            value: ReaderTapZone.leftHanded,
                            icon: Icon(Icons.pan_tool_alt_rounded, size: 14),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Trái',
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          ButtonSegment(
                            value: ReaderTapZone.kindle,
                            icon: Icon(Icons.menu_book_rounded, size: 14),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Kindle',
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          ButtonSegment(
                            value: ReaderTapZone.swipeOnly,
                            icon: Icon(Icons.swipe_rounded, size: 14),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Vuốt',
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ],
                        selected: {current.tapZone},
                        onSelectionChanged: (values) {
                          HapticFeedback.selectionClick();
                          notifier.setTapZone(values.first);
                        },
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: onSurface.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: divider.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              size: 14,
                              color: Colors.amberAccent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _tapZoneDescription(
                                  current.tapZone,
                                  isVertical: current.isVerticalMode,
                                ),
                                style: TextStyle(
                                  color: onSurface.withValues(alpha: 0.75),
                                  fontSize: 11.5,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _TapZoneDiagram(
                        tapZone: current.tapZone,
                        isVertical: current.isVerticalMode,
                        isRtl: current.direction == ReaderDirection.rtl,
                        tapZoneInvert: current.tapZoneInvert,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Đảo ngược vùng chạm',
                        style: TextStyle(color: onSurface.withValues(alpha: 0.7)),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<ReaderTapZoneInvert>(
                        showSelectedIcon: false,
                        style: ButtonStyle(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          padding: WidgetStateProperty.all(
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          ),
                        ),
                        segments: const [
                          ButtonSegment(
                            value: ReaderTapZoneInvert.none,
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Không', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          ButtonSegment(
                            value: ReaderTapZoneInvert.horizontal,
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Ngang', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          ButtonSegment(
                            value: ReaderTapZoneInvert.vertical,
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Dọc', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          ButtonSegment(
                            value: ReaderTapZoneInvert.both,
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Cả hai', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                        selected: {current.tapZoneInvert},
                        onSelectionChanged: (values) {
                          HapticFeedback.selectionClick();
                          notifier.setTapZoneInvert(values.first);
                        },
                      ),
                      const SizedBox(height: 16),

                      // ===== BỘ LỌC ẢNH BAN ĐÊM =====
                      Divider(color: divider, height: 24),
                      Row(
                        children: [
                          const Icon(
                            Icons.bedtime_outlined,
                            color: Colors.amber,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Bộ lọc ban đêm',
                            style: TextStyle(
                              color: onSurface,
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
                              activeColor: Colors.lightBlueAccent,
                              isSelected:
                                  current.dimLevel == 0.0 &&
                                  current.tintLevel == 0.0 &&
                                  !current.invertColors,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                ref
                                    .read(readerProvider.notifier)
                                    .setDimLevel(0.0);
                                ref
                                    .read(readerProvider.notifier)
                                    .setTintLevel(0.0);
                                ref
                                    .read(readerProvider.notifier)
                                    .setInvertColors(false);
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _EyeCarePresetBtn(
                              label: 'Ấm áp',
                              icon: Icons.wb_twilight,
                              activeColor: Colors.orangeAccent,
                              isSelected:
                                  current.tintLevel >= 0.2 &&
                                  current.dimLevel < 0.1 &&
                                  !current.invertColors,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                ref
                                    .read(readerProvider.notifier)
                                    .setDimLevel(0.0);
                                ref
                                    .read(readerProvider.notifier)
                                    .setTintLevel(0.25);
                                ref
                                    .read(readerProvider.notifier)
                                    .setInvertColors(false);
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _EyeCarePresetBtn(
                              label: 'Đảo màu',
                              icon: Icons.invert_colors,
                              activeColor: Colors.purpleAccent,
                              isSelected: current.invertColors,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                ref
                                    .read(readerProvider.notifier)
                                    .setInvertColors(!current.invertColors);
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _EyeCarePresetBtn(
                              label: 'Dịu mắt',
                              icon: Icons.nightlight_round,
                              activeColor: Colors.amberAccent,
                              isSelected:
                                  current.dimLevel >= 0.3 &&
                                  current.tintLevel >= 0.1 &&
                                  !current.invertColors,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                ref
                                    .read(readerProvider.notifier)
                                    .setDimLevel(0.35);
                                ref
                                    .read(readerProvider.notifier)
                                    .setTintLevel(0.15);
                                ref
                                    .read(readerProvider.notifier)
                                    .setInvertColors(false);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Thanh giảm sáng
                      Row(
                        children: [
                          Icon(
                            Icons.brightness_4,
                            color: onSurface.withValues(alpha: 0.6),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Giảm sáng',
                              style: TextStyle(
                                color: onSurface.withValues(alpha: 0.7),
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            '${(current.dimLevel * 100).round()}%',
                            style: TextStyle(
                              color: onSurface.withValues(alpha: 0.54),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2.5,
                          activeTrackColor: onSurface.withValues(alpha: 0.7),
                          inactiveTrackColor: divider,
                          thumbColor: onSurface,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 14,
                          ),
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
                          Icon(
                            Icons.filter_vintage,
                            color: primary,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Lọc ánh sáng xanh',
                              style: TextStyle(
                                color: onSurface.withValues(alpha: 0.7),
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            '${(current.tintLevel * 200).round()}%',
                            style: TextStyle(
                              color: onSurface.withValues(alpha: 0.54),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2.5,
                          activeTrackColor: primary,
                          inactiveTrackColor: divider,
                          thumbColor: primary,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 14,
                          ),
                        ),
                        child: Slider(
                          value: current.tintLevel,
                          min: 0.0,
                          max: 0.5,
                          onChanged: (v) =>
                              ref.read(readerProvider.notifier).setTintLevel(v),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Divider(color: divider),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primary,
                            side: BorderSide(
                              color: primary,
                              width: 0.8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          icon: const Icon(
                            Icons.report_problem_outlined,
                            size: 18,
                          ),
                          label: const Text(
                            'B\u00e1o l\u1ed7i ch\u01b0\u01a1ng / h\u00ecnh \u1ea3nh',
                            style: TextStyle(fontSize: 13),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            _showReportDialog(state);
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
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

    final screenWidth = MediaQuery.sizeOf(context).width;
    final itemWidth = (screenWidth - 62) / 4;
    final itemHeight = itemWidth / 0.68;
    final rowHeight = itemHeight + 10;
    final currentRow = state.currentPageIndex ~/ 4;
    final targetOffset = (currentRow * rowHeight - rowHeight).clamp(0.0, double.infinity);
    final scrollController = ScrollController(initialScrollOffset: targetOffset);

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final theme = Theme.of(context);
        final primary = theme.colorScheme.primary;
        final onPrimary = theme.colorScheme.onPrimary;
        final onSurface = theme.colorScheme.onSurface;
        final divider = theme.dividerColor;
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.78,
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
                              style: TextStyle(
                                color: onSurface,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Tổng cộng ${state.pages.length} trang • Chạm để nhảy trang',
                              style: TextStyle(
                                color: onSurface.withValues(alpha: 0.6),
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
                          color: primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: primary.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          'Trang ${state.currentPageIndex + 1}/${state.pages.length}',
                          style: TextStyle(
                            color: primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: Icon(Icons.close, color: onSurface.withValues(alpha: 0.7)),
                        tooltip: 'Đóng',
                        onPressed: () => Navigator.pop(context),
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: GridView.builder(
                      controller: scrollController,
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
                            color: theme.scaffoldBackgroundColor,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? primary
                                  : divider,
                              width: selected ? 2.5 : 1,
                            ),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: primary.withValues(
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
                                      color: primary,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Đang đọc',
                                      style: TextStyle(
                                        color: onPrimary,
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
                                            ? primary
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
        ),
      );
    },
  ).then((_) {
    scrollController.dispose();
  });
}

  /// Lưu ảnh của trang truyện hiện tại vào Thư viện máy (Pictures/MangaReader)
  Future<void> _saveCurrentPageImage(
    ReaderState state, {
    int? pageIndex,
  }) async {
    final targetIndex = pageIndex ?? _currentPageNotifier.value;
    if (state.pages.isEmpty ||
        targetIndex < 0 ||
        targetIndex >= state.pages.length) {
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
            content: Text(
              'Cần cấp quyền truy cập bộ nhớ để lưu ảnh vào Thư viện',
            ),
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
              const Icon(
                Icons.check_circle_rounded,
                color: Colors.greenAccent,
                size: 20,
              ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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
    final textController = TextEditingController(
      text: existingBookmark?.note ?? '',
    );

    if (!mounted) return;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor:
            Theme.of(dialogCtx).dialogTheme.backgroundColor ??
            Theme.of(dialogCtx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.edit_note_rounded, color: Colors.amber, size: 24),
            const SizedBox(width: 8),
            Text(
              'Ghi chú Bookmark (Trang ${state.currentPageIndex + 1})',
              style: const TextStyle(
                color: Colors.white,
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
                hintText:
                    'Ví dụ: Đoạn đánh nhau hay, manh mối cốt truyện, wallpaper đẹp...',
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
          if (existingBookmark?.note != null &&
              existingBookmark!.note!.isNotEmpty)
            TextButton(
              onPressed: () {
                textController.clear();
                Navigator.pop(dialogCtx, true);
              },
              child: const Text(
                'Xóa ghi chú',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text(
              'Lưu ghi chú',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
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
          final baseScale = _initialPhotoScale(
            state.imageFit,
            filePath: state.pages[pageIdx],
          );
          final effectiveInitialScale =
              (state.cropBorders && baseScale is PhotoViewComputedScale)
              ? baseScale * 1.04
              : (state.cropBorders && baseScale is num)
              ? baseScale * 1.04
              : baseScale;

          bool shouldRotate = false;
          if (state.rotateLandscapeImages) {
            final size = _getImageSize(state.pages[pageIdx]);
            if (size != null && size.width > size.height) {
              shouldRotate = true;
            }
          }

          if (shouldRotate) {
            Widget child = RotatedBox(
              quarterTurns: 1, // Xoay 90 độ
              child: Image.file(
                File(state.pages[pageIdx]),
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            );
            if (state.cropBorders) {
              child = ClipRect(
                child: Transform.scale(
                  scale: 1.04,
                  alignment: Alignment.center,
                  child: child,
                ),
              );
            }
            return PhotoViewGalleryPageOptions.customChild(
              child: child,
              initialScale: PhotoViewComputedScale.contained,
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 3,
              basePosition: _getZoomAlignment(state.zoomStart),
            );
          }

          return PhotoViewGalleryPageOptions(
            imageProvider: FileImage(File(state.pages[pageIdx])),
            initialScale: effectiveInitialScale,
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 3,
            basePosition: _getZoomAlignment(state.zoomStart),
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
              scale: 1.03, // Tỷ lệ an toàn cho manga scan trang đôi
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
          basePosition: _getZoomAlignment(state.zoomStart),
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
    final isRtl = state.direction == ReaderDirection.rtl;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isRtl
                ? Icons.keyboard_double_arrow_left
                : Icons.keyboard_double_arrow_right,
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
            Column(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: Colors.green,
                  size: 36,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Bạn đã đọc hết truyện!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Đây là chương cuối cùng của bộ truyện này.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Quay lại chi tiết truyện'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
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

        bool shouldRotate = false;
        Size? imageSize;
        if (state.rotateLandscapeImages) {
          imageSize = _getImageSize(state.pages[pageIndex]);
          if (imageSize != null && imageSize.width > imageSize.height) {
            shouldRotate = true;
          }
        }

        Widget imageWidget;
        if (shouldRotate && imageSize != null && imageSize.width > 0) {
          imageWidget = AspectRatio(
            aspectRatio: imageSize.height / imageSize.width,
            child: RotatedBox(
              quarterTurns: 1,
              child: Image.file(
                File(state.pages[pageIndex]),
                fit: BoxFit.contain,
                gaplessPlayback: true,
                filterQuality: FilterQuality.none,
              ),
            ),
          );
        } else {
          imageWidget = Image.file(
            File(state.pages[pageIndex]),
            fit: _verticalImageFit(state.imageFit),
            width: double.infinity,
            alignment: Alignment.topCenter,
            gaplessPlayback: true, // Khử flash trắng khi rebuild item
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
                    const Icon(
                      Icons.broken_image_rounded,
                      size: 36,
                      color: Colors.white38,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Không thể tải trang ${pageIndex + 1}',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (state.cropBorders) {
          // Chỉ scale nhẹ theo chiều ngang (X: 1.03) để khử lề quét scan 2 bên,
          // TUYỆT ĐỐI GIỮ NGUYÊN 100% CHIỀU DỌC (Y: 1.0) để không làm đứt gãy mối nối các trang Webtoon!
          imageWidget = ClipRect(
            child: Transform(
              transform: Matrix4.diagonal3Values(1.03, 1.0, 1.0),
              alignment: Alignment.center,
              child: imageWidget,
            ),
          );
        }

        if (state.isGapMode) {
          imageWidget = Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: imageWidget,
          );
        }

        return RepaintBoundary(
          child: Container(
            key: key,
            child: state.isGapMode
                ? imageWidget
                : Transform.translate(
                    offset: const Offset(
                      0,
                      -0.5,
                    ), // Khử hở viền 1px cho continuous scroll
                    child: imageWidget,
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
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          // Biểu tượng mũi tên lên
                          Icon(
                            Icons.arrow_upward,
                            color: Theme.of(context).colorScheme.primary.withValues(
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
                Text(
                  'Giữ để đọc chương trước...',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
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
                Icon(
                  Icons.first_page,
                  color: Theme.of(context).colorScheme.primary,
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
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          // Biểu tượng ở giữa
                          Icon(
                            Icons.arrow_downward,
                            color: Theme.of(context).colorScheme.primary.withValues(
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
                Text(
                  'Giữ để đọc chương tiếp...',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
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
  final Function(String chapterId, String? mangaId, {int? page})
  onNavigateChapter;
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
  ConsumerState<_ReaderDrawerContent> createState() =>
      _ReaderDrawerContentState();
}

class _ReaderDrawerContentState extends ConsumerState<_ReaderDrawerContent>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _chapterSearchController =
      TextEditingController();
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
      final reversed = prefs.getBool('manga_sort_reversed_$mangaId') ?? false;
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
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'HOÀN TÁC',
          textColor: Colors.amber,
          onPressed: () async {
            HapticFeedback.lightImpact();
            await widget.notifier.restoreBookmark(bookmark);
            await _loadBookmarks();
          },
        ),
      ),
    );
  }

  Future<void> _editBookmarkNote(ReaderBookmark bookmark) async {
    HapticFeedback.lightImpact();
    final textController = TextEditingController(text: bookmark.note ?? '');
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor:
            Theme.of(dialogCtx).dialogTheme.backgroundColor ??
            Theme.of(dialogCtx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.edit_note_rounded, color: Colors.amber, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Ghi chú (Trang ${bookmark.pageIndex + 1})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
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
              child: const Text(
                'Xóa ghi chú',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text(
              'Lưu',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
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
    final normalizedSearch = CatalogCacheService.instance.normalize(
      _chapterSearchQuery,
    );
    final rawChapters = state.chapters.where((c) => seen.add(c.id)).where((c) {
      if (normalizedSearch.isEmpty) return true;
      final normTitle = CatalogCacheService.instance.normalize(c.title);
      return normTitle.contains(normalizedSearch);
    }).toList();
    final filteredChapters = _isSortReversed
        ? rawChapters.reversed.toList()
        : rawChapters;

    // Auto-scroll to current chapter
    if (!_hasAutoScrolled && currentChapter != null) {
      final selectedIndex = filteredChapters.indexWhere(
        (c) => c.id == currentChapter.id,
      );
      if (selectedIndex > 0) {
        _hasAutoScrolled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_chapterScrollController.hasClients) {
            final targetOffset = (selectedIndex * 56.0) - 100.0;
            _chapterScrollController.jumpTo(
              targetOffset.clamp(
                0.0,
                _chapterScrollController.position.maxScrollExtent,
              ),
            );
          }
        });
      }
    }

    // Filter bookmarks
    final currentChapterId = currentChapter?.id;
    final displayBookmarks =
        _filterOnlyCurrentChapter && currentChapterId != null
        ? _bookmarks.where((b) => b.chapterId == currentChapterId).toList()
        : _bookmarks;

    final currentChapterBookmarkCount = currentChapterId == null
        ? 0
        : _bookmarks.where((b) => b.chapterId == currentChapterId).length;

    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final onPrimary = theme.colorScheme.onPrimary;
    final onSurface = theme.colorScheme.onSurface;
    final divider = theme.dividerColor;

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
                border: Border(
                  bottom: BorderSide(color: divider, width: 1),
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
                              style: TextStyle(
                                color: onSurface,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              state.currentChapter?.title ?? '',
                              style: TextStyle(
                                color: primary,
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
                        icon: Icon(
                          Icons.close,
                          color: onSurface.withValues(alpha: 0.7),
                          size: 20,
                        ),
                        tooltip: 'Đóng',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TabBar(
                    controller: _tabController,
                    indicatorColor: primary,
                    indicatorWeight: 3,
                    labelColor: primary,
                    unselectedLabelColor: onSurface.withValues(alpha: 0.6),
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.format_list_numbered_rounded,
                              size: 16,
                            ),
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
                                style: TextStyle(
                                  color: onSurface,
                                  fontSize: 13,
                                ),
                                textInputAction: TextInputAction.search,
                                decoration: InputDecoration(
                                  hintText: 'Tìm số chương...',
                                  hintStyle: TextStyle(
                                    color: onSurface.withValues(alpha: 0.38),
                                    fontSize: 12,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.search,
                                    color: onSurface.withValues(alpha: 0.54),
                                    size: 16,
                                  ),
                                  suffixIcon: _chapterSearchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: Icon(
                                            Icons.clear,
                                            color: onSurface.withValues(alpha: 0.54),
                                            size: 14,
                                          ),
                                          onPressed: () {
                                            _chapterSearchController.clear();
                                            setState(
                                              () => _chapterSearchQuery = '',
                                            );
                                          },
                                        )
                                      : null,
                                  filled: true,
                                  fillColor: onSurface.withValues(
                                    alpha: 0.08,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                onChanged: (val) {
                                  if (_searchDebounce?.isActive ?? false) {
                                    _searchDebounce!.cancel();
                                  }
                                  _searchDebounce = Timer(
                                    const Duration(milliseconds: 150),
                                    () {
                                      if (mounted) {
                                        setState(
                                          () => _chapterSearchQuery = val,
                                        );
                                      }
                                    },
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              icon: Icon(
                                Icons.swap_vert_rounded,
                                color: _isSortReversed
                                    ? primary
                                    : onSurface.withValues(alpha: 0.7),
                                size: 22,
                              ),
                              tooltip: _isSortReversed
                                  ? 'Mới nhất trước'
                                  : 'Cũ nhất trước',
                              onPressed: () async {
                                HapticFeedback.selectionClick();
                                setState(
                                  () => _isSortReversed = !_isSortReversed,
                                );
                                if (widget.state.mangaId != null &&
                                    widget.state.mangaId!.isNotEmpty) {
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  await prefs.setBool(
                                    'manga_sort_reversed_${widget.state.mangaId}',
                                    _isSortReversed,
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      // Chapter ListView
                      Expanded(
                        child: filteredChapters.isEmpty
                            ? Center(
                                child: Text(
                                  'Không tìm thấy chương nào',
                                  style: TextStyle(
                                    color: onSurface.withValues(alpha: 0.54),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                controller: _chapterScrollController,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                itemCount: filteredChapters.length,
                                itemBuilder: (context, index) {
                                  final chapter = filteredChapters[index];
                                  final isCurrent =
                                      chapter.id == currentChapter?.id;
                                  final isRead = _readChapterIds.contains(
                                    chapter.id,
                                  );

                                  return Container(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isCurrent
                                          ? primary.withValues(
                                              alpha: 0.14,
                                            )
                                          : onSurface.withValues(
                                              alpha: 0.04,
                                            ),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isCurrent
                                            ? primary.withValues(
                                                alpha: 0.7,
                                              )
                                            : divider,
                                        width: isCurrent ? 1.5 : 1,
                                      ),
                                    ),
                                    child: ListTile(
                                      dense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 0,
                                          ),
                                      leading: Icon(
                                        isCurrent
                                            ? Icons.play_circle_filled_rounded
                                            : isRead
                                            ? Icons.check_circle_rounded
                                            : Icons.radio_button_unchecked,
                                        color: isCurrent
                                            ? primary
                                            : isRead
                                            ? Colors.greenAccent
                                            : onSurface.withValues(alpha: 0.24),
                                        size: 20,
                                      ),
                                      title: Text(
                                        chapter.title,
                                        style: TextStyle(
                                          color: isCurrent
                                              ? primary
                                              : isRead
                                              ? onSurface.withValues(alpha: 0.4)
                                              : onSurface,
                                          fontWeight: isCurrent
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          fontSize: 13,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: isCurrent
                                          ? Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: primary,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                'Đang đọc',
                                                style: TextStyle(
                                                  color: onPrimary,
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
                                          widget.onNavigateChapter(
                                            chapter.id,
                                            widget.state.mangaId,
                                          );
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
                              label: Text(
                                'Tất cả (${_bookmarks.length})',
                                style: const TextStyle(fontSize: 11.5),
                              ),
                              selected: !_filterOnlyCurrentChapter,
                              selectedColor: primary,
                              labelStyle: TextStyle(
                                color: !_filterOnlyCurrentChapter
                                    ? onPrimary
                                    : onSurface.withValues(alpha: 0.7),
                                fontWeight: !_filterOnlyCurrentChapter
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              backgroundColor: onSurface.withValues(
                                alpha: 0.08,
                              ),
                              onSelected: (val) {
                                if (val) {
                                  HapticFeedback.selectionClick();
                                  setState(
                                    () => _filterOnlyCurrentChapter = false,
                                  );
                                }
                              },
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: Text(
                                'Chương này ($currentChapterBookmarkCount)',
                                style: const TextStyle(fontSize: 11.5),
                              ),
                              selected: _filterOnlyCurrentChapter,
                              selectedColor: primary,
                              labelStyle: TextStyle(
                                color: _filterOnlyCurrentChapter
                                    ? onPrimary
                                    : onSurface.withValues(alpha: 0.7),
                                fontWeight: _filterOnlyCurrentChapter
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              backgroundColor: onSurface.withValues(
                                alpha: 0.08,
                              ),
                              onSelected: (val) {
                                if (val) {
                                  HapticFeedback.selectionClick();
                                  setState(
                                    () => _filterOnlyCurrentChapter = true,
                                  );
                                }
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
                                        color: onSurface.withValues(
                                          alpha: 0.25,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        _filterOnlyCurrentChapter
                                            ? 'Chưa có bookmark nào trong chương này'
                                            : 'Chưa có trang đánh dấu nào',
                                        style: TextStyle(
                                          color: onSurface.withValues(alpha: 0.7),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Chạm vào biểu tượng Bookmark trên thanh điều khiển khi đọc để lưu lại trang yêu thích!',
                                        style: TextStyle(
                                          color: onSurface.withValues(alpha: 0.38),
                                          fontSize: 12,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                itemCount: displayBookmarks.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final bookmark = displayBookmarks[index];
                                  final chapterTitle = _getChapterTitle(
                                    bookmark.chapterId,
                                  );
                                  final isSameChapter =
                                      bookmark.chapterId == currentChapter?.id;

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
                                        color: onSurface.withValues(
                                          alpha: 0.05,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isSameChapter
                                              ? Colors.amber.withValues(
                                                  alpha: 0.4,
                                                )
                                              : divider,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.amber
                                                      .withValues(alpha: 0.2),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: Colors.amber
                                                        .withValues(alpha: 0.5),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                      Icons.bookmark_rounded,
                                                      color: Colors.amber,
                                                      size: 12,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Trang ${bookmark.pageIndex + 1}',
                                                      style: const TextStyle(
                                                        color: Colors.amber,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  chapterTitle,
                                                  style: TextStyle(
                                                    color: onSurface,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (bookmark.note != null &&
                                              bookmark.note!.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Container(
                                              width: double.infinity,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.amber.withValues(
                                                  alpha: 0.08,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: const Border(
                                                  left: BorderSide(
                                                    color: Colors.amber,
                                                    width: 3,
                                                  ),
                                                ),
                                              ),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  const Icon(
                                                    Icons.format_quote_rounded,
                                                    color: Colors.amber,
                                                    size: 14,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      bookmark.note!,
                                                      style: TextStyle(
                                                        color: onSurface.withValues(alpha: 0.7),
                                                        fontSize: 12,
                                                        fontStyle:
                                                            FontStyle.italic,
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
                                                _formatDateTime(
                                                  bookmark.updatedAt,
                                                ),
                                                style: TextStyle(
                                                  color: onSurface.withValues(alpha: 0.38),
                                                  fontSize: 11,
                                                ),
                                              ),
                                              const Spacer(),
                                              IconButton(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(
                                                      minWidth: 34,
                                                      minHeight: 34,
                                                    ),
                                                icon: const Icon(
                                                  Icons.edit_note_rounded,
                                                  color: Colors.amberAccent,
                                                  size: 20,
                                                ),
                                                tooltip: 'Sửa ghi chú',
                                                onPressed: () =>
                                                    _editBookmarkNote(bookmark),
                                              ),
                                              const SizedBox(width: 8),
                                              IconButton(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(
                                                      minWidth: 34,
                                                      minHeight: 34,
                                                    ),
                                                icon: const Icon(
                                                  Icons.delete_outline_rounded,
                                                  color: Colors.redAccent,
                                                  size: 20,
                                                ),
                                                tooltip: 'Xóa bookmark',
                                                onPressed: () =>
                                                    _deleteBookmark(bookmark),
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
                border: Border(
                  top: BorderSide(color: divider, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: onSurface,
                        side: BorderSide(color: divider),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: Icon(
                        state.readingMode == ReadingMode.horizontal
                            ? Icons.swap_vert
                            : Icons.swap_horiz,
                        size: 16,
                      ),
                      label: Text(
                        state.readingMode == ReadingMode.horizontal
                            ? 'Đọc Dọc'
                            : 'Đọc Ngang',
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
                        foregroundColor: onSurface.withValues(alpha: 0.7),
                        side: BorderSide(color: divider),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text(
                        'Tải lại',
                        style: TextStyle(fontSize: 12),
                      ),
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
        final normalizedSearch = CatalogCacheService.instance.normalize(
          _searchQuery,
        );
        final rawChapters = widget.chapters.where((c) => seen.add(c.id)).where((
          c,
        ) {
          if (normalizedSearch.isEmpty) return true;
          final normTitle = CatalogCacheService.instance.normalize(c.title);
          return normTitle.contains(normalizedSearch);
        }).toList();
        final filteredChapters = _isSortReversed
            ? rawChapters.reversed.toList()
            : rawChapters;

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
                  targetOffset.clamp(
                    0.0,
                    scrollController.position.maxScrollExtent,
                  ),
                );
              }
            });
          }
        }

        final theme = Theme.of(context);
        final primary = theme.colorScheme.primary;
        final onSurface = theme.colorScheme.onSurface;
        final divider = theme.dividerColor;

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
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: divider, width: 1),
                  ),
                ),
                child: Consumer(
                  builder: (context, ref, child) {
                    final state = ref.watch(readerProvider);
                    final notifier = ref.read(readerProvider.notifier);

                    return Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.close, color: onSurface),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Danh Sách Chương',
                                style: TextStyle(
                                  color: onSurface,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${filteredChapters.length} chương',
                                style: TextStyle(
                                  color: onSurface.withValues(alpha: 0.54),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Nút đảo chiều thứ tự chương
                        IconButton(
                          icon: Icon(
                            Icons.swap_vert_rounded,
                            color: _isSortReversed
                                ? primary
                                : onSurface,
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
                            color: state.isFollowed ? Colors.red : onSurface,
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
                          icon: Icon(
                            Icons.unfold_more_rounded,
                            color: onSurface,
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
                  style: TextStyle(color: onSurface, fontSize: 13),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Tìm nhanh số chương (vd: 12, Chapter 50)...',
                    hintStyle: TextStyle(
                      color: onSurface.withValues(alpha: 0.38),
                      fontSize: 12,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: onSurface.withValues(alpha: 0.54),
                      size: 18,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.clear,
                              color: onSurface.withValues(alpha: 0.54),
                              size: 16,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: onSurface.withValues(alpha: 0.08),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) {
                    if (_searchDebounce?.isActive ?? false) {
                      _searchDebounce!.cancel();
                    }
                    _searchDebounce = Timer(
                      const Duration(milliseconds: 150),
                      () {
                        if (mounted) {
                          setState(() => _searchQuery = val);
                        }
                      },
                    );
                  },
                ),
              ),

              // Danh sách
              Expanded(
                child: filteredChapters.isEmpty
                    ? Center(
                        child: Text(
                          'Không tìm thấy chương phù hợp',
                          style: TextStyle(color: onSurface.withValues(alpha: 0.38)),
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
                                  ? onSurface.withValues(alpha: 0.08)
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
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                  Expanded(
                                    child: Text(
                                      chapter.title,
                                      style: TextStyle(
                                        color: isSelected
                                            ? primary
                                            : isRead
                                            ? onSurface.withValues(alpha: 0.38)
                                            : onSurface,
                                        fontWeight: isSelected || !isRead
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    Container(
                                      margin: const EdgeInsets.only(left: 8),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: primary.withValues(
                                          alpha: 0.2,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: primary.withValues(
                                            alpha: 0.6,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.play_arrow_rounded,
                                            size: 13,
                                            color: primary,
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            'Đang đọc',
                                            style: TextStyle(
                                              color: primary,
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    Text(
                                      date,
                                      style: TextStyle(
                                        color: isRead
                                            ? onSurface.withValues(alpha: 0.24)
                                            : onSurface.withValues(alpha: 0.6),
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

class _ReaderSheetSectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _ReaderSheetSectionHeader(this.title, this.icon);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final divider = theme.dividerColor;
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: primary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: divider, height: 1)),
        ],
      ),
    );
  }
}

class _EyeCarePresetBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final Color activeColor;

  const _EyeCarePresetBtn({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.activeColor = Colors.orangeAccent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final divider = theme.dividerColor;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.2)
              : onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor : divider,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? activeColor : onSurface.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? activeColor : onSurface.withValues(alpha: 0.7),
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

  const _MiniReaderHud({required this.currentPage, required this.totalPages});

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
    _scheduleNextMinute();
  }

  void _scheduleNextMinute() {
    final now = DateTime.now();
    final msUntilNextMinute = 60000 - (now.second * 1000 + now.millisecond);
    _timer = Timer(Duration(milliseconds: msUntilNextMinute), () {
      if (!mounted) return;
      _updateTime();
      _scheduleNextMinute();
    });
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
            const Icon(
              Icons.access_time_rounded,
              size: 11.5,
              color: Colors.white70,
            ),
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
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
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

class _TapZoneDiagram extends StatelessWidget {
  final ReaderTapZone tapZone;
  final bool isVertical;
  final bool isRtl;
  final ReaderTapZoneInvert tapZoneInvert;

  const _TapZoneDiagram({
    required this.tapZone,
    required this.isVertical,
    this.isRtl = false,
    this.tapZoneInvert = ReaderTapZoneInvert.none,
  });

  static const _forwardColorBase = Color(0xFF4CAF50);
  static const _backwardColorBase = Color(0xFFFF9800);
  static const _menuColorBase = Color(0xFF2196F3);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Sơ đồ chính
        Container(
          height: 160,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _buildDiagram(),
          ),
        ),
        const SizedBox(height: 8),
        // Legend chú giải màu
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendItem(
              color: _forwardColorBase,
              label: isVertical ? 'Cuộn xuống' : 'Trang sau',
              icon: isVertical
                  ? Icons.keyboard_arrow_down
                  : Icons.arrow_forward_ios,
            ),
            const SizedBox(width: 16),
            _LegendItem(
              color: _backwardColorBase,
              label: isVertical ? 'Cuộn lên' : 'Trang trước',
              icon: isVertical ? Icons.keyboard_arrow_up : Icons.arrow_back_ios,
            ),
            const SizedBox(width: 16),
            const _LegendItem(
              color: _menuColorBase,
              label: 'Mở menu',
              icon: Icons.menu_rounded,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildZone({
    required Color baseColor,
    required IconData icon,
    required String label,
    String? sublabel,
    double iconSize = 18,
    double labelSize = 9.5,
  }) {
    return Container(
      color: baseColor.withValues(alpha: 0.22),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: baseColor, size: iconSize),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: baseColor.withValues(alpha: 0.95),
                  fontSize: labelSize,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              if (sublabel != null) ...[
                const SizedBox(height: 1),
                Text(
                  sublabel,
                  style: const TextStyle(color: Colors.white54, fontSize: 8),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDiagram() {
    final bool invertH =
        tapZoneInvert == ReaderTapZoneInvert.horizontal ||
        tapZoneInvert == ReaderTapZoneInvert.both;
    final bool invertV =
        tapZoneInvert == ReaderTapZoneInvert.vertical ||
        tapZoneInvert == ReaderTapZoneInvert.both;

    IconData fwdIconRaw = isVertical
        ? Icons.keyboard_double_arrow_down
        : Icons.arrow_forward_ios_rounded;
    IconData bwdIconRaw = isVertical
        ? Icons.keyboard_double_arrow_up
        : Icons.arrow_back_ios_rounded;
    String fwdLabelRaw = isVertical ? 'Cuộn xuống' : 'Trang sau';
    String bwdLabelRaw = isVertical ? 'Cuộn lên' : 'Trang trước';

    // Đảo ngược dọc → hoán đổi tiến/lùi theo chiều Y
    final IconData forwardIcon = invertV ? bwdIconRaw : fwdIconRaw;
    final IconData backwardIcon = invertV ? fwdIconRaw : bwdIconRaw;
    final String forwardLabel = invertV ? bwdLabelRaw : fwdLabelRaw;
    final String backwardLabel = invertV ? fwdLabelRaw : bwdLabelRaw;

    // Chỉ vuốt
    if (tapZone == ReaderTapZone.swipeOnly) {
      return _buildZone(
        baseColor: _menuColorBase,
        icon: Icons.touch_app_rounded,
        label: 'Chạm = Mở menu',
        sublabel: 'Vuốt để lật trang / cuộn',
        iconSize: 22,
        labelSize: 11,
      );
    }

    // Kiểu Kindle (chia nửa màn hình)
    if (tapZone == ReaderTapZone.kindle) {
      final bool effectiveRtl = invertH ? !isRtl : isRtl;
      final leftColor = effectiveRtl ? _forwardColorBase : _backwardColorBase;
      final rightColor = effectiveRtl ? _backwardColorBase : _forwardColorBase;
      final leftLbl = effectiveRtl ? forwardLabel : backwardLabel;
      final rightLbl = effectiveRtl ? backwardLabel : forwardLabel;
      final leftIco = effectiveRtl ? forwardIcon : backwardIcon;
      final rightIco = effectiveRtl ? backwardIcon : forwardIcon;

      return Row(
        children: [
          Expanded(
            flex: 30,
            child: _buildZone(
              baseColor: leftColor,
              icon: leftIco,
              label: leftLbl,
              sublabel: 'Chạm nửa TRÁI',
            ),
          ),
          Expanded(
            flex: 40,
            child: _buildZone(
              baseColor: _menuColorBase,
              icon: Icons.menu_rounded,
              label: 'Menu',
              sublabel: 'Chạm chính GIỮA\n(40% giữa)',
            ),
          ),
          Expanded(
            flex: 30,
            child: _buildZone(
              baseColor: rightColor,
              icon: rightIco,
              label: rightLbl,
              sublabel: 'Chạm nửa PHẢI',
            ),
          ),
        ],
      );
    }

    // 1 Tay (L-shape / One-Handed)
    if (tapZone == ReaderTapZone.oneHanded) {
      return Column(
        children: [
          // Dải đỉnh màn hình: 18% chiều cao -> Lùi / Cuộn lên
          Expanded(
            flex: 18,
            child: _buildZone(
              baseColor: _backwardColorBase,
              icon: backwardIcon,
              label: backwardLabel,
              sublabel: 'Chạm đỉnh (18%)',
              iconSize: 14,
              labelSize: 9,
            ),
          ),
          // Vùng còn lại: 82% chiều cao -> Toàn bộ vùng ngón cái với hộp Menu ở trung tâm
          Expanded(
            flex: 82,
            child: Stack(
              children: [
                // Nền xanh toàn bộ (Cuộn xuống / Trang sau - Thuận ngón cái)
                Positioned.fill(
                  child: Container(
                    color: _forwardColorBase.withValues(alpha: 0.22),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(forwardIcon, color: _forwardColorBase, size: 20),
                            const SizedBox(height: 2),
                            Text(
                              forwardLabel,
                              style: TextStyle(
                                color: _forwardColorBase.withValues(alpha: 0.95),
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 1),
                            const Text(
                              'Nửa dưới màn hình (Vừa tầm ngón cái)',
                              style: TextStyle(color: Colors.white54, fontSize: 8),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Hộp Mở menu ở trung tâm (Chạm giữa màn hình)
                Align(
                  alignment: const Alignment(0, -0.25),
                  child: FractionallySizedBox(
                    widthFactor: 0.52,
                    heightFactor: 0.45,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _menuColorBase.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _menuColorBase.withValues(alpha: 0.7),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: _buildZone(
                          baseColor: _menuColorBase,
                          icon: Icons.menu_rounded,
                          label: 'Mở menu',
                          sublabel: 'Chạm giữa màn hình',
                          iconSize: 16,
                          labelSize: 9.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Chế độ DỌC
    if (isVertical) {
      if (tapZone == ReaderTapZone.leftHanded) {
        // Thuận tay trái đọc dọc: trái=tiến, phải=lùi (có thể đảo ngang)
        final leftColor = invertH ? _backwardColorBase : _forwardColorBase;
        final rightColor = invertH ? _forwardColorBase : _backwardColorBase;
        final leftLbl = invertH ? backwardLabel : forwardLabel;
        final rightLbl = invertH ? forwardLabel : backwardLabel;
        final leftIco = invertH ? backwardIcon : forwardIcon;
        final rightIco = invertH ? forwardIcon : backwardIcon;
        return Row(
          children: [
            Expanded(
              flex: 40,
              child: _buildZone(
                baseColor: leftColor,
                icon: leftIco,
                label: leftLbl,
                sublabel: 'Chạm mép TRÁI',
              ),
            ),
            Expanded(
              flex: 20,
              child: _buildZone(
                baseColor: _menuColorBase,
                icon: Icons.menu_rounded,
                label: 'Menu',
                sublabel: 'Giữa',
              ),
            ),
            Expanded(
              flex: 40,
              child: _buildZone(
                baseColor: rightColor,
                icon: rightIco,
                label: rightLbl,
                sublabel: 'Chạm mép PHẢI',
              ),
            ),
          ],
        );
      }
      // default3Cols dọc: trên=lùi, giữa=menu, dưới=tiến
      final topColor = _backwardColorBase;
      final botColor = _forwardColorBase;
      final topLabel = backwardLabel;
      final botLabel = forwardLabel;
      final topIcon = backwardIcon;
      final botIcon = forwardIcon;
      return Column(
        children: [
          Expanded(
            flex: 35,
            child: _buildZone(
              baseColor: topColor,
              icon: topIcon,
              label: topLabel,
              sublabel: 'Chạm 1/3 TRÊN',
            ),
          ),
          Expanded(
            flex: 30,
            child: _buildZone(
              baseColor: _menuColorBase,
              icon: Icons.menu_rounded,
              label: 'Mở menu',
              sublabel: 'Chạm vùng GIỮA',
            ),
          ),
          Expanded(
            flex: 35,
            child: _buildZone(
              baseColor: botColor,
              icon: botIcon,
              label: botLabel,
              sublabel: 'Chạm 1/3 DƯỚI',
            ),
          ),
        ],
      );
    }

    // Chế độ NGANG – Tay trái
    if (tapZone == ReaderTapZone.leftHanded) {
      final leftColor = invertH ? _backwardColorBase : _forwardColorBase;
      final rightColor = invertH ? _forwardColorBase : _backwardColorBase;
      final leftLbl = invertH ? backwardLabel : forwardLabel;
      final rightLbl = invertH ? forwardLabel : backwardLabel;
      final leftIco = invertH ? backwardIcon : forwardIcon;
      final rightIco = invertH ? forwardIcon : backwardIcon;
      return Row(
        children: [
          Expanded(
            flex: 40,
            child: _buildZone(
              baseColor: leftColor,
              icon: leftIco,
              label: leftLbl,
              sublabel: 'Chạm mép TRÁI\n(ngón cái tay trái)',
            ),
          ),
          Expanded(
            flex: 20,
            child: _buildZone(
              baseColor: _menuColorBase,
              icon: Icons.menu_rounded,
              label: 'Menu',
              sublabel: 'Giữa',
            ),
          ),
          Expanded(
            flex: 40,
            child: _buildZone(
              baseColor: rightColor,
              icon: rightIco,
              label: rightLbl,
              sublabel: 'Chạm mép PHẢI',
            ),
          ),
        ],
      );
    }

    // default3Cols ngang (LTR / RTL) + hỗ trợ invertH
    final bool effectiveRtl = invertH ? !isRtl : isRtl;
    final leftLabel = effectiveRtl ? forwardLabel : backwardLabel;
    final leftIcon = effectiveRtl ? forwardIcon : backwardIcon;
    final leftColor = effectiveRtl ? _forwardColorBase : _backwardColorBase;
    final rightLabel = effectiveRtl ? backwardLabel : forwardLabel;
    final rightIcon = effectiveRtl ? backwardIcon : forwardIcon;
    final rightColor = effectiveRtl ? _backwardColorBase : _forwardColorBase;

    return Row(
      children: [
        Expanded(
          flex: 35,
          child: _buildZone(
            baseColor: leftColor,
            icon: leftIcon,
            label: leftLabel,
            sublabel: 'Chạm mép TRÁI',
          ),
        ),
        Expanded(
          flex: 30,
          child: _buildZone(
            baseColor: _menuColorBase,
            icon: Icons.menu_rounded,
            label: 'Mở menu',
            sublabel: 'Chạm vùng GIỮA',
          ),
        ),
        Expanded(
          flex: 35,
          child: _buildZone(
            baseColor: rightColor,
            icon: rightIcon,
            label: rightLabel,
            sublabel: 'Chạm mép PHẢI',
          ),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final IconData icon;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.6), width: 1),
          ),
          child: Icon(icon, color: color, size: 10),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.85),
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
