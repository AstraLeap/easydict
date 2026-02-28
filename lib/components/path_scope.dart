import 'package:flutter/material.dart';

class PathScope extends InheritedWidget {
  final List<String> path;

  const PathScope({super.key, required this.path, required super.child});

  static List<String> of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PathScope>();
    return scope?.path ?? [];
  }

  static Widget append(
    BuildContext context, {
    required String key,
    required Widget child,
  }) {
    final parentPath = PathScope.of(context);
    // 如果 key 包含点号，说明这是一个复合路径，需要拆分
    final List<String> newParts;
    if (key.contains('.')) {
      newParts = key.split('.');
    } else {
      newParts = [key];
    }
    return PathScope(path: [...parentPath, ...newParts], child: child);
  }

  @override
  bool updateShouldNotify(PathScope oldWidget) {
    // 简单的列表比较，实际应用中可能需要更高效的比较
    if (path.length != oldWidget.path.length) return true;
    for (int i = 0; i < path.length; i++) {
      if (path[i] != oldWidget.path[i]) return true;
    }
    return false;
  }
}
