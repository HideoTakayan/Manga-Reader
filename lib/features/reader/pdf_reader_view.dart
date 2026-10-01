import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'reader_provider.dart';

class _AsyncLock {
  Future<void>? _last;
  Future<T> synchronized<T>(Future<T> Function() action) async {
    final previous = _last;
    final completer = Completer<void>();
    _last = completer.future;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {}
    }
    try {
      return await action();
    } finally {
      completer.complete();
    }
  }
}

class _LruPageCache {
  final int maxCapacity;
  final LinkedHashMap<int, PdfPageImage> _cache = LinkedHashMap();

  _LruPageCache({this.maxCapacity = 16});

  PdfPageImage? get(int key) {
    final value = _cache.remove(key);
    if (value != null) {
      _cache[key] = value;
    }
    return value;
  }

  void put(int key, PdfPageImage value) {
    if (_cache.containsKey(key)) {
      _cache.remove(key);
    } else if (_cache.length >= maxCapacity) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = value;
  }

  bool containsKey(int key) => _cache.containsKey(key);
  void clear() => _cache.clear();
}

class PdfReaderView extends StatefulWidget {
  final String pdfPath;
  final int initialPage;
  final ReadingMode readingMode;
  final ReaderImageFit imageFit;
  final ReaderZoomStart zoomStart;
  final ReaderDirection direction;
  final Color backgroundColor;
  final bool cropBorders;
  final Axis? scrollDirection;
  final ValueChanged<int>? onPageChanged;
  final VoidCallback? onToggleControls;
  final ValueChanged<TapUpDetails>? onTapUp;
  final ValueChanged<int>? onDocumentLoaded;
  final VoidCallback? onReloadRequested;
  final VoidCallback? onUserScrollStart;
  final bool rotateLandscapeImages;
  final double? initialScrollOffset;
  final void Function(double offset, int pageIndex)? onScrollProgress;

  const PdfReaderView({
    super.key,
    required this.pdfPath,
    this.initialPage = 0,
    this.initialScrollOffset,
    this.readingMode = ReadingMode.vertical,
    this.imageFit = ReaderImageFit.width,
    this.zoomStart = ReaderZoomStart.center,
    this.direction = ReaderDirection.ltr,
    this.backgroundColor = Colors.black,
    this.cropBorders = false,
    this.scrollDirection,
    this.onPageChanged,
    this.onScrollProgress,
    this.onToggleControls,
    this.onTapUp,
    this.onDocumentLoaded,
    this.onReloadRequested,
    this.onUserScrollStart,
    this.rotateLandscapeImages = false,
  });

  @override
  PdfReaderViewState createState() => PdfReaderViewState();
}

class PdfReaderViewState extends State<PdfReaderView> {
  final ScrollController _scrollController = ScrollController();
  PdfController? _pdfController;
  bool _isLoading = true;
  String? _errorMessage;
  String? _technicalDetails;
  bool _showTechnicalDetails = false;
  PdfDocument? _document;
  int _lastReportedPage = -1;
  double _defaultAspectRatio = 0.707; // Default A4/manga ratio fallback
  final Map<int, double> _pageAspectRatios = {};
  final Map<int, double> _pageNativeWidths = {};
  final Map<int, double> _pageNativeHeights = {};
  final _LruPageCache _lruCache = _LruPageCache(maxCapacity: 16);
  final Map<int, Future<PdfPageImage>> _inFlightRenders = {};
  final _AsyncLock _renderLock = _AsyncLock();
  Timer? _prefetchDebounceTimer;
  double _lastEvaluatedOffset = -1;

  bool get isHorizontal =>
      widget.readingMode == ReadingMode.horizontal ||
      widget.scrollDirection == Axis.horizontal;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onVerticalScroll);
    _initPdf();
  }

  double _calculateVerticalPageHeight(
    int index,
    double screenWidth,
    double screenHeight,
  ) {
    final rawRatio = _pageAspectRatios[index] ?? _defaultAspectRatio;
    final ratio = (rawRatio > 0 && !rawRatio.isNaN && !rawRatio.isInfinite)
        ? rawRatio
        : _defaultAspectRatio;
    final shouldRotate = widget.rotateLandscapeImages && ratio > 1.05;
    final effectiveRatio = shouldRotate ? (1.0 / ratio) : ratio;

    switch (widget.imageFit) {
      case ReaderImageFit.width:
        return screenWidth / effectiveRatio;

      case ReaderImageFit.height:
        return screenHeight > 0 ? screenHeight : (screenWidth / effectiveRatio);

      case ReaderImageFit.screen:
        final wBasedHeight = screenWidth / effectiveRatio;
        if (screenHeight > 0 && wBasedHeight > screenHeight) {
          return screenHeight;
        }
        return wBasedHeight;

      case ReaderImageFit.original:
        final nativeW = _pageNativeWidths[index];
        final nativeH = _pageNativeHeights[index];
        if (nativeH != null && nativeH > 0) {
          return shouldRotate ? (nativeW ?? nativeH) : nativeH;
        }
        return screenWidth / effectiveRatio;

      case ReaderImageFit.smart:
        if (effectiveRatio > 1.15 && screenHeight > 0) {
          final wBasedHeight = screenWidth / effectiveRatio;
          if (wBasedHeight > screenHeight) {
            return screenHeight;
          }
          return wBasedHeight;
        }
        return screenWidth / effectiveRatio;
    }
  }

  void _onVerticalScroll() {
    if (!_scrollController.hasClients || _document == null) return;
    final offset = _scrollController.offset;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final pageCount = _document!.pagesCount;
    if (pageCount <= 1 || maxScroll <= 0) return;

    // Throttle micro-scroll calculations to save UI thread cycles
    final delta = (offset - _lastEvaluatedOffset).abs();
    if (delta < 20.0 && offset > 0 && offset < maxScroll) return;
    _lastEvaluatedOffset = offset;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final isGap = widget.readingMode == ReadingMode.verticalGap;
    final gap = isGap ? 16.0 : 0.0;

    double accumulated = 0;
    int estimatedPage = 0;
    for (int i = 0; i < pageCount; i++) {
      final pageH = _calculateVerticalPageHeight(i, screenWidth, screenHeight);
      final h = pageH + gap;
      if (offset < accumulated + (h * 0.5)) {
        estimatedPage = i;
        break;
      }
      accumulated += h;
      if (i == pageCount - 1) estimatedPage = i;
    }

    if (_lastReportedPage != estimatedPage) {
      _lastReportedPage = estimatedPage;
      widget.onPageChanged?.call(estimatedPage);
      _schedulePrefetch(estimatedPage);
    }
    widget.onScrollProgress?.call(offset, estimatedPage);
  }

  void _initPdf() {
    final activePath = widget.pdfPath;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    PdfDocument.openFile(activePath).then((doc) async {
      if (!mounted || activePath != widget.pdfPath) {
        doc.close();
        return;
      }
      _document = doc;
      widget.onDocumentLoaded?.call(doc.pagesCount);

      // Extract first page aspect ratio and dimensions for instant layout sizing
      try {
        if (doc.pagesCount > 0) {
          await _renderLock.synchronized(() async {
            final firstPage = await doc.getPage(1);
            if (firstPage.height > 0) {
              _defaultAspectRatio = firstPage.width / firstPage.height;
              _pageAspectRatios[0] = _defaultAspectRatio;
              _pageNativeWidths[0] = firstPage.width;
              _pageNativeHeights[0] = firstPage.height;
            }
            await firstPage.close();
          });
        }
      } catch (e) {
        debugPrint('⚠️ Error getting first page aspect ratio: $e');
      }

      _cacheDocumentPageDimensions(doc);
      _initControllers(doc, startPage: widget.initialPage + 1);
    }).catchError((e) {
      debugPrint('⚠️ PdfDocument.openFile error: $e');
      try {
        final f = File(activePath);
        if (f.existsSync() && activePath.contains('temp_online_')) {
          f.deleteSync();
          debugPrint('🗑️ Deleted corrupted temp PDF file: $activePath');
        }
      } catch (_) {}

      if (mounted && activePath == widget.pdfPath) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Tệp PDF bị lỗi hoặc tải về chưa hoàn tất.';
          _technicalDetails = e.toString();
        });
      }
    });
  }

  void _cacheDocumentPageDimensions(PdfDocument doc) async {
    final count = doc.pagesCount;
    final limit = count > 30 ? 30 : count;
    for (int i = 1; i <= limit; i++) {
      if (!mounted || _document != doc) return;
      final pageIndex = i - 1;
      if (_pageAspectRatios.containsKey(pageIndex)) continue;
      try {
        await _renderLock.synchronized(() async {
          if (!mounted || _document != doc) return;
          final page = await doc.getPage(i);
          if (page.height > 0) {
            _pageAspectRatios[pageIndex] = page.width / page.height;
            _pageNativeWidths[pageIndex] = page.width;
            _pageNativeHeights[pageIndex] = page.height;
          }
          await page.close();
        });
      } catch (_) {}
    }
  }

  void _initControllers(PdfDocument doc, {int? startPage}) {
    final pageCount = doc.pagesCount;
    final targetPage = (startPage ?? (widget.initialPage + 1))
        .clamp(1, pageCount > 0 ? pageCount : 1);
    if (isHorizontal) {
      _pdfController?.dispose();
      _pdfController = PdfController(
        document: Future.value(doc),
        initialPage: targetPage,
      );
    } else {
      _pdfController?.dispose();
      _pdfController = null;
      // Scroll to initial page or offset after layout
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.initialScrollOffset != null &&
            widget.initialScrollOffset! > 0) {
          jumpToOffset(widget.initialScrollOffset!);
        } else {
          jumpToPage(targetPage - 1);
        }
      });
    }
    setState(() => _isLoading = false);
    _prefetchNearbyPages(targetPage - 1);
  }

  Future<PdfPageImage> _getPageImage(int pageIndex) {
    final cached = _lruCache.get(pageIndex);
    if (cached != null) {
      return Future.value(cached);
    }
    if (_inFlightRenders.containsKey(pageIndex)) {
      return _inFlightRenders[pageIndex]!;
    }

    final future = _renderLock.synchronized(() async {
      final existing = _lruCache.get(pageIndex);
      if (existing != null) return existing;

      if (_document == null) {
        throw StateError('Document is closed');
      }
      final page = await _document!.getPage(pageIndex + 1);
      try {
        final ratio =
            page.height > 0 ? page.width / page.height : _defaultAspectRatio;
        _pageAspectRatios[pageIndex] = ratio;

        final safeRatio = (ratio > 0 && !ratio.isNaN && !ratio.isInfinite)
            ? ratio
            : _defaultAspectRatio;

        // Render at screen physical width for 100% crisp sharpness without massive memory waste
        final views = WidgetsBinding.instance.platformDispatcher.views;
        final physicalWidth = views.isNotEmpty && views.first.physicalSize.width > 0
            ? views.first.physicalSize.width
            : 1080.0;
        final targetWidth = physicalWidth.clamp(720.0, 1440.0);
        final targetHeight =
            (targetWidth / safeRatio).roundToDouble().clamp(100.0, 15000.0);

        final image = await page.render(
          width: targetWidth,
          height: targetHeight,
          format: PdfPageImageFormat.jpeg,
          backgroundColor: '#ffffff',
        );
        if (image != null) {
          _lruCache.put(pageIndex, image);
          return image;
        }
        throw StateError('Failed to render page $pageIndex');
      } finally {
        await page.close();
      }
    });

    _inFlightRenders[pageIndex] = future;
    future.whenComplete(() => _inFlightRenders.remove(pageIndex));
    return future;
  }

  void _schedulePrefetch(int centerPage) {
    _prefetchDebounceTimer?.cancel();
    _prefetchDebounceTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _prefetchNearbyPages(centerPage);
    });
  }

  Future<void> _prefetchNearbyPages(int centerPage) async {
    if (_document == null) return;
    final total = _document!.pagesCount;
    for (final offset in [1, 2, -1]) {
      final p = centerPage + offset;
      if (p >= 0 &&
          p < total &&
          !_lruCache.containsKey(p) &&
          !_inFlightRenders.containsKey(p)) {
        try {
          await _getPageImage(p);
        } catch (_) {}
      }
    }
  }

  @override
  void didUpdateWidget(PdfReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pdfPath != widget.pdfPath) {
      _pdfController?.dispose();
      _pdfController = null;
      _lruCache.clear();
      _inFlightRenders.clear();
      _pageAspectRatios.clear();
      _pageNativeWidths.clear();
      _pageNativeHeights.clear();
      _document?.close();
      _document = null;
      _isLoading = true;
      _initPdf();
    } else {
      final wasHorizontal = oldWidget.readingMode == ReadingMode.horizontal ||
          oldWidget.scrollDirection == Axis.horizontal;
      final nowHorizontal = isHorizontal;

      if (wasHorizontal != nowHorizontal) {
        // Transition between horizontal and vertical
        final currentPage = _lastReportedPage >= 0
            ? _lastReportedPage + 1
            : (_pdfController?.page ?? (widget.initialPage + 1));
        if (_document != null) {
          _initControllers(_document!, startPage: currentPage);
        }
      } else if (nowHorizontal &&
          (oldWidget.direction != widget.direction ||
           oldWidget.imageFit != widget.imageFit ||
           oldWidget.zoomStart != widget.zoomStart ||
           oldWidget.cropBorders != widget.cropBorders ||
           oldWidget.rotateLandscapeImages != widget.rotateLandscapeImages)) {
        // Reinit controller so PhotoView picks up new scale/alignment.
        final currentPage = _pdfController?.page ?? widget.initialPage + 1;
        _pdfController?.dispose();
        _pdfController = null;
        if (_document != null) {
          _initControllers(_document!, startPage: currentPage);
        }
      } else if (oldWidget.initialPage != widget.initialPage && !_isLoading) {
        // Only jump if page changed from external source (slider, bookmark, TOC),
        // NEVER if it's just reflecting what we reported to avoid snap/jitter loop!
        if (_lastReportedPage != widget.initialPage) {
          jumpToPage(widget.initialPage);
        }
      } else if (oldWidget.imageFit != widget.imageFit ||
          oldWidget.zoomStart != widget.zoomStart ||
          oldWidget.backgroundColor != widget.backgroundColor ||
          oldWidget.cropBorders != widget.cropBorders ||
          oldWidget.rotateLandscapeImages != widget.rotateLandscapeImages ||
          oldWidget.readingMode != widget.readingMode) {
        // Rebuild seamlessly when user changes any reader setting
        setState(() {});
        if (!isHorizontal && _lastReportedPage >= 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            jumpToPage(_lastReportedPage);
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _prefetchDebounceTimer?.cancel();
    _scrollController.removeListener(_onVerticalScroll);
    _scrollController.dispose();
    _pdfController?.dispose();
    _lruCache.clear();
    _inFlightRenders.clear();
    _document?.close();
    super.dispose();
  }

  double get currentScrollOffset =>
      _scrollController.hasClients ? _scrollController.offset : 0.0;

  void jumpToOffset(double offset) {
    if (_isLoading || _document == null) return;
    if (_scrollController.hasClients) {
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(offset.clamp(0.0, max));
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        jumpToOffset(offset);
      });
    }
  }

  void jumpToPage(int pageIndex) {
    if (_isLoading || _document == null || _document!.pagesCount <= 0) return;
    final pageCount = _document!.pagesCount;
    final target = pageIndex.clamp(0, pageCount - 1);
    _lastReportedPage = target;

    if (isHorizontal) {
      if (_pdfController != null && _pdfController!.page != target + 1) {
        _pdfController!.jumpToPage(target + 1);
      }
    } else {
      if (_scrollController.hasClients) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final screenHeight = MediaQuery.sizeOf(context).height;
        final isGap = widget.readingMode == ReadingMode.verticalGap;
        final gap = isGap ? 16.0 : 0.0;
        double targetOffset = 0;
        for (int i = 0; i < target; i++) {
          targetOffset +=
              _calculateVerticalPageHeight(i, screenWidth, screenHeight) + gap;
        }
        final position = _scrollController.position;
        if (targetOffset <= position.maxScrollExtent) {
          _scrollController.jumpTo(targetOffset);
        } else {
          _scrollController.jumpTo(position.maxScrollExtent);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_scrollController.hasClients) return;
            final max = _scrollController.position.maxScrollExtent;
            _scrollController.jumpTo(targetOffset.clamp(0.0, max));
          });
        }
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          jumpToPage(target);
        });
      }
    }
    _schedulePrefetch(target);
  }

  void nextPage() {
    if (isHorizontal && _pdfController != null) {
      try {
        _pdfController!.nextPage(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      } catch (_) {}
    } else if (!isHorizontal && _scrollController.hasClients) {
      final screenHeight = MediaQuery.sizeOf(context).height;
      scrollBy(screenHeight * 0.65, animated: true);
    }
  }

  void previousPage() {
    if (isHorizontal && _pdfController != null) {
      try {
        _pdfController!.previousPage(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      } catch (_) {}
    } else if (!isHorizontal && _scrollController.hasClients) {
      final screenHeight = MediaQuery.sizeOf(context).height;
      scrollBy(-(screenHeight * 0.65), animated: true);
    }
  }

  /// High-performance 60/120 FPS vertical scrolling via ScrollController.
  bool scrollBy(double deltaPixels, {bool animated = false}) {
    if (isHorizontal) return false;
    if (!_scrollController.hasClients) return false;
    final pos = _scrollController.position;
    if (deltaPixels > 0 && pos.pixels >= pos.maxScrollExtent) return false;
    if (deltaPixels < 0 && pos.pixels <= pos.minScrollExtent) return false;

    final target = (pos.pixels + deltaPixels).clamp(0.0, pos.maxScrollExtent);
    if ((target - pos.pixels).abs() < 0.001) return false;

    if (animated || deltaPixels.abs() > 50) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }
    return true;
  }

  bool autoScrollNext() {
    if (isHorizontal && _pdfController != null) {
      final currentPage = _pdfController!.page;
      final pageCount = _document?.pagesCount ?? 1;
      if (currentPage >= pageCount) {
        return false;
      }
      try {
        _pdfController!.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeIn,
        );
        return true;
      } catch (_) {
        return false;
      }
    }
    return false;
  }



  dynamic _initialPdfScale(ReaderImageFit fit, {int? pageIndex, bool isRotated = false}) {
    if (pageIndex != null) {
      final rawRatio = _pageAspectRatios[pageIndex] ?? _defaultAspectRatio;
      final ratio = (rawRatio > 0 && !rawRatio.isNaN && !rawRatio.isInfinite)
          ? rawRatio
          : _defaultAspectRatio;
      final effectiveRatio = isRotated ? (1.0 / ratio) : ratio;
      final screenSize = MediaQuery.sizeOf(context);
      if (screenSize.height > 0 && screenSize.width > 0) {
        final screenRatio = screenSize.width / screenSize.height;
        if (fit == ReaderImageFit.width) {
          if (effectiveRatio < screenRatio) {
            return PhotoViewComputedScale.contained * (screenRatio / effectiveRatio);
          } else {
            return PhotoViewComputedScale.contained;
          }
        } else if (fit == ReaderImageFit.height) {
          if (effectiveRatio > screenRatio) {
            return PhotoViewComputedScale.contained * (effectiveRatio / screenRatio);
          } else {
            return PhotoViewComputedScale.contained;
          }
        } else if (fit == ReaderImageFit.smart) {
          if (effectiveRatio < screenRatio * 0.8) {
            return PhotoViewComputedScale.contained * (screenRatio / effectiveRatio);
          } else {
            return PhotoViewComputedScale.contained;
          }
        }
      }
    }

    switch (fit) {
      case ReaderImageFit.width:
        return PhotoViewComputedScale.covered;
      case ReaderImageFit.height:
      case ReaderImageFit.screen:
        return PhotoViewComputedScale.contained;
      case ReaderImageFit.original:
        return 1.0;
      case ReaderImageFit.smart:
        return PhotoViewComputedScale.contained;
    }
  }

  /// Returns the PhotoView basePosition alignment.
  /// [anchorTop] should be true when the page is taller than the screen
  /// (horizontal reader with fitHeight/fitWidth on tall pages) so readers
  /// always start at the top of the page, not the middle.
  Alignment _getZoomAlignment(
    ReaderZoomStart zoomStart,
    ReaderDirection direction, {
    bool anchorTop = false,
  }) {
    final double y = anchorTop ? -1.0 : 0.0;
    switch (zoomStart) {
      case ReaderZoomStart.left:
        return Alignment(-1.0, y);
      case ReaderZoomStart.right:
        return Alignment(1.0, y);
      case ReaderZoomStart.center:
        return Alignment(0.0, y);
      case ReaderZoomStart.auto:
        return Alignment(
          direction == ReaderDirection.rtl ? 1.0 : -1.0,
          y,
        );
    }
  }

  Widget _buildVerticalPage(BuildContext context, int pageIndex) {
    final screenSize = MediaQuery.sizeOf(context);
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    final rawRatio = _pageAspectRatios[pageIndex] ?? _defaultAspectRatio;
    final ratio = (rawRatio > 0 && !rawRatio.isNaN && !rawRatio.isInfinite)
        ? rawRatio
        : _defaultAspectRatio;
    final isGap = widget.readingMode == ReadingMode.verticalGap;
    final shouldRotate = widget.rotateLandscapeImages && ratio > 1.05;
    final effectiveRatio = shouldRotate ? (1.0 / ratio) : ratio;

    // ---- Compute explicit page dimensions based on imageFit ----
    double pageW;
    double pageH;
    switch (widget.imageFit) {
      case ReaderImageFit.width:
        pageW = screenWidth;
        pageH = screenWidth / effectiveRatio;
      case ReaderImageFit.height:
        // Fit to screen height, center horizontally if narrower than screen
        pageH = screenHeight > 0 ? screenHeight : (screenWidth / effectiveRatio);
        pageW = pageH * effectiveRatio;
      case ReaderImageFit.screen:
        final wBasedH = screenWidth / effectiveRatio;
        if (screenHeight > 0 && wBasedH > screenHeight) {
          pageH = screenHeight;
          pageW = screenHeight * effectiveRatio;
        } else {
          pageW = screenWidth;
          pageH = wBasedH;
        }
      case ReaderImageFit.original:
        final nW = _pageNativeWidths[pageIndex];
        final nH = _pageNativeHeights[pageIndex];
        if (nW != null && nH != null && nW > 0 && nH > 0) {
          pageW = shouldRotate ? nH : nW;
          pageH = shouldRotate ? nW : nH;
        } else {
          pageW = screenWidth;
          pageH = screenWidth / effectiveRatio;
        }
      case ReaderImageFit.smart:
        if (effectiveRatio > 1.15 && screenHeight > 0) {
          // Wide/landscape page: fit to screen
          final wBasedH = screenWidth / effectiveRatio;
          if (wBasedH > screenHeight) {
            pageH = screenHeight;
            pageW = screenHeight * effectiveRatio;
          } else {
            pageW = screenWidth;
            pageH = wBasedH;
          }
        } else {
          pageW = screenWidth;
          pageH = screenWidth / effectiveRatio;
        }
    }

    // ---- Build image ----
    // When shouldRotate is true, the child before rotation needs width: pageH and height: pageW
    // so that RotatedBox(quarterTurns: 1) outputs width: pageW and height: pageH with no distortion.
    final childW = shouldRotate ? pageH : pageW;
    final childH = shouldRotate ? pageW : pageH;

    Widget imageChild = Image(
      image: PdfPageImageProvider(
        _getPageImage(pageIndex),
        pageIndex,
        _document!.id,
      ),
      width: childW,
      height: childH,
      fit: BoxFit.fill,
      gaplessPlayback: true,
      filterQuality: FilterQuality.none,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return SizedBox(
          width: childW,
          height: childH,
          child: Container(
            color: widget.backgroundColor,
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white38,
                ),
              ),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        debugPrint('⚠️ PDF Page $pageIndex render error: $error');
        return SizedBox(
          width: childW,
          height: childH,
          child: Container(
            color: widget.backgroundColor,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.broken_image_rounded,
                      color: Colors.white38, size: 32),
                  const SizedBox(height: 8),
                  Text('Trang ${pageIndex + 1} lỗi',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12)),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _lruCache.clear();
                        _inFlightRenders.clear();
                      });
                    },
                    icon: const Icon(Icons.refresh_rounded,
                        size: 16, color: Colors.white70),
                    label: const Text('Thử lại',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (shouldRotate) {
      imageChild = RotatedBox(quarterTurns: 1, child: imageChild);
    }

    if (widget.cropBorders) {
      imageChild = ClipRect(
        child: Transform(
          transform: Matrix4.diagonal3Values(1.04, 1.04, 1.0),
          alignment: Alignment.center,
          child: imageChild,
        ),
      );
    }

    // ---- Wrap in a screen-width row so Align can actually reposition ----
    // When pageW < screenWidth (e.g. fitHeight on a tall narrow page)
    // we let Align position the page according to zoomStart.
    // When pageW >= screenWidth the SizedBox is screen-width and the
    // image is full-width anyway, so alignment has no visual effect (correct).
    final alignWidth = pageW < screenWidth ? screenWidth : pageW;
    Widget pageWidget = SizedBox(
      width: alignWidth,
      height: pageH,
      child: Align(
        alignment: _getZoomAlignment(widget.zoomStart, widget.direction),
        child: imageChild,
      ),
    );

    if (isGap) {
      pageWidget = Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: pageWidget,
      );
    } else {
      pageWidget = Transform.translate(
        offset: const Offset(0, -0.5),
        child: pageWidget,
      );
    }

    return pageWidget;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: widget.backgroundColor,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (_errorMessage != null) {
      return Container(
        color: widget.backgroundColor,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 64,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () {
                    if (widget.onReloadRequested != null) {
                      widget.onReloadRequested!();
                    } else {
                      _initPdf();
                    }
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Thử lại',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white12,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                if (_technicalDetails != null) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => setState(
                        () => _showTechnicalDetails = !_showTechnicalDetails),
                    child: Text(
                      _showTechnicalDetails
                          ? 'Ẩn chi tiết lỗi'
                          : 'Xem chi tiết lỗi',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                    ),
                  ),
                  if (_showTechnicalDetails)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _technicalDetails!,
                        textAlign: TextAlign.left,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    Widget content;

    if (!isHorizontal) {
      final pageCount = _document?.pagesCount ?? 0;
      content = NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            widget.onUserScrollStart?.call();
          }
          return false;
        },
        child: ListView.builder(
          key: const PageStorageKey('pdf_vertical_list'),
          controller: _scrollController,
          padding: EdgeInsets.zero,
          physics: const BouncingScrollPhysics(),
          itemCount: pageCount,
          cacheExtent: 600.0,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          itemBuilder: (context, index) => _buildVerticalPage(context, index),
        ),
      );
    } else {
      if (_pdfController == null) {
        content = const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      } else {
        content = PdfView(
          key: ValueKey(
              'pdf_h_${widget.direction}_${widget.imageFit}_${widget.zoomStart}_${widget.cropBorders}_${widget.rotateLandscapeImages}'),
          controller: _pdfController!,
          scrollDirection: Axis.horizontal,
          reverse: widget.direction == ReaderDirection.rtl,
          backgroundDecoration: BoxDecoration(color: widget.backgroundColor),
          onPageChanged: (page) {
            final zeroPage = page - 1;
            if (_lastReportedPage != zeroPage) {
              _lastReportedPage = zeroPage;
              widget.onPageChanged?.call(zeroPage);
              _schedulePrefetch(zeroPage);
            }
          },
          builders: PdfViewBuilders<DefaultBuilderOptions>(
            options: const DefaultBuilderOptions(),
            documentLoaderBuilder: (_) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            pageLoaderBuilder: (_) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            errorBuilder: (_, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.broken_image_rounded,
                        color: Colors.white38, size: 36),
                    const SizedBox(height: 8),
                    const Text('Lỗi hiển thị trang',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => _initPdf(),
                      icon: const Icon(Icons.refresh_rounded,
                          size: 16, color: Colors.white70),
                      label: const Text('Thử lại',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),
            pageBuilder: (context, pageImage, index, document) {
              final rawRatio = _pageAspectRatios[index] ?? _defaultAspectRatio;
              final ratio = (rawRatio > 0 && !rawRatio.isNaN && !rawRatio.isInfinite)
                  ? rawRatio
                  : _defaultAspectRatio;
              final shouldRotate = widget.rotateLandscapeImages && ratio > 1.05;
              final effectiveRatio = shouldRotate ? (1.0 / ratio) : ratio;

              // Anchor at top when page would be taller than the screen.
              final screenSize = MediaQuery.sizeOf(context);
              final screenRatio = screenSize.height > 0
                  ? screenSize.width / screenSize.height
                  : 1.0;
              final anchorTop = effectiveRatio < screenRatio &&
                  (widget.imageFit == ReaderImageFit.width ||
                   widget.imageFit == ReaderImageFit.smart);

              final baseScale = _initialPdfScale(
                widget.imageFit,
                pageIndex: index,
                isRotated: shouldRotate,
              );
              final effectiveScale = (widget.cropBorders &&
                      baseScale is PhotoViewComputedScale)
                  ? baseScale * 1.04
                  : (widget.cropBorders && baseScale is num)
                      ? baseScale * 1.04
                      : baseScale;

              final minScale = widget.imageFit == ReaderImageFit.original
                  ? 0.2
                  : PhotoViewComputedScale.contained * 0.8;
              final maxScale = widget.imageFit == ReaderImageFit.original
                  ? 5.0
                  : PhotoViewComputedScale.covered * 3.0;

              if (shouldRotate) {
                Widget child = RotatedBox(
                  quarterTurns: 1,
                  child: Image(
                    image: PdfPageImageProvider(
                      pageImage,
                      index,
                      document.id,
                    ),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.none,
                  ),
                );
                if (widget.cropBorders) {
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
                  minScale: minScale,
                  maxScale: maxScale,
                  initialScale: effectiveScale,
                  basePosition: _getZoomAlignment(
                    widget.zoomStart,
                    widget.direction,
                    anchorTop: anchorTop,
                  ),
                  heroAttributes:
                      PhotoViewHeroAttributes(tag: '${document.id}-$index'),
                  onTapUp: widget.onTapUp != null
                      ? (context, details, controllerValue) =>
                          widget.onTapUp!(details)
                      : null,
                );
              }

              return PhotoViewGalleryPageOptions(
                imageProvider: PdfPageImageProvider(
                  pageImage,
                  index,
                  document.id,
                ),
                minScale: minScale,
                maxScale: maxScale,
                initialScale: effectiveScale,
                basePosition: _getZoomAlignment(
                  widget.zoomStart,
                  widget.direction,
                  anchorTop: anchorTop,
                ),
                heroAttributes:
                    PhotoViewHeroAttributes(tag: '${document.id}-$index'),
                onTapUp: widget.onTapUp != null
                    ? (context, details, controllerValue) =>
                        widget.onTapUp!(details)
                    : null,
              );
            },
          ),
        );
      }
    }

    return Container(
      color: widget.backgroundColor,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: widget.onTapUp,
        onTap: widget.onTapUp == null ? widget.onToggleControls : null,
        child: content,
      ),
    );
  }
}
