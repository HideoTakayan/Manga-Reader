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
  PdfDocument? _document;

  @override
  void initState() {
    super.initState();
    _initPdf();
  }

  void _initPdf() {
    final activePath = widget.pdfPath;
    final docFuture = PdfDocument.openFile(activePath);
    docFuture.then((doc) {
      if (mounted && activePath == widget.pdfPath) {
        _document = doc;
        widget.onDocumentLoaded?.call(doc.pagesCount);
        _initControllers(doc);
      }
    });
  }

  void _initControllers(PdfDocument doc) {
    if (widget.scrollDirection == Axis.vertical) {
      _pdfPinchController = PdfControllerPinch(
        document: Future.value(doc),
        initialPage: widget.initialPage + 1,
      );
    } else {
      _pdfController = PdfController(
        document: Future.value(doc),
        initialPage: widget.initialPage + 1,
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
      if (widget.scrollDirection == Axis.vertical) {
        if (_pdfPinchController != null && _pdfPinchController!.page != widget.initialPage + 1) {
          _pdfPinchController!.jumpToPage(widget.initialPage + 1);
        }
      } else {
        if (_pdfController != null && _pdfController!.page != widget.initialPage + 1) {
          _pdfController!.jumpToPage(widget.initialPage + 1);
        }
      }
    }
  }

  @override
  void dispose() {
    _pdfPinchController?.dispose();
    _pdfController?.dispose();
    super.dispose();
  }

  bool scrollBy(double deltaPixels) {
    if (widget.scrollDirection == Axis.vertical && _pdfPinchController != null) {
      if (_pdfPinchController!.documentProgress >= 0.999) {
        return false;
      }
      final matrix = _pdfPinchController!.value.clone();
      final currentY = matrix.row1[3];
      matrix.setTranslationRaw(matrix.row0[3], currentY - deltaPixels, matrix.row2[3]);
      _pdfPinchController!.value = matrix;
      return true;
    }
    return false;
  }

  void autoScrollNext() {
    if (widget.scrollDirection == Axis.horizontal) {
      if (_pdfController != null) {
        _pdfController!.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeIn,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    return GestureDetector(
      onTap: widget.onToggleControls,
      child: widget.scrollDirection == Axis.vertical
          ? PdfViewPinch(
              controller: _pdfPinchController!,
              scrollDirection: Axis.vertical,
              onPageChanged: (page) {
                if (widget.onPageChanged != null) {
                  widget.onPageChanged!(page - 1);
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
          : PdfView(
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
            ),
    );
  }
}
