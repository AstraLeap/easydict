import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../services/font_loader_service.dart';

/// 全局缩放包装器
///
/// 用于在 Navigator 层面统一应用文字缩放
class GlobalScaleWrapper extends StatelessWidget {
  final Widget child;

  const GlobalScaleWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final scale = FontLoaderService().getDictionaryContentScale();

    if (scale == 1.0) {
      return child;
    }

    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child,
    );
  }
}

/// 页面级缩放包装器
///
/// 用于单个页面的缩放，使用 RenderObject 实现正确的点击事件处理
/// 注意：此类监听全局缩放通知器，确保在父组件不重建时也能正确响应缩放变化
class PageScaleWrapper extends StatelessWidget {
  final Widget child;

  /// 已弃用：缩放值现在总是动态获取，此参数仅用于向后兼容
  @Deprecated(
    'Scale is now always dynamically fetched. This parameter is ignored.',
  )
  final double? scale;

  const PageScaleWrapper({super.key, required this.child, this.scale});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: FontLoaderService().dictionaryContentScaleNotifier,
      builder: (context, effectiveScale, _) {
        if (effectiveScale == 1.0) {
          return child;
        }

        return _ScaleLayoutWrapper(scale: effectiveScale, child: child);
      },
    );
  }
}

/// 内容缩放包装器
///
/// 与 PageScaleWrapper 相同实现，用于兼容旧代码
class ContentScaleWrapper extends StatelessWidget {
  final Widget child;
  final double? scale;

  const ContentScaleWrapper({super.key, required this.child, this.scale});

  @override
  Widget build(BuildContext context) {
    final effectiveScale =
        scale ?? FontLoaderService().getDictionaryContentScale();

    if (effectiveScale == 1.0) {
      return child;
    }

    return _ScaleLayoutWrapper(scale: effectiveScale, child: child);
  }
}

/// 底层缩放布局包装器 - 使用RenderObject实现缩放和正确的点击处理
class _ScaleLayoutWrapper extends SingleChildRenderObjectWidget {
  final double scale;

  const _ScaleLayoutWrapper({required this.scale, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderScaleLayout(scale: scale);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderScaleLayout renderObject,
  ) {
    renderObject.scale = scale;
  }
}

class _RenderScaleLayout extends RenderProxyBox {
  double _scale;

  _RenderScaleLayout({required double scale, RenderBox? child})
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
      // 转换点击坐标 - 这是关键！将点击坐标除以 scale 来匹配子组件的坐标系
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
