import 'package:flutter/material.dart';

OverlayEntry? _currentOverlayEntry;

double _getBottomPosition(BuildContext context) {
  String? pageType;

  context.visitAncestorElements((element) {
    final widgetType = element.widget.runtimeType.toString();
    if (widgetType == 'EntryDetailPage') {
      pageType = 'EntryDetailPage';
      return false;
    }
    if (widgetType == 'MainScreen' || widgetType == 'HomePage') {
      pageType = widgetType;
      return false;
    }
    return true;
  });

  switch (pageType) {
    case 'EntryDetailPage':
      return 80.0;
    case 'MainScreen':
    case 'HomePage':
      return 90.0;
    default:
      return 10.0;
  }
}

void showToast(BuildContext context, String message, {SnackBarAction? action}) {
  final colorScheme = Theme.of(context).colorScheme;
  final bottom = _getBottomPosition(context);

  _currentOverlayEntry?.remove();
  _currentOverlayEntry = null;

  final overlay = Overlay.of(context);
  final overlayEntry = OverlayEntry(
    builder: (context) => Positioned(
      bottom: bottom,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withOpacity(0.5),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                ),
                if (action != null) action,
              ],
            ),
          ),
        ),
      ),
    ),
  );

  _currentOverlayEntry = overlayEntry;
  overlay.insert(overlayEntry);

  Future.delayed(const Duration(seconds: 3), () {
    // 检查是否是当前显示的 Toast，避免重复移除
    if (_currentOverlayEntry == overlayEntry) {
      _currentOverlayEntry?.remove();
      _currentOverlayEntry = null;
    }
  });
}

void clearAllToasts(BuildContext context) {
  _currentOverlayEntry?.remove();
  _currentOverlayEntry = null;
  ScaffoldMessenger.of(context).clearSnackBars();
}
