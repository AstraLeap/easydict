/// 根据窗口宽度计算响应式数值
///
/// 采用三段式策略：
/// - 宽度 ≤ [minWidth]：返回 [minValue]
/// - 宽度 ≥ [maxWidth]：返回 [maxValue]
/// - 宽度在两者之间：线性插值
double responsiveValue({
  required double screenWidth,
  required double minWidth,
  required double maxWidth,
  required double minValue,
  required double maxValue,
}) {
  if (screenWidth <= minWidth) {
    return minValue;
  } else if (screenWidth >= maxWidth) {
    return maxValue;
  } else {
    // 线性插值
    final t = (screenWidth - minWidth) / (maxWidth - minWidth);
    return minValue + (maxValue - minValue) * t;
  }
}
