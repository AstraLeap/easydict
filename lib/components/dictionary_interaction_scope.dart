import 'package:flutter/material.dart';

class DictionaryInteractionScope extends InheritedWidget {
  final void Function(String path, String label)? onElementTap;
  final void Function(
    String path,
    String label,
    BuildContext context,
    Offset position,
  )?
  onElementSecondaryTap;

  const DictionaryInteractionScope({
    super.key,
    required this.onElementTap,
    this.onElementSecondaryTap,
    required super.child,
  });

  static DictionaryInteractionScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<
      DictionaryInteractionScope
    >();
  }

  @override
  bool updateShouldNotify(DictionaryInteractionScope oldWidget) {
    return onElementTap != oldWidget.onElementTap ||
        onElementSecondaryTap != oldWidget.onElementSecondaryTap;
  }
}
