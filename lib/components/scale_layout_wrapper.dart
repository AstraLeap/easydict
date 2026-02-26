import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 缩放布局包装器 - 用于统一应用软件布局缩放
///
/// 使用方式：
/// ```dart
/// class _MyPageState extends State<MyPage> {
///   final double _contentScale = FontLoaderService().getDictionaryContentScale();
///
///   @override
///   Widget build(BuildContext context) {
///     return Scaffold(
///       body: ScaledContent(
///         scale: _contentScale,
///         child: YourContent(),
///       ),
///     );
///   }
/// }
/// ```
class ScaledContent extends StatelessWidget {
  final double scale;
  final Widget child;

  const ScaledContent({super.key, required this.scale, required this.child});

  @override
  Widget build(BuildContext context) {
    if (scale == 1.0) {
      return child;
    }
    return ScaleLayoutWrapper(scale: scale, child: child);
  }
}

/// 底层缩放布局包装器 - 使用RenderObject实现缩放
class ScaleLayoutWrapper extends SingleChildRenderObjectWidget {
  final double scale;

  const ScaleLayoutWrapper({
    super.key,
    required this.scale,
    required Widget super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderScaleLayout(scale: scale);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderScaleLayout renderObject,
  ) {
    renderObject.scale = scale;
  }
}

class RenderScaleLayout extends RenderProxyBox {
  double _scale;

  RenderScaleLayout({required double scale, RenderBox? child})
    : _scale = scale,
      super(child);

  set scale(double value) {
    if (_scale != value) {
      _scale = value;
      markNeedsLayout();
    }
  }

  @override
  void performLayout() {
    if (child != null) {
      if (_scale == 0) {
        _scale = 1.0;
      }

      double childMaxWidth = constraints.maxWidth;
      double childMinWidth = constraints.minWidth;
      double childMaxHeight = constraints.maxHeight;
      double childMinHeight = constraints.minHeight;

      if (constraints.maxWidth.isFinite) {
        childMaxWidth = constraints.maxWidth / _scale;
      }
      if (constraints.minWidth.isFinite) {
        childMinWidth = constraints.minWidth / _scale;
      }
      if (constraints.maxHeight.isFinite) {
        childMaxHeight = constraints.maxHeight / _scale;
      }
      if (constraints.minHeight.isFinite) {
        childMinHeight = constraints.minHeight / _scale;
      }

      final BoxConstraints childConstraints = constraints.copyWith(
        maxWidth: childMaxWidth,
        minWidth: childMinWidth,
        maxHeight: childMaxHeight,
        minHeight: childMinHeight,
      );
      child!.layout(childConstraints, parentUsesSize: true);

      final desiredSize = child!.size * _scale;
      size = constraints.constrain(desiredSize);
    } else {
      size = constraints.smallest;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) {
      // 缩放绘制
      context.pushTransform(
        needsCompositing,
        offset,
        Matrix4.diagonal3Values(_scale, _scale, 1.0),
        (context, offset) {
          context.paintChild(child!, offset);
        },
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (child != null) {
      // 转换点击坐标
      final Matrix4 transform = Matrix4.diagonal3Values(_scale, _scale, 1.0);

      return result.addWithPaintTransform(
        transform: transform,
        position: position,
        hitTest: (BoxHitTestResult result, Offset position) {
          return child!.hitTest(result, position: position);
        },
      );
    }
    return false;
  }
}
