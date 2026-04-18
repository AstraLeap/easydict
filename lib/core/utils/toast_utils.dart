import 'package:flutter/material.dart';

import '../../services/entry_tab_service.dart';
import '../../services/entry_tab_visibility_service.dart';

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

const double _mobileTabBarExtraOffset = 34.0;

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
      }
      if (widgetType == '_JsonEditorBottomSheet') {
        hasJsonEditorBottomSheet = true;
      }
      if (widgetType == 'MainScreen' || widgetType == 'HomePage') {
        pageType ??= widgetType;
        return false;
      }
      return true;
    });
  }

  final platform = Theme.of(context).platform;
  final isPhonePlatform =
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  final hasVisibleTabBar =
      EntryTabVisibilityService().isVisible &&
      EntryTabService().tabs.length > 1;
  // 仅在手机端且确实显示标签栏时，才为 toast 额外抬高。
  // 与词条页其他底部浮层使用同一预留高度，保持底部对齐基线一致。
  final tabBarHeight = (isPhonePlatform && hasVisibleTabBar)
      ? _mobileTabBarExtraOffset
      : 0.0;

  switch (pageType) {
    case 'EntryDetailPage':
      return 75.0 + tabBarHeight;
    case 'MainScreen':
    case 'HomePage':
      return 90.0;
    default:
      if (hasJsonEditorBottomSheet) {
        return 75.0 + tabBarHeight;
      }
      return 10.0;
  }
}

void showToast(BuildContext context, String message, {SnackBarAction? action}) {
  clearAllToasts();
  final colorScheme = Theme.of(context).colorScheme;
  final mediaQuery = MediaQuery.of(context);
  final viewInsets = mediaQuery.viewInsets.bottom;
  final keyboardHeight = viewInsets > 0 ? viewInsets + 16 : 0.0;
  final safeBottomInset = mediaQuery.viewPadding.bottom;
  final fixedBottomOffset =
      _getBottomPosition(context) + keyboardHeight + safeBottomInset;

  _currentOverlayEntry?.remove();
  _currentOverlayEntry = null;

  final overlay = Overlay.of(context);
  final overlayEntry = OverlayEntry(
    builder: (context) => Positioned(
      bottom: fixedBottomOffset,
      left: 0,
      right: 0,
      child: Material(
        color: Colors.transparent,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 630),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
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
                  ?action,
                ],
              ),
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
