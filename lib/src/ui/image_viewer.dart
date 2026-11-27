import 'dart:io';

import 'package:flutter/material.dart';

import '../models.dart';
import 'file_urls.dart';

/// Opens images full screen: the whole image, pinch to zoom, swipe between them.
Future<void> showImageViewer(BuildContext context, List<FileMeta> images, {int initial = 0}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (_, _, _) => ImageViewerScreen(images: images, initial: initial),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ),
  );
}

class ImageViewerScreen extends StatefulWidget {
  const ImageViewerScreen({super.key, required this.images, this.initial = 0});
  final List<FileMeta> images;
  final int initial;

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late final PageController _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;
  bool _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final many = widget.images.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            // A zoomed image pans instead of turning the page.
            physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() {
              _index = i;
              _zoomed = false;
            }),
            itemBuilder: (_, i) => _ZoomableImage(
              file: widget.images[i],
              onZoomChanged: (z) {
                if (z != _zoomed) setState(() => _zoomed = z);
              },
            ),
          ),
          SafeArea(
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                if (many) Text('${_index + 1} / ${widget.images.length}', style: const TextStyle(color: Colors.white, fontSize: 15)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({required this.file, required this.onZoomChanged});
  final FileMeta file;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  final _zoom = TransformationController();

  /// Panning is off until the photo is zoomed, so a sideways swipe turns the page.
  bool _zoomed = false;

  void _setZoomed(bool z) {
    if (z != _zoomed) setState(() => _zoomed = z);
    widget.onZoomChanged(z);
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _toggleZoom(TapDownDetails d) {
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed) {
      _zoom.value = Matrix4.identity();
    } else {
      final p = d.localPosition;
      _zoom.value = Matrix4.identity()
        ..translateByDouble(-p.dx * 1.5, -p.dy * 1.5, 0, 1)
        ..scaleByDouble(2.5, 2.5, 1, 1);
    }
    _setZoomed(!zoomed);
  }

  @override
  Widget build(BuildContext context) {
    TapDownDetails? lastTap;
    return GestureDetector(
      onDoubleTapDown: (d) => lastTap = d,
      onDoubleTap: () {
        if (lastTap != null) _toggleZoom(lastTap!);
      },
      child: InteractiveViewer(
        transformationController: _zoom,
        minScale: 1,
        maxScale: 6,
        panEnabled: _zoomed,
        onInteractionEnd: (_) => _setZoomed(_zoom.value.getMaxScaleOnAxis() > 1.01),
        child: SizedBox.expand(
          child: FileImageView(file: widget.file, fit: BoxFit.contain, dark: true),
        ),
      ),
    );
  }
}

/// One stored image: from this device while it waits to upload, otherwise from a short-lived signed URL.
class FileImageView extends StatelessWidget {
  const FileImageView({super.key, required this.file, this.fit = BoxFit.contain, this.dark = false});
  final FileMeta file;
  final BoxFit fit;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final broken = Center(child: Icon(Icons.broken_image_outlined, color: dark ? Colors.white54 : c.onSurfaceVariant));
    final placeholder = dark
        ? const Center(
            child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)),
          )
        : Container(color: c.surfaceContainerHighest, constraints: const BoxConstraints.tightFor(height: 180));
    if (file.localPath != null) {
      return Image.file(File(file.localPath!), fit: fit, errorBuilder: (_, _, _) => broken);
    }
    return FutureBuilder(
      future: FileUrls.get(file.id),
      builder: (context, snap) {
        if (snap.hasError) return broken;
        if (!snap.hasData) return placeholder;
        return Image.network(
          snap.data!.view,
          fit: fit,
          loadingBuilder: (context, child, progress) => progress == null ? child : placeholder,
          errorBuilder: (_, _, _) => broken,
        );
      },
    );
  }
}
