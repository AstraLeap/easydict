import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';

/// Ruby 文本布局组件
/// 用于正确渲染振假名（日语注音假名）
///
/// 使用自定义 RenderObject 正确处理基线对齐：
/// - 汉字的基线与周围文本的基线对齐
/// - 假名显示在汉字上方
class RubyLayout extends MultiChildRenderObjectWidget {
  final double rubyFontSize;
  final double rubySpacing;
  final String baseText;
  final TextStyle baseStyle;
  final String rubyText;

  const RubyLayout({
    super.key,
    required this.rubyFontSize,
    required this.rubySpacing,
    required this.baseText,
    required this.baseStyle,
    required this.rubyText,
  }) : super(children: const []);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderRubyLayout(
      rubyFontSize: rubyFontSize,
      rubySpacing: rubySpacing,
      baseText: baseText,
      baseStyle: baseStyle,
      rubyText: rubyText,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderRubyLayout renderObject,
  ) {
    renderObject
      ..rubyFontSize = rubyFontSize
      ..rubySpacing = rubySpacing
      ..baseText = baseText
      ..baseStyle = baseStyle
      ..rubyText = rubyText;
  }
}

/// RubyLayout 的父数据
class _RubyParentData extends ContainerBoxParentData<RenderBox> {}

/// 自定义 RenderObject，正确处理振假名的基线对齐
///
/// 关键点：
/// 1. 在 layout 中将汉字向下偏移 rubyHeight + spacing
/// 2. 在 computeDistanceToActualBaseline 中直接返回汉字的基线位置
/// 3. 不将 topOffset 计入基线距离
class RenderRubyLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _RubyParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _RubyParentData> {
  RenderRubyLayout({
    required double rubyFontSize,
    required double rubySpacing,
    required String baseText,
    required TextStyle baseStyle,
    required String rubyText,
  })  : _rubyFontSize = rubyFontSize,
        _rubySpacing = rubySpacing,
        _baseText = baseText,
        _baseStyle = baseStyle,
        _rubyText = rubyText {
    _updateChildren();
  }

  double _rubyFontSize;
  double _rubySpacing;
  String _baseText;
  TextStyle _baseStyle;
  String _rubyText;

  set rubyFontSize(double value) {
    if (_rubyFontSize != value) {
      _rubyFontSize = value;
      _updateChildren();
    }
  }

  set rubySpacing(double value) {
    if (_rubySpacing != value) {
      _rubySpacing = value;
      markNeedsLayout();
    }
  }

  set baseText(String value) {
    if (_baseText != value) {
      _baseText = value;
      _updateChildren();
    }
  }

  set baseStyle(TextStyle value) {
    if (_baseStyle != value) {
      _baseStyle = value;
      _updateChildren();
    }
  }

  set rubyText(String value) {
    if (_rubyText != value) {
      _rubyText = value;
      _updateChildren();
    }
  }

  void _updateChildren() {
    _rubyTextPainter = TextPainter(
      text: TextSpan(
        text: _rubyText,
        style: _baseStyle.copyWith(
          fontSize: _rubyFontSize,
          color: Colors.grey.shade600,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    _baseTextPainter = TextPainter(
      text: TextSpan(
        text: _baseText,
        style: _baseStyle.copyWith(height: 1.0),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    markNeedsLayout();
  }

  late TextPainter _rubyTextPainter;
  late TextPainter _baseTextPainter;

  @override
  void setupParentData(covariant RenderObject child) {
    if (child.parentData is! _RubyParentData) {
      child.parentData = _RubyParentData();
    }
  }

  @override
  void performLayout() {
    final rubyWidth = _rubyTextPainter.width;
    final rubyHeight = _rubyTextPainter.height;
    final baseWidth = _baseTextPainter.width;
    final baseHeight = _baseTextPainter.height;

    // 总宽度取汉字和假名中较宽的
    final totalWidth = rubyWidth > baseWidth ? rubyWidth : baseWidth;
    // 总高度 = 假名高度 + 间距 + 汉字高度
    final totalHeight = rubyHeight + _rubySpacing + baseHeight;

    size = constraints.constrain(Size(totalWidth, totalHeight));

    // 计算假名位置：水平居中，顶部对齐
    final rubyOffset = Offset((totalWidth - rubyWidth) / 2, 0);
    // 计算汉字位置：水平居中，位于假名下方
    final baseOffset = Offset(
      (totalWidth - baseWidth) / 2,
      rubyHeight + _rubySpacing,
    );

    // 存储偏移量用于绘制
    _rubyOffset = rubyOffset;
    _baseOffset = baseOffset;
  }

  late Offset _rubyOffset;
  late Offset _baseOffset;

  @override
  void paint(PaintingContext context, Offset offset) {
    // 绘制假名
    _rubyTextPainter.paint(context.canvas, offset + _rubyOffset);
    // 绘制汉字
    _baseTextPainter.paint(context.canvas, offset + _baseOffset);
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    // 关键：返回汉字的基线位置，加上假名高度和间距
    // 这样 WidgetSpan 使用 PlaceholderAlignment.baseline 时，
    // 会将汉字的基线与其他文本的基线对齐
    final rubyHeight = _rubyTextPainter.height;
    final baseBaseline = _baseTextPainter
        .computeDistanceToActualBaseline(TextBaseline.alphabetic);
    return rubyHeight + _rubySpacing + baseBaseline;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return false;
  }

  @override
  bool hitTestSelf(Offset position) {
    // 返回 true 让 Listener 能够捕获事件
    return size.contains(position);
  }
}
