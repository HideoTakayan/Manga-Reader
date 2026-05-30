import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

class PdfReaderView extends StatefulWidget {
  final Uint8List pdfBytes;
  final int initialPage;
  final ValueChanged<int>? onPageChanged;
  final VoidCallback? onToggleControls;
  final ValueChanged<int>? onDocumentLoaded;

  const PdfReaderView({
    super.key,
    required this.pdfBytes,
    this.initialPage = 0,
    this.onPageChanged,
    this.onToggleControls,
    this.onDocumentLoaded,
  });

  @override
  State<PdfReaderView> createState() => _PdfReaderViewState();
}

class _PdfReaderViewState extends State<PdfReaderView> {
  late PdfControllerPinch _pdfController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initPdf();
  }

  void _initPdf() {
    final activeBytes = widget.pdfBytes;
    final document = PdfDocument.openData(activeBytes);
    document.then((doc) {
      if (mounted && identical(activeBytes, widget.pdfBytes)) {
        widget.onDocumentLoaded?.call(doc.pagesCount);
      }
    });

    _pdfController = PdfControllerPinch(
      document: document,
      initialPage: widget.initialPage + 1, // pdfx uses 1-based index
    );
    // Fake loading delay to let PDF parser warm up
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted && identical(activeBytes, widget.pdfBytes)) {
        setState(() => _isLoading = false);
      }
    });
  }

  @override
  void didUpdateWidget(PdfReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pdfBytes != widget.pdfBytes) {
      _pdfController.dispose();
      _isLoading = true;
      _initPdf();
    } else if (oldWidget.initialPage != widget.initialPage && !_isLoading) {
      // Jump to the new page when bookmark is clicked
      if (_pdfController.page != widget.initialPage + 1) {
        _pdfController.jumpToPage(widget.initialPage + 1);
      }
    }
  }

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    return GestureDetector(
      onTap: widget.onToggleControls,
      child: PdfViewPinch(
        controller: _pdfController,
        onPageChanged: (page) {
          if (widget.onPageChanged != null) {
            widget.onPageChanged!(page - 1); // convert to 0-based index
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
            child: Text('Lỗi hiển thị PDF: $error', style: const TextStyle(color: Colors.red)),
          ),
        ),
      ),
    );
  }
}
