import 'package:flutter/widgets.dart';

class DpiUtils {
  static double getDevicePixelRatio(BuildContext context) {
    return MediaQuery.of(context).devicePixelRatio;
  }

  static double scale(BuildContext context, double value) {
    final ratio = getDevicePixelRatio(context);
    if (ratio <= 1.0) return value;

    if (ratio >= 1.5 && ratio < 2.0) {
      return value * 1.25;
    } else if (ratio >= 2.0 && ratio < 2.5) {
      return value * 1.5;
    } else if (ratio >= 2.5 && ratio < 3.0) {
      return value * 1.75;
    } else if (ratio >= 3.0) {
      return value * 2.0;
    }

    return value * 1.15;
  }

  static double scaleFontSize(BuildContext context, double fontSize) {
    return scale(context, fontSize);
  }

  static double scaleIconSize(BuildContext context, double iconSize) {
    return scale(context, iconSize);
  }

  static EdgeInsets scaleEdgeInsets(BuildContext context, EdgeInsets padding) {
    final scaleFactor = getDevicePixelRatio(context) > 1.25 ? 1.25 : 1.0;
    return EdgeInsets.only(
      left: padding.left * scaleFactor,
      top: padding.top * scaleFactor,
      right: padding.right * scaleFactor,
      bottom: padding.bottom * scaleFactor,
    );
  }

  static double scaleBorderRadius(BuildContext context, double radius) {
    final scaleFactor = getDevicePixelRatio(context) > 1.25 ? 1.25 : 1.0;
    return radius * scaleFactor;
  }
}
