import 'package:flutter/material.dart';
import '../core/utils/toast_utils.dart';
import '../i18n/strings.g.dart';

class PathNavigator extends StatefulWidget {
  final List<String> pathParts;
  final List<String>? cursorPath;
  final Function(List<String>) onNavigate;
  final Function(List<String>)? onCursorPathTap;
  final VoidCallback? onHomeTap;
  final bool showReturnToStart;
  final VoidCallback? onReturnToStart;
  final String? Function(List<String>)? validatePath;

  const PathNavigator({
    super.key,
    required this.pathParts,
    this.cursorPath,
    required this.onNavigate,
    this.onCursorPathTap,
    this.onHomeTap,
    this.showReturnToStart = false,
    this.onReturnToStart,
    this.validatePath,
  });

  @override
  State<PathNavigator> createState() => PathNavigatorState();
}

class PathNavigatorState extends State<PathNavigator> {
  bool _isEditingPath = false;
  final FocusNode _pathFocusNode = FocusNode();
  final TextEditingController _pathEditingController = TextEditingController();

  @override
  void dispose() {
    _pathFocusNode.dispose();
    _pathEditingController.dispose();
    super.dispose();
  }

  void startEditing() {
    setState(() {
      _isEditingPath = true;
      _pathEditingController.text = widget.pathParts.join('.');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pathFocusNode.requestFocus();
      _pathEditingController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _pathEditingController.text.length,
      );
    });
  }

  void stopEditing() {
    if (_isEditingPath) {
      _applyPath(_pathEditingController.text);
    }
  }

  void _applyPath(String value) {
    final newPath = value.split('.').where((p) => p.isNotEmpty).toList();

    if (widget.validatePath != null) {
      final error = widget.validatePath!(newPath);
      if (error != null) {
        showToast(context, error);
        setState(() {
          _isEditingPath = false;
        });
        return;
      }
    }

    setState(() {
      _isEditingPath = false;
    });
    widget.onNavigate(newPath);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasCursorPath =
        widget.cursorPath != null && widget.cursorPath!.isNotEmpty;

    if (_isEditingPath) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colorScheme.primary),
        ),
        child: TextField(
          controller: _pathEditingController,
          focusNode: _pathFocusNode,
          style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            isDense: true,
          ),
          onSubmitted: _applyPath,
          onTapOutside: (_) {
            _applyPath(_pathEditingController.text);
          },
        ),
      );
    }

    return GestureDetector(
      onTap: startEditing,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            if (widget.onHomeTap != null)
              InkWell(
                onTap: widget.onHomeTap,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Icon(Icons.home, size: 16, color: colorScheme.primary),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (widget.pathParts.isNotEmpty) ...[
                      ...widget.pathParts.asMap().entries.expand((entry) {
                        final index = entry.key;
                        final part = entry.value;
                        final currentPath = widget.pathParts.sublist(
                          0,
                          index + 1,
                        );

                        final widgets = <Widget>[];

                        if (index > 0) {
                          widgets.add(
                            Padding(
                              key: ValueKey('path_sep_$index'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: Icon(
                                Icons.chevron_right,
                                size: 14,
                                color: colorScheme.outline,
                              ),
                            ),
                          );
                        }

                        final isLast =
                            index == widget.pathParts.length - 1 &&
                            !hasCursorPath;
                        widgets.add(
                          InkWell(
                            key: ValueKey('path_part_$index'),
                            onTap: isLast
                                ? null
                                : () => widget.onNavigate(currentPath),
                            borderRadius: BorderRadius.circular(3),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Text(
                                part,
                                style: TextStyle(
                                  color: isLast
                                      ? colorScheme.primary
                                      : colorScheme.onSurface,
                                  fontWeight: isLast
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        );

                        return widgets;
                      }),
                    ],
                    if (hasCursorPath) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.arrow_forward,
                          size: 12,
                          color: colorScheme.outline,
                        ),
                      ),
                      ...widget.cursorPath!.asMap().entries.expand((entry) {
                        final index = entry.key;
                        final part = entry.value;
                        final currentCursorPath = widget.cursorPath!.sublist(
                          0,
                          index + 1,
                        );

                        final widgets = <Widget>[];

                        if (index > 0) {
                          widgets.add(
                            Padding(
                              key: ValueKey('cursor_sep_$index'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: Icon(
                                Icons.chevron_right,
                                size: 14,
                                color: colorScheme.outline,
                              ),
                            ),
                          );
                        }

                        final isLast = index == widget.cursorPath!.length - 1;
                        widgets.add(
                          InkWell(
                            key: ValueKey('cursor_part_$index'),
                            onTap: isLast
                                ? null
                                : () => widget.onCursorPathTap?.call(
                                    currentCursorPath,
                                  ),
                            borderRadius: BorderRadius.circular(3),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Text(
                                part,
                                style: TextStyle(
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.6,
                                  ),
                                  fontWeight: isLast
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        );

                        return widgets;
                      }),
                    ],
                  ],
                ),
              ),
            ),
            if (widget.showReturnToStart && widget.onReturnToStart != null)
              InkWell(
                onTap: widget.onReturnToStart,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Tooltip(
                    message: context.t.entry.returnToStart,
                    child: Icon(
                      Icons.first_page,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
