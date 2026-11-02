import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../config/drive_config.dart';

/// Hộp thoại xem ảnh / GIF phóng to toàn màn hình với tính năng zoom (InteractiveViewer).
class ImageViewerDialog extends StatefulWidget {
  final String imageUrl;
  final bool isGif;

  const ImageViewerDialog({
    super.key,
    required this.imageUrl,
    this.isGif = false,
  });

  /// Hiển thị hộp thoại xem ảnh toàn màn hình
  static void show(BuildContext context, {required String imageUrl, bool? isGif}) {
    // Chỉ check phần filename (sau dấu / hoặc \), tránh nhận dạng sai với path chứa ".gif"
    final fileNameOnly = imageUrl.split(RegExp(r'[/\\]')).last.toLowerCase();
    final effectiveIsGif = isGif ?? (fileNameOnly.endsWith('.gif') || fileNameOnly.contains('.gif?'));

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (ctx) => ImageViewerDialog(
        imageUrl: imageUrl,
        isGif: effectiveIsGif,
      ),
    );
  }

  @override
  State<ImageViewerDialog> createState() => _ImageViewerDialogState();
}

class _ImageViewerDialogState extends State<ImageViewerDialog>
    with SingleTickerProviderStateMixin {
  late final TransformationController _transformationController;
  late final AnimationController _animationController;
  final GlobalKey _childKey = GlobalKey();
  Animation<Matrix4>? _zoomAnimation;
  TapDownDetails? _doubleTapDetails;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        if (_zoomAnimation != null) {
          _transformationController.value = _zoomAnimation!.value;
        }
      });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _handleDoubleTap(Size viewportSize) {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();

    if (currentScale > 1.2) {
      // Đang zoom → reset về kích thước ban đầu 1.0x
      _animateZoom(Matrix4.identity());
    } else {
      // Đang ở 1.0x → zoom 2.5x vào vị trí double-tap
      final tapPos = _doubleTapDetails?.localPosition ??
          Offset(viewportSize.width / 2, viewportSize.height / 2);
      final scenePoint = _transformationController.toScene(tapPos);

      const targetScale = 2.5;
      final tx = viewportSize.width / 2 - scenePoint.dx * targetScale;
      final ty = viewportSize.height / 2 - scenePoint.dy * targetScale;

      final endMatrix = Matrix4.identity()
        ..translate(tx, ty)
        ..scale(targetScale);

      _animateZoom(endMatrix);
    }
  }

  void _animateZoom(Matrix4 endMatrix) {
    _zoomAnimation = Matrix4Tween(
      begin: _transformationController.value,
      end: endMatrix,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _animationController.forward(from: 0);
  }

  void _handleTapUp(TapUpDetails details) {
    final renderBox = _childKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      Navigator.of(context).pop();
      return;
    }

    final scenePoint = _transformationController.toScene(details.localPosition);
    final isInsideImage = Rect.fromLTWH(0, 0, renderBox.size.width, renderBox.size.height)
        .contains(scenePoint);

    if (isInsideImage) {
      // Chạm vào ảnh → ẩn/hiện nút điều khiển (Close button)
      setState(() {
        _showControls = !_showControls;
      });
    } else {
      // Chạm ra ngoài ảnh (vùng đen viền) → đóng dialog
      Navigator.of(context).pop();
    }
  }

  Widget _buildImageContent() {
    final url = widget.imageUrl.trim();

    if (url.isEmpty) {
      return _buildErrorWidget('Đường dẫn ảnh không hợp lệ');
    }

    final isNetworkUrl = url.startsWith('http://') || url.startsWith('https://');

    // 1. Nếu là ảnh động GIF
    if (widget.isGif) {
      if (isNetworkUrl) {
        return Image.network(
          url,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            );
          },
          errorBuilder: (_, __, ___) => _buildErrorWidget('Không thể tải GIF'),
        );
      } else {
        // GIF từ file cục bộ
        try {
          final file = File(url);
          if (file.existsSync()) {
            return Image.file(
              file,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _buildErrorWidget('File GIF không hợp lệ'),
            );
          }
        } catch (_) {}
      }
    }

    // 2. Nếu là file ảnh tĩnh cục bộ (chỉ kiểm tra khi KHÔNG PHẢI URL mạng)
    if (!isNetworkUrl &&
        (url.startsWith('/') ||
            url.startsWith('\\') ||
            (url.length > 2 && url[1] == ':') ||
            url.contains('/') ||
            url.contains('\\'))) {
      try {
        final file = File(url);
        if (file.existsSync()) {
          return Image.file(
            file,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _buildErrorWidget('File ảnh không hợp lệ'),
          );
        }
      } catch (_) {}
    }

    // 3. Nếu là URL trực tuyến (Cloudinary / Imgur / Web) hoặc Google Drive file ID
    final effectiveUrl = isNetworkUrl ? url : DriveConfig.getCdnOrDirectUrl(url);

    return CachedNetworkImage(
      imageUrl: effectiveUrl,
      fit: BoxFit.contain,
      placeholder: (context, _) => const Center(
        child: CircularProgressIndicator(color: Colors.white70),
      ),
      errorWidget: (_, __, ___) => _buildErrorWidget('Không thể tải ảnh'),
    );
  }

  Widget _buildErrorWidget(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_rounded, size: 48, color: Colors.white54),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Stack(
        children: [
          // Vùng ảnh có thể zoom, kéo thả và tương tác cử chỉ
          LayoutBuilder(
            builder: (context, constraints) {
              final viewportSize = constraints.biggest;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTapDown: (details) => _doubleTapDetails = details,
                onDoubleTap: () => _handleDoubleTap(viewportSize),
                onTapUp: _handleTapUp,
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 0.8,
                  maxScale: 5.0,
                  child: Center(
                    child: KeyedSubtree(
                      key: _childKey,
                      child: _buildImageContent(),
                    ),
                  ),
                ),
              );
            },
          ),

          // Nút Đóng góc trên bên phải
          if (_showControls)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    tooltip: 'Đóng',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.5),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.close_rounded, size: 26),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
