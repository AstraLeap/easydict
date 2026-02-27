import 'package:flutter/material.dart';

OverlayEntry? _currentOverlayEntry;

void clearAllToasts() {
  _currentOverlayEntry?.remove();
  _currentOverlayEntry = null;
}

class ToastRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    clearAllToasts();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    clearAllToasts();
  }
}

final toastRouteObserver = ToastRouteObserver();

double _getBottomPosition(BuildContext context) {
  String? pageType;
  bool hasJsonEditorBottomSheet = false;

  final currentWidgetType = context.widget.runtimeType.toString();

  if (currentWidgetType == 'EntryDetailPage') {
    pageType = 'EntryDetailPage';
  } else if (currentWidgetType == '_JsonEditorBottomSheet') {
    hasJsonEditorBottomSheet = true;
  }

  if (pageType == null) {
    context.visitAncestorElements((element) {
      final widgetType = element.widget.runtimeType.toString();
      if (widgetType == 'EntryDetailPage') {
        pageType = 'EntryDetailPage';
        return false;
      }
      if (widgetType == '_JsonEditorBottomSheet') {
        hasJsonEditorBottomSheet = true;
      }
      if (widgetType == 'MainScreen' || widgetType == 'HomePage') {
        pageType = widgetType;
        return false;
      }
      return true;
    });
  }

  switch (pageType) {
    case 'EntryDetailPage':
      return 75.0;
    case 'MainScreen':
    case 'HomePage':
      return 90.0;
    default:
      if (hasJsonEditorBottomSheet) {
        return 75.0;
      }
      return 10.0;
  }
}

void showToast(BuildContext context, String message, {SnackBarAction? action}) {
  clearAllToasts();
  final colorScheme = Theme.of(context).colorScheme;
  final viewInsets = MediaQuery.of(context).viewInsets.bottom;
  final keyboardHeight = viewInsets > 0 ? viewInsets + 16 : 0.0;
  final bottom = _getBottomPosition(context) + keyboardHeight;

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
    if (_currentOverlayEntry == overlayEntry) {
      _currentOverlayEntry?.remove();
      _currentOverlayEntry = null;
    }
  });
}
