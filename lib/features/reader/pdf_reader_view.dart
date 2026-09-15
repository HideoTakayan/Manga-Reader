import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

class PdfReaderView extends StatefulWidget {
  final String pdfPath;
  final int initialPage;
  final Axis scrollDirection;
  final ValueChanged<int>? onPageChanged;
  final VoidCallback? onToggleControls;
  final ValueChanged<int>? onDocumentLoaded;

  const PdfReaderView({
    super.key,
    required this.pdfPath,
    this.initialPage = 0,
    this.scrollDirection = Axis.vertical,
    this.onPageChanged,
    this.onToggleControls,
    this.onDocumentLoaded,
  });

  @override
  PdfReaderViewState createState() => PdfReaderViewState();
}

class PdfReaderViewState extends State<PdfReaderView> {
  PdfControllerPinch? _pdfPinchController;
  PdfController? _pdfController;
  bool _isLoading = true;
  String? _errorMessage;
  PdfDocument? _document;
  // BUG-08 fix: track current page for vertical PDF to sync scrubber
  int _lastReportedPage = -1;

  @override
  void initState() {
    super.initState();
    _initPdf();
  }

  void _initPdf() {
    final activePath = widget.pdfPath;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    PdfDocument.openFile(activePath).then((doc) {
      if (mounted && activePath == widget.pdfPath) {
        _document = doc;
        widget.onDocumentLoaded?.call(doc.pagesCount);
        _initControllers(doc);
      } else {
        // Prevent native memory leak if the widget was updated/disposed before loading finished
        doc.close();
      }
    }).catchError((e) {
      if (mounted && activePath == widget.pdfPath) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Không thể mở file PDF: $e';
        });
      }
    });
  }

  void _initControllers(PdfDocument doc) {
    final pageCount = doc.pagesCount;
    final targetPage = (widget.initialPage + 1).clamp(1, pageCount > 0 ? pageCount : 1);
    if (widget.scrollDirection == Axis.vertical) {
      _pdfPinchController = PdfControllerPinch(
        document: Future.value(doc),
        initialPage: targetPage,
      );
    } else {
      _pdfController = PdfController(
        document: Future.value(doc),
        initialPage: targetPage,
      );
    }
    setState(() => _isLoading = false);
  }

  @override
  void didUpdateWidget(PdfReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pdfPath != widget.pdfPath) {
      _pdfPinchController?.dispose();
      _pdfController?.dispose();
      _pdfPinchController = null;
      _pdfController = null;
      _document?.close();
      _document = null;
      _isLoading = true;
      _initPdf();
    } else if (oldWidget.scrollDirection != widget.scrollDirection) {
      // Switch mode
      final currentPage = _pdfPinchController?.page ?? _pdfController?.page ?? widget.initialPage + 1;
      _pdfPinchController?.dispose();
      _pdfController?.dispose();
      _pdfPinchController = null;
      _pdfController = null;
      if (_document != null) {
        if (widget.scrollDirection == Axis.vertical) {
          _pdfPinchController = PdfControllerPinch(
            document: Future.value(_document),
            initialPage: currentPage,
          );
        } else {
          _pdfController = PdfController(
            document: Future.value(_document),
            initialPage: currentPage,
          );
        }
      }
    } else if (oldWidget.initialPage != widget.initialPage && !_isLoading) {
      // Jump to the new page when bookmark is clicked
      final pageCount = _document?.pagesCount ?? 1;
      final targetPage = (widget.initialPage + 1).clamp(1, pageCount > 0 ? pageCount : 1);
      if (widget.scrollDirection == Axis.vertical) {
        if (_pdfPinchController != null && _pdfPinchController!.page != targetPage) {
          _pdfPinchController!.animateToPage(
            pageNumber: targetPage,
            duration: Duration.zero,
            curve: Curves.linear,
          );
        }
      } else {
        if (_pdfController != null && _pdfController!.page != targetPage) {
          _pdfController!.jumpToPage(targetPage);
        }
      }
    }
  }

  @override
  void dispose() {
    _pdfPinchController?.dispose();
    _pdfController?.dispose();
    _document?.close();
    super.dispose();
  }

  void jumpToPage(int pageIndex) {
    if (_isLoading || _document == null) return;
    final pageCount = _document?.pagesCount ?? 1;
    final targetPage = (pageIndex + 1).clamp(1, pageCount > 0 ? pageCount : 1);
    if (widget.scrollDirection == Axis.vertical) {
      if (_pdfPinchController != null) {
        _pdfPinchController!.animateToPage(
          pageNumber: targetPage,
          duration: Duration.zero,
          curve: Curves.linear,
        );
      }
    } else {
      if (_pdfController != null) {
        _pdfController!.jumpToPage(targetPage);
      }
    }
  }

  void nextPage() {
    if (widget.scrollDirection == Axis.horizontal && _pdfController != null) {
      try {
        _pdfController!.nextPage(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      } catch (_) {}
    } else if (widget.scrollDirection == Axis.vertical && _pdfPinchController != null) {
      try {
        _pdfPinchController!.nextPage(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      } catch (_) {}
    }
  }

  void previousPage() {
    if (widget.scrollDirection == Axis.horizontal && _pdfController != null) {
      try {
        _pdfController!.previousPage(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      } catch (_) {}
    } else if (widget.scrollDirection == Axis.vertical && _pdfPinchController != null) {
      try {
        _pdfPinchController!.previousPage(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      } catch (_) {}
    }
  }

  // BUG-01 fix: replaced broken matrix-hack with proper page-based scroll.
  // PdfControllerPinch manages its own internal pan/zoom state — mutating
  // its transformation matrix directly was unreliable when zoomed in.
  bool scrollBy(double deltaPixels) {
    if (widget.scrollDirection == Axis.vertical && _pdfPinchController != null) {
      try {
        final progress = _pdfPinchController!.documentProgress;
        if (deltaPixels > 0 && progress >= 0.999) return false;
        if (deltaPixels < 0 && progress <= 0.001) return false;
        if (deltaPixels > 0) {
          _pdfPinchController!.nextPage(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          );
        } else {
          _pdfPinchController!.previousPage(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          );
        }
        return true;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  bool autoScrollNext() {
    if (widget.scrollDirection == Axis.horizontal && _pdfController != null) {
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    if (_errorMessage != null) {
      return Center(
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
                onPressed: _initPdf,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white12,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.onToggleControls,
      child: widget.scrollDirection == Axis.vertical
          ? (_pdfPinchController != null
              ? PdfViewPinch(
                  controller: _pdfPinchController!,
                  scrollDirection: Axis.vertical,
                  onPageChanged: (page) {
                    // BUG-08 fix: deduplicate onPageChanged to prevent double-fires
                    final zeroPage = page - 1;
                    if (_lastReportedPage != zeroPage) {
                      _lastReportedPage = zeroPage;
                      widget.onPageChanged?.call(zeroPage);
                    }
                  },
                  builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
                    options: const DefaultBuilderOptions(),
                    documentLoaderBuilder: (_) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    pageLoaderBuilder: (_) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorBuilder: (_, error) => Center(
                      child: Text('Lỗi: $error', style: const TextStyle(color: Colors.red)),
                    ),
                  ),
                )
              : const Center(child: CircularProgressIndicator(color: Colors.white)))
          : (_pdfController != null
              ? PdfView(
                  controller: _pdfController!,
                  scrollDirection: Axis.horizontal,
                  onPageChanged: (page) {
                    if (widget.onPageChanged != null) {
                      widget.onPageChanged!(page - 1);
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
                      child: Text('Lỗi: $error', style: const TextStyle(color: Colors.red)),
                    ),
                  ),
                )
              : const Center(child: CircularProgressIndicator(color: Colors.white))),
    );
  }
}
