import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/note_service.dart';
import 'image_viewer_dialog.dart';

/// Markdown 图片渲染器：支持 media://name 从 notes 媒体表读取。
///
/// 尺寸仅由 Markdown 参数控制，例如：
/// ![alt|w=80%|h=200](media://xxx.png)
class NoteMarkdownMediaImage extends StatefulWidget {
  final Uri uri;
  final String? altText;
  final Future<void> Function(String mediaName, int widthPercent)?
  onWidthPercentResolved;

  const NoteMarkdownMediaImage({
    super.key,
    required this.uri,
    this.altText,
    this.onWidthPercentResolved,
  });

  @override
  State<NoteMarkdownMediaImage> createState() => _NoteMarkdownMediaImageState();
}

class _NoteMarkdownMediaImageState extends State<NoteMarkdownMediaImage> {
  Uint8List? _mediaBytes;
  String? _loadedMediaName;
  bool _isMediaLoading = false;
  final GlobalKey _imageBoxKey = GlobalKey();
  double? _interactiveWidth;
  double? _interactiveHeight;
  _ResizeEdge? _activeEdge;

  @override
  void initState() {
    super.initState();
    _prepareMediaBytes();
  }

  @override
  void didUpdateWidget(NoteMarkdownMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri.toString() != widget.uri.toString()) {
      _prepareMediaBytes();
      _interactiveWidth = null;
      _interactiveHeight = null;
      _activeEdge = null;
    }
  }

  Future<void> _prepareMediaBytes() async {
    if (widget.uri.scheme != 'media') {
      _loadedMediaName = null;
      _mediaBytes = null;
      _isMediaLoading = false;
      return;
    }

    final mediaName = _extractMediaName(widget.uri);
    if (mediaName.isEmpty) {
      _loadedMediaName = null;
      _mediaBytes = null;
      _isMediaLoading = false;
      return;
    }

    if (_loadedMediaName == mediaName &&
        (_mediaBytes != null || _isMediaLoading)) {
      return;
    }

    _loadedMediaName = mediaName;
    _mediaBytes = null;
    _isMediaLoading = true;
    if (mounted) {
      setState(() {});
    }

    final bytes = await NoteService().getMedia(mediaName);
    if (!mounted || _loadedMediaName != mediaName) {
      return;
    }

    setState(() {
      _mediaBytes = bytes;
      _isMediaLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = _parseAltStyle(widget.altText);

    return LayoutBuilder(
      builder: (context, constraints) {
        final targetWidth = _resolveDimension(
          style.width,
          constraints.maxWidth,
        );
        final targetHeight = _resolveDimension(
          style.height,
          constraints.maxHeight,
        );

        if (widget.uri.scheme != 'media') {
          final provider = NetworkImage(widget.uri.toString());
          return _buildFrame(
            child: _buildPreviewableImage(
              context,
              provider: provider,
              previewBytes: null,
              width: _effectiveWidth(targetWidth, constraints.maxWidth),
              height: _effectiveHeight(targetHeight, constraints.maxHeight),
            ),
            constraints: constraints,
          );
        }

        if (_isMediaLoading && _mediaBytes == null) {
          return _buildFrame(
            child: _buildLoadingPlaceholder(targetWidth, targetHeight),
            constraints: constraints,
          );
        }

        final bytes = _mediaBytes;
        if (bytes == null || bytes.isEmpty) {
          return _buildError(context);
        }

        final provider = MemoryImage(bytes);
        return _buildFrame(
          child: _buildPreviewableImage(
            context,
            provider: provider,
            previewBytes: bytes,
            width: _effectiveWidth(targetWidth, constraints.maxWidth),
            height: _effectiveHeight(targetHeight, constraints.maxHeight),
          ),
          constraints: constraints,
        );
      },
    );
  }

  Widget _buildPreviewableImage(
    BuildContext context, {
    required ImageProvider provider,
    required Uint8List? previewBytes,
    double? width,
    double? height,
  }) {
    return GestureDetector(
      onTap: () => _openPreview(context, provider, previewBytes),
      child: Image(
        image: provider,
        width: width,
        height: height,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => _buildError(context),
      ),
    );
  }

  Future<void> _openPreview(
    BuildContext context,
    ImageProvider provider,
    Uint8List? previewBytes,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => ImageViewerDialog(
        imageBytes: previewBytes,
        imageProvider: previewBytes == null ? provider : null,
      ),
    );
  }

  Widget _buildFrame({
    required Widget child,
    required BoxConstraints constraints,
  }) {
    final imageChild = SizedBox(key: _imageBoxKey, child: child);

    if (!Theme.of(context).platform.isDesktopLike) {
      return imageChild;
    }

    final resizeLayer = _buildResizeLayer(constraints: constraints);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        imageChild,
        Positioned.fill(child: resizeLayer),
      ],
    );
  }

  Widget _buildResizeLayer({required BoxConstraints constraints}) {
    const edgeWidth = 10.0;
    const cornerSize = 16.0;
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: edgeWidth,
          bottom: edgeWidth,
          width: edgeWidth,
          child: _buildResizeHandle(
            edge: _ResizeEdge.left,
            constraints: constraints,
          ),
        ),
        Positioned(
          right: 0,
          top: edgeWidth,
          bottom: edgeWidth,
          width: edgeWidth,
          child: _buildResizeHandle(
            edge: _ResizeEdge.right,
            constraints: constraints,
          ),
        ),
        Positioned(
          left: edgeWidth,
          right: edgeWidth,
          top: 0,
          height: edgeWidth,
          child: _buildResizeHandle(
            edge: _ResizeEdge.top,
            constraints: constraints,
          ),
        ),
        Positioned(
          left: edgeWidth,
          right: edgeWidth,
          bottom: 0,
          height: edgeWidth,
          child: _buildResizeHandle(
            edge: _ResizeEdge.bottom,
            constraints: constraints,
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          width: cornerSize,
          height: cornerSize,
          child: _buildResizeHandle(
            edge: _ResizeEdge.topLeft,
            constraints: constraints,
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          width: cornerSize,
          height: cornerSize,
          child: _buildResizeHandle(
            edge: _ResizeEdge.topRight,
            constraints: constraints,
          ),
        ),
        Positioned(
          left: 0,
          bottom: 0,
          width: cornerSize,
          height: cornerSize,
          child: _buildResizeHandle(
            edge: _ResizeEdge.bottomLeft,
            constraints: constraints,
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          width: cornerSize,
          height: cornerSize,
          child: _buildResizeHandle(
            edge: _ResizeEdge.bottomRight,
            constraints: constraints,
          ),
        ),
      ],
    );
  }

  Widget _buildResizeHandle({
    required _ResizeEdge edge,
    required BoxConstraints constraints,
  }) {
    final cursor = edge.cursor;

    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => _activeEdge = edge,
        onPanUpdate: (details) {
          if (_activeEdge != edge) {
            return;
          }
          _resizeFromEdge(edge, details.delta, constraints);
        },
        onPanEnd: (_) {
          _activeEdge = null;
          _persistWidthPercent(constraints);
        },
        onPanCancel: () {
          _activeEdge = null;
        },
      ),
    );
  }

  void _persistWidthPercent(BoxConstraints constraints) {
    if (widget.onWidthPercentResolved == null || widget.uri.scheme != 'media') {
      return;
    }

    final maxWidth = constraints.maxWidth;
    final width = _interactiveWidth;
    if (width == null || !maxWidth.isFinite || maxWidth <= 0) {
      return;
    }

    final mediaName = _extractMediaName(widget.uri);
    if (mediaName.isEmpty) {
      return;
    }

    final percent = ((width / maxWidth) * 100).round().clamp(1, 100);
    widget.onWidthPercentResolved!(mediaName, percent);
  }

  void _resizeFromEdge(
    _ResizeEdge edge,
    Offset delta,
    BoxConstraints constraints,
  ) {
    final renderObject = _imageBoxKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return;
    }

    final size = renderObject.size;
    var nextWidth = _interactiveWidth ?? size.width;
    final currentHeight = _interactiveHeight ?? size.height;
    if (nextWidth <= 0 || currentHeight <= 0) {
      return;
    }
    final aspect = nextWidth / currentHeight;

    final minWidth = 48.0;
    final minHeight = 48.0;

    final horizontalDelta = edge.dxSign * delta.dx;
    final verticalDelta = edge.dySign * delta.dy;
    if (edge.isHorizontalEdge) {
      nextWidth += horizontalDelta;
    } else if (edge.isVerticalEdge) {
      nextWidth += verticalDelta * aspect;
    } else {
      nextWidth += (horizontalDelta + verticalDelta) * 0.5;
    }

    final maxWidthByConstraint = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : double.infinity;
    final maxHeightByConstraint = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : double.infinity;

    final maxAllowedWidth = aspect > 0
        ? (maxHeightByConstraint * aspect)
        : double.infinity;
    final minAllowedWidth = aspect > 0 ? (minHeight * aspect) : minWidth;

    final upperBound = maxWidthByConstraint < maxAllowedWidth
        ? maxWidthByConstraint
        : maxAllowedWidth;
    final lowerBound = minWidth > minAllowedWidth ? minWidth : minAllowedWidth;
    if (upperBound <= 0 || upperBound < lowerBound) {
      return;
    }

    final clampedWidth = nextWidth.clamp(lowerBound, upperBound).toDouble();
    final clampedHeight = clampedWidth / aspect;

    if (!mounted) {
      return;
    }
    setState(() {
      _interactiveWidth = clampedWidth;
      _interactiveHeight = clampedHeight;
    });
  }

  Widget _buildLoadingPlaceholder(double? width, double? height) {
    final fallbackHeight = (height != null && height > 0) ? height : 120.0;
    return SizedBox(
      width: width,
      height: fallbackHeight,
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  double? _effectiveWidth(double? parsedWidth, double maxWidthConstraint) {
    final current = _interactiveWidth ?? parsedWidth;
    if (current == null) {
      return null;
    }
    if (!maxWidthConstraint.isFinite) {
      return current;
    }
    return current.clamp(48.0, maxWidthConstraint).toDouble();
  }

  double? _effectiveHeight(double? parsedHeight, double maxHeightConstraint) {
    final current = _interactiveHeight ?? parsedHeight;
    if (current == null) {
      return null;
    }
    if (!maxHeightConstraint.isFinite) {
      return current;
    }
    return current.clamp(48.0, maxHeightConstraint).toDouble();
  }

  double? _resolveDimension(_ImageDimension? dimension, double maxConstraint) {
    if (dimension == null) {
      return null;
    }
    if (dimension.isPercent) {
      if (maxConstraint.isInfinite || maxConstraint <= 0) {
        return null;
      }
      final ratio = (dimension.value / 100).clamp(0.0, 1.0);
      return maxConstraint * ratio;
    }
    return dimension.value > 0 ? dimension.value : null;
  }

  _AltImageStyle _parseAltStyle(String? rawAlt) {
    if (rawAlt == null || rawAlt.trim().isEmpty) {
      return const _AltImageStyle();
    }

    _ImageDimension? width;
    _ImageDimension? height;
    final parts = rawAlt.split('|');
    for (final rawPart in parts) {
      final part = rawPart.trim().toLowerCase();
      if (part.isEmpty || !part.contains('=')) {
        continue;
      }
      final kv = part.split('=');
      if (kv.length != 2) {
        continue;
      }
      final key = kv[0].trim();
      final value = kv[1].trim();
      final parsed = _parseDimension(value);
      if (parsed == null) {
        continue;
      }
      if (key == 'w' || key == 'width') {
        width = parsed;
      } else if (key == 'h' || key == 'height') {
        height = parsed;
      }
    }

    return _AltImageStyle(width: width, height: height);
  }

  _ImageDimension? _parseDimension(String raw) {
    if (raw.isEmpty) {
      return null;
    }
    final isPercent = raw.endsWith('%');
    final numberPart = isPercent ? raw.substring(0, raw.length - 1) : raw;
    final value = double.tryParse(numberPart);
    if (value == null || value <= 0) {
      return null;
    }
    return _ImageDimension(value: value, isPercent: isPercent);
  }

  String _extractMediaName(Uri target) {
    final host = target.host;
    final path = target.path.startsWith('/')
        ? target.path.substring(1)
        : target.path;
    final raw = host.isNotEmpty
        ? (path.isNotEmpty ? '$host/$path' : host)
        : path;
    return Uri.decodeComponent(raw);
  }

  Widget _buildError(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withOpacity(0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        widget.altText?.trim().isNotEmpty == true
            ? widget.altText!
            : 'Image unavailable',
        style: TextStyle(color: colorScheme.onErrorContainer, fontSize: 12),
      ),
    );
  }
}

class _AltImageStyle {
  final _ImageDimension? width;
  final _ImageDimension? height;

  const _AltImageStyle({this.width, this.height});
}

class _ImageDimension {
  final double value;
  final bool isPercent;

  const _ImageDimension({required this.value, required this.isPercent});
}

enum _ResizeEdge {
  left,
  right,
  top,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

extension on _ResizeEdge {
  bool get isHorizontalEdge =>
      this == _ResizeEdge.left || this == _ResizeEdge.right;

  bool get isVerticalEdge =>
      this == _ResizeEdge.top || this == _ResizeEdge.bottom;

  double get dxSign {
    switch (this) {
      case _ResizeEdge.right:
      case _ResizeEdge.topRight:
      case _ResizeEdge.bottomRight:
        return 1;
      case _ResizeEdge.left:
      case _ResizeEdge.topLeft:
      case _ResizeEdge.bottomLeft:
        return -1;
      case _ResizeEdge.top:
      case _ResizeEdge.bottom:
        return 0;
    }
  }

  double get dySign {
    switch (this) {
      case _ResizeEdge.bottom:
      case _ResizeEdge.bottomLeft:
      case _ResizeEdge.bottomRight:
        return 1;
      case _ResizeEdge.top:
      case _ResizeEdge.topLeft:
      case _ResizeEdge.topRight:
        return -1;
      case _ResizeEdge.left:
      case _ResizeEdge.right:
        return 0;
    }
  }

  MouseCursor get cursor {
    switch (this) {
      case _ResizeEdge.left:
      case _ResizeEdge.right:
        return SystemMouseCursors.resizeLeftRight;
      case _ResizeEdge.top:
      case _ResizeEdge.bottom:
        return SystemMouseCursors.resizeUpDown;
      case _ResizeEdge.topLeft:
      case _ResizeEdge.bottomRight:
        return SystemMouseCursors.resizeUpLeftDownRight;
      case _ResizeEdge.topRight:
      case _ResizeEdge.bottomLeft:
        return SystemMouseCursors.resizeUpRightDownLeft;
    }
  }
}

extension on TargetPlatform {
  bool get isDesktopLike =>
      this == TargetPlatform.windows ||
      this == TargetPlatform.macOS ||
      this == TargetPlatform.linux;
}
