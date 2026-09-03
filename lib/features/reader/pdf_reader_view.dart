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
          _pdfPinchController!.jumpToPage(targetPage);
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
