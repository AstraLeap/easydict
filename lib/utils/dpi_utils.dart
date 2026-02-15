import 'dart:async';
import 'package:flutter/widgets.dart';

class DpiUtils {
  static double? _cachedScaleFactor;
  static DateTime? _lastCalculateTime;
  static Timer? _debounceTimer;
  static const _debounceDuration = Duration(milliseconds: 200);

  static double getDevicePixelRatio(BuildContext context) {
    return MediaQuery.of(context).devicePixelRatio;
  }

  static double _calculateScaleFactor(double ratio) {
    if (ratio <= 1.0) return 1.0;

    if (ratio >= 1.5 && ratio < 2.0) {
      return 1.25;
    } else if (ratio >= 2.0 && ratio < 2.5) {
      return 1.5;
    } else if (ratio >= 2.5 && ratio < 3.0) {
      return 1.75;
    } else if (ratio >= 3.0) {
      return 2.0;
    }

    return 1.15;
  }

  static double _getOrUpdateScaleFactor(BuildContext context) {
    final now = DateTime.now();
    final ratio = MediaQuery.of(context).devicePixelRatio;

    if (_lastCalculateTime == null) {
      _cachedScaleFactor = _calculateScaleFactor(ratio);
      _lastCalculateTime = now;
    } else {
      final elapsed = now.difference(_lastCalculateTime!);
      if (elapsed > _debounceDuration) {
        _cachedScaleFactor = _calculateScaleFactor(ratio);
        _lastCalculateTime = now;
      }
    }

    return _cachedScaleFactor ?? 1.0;
  }

  static double scale(BuildContext context, double value) {
    final scaleFactor = _getOrUpdateScaleFactor(context);
    return value * scaleFactor;
  }

  static double scaleFontSize(BuildContext context, double fontSize) {
    return scale(context, fontSize);
  }

  static double scaleIconSize(BuildContext context, double iconSize) {
    return scale(context, iconSize);
  }

  static EdgeInsets scaleEdgeInsets(BuildContext context, EdgeInsets padding) {
    final scaleFactor = _getOrUpdateScaleFactor(context);
    return EdgeInsets.only(
      left: padding.left * scaleFactor,
      top: padding.top * scaleFactor,
      right: padding.right * scaleFactor,
      bottom: padding.bottom * scaleFactor,
    );
  }

  static double scaleBorderRadius(BuildContext context, double radius) {
    final scaleFactor = _getOrUpdateScaleFactor(context);
    return radius * scaleFactor;
  }
}
