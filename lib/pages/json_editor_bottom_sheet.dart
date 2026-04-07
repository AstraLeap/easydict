import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/styles/all.dart' show builtThemes;
import '../data/database_service.dart';
import '../core/utils/toast_utils.dart';
import '../i18n/strings.g.dart';
import '../widgets/path_navigator.dart';

/// JSON 编辑器底部弹出面板，用于在词条详情页中直接编辑 JSON 元素
class JsonEditorBottomSheet extends StatefulWidget {
  final DictionaryEntry entry;
  final List<String> pathParts;
  final String initialText;
  final int historyIndex;
  final List<List<String>> pathHistory;
  final List<String>? initialPath;
  final Function(dynamic) onSave;
  final Function(List<String>, dynamic) onNavigate;

  /// 状态栏高度，需要从父级 context 获取，因为底部弹出层的 context 中 viewPadding.top 为 0
  final double statusBarHeight;

  const JsonEditorBottomSheet({
    super.key,
    required this.entry,
    required this.pathParts,
    required this.initialText,
    required this.historyIndex,
    required this.pathHistory,
    this.initialPath,
    required this.onSave,
    required this.onNavigate,
    required this.statusBarHeight,
  });

  @override
  State<JsonEditorBottomSheet> createState() => _JsonEditorBottomSheetState();
}

class _JsonEditorBottomSheetState extends State<JsonEditorBottomSheet> {
  late CodeLineEditingController _controller;
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  int _currentEditPosition = 0;
  bool _hasSyntaxError = false;
  String? _errorMessage;
  bool _isFullScreen = false;
  final List<String> _currentPath = [];
  final GlobalKey<PathNavigatorState> _pathNavigatorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController.fromText(widget.initialText);
    _undoStack.add(widget.initialText);
    _controller.addListener(_trackChanges);
    _validateJson();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _trackChanges() {
    final currentText = _controller.text;
    if (_undoStack[_currentEditPosition] != currentText) {
      if (_currentEditPosition < _undoStack.length - 1) {
        _undoStack.removeRange(_currentEditPosition + 1, _undoStack.length);
      }
      _undoStack.add(currentText);
      _currentEditPosition = _undoStack.length - 1;
      _redoStack.clear();
      _validateJson();
    }
  }

  void _undo() {
    if (_currentEditPosition > 0) {
      setState(() {
        _currentEditPosition--;
        _controller.text = _undoStack[_currentEditPosition];
        _redoStack.clear();
        _validateJson();
      });
    }
  }

  void _redo() {
    if (_currentEditPosition < _undoStack.length - 1) {
      setState(() {
        _currentEditPosition++;
        _controller.text = _undoStack[_currentEditPosition];
        _validateJson();
      });
    }
  }

  void _formatJson() {
    try {
      final json = jsonDecode(_controller.text);
      final formatted = const JsonEncoder.withIndent('  ').convert(json);
      setState(() {
        _controller.text = formatted;
      });
    } catch (e) {
      setState(() {
        _hasSyntaxError = true;
        _errorMessage = context.t.entry.jsonFormatFailed(error: e);
      });
    }
  }

  void _validateJson() {
    try {
      jsonDecode(_controller.text);
      setState(() {
        _hasSyntaxError = false;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _hasSyntaxError = true;
        _errorMessage = e.toString();
      });
    }
  }

  void _handleSave() async {
    if (_hasSyntaxError) {
      showToast(
        context,
        context.t.entry.jsonSyntaxError(error: _errorMessage ?? ''),
      );
      return;
    }

    try {
      final newValue = jsonDecode(_controller.text);
      await widget.onSave(newValue);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      showToast(context, context.t.entry.saveFailed(error: e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 使用从父级传入的状态栏高度，因为底部弹出层的 context 中 viewPadding.top 为 0
    final statusBarHeight = widget.statusBarHeight;
    final screenSize = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: _isFullScreen ? 1.0 : 0.7,
      minChildSize: _isFullScreen ? 1.0 : 0.5,
      maxChildSize: _isFullScreen
          ? 1.0
          : (screenSize.height - statusBarHeight - 8) / screenSize.height,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          width: _isFullScreen ? screenSize.width : null,
          padding: EdgeInsets.only(
            top: _isFullScreen ? statusBarHeight + 8 : 16,
            left: 16,
            right: 16,
            bottom: 16,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: _isFullScreen
                ? BorderRadius.zero
                : const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          clipBehavior: _isFullScreen ? Clip.none : Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: PathNavigator(
                      key: _pathNavigatorKey,
                      pathParts: widget.pathParts,
                      cursorPath: _currentPath.isNotEmpty ? _currentPath : null,
                      onNavigate: (newPathParts) {
                        Navigator.pop(context);
                        dynamic currentValue;
                        try {
                          currentValue = jsonDecode(_controller.text);
                        } catch (_) {
                          final json = widget.entry.toJson();
                          currentValue = json;
                        }
                        for (final part in newPathParts) {
                          if (currentValue is Map) {
                            currentValue = currentValue[part];
                          } else if (currentValue is List) {
                            final index = int.tryParse(part);
                            if (index != null &&
                                index >= 0 &&
                                index < currentValue.length) {
                              currentValue = currentValue[index];
                            } else {
                              // 索引无效，停止遍历
                              break;
                            }
                          }
                        }
                        widget.onNavigate(newPathParts, currentValue);
                      },
                      onHomeTap: () {
                        Navigator.pop(context);
                        final json = widget.entry.toJson();
                        widget.onNavigate([], json);
                      },
                      onCursorPathTap: (cursorPath) {
                        // re_editor 不支持路径跳转
                      },
                      showReturnToStart:
                          widget.initialPath != null &&
                          widget.pathParts.join('.') !=
                              widget.initialPath!.join('.'),
                      onReturnToStart:
                          widget.initialPath != null &&
                              widget.pathParts.join('.') !=
                                  widget.initialPath!.join('.')
                          ? () {
                              Navigator.pop(context);
                              final startPath = widget.initialPath!;
                              final json = widget.entry.toJson();
                              dynamic currentValue = json;
                              for (final part in startPath) {
                                if (currentValue is Map) {
                                  currentValue = currentValue[part];
                                } else if (currentValue is List) {
                                  int? index = int.tryParse(part);
                                  if (index != null)
                                    currentValue = currentValue[index];
                                }
                              }
                              widget.onNavigate(startPath, currentValue);
                            }
                          : null,
                      validatePath: (newPath) {
                        final json = widget.entry.toJson();
                        dynamic currentValue = json;

                        for (final part in newPath) {
                          if (currentValue is Map) {
                            if (currentValue.containsKey(part)) {
                              currentValue = currentValue[part];
                            } else {
                              return context.t.entry.pathNotFound;
                            }
                          } else if (currentValue is List) {
                            final index = int.tryParse(part);
                            if (index != null &&
                                index >= 0 &&
                                index < currentValue.length) {
                              currentValue = currentValue[index];
                            } else {
                              return context.t.entry.pathNotFound;
                            }
                          } else {
                            return context.t.entry.pathNotFound;
                          }
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildToolbarIconButton(
                    icon: Icons.save,
                    onPressed: _hasSyntaxError ? null : _handleSave,
                    tooltip: context.t.common.save,
                    color: _hasSyntaxError ? null : colorScheme.primary,
                  ),
                  _buildToolbarIconButton(
                    icon: Icons.undo,
                    onPressed: _currentEditPosition > 0 ? _undo : null,
                    tooltip: context.t.common.undo,
                  ),
                  _buildToolbarIconButton(
                    icon: Icons.redo,
                    onPressed: _currentEditPosition < _undoStack.length - 1
                        ? _redo
                        : null,
                    tooltip: context.t.common.redo,
                  ),
                  _buildToolbarIconButton(
                    icon: Icons.format_align_left,
                    onPressed: _formatJson,
                    tooltip: context.t.entry.formatJson,
                  ),
                  _buildToolbarIconButton(
                    icon: _hasSyntaxError
                        ? Icons.error
                        : Icons.check_circle_outline,
                    onPressed: _validateJson,
                    tooltip: _hasSyntaxError
                        ? context.t.entry.syntaxError
                        : context.t.entry.syntaxCheck,
                    color: _hasSyntaxError ? colorScheme.error : null,
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _isFullScreen = !_isFullScreen;
                      });
                    },
                    icon: Icon(
                      _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      size: 20,
                    ),
                    visualDensity: VisualDensity.compact,
                    tooltip: _isFullScreen
                        ? context.t.common.exitFullscreen
                        : context.t.common.fullscreen,
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              if (_hasSyntaxError && _errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    context.t.entry.jsonErrorLabel(error: _errorMessage!),
                    style: TextStyle(color: colorScheme.error, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _hasSyntaxError
                          ? colorScheme.error
                          : colorScheme.outlineVariant.withOpacity(0.5),
                    ),
                  ),
                  child: CodeEditor(
                    controller: _controller,
                    chunkAnalyzer: const DefaultCodeChunkAnalyzer(),
                    style: CodeEditorStyle(
                      fontSize: 14,
                      fontFamily: 'Consolas',
                      backgroundColor: isDark
                          ? colorScheme.primaryContainer.withOpacity(0.05)
                          : colorScheme.primaryContainer.withOpacity(0.08),
                      codeTheme: CodeHighlightTheme(
                        languages: {
                          'json': CodeHighlightThemeMode(mode: langJson)
                        },
                        theme: isDark
                            ? builtThemes['atom-one-dark']!
                            : builtThemes['atom-one-light']!,
                      ),
                    ),
                    wordWrap: true,
                    indicatorBuilder: (context, editingController, chunkController, notifier) {
                      return Row(
                        children: [
                          DefaultCodeLineNumber(
                            controller: editingController,
                            notifier: notifier,
                          ),
                          DefaultCodeChunkIndicator(
                            width: 20,
                            controller: chunkController,
                            notifier: notifier,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToolbarIconButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
    Color? color,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return IconButton(
      onPressed: onPressed,
      icon: Icon(
        icon,
        color:
            color ??
            (onPressed != null ? colorScheme.primary : colorScheme.outline),
        size: 20,
      ),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }
}
