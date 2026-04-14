import 'dart:io';

import 'package:flutter/widgets.dart';

bool isMobilePlatform() => Platform.isAndroid || Platform.isIOS;

double topInsetWithMargin(double topInset, {double extraMargin = 8.0}) {
  return topInset + extraMargin;
}

double mobileTopSafeOffset(
  BuildContext context, {
  double extraMargin = 8.0,
  bool useViewPadding = false,
}) {
  if (!isMobilePlatform()) return 0.0;
  final mediaQuery = MediaQuery.of(context);
  final topInset = useViewPadding ? mediaQuery.viewPadding.top : mediaQuery.padding.top;
  return topInsetWithMargin(topInset, extraMargin: extraMargin);
}

double availableHeightRatio({
  required double totalHeight,
  required double reservedTop,
  double minRatio = 0.0,
  double maxRatio = 1.0,
}) {
  if (totalHeight <= 0) return maxRatio;
  return ((totalHeight - reservedTop) / totalHeight)
      .clamp(minRatio, maxRatio)
      .toDouble();
}

double topOffsetToAlignment(
  BuildContext context, {
  required double topOffset,
  double minAlignment = 0.0,
  double maxAlignment = 0.4,
}) {
  final viewportHeight = MediaQuery.of(context).size.height;
  if (viewportHeight <= 0) return 0.0;
  return (topOffset / viewportHeight)
      .clamp(minAlignment, maxAlignment)
      .toDouble();
}

double mobileTopSafeAlignment(
  BuildContext context, {
  double extraMargin = 8.0,
  bool useViewPadding = false,
  double minAlignment = 0.0,
  double maxAlignment = 0.4,
}) {
  final topOffset = mobileTopSafeOffset(
    context,
    extraMargin: extraMargin,
    useViewPadding: useViewPadding,
  );
  if (topOffset <= 0) return 0.0;
  return topOffsetToAlignment(
    context,
    topOffset: topOffset,
    minAlignment: minAlignment,
    maxAlignment: maxAlignment,
  );
}

double scrollTopSafeOffset(
  BuildContext context, {
  double mobileExtraMargin = 8.0,
  double desktopTopSpacing = 10.0,
  bool useViewPadding = false,
}) {
  if (isMobilePlatform()) {
    return mobileTopSafeOffset(
      context,
      extraMargin: mobileExtraMargin,
      useViewPadding: useViewPadding,
    );
  }
  return desktopTopSpacing;
}

double scrollTopSafeAlignment(
  BuildContext context, {
  double mobileExtraMargin = 8.0,
  double desktopTopSpacing = 10.0,
  bool useViewPadding = false,
  double minAlignment = 0.0,
  double maxAlignment = 0.4,
}) {
  final topOffset = scrollTopSafeOffset(
    context,
    mobileExtraMargin: mobileExtraMargin,
    desktopTopSpacing: desktopTopSpacing,
    useViewPadding: useViewPadding,
  );
  return topOffsetToAlignment(
    context,
    topOffset: topOffset,
    minAlignment: minAlignment,
    maxAlignment: maxAlignment,
  );
}