import 'dart:typed_data';
import 'dart:ui' show instantiateImageCodec;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ImageViewerDialog extends StatefulWidget {
  final Uint8List? imageBytes;
  final String? svgString;
  final ImageProvider? imageProvider;

  const ImageViewerDialog({
    super.key,
    this.imageBytes,
    this.svgString,
    this.imageProvider,
  });

  @override
  State<ImageViewerDialog> createState() => _ImageViewerDialogState();
}

class _ImageViewerDialogState extends State<ImageViewerDialog> {
  final TransformationController _transformController =
      TransformationController();
  Size? _imageSize;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImageDimensions();
  }

  Future<void> _loadImageDimensions() async {
    final bytes = widget.imageBytes;
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final codec = await instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      if (mounted) {
        setState(() {
          _imageSize = Size(image.width.toDouble(), image.height.toDouble());
          _isLoading = false;
        });
      }
      image.dispose();
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    const padding = 32.0;
    final availableSize = Size(
      screenSize.width - padding * 2,
      screenSize.height - padding * 2,
    );

    double? displayWidth;
    double? displayHeight;
    if (_imageSize != null) {
      final aspectRatio = _imageSize!.width / _imageSize!.height;
      final screenAspectRatio = availableSize.width / availableSize.height;
      if (aspectRatio > screenAspectRatio) {
        displayWidth = availableSize.width;
        displayHeight = displayWidth / aspectRatio;
      } else {
        displayHeight = availableSize.height;
        displayWidth = displayHeight * aspectRatio;
      }
    }

    Widget buildContent() {
      if (widget.svgString != null) {
        return SvgPicture.string(
          widget.svgString!,
          width: displayWidth,
          height: displayHeight,
          fit: BoxFit.contain,
          allowDrawingOutsideViewBox: true,
          clipBehavior: Clip.none,
        );
      }

      if (widget.imageBytes != null && widget.imageBytes!.isNotEmpty) {
        return Image.memory(
          widget.imageBytes!,
          width: displayWidth,
          height: displayHeight,
          fit: BoxFit.contain,
        );
      }

      if (widget.imageProvider != null) {
        return Image(
          image: widget.imageProvider!,
          fit: BoxFit.contain,
          width: displayWidth,
          height: displayHeight,
        );
      }

      return const SizedBox.shrink();
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          color: Colors.transparent,
          alignment: Alignment.center,
          child: _isLoading
              ? CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.primary,
                )
              : InteractiveViewer(
                  transformationController: _transformController,
                  maxScale: 5.0,
                  minScale: 0.5,
                  constrained: true,
                  clipBehavior: Clip.none,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  child: buildContent(),
                ),
        ),
      ),
    );
  }
}
