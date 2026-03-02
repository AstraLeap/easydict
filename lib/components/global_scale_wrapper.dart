import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 全局缩放包装器
///
/// 用于在 Navigator 层面统一应用文字缩放
class GlobalScaleWrapper extends StatelessWidget {
  final Widget child;

  const GlobalScaleWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // 全局缩放已在 MaterialApp.builder 中统一由 ScaleLayoutWrapper 处理，
    // 此处直接透传，避免重复缩放。
    return child;
  }
}

/// 页面级缩放包装器
///
/// 使用 MediaQuery.textScaler 实现缩放，确保文字在任意缩放比例下都以原生
/// 物理分辨率光栅化（blur-free）。监听全局缩放通知器，缩放值变化时自动重建。
///
/// 注意：此包装器只改变 textScaler，padding / icon 尺寸不随之等比缩放，
/// 这与 iOS 的辅助功能「更大文字」行为一致。
/// 如需整体布局缩放（含 icon/padding），请使用 ScaleLayoutWrapper，
/// 但须接受 scale > 1.0 时文字存在放大模糊的已知权衡。
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
    // 全局缩放已在 MaterialApp.builder 中统一由 ScaleLayoutWrapper 处理，
    // 此处直接透传，避免重复缩放。
    return child;
  }
}

/// 内容缩放包装器
///
/// 与 PageScaleWrapper 相同实现（textScaler），用于兼容旧代码。
class ContentScaleWrapper extends StatelessWidget {
  final Widget child;
  final double? scale;

  const ContentScaleWrapper({super.key, required this.child, this.scale});

  @override
  Widget build(BuildContext context) {
    // 全局缩放已在 MaterialApp.builder 中统一由 ScaleLayoutWrapper 处理，
    // 此处直接透传，避免重复缩放。
    return child;
  }
}

/// 底层缩放布局包装器 - 使用RenderObject实现缩放和正确的点击处理
///
/// 可直接构造，用于在任意局部位置应用独立缩放（不依赖全局 notifier）
class ScaleLayoutWrapper extends SingleChildRenderObjectWidget {
  final double scale;

  const ScaleLayoutWrapper({super.key, required this.scale, required Widget super.child});

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
