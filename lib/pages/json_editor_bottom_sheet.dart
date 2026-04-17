import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/styles/all.dart' show builtThemes;
import '../data/database_service.dart';
import '../core/utils/scroll_safe_utils.dart';
import '../core/utils/toast_utils.dart';
import '../i18n/strings.g.dart';
import '../widgets/path_navigator.dart';
import '../widgets/re_editor_selection_toolbar.dart';

enum _UnsavedCloseAction { save, discard }

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
  SelectionToolbarController? _toolbarController;
  late String _savedText;
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  int _currentEditPosition = 0;
  bool _hasSyntaxError = false;
  String? _errorMessage;
  bool _isFullScreen = false;
  final List<String> _currentPath = [];
  late final bool Function(KeyEvent event) _keyboardSaveHandler;

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController.fromText(widget.initialText);
    _toolbarController = buildReEditorSelectionToolbarController();
    _keyboardSaveHandler = _handleGlobalKeyEvent;
    HardwareKeyboard.instance.addHandler(_keyboardSaveHandler);
    _savedText = widget.initialText;
    _undoStack.add(widget.initialText);
    _controller.addListener(_trackChanges);
    _validateJson();
  }

  bool _isSaveShortcut(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return false;
    }
    final isSKey = event.logicalKey == LogicalKeyboardKey.keyS;
    final keyboard = HardwareKeyboard.instance;
    final hasModifier = keyboard.isControlPressed || keyboard.isMetaPressed;
    return isSKey && hasModifier;
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (!_isSaveShortcut(event)) {
      return false;
    }

    _save();
    return true;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_keyboardSaveHandler);
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

  bool get _hasUnsavedChanges => _controller.text != _savedText;

  Future<bool> _save({bool closeAfterSave = false}) async {
    if (_hasSyntaxError) {
      showToast(
        context,
        context.t.entry.jsonSyntaxError(error: _errorMessage ?? ''),
      );
      return false;
    }

    try {
      final content = _controller.text;
      final newValue = jsonDecode(content);
      await widget.onSave(newValue);

      if (!mounted) {
        return true;
      }

      setState(() {
        _savedText = content;
      });

      if (closeAfterSave) {
        Navigator.pop(context);
      }
      return true;
    } catch (e) {
      showToast(context, context.t.entry.saveFailed(error: e));
      return false;
    }
  }

  Future<_UnsavedCloseAction?> _showUnsavedCloseDialog() {
    return showDialog<_UnsavedCloseAction>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Expanded(child: Text(context.t.common.unsavedChangesTitle)),
              IconButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(Icons.close),
                tooltip: context.t.common.continueEditing,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          content: Text(context.t.common.unsavedChangesMessage),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_UnsavedCloseAction.discard),
              child: Text(context.t.common.discard),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_UnsavedCloseAction.save),
              child: Text(context.t.common.save),
            ),
          ],
        );
      },
    );
  }

  Future<void> _attemptClose() async {
    if (!_hasUnsavedChanges) {
      if (mounted) {
        Navigator.pop(context);
      }
      return;
    }

    final action = await _showUnsavedCloseDialog();
    if (!mounted) return;

    if (action == _UnsavedCloseAction.save) {
      await _save(closeAfterSave: true);
      return;
    }

    if (action == _UnsavedCloseAction.discard) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final notePreviewBackground = colorScheme.surface;
    // 使用从父级传入的状态栏高度，因为底部弹出层的 context 中 viewPadding.top 为 0
    final statusBarHeight = widget.statusBarHeight;
    final screenSize = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = Theme.of(context).platform.isDesktopLike;

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _attemptClose();
      },
      child: Shortcuts(
        shortcuts: {
          // Ctrl+Z / Cmd+Z 撤销
          LogicalKeySet(
            Platform.isMacOS
                ? LogicalKeyboardKey.meta
                : LogicalKeyboardKey.control,
            LogicalKeyboardKey.keyZ,
          ): const _UndoIntent(),
          // Ctrl+Shift+Z / Cmd+Shift+Z 重做
          LogicalKeySet(
            Platform.isMacOS
                ? LogicalKeyboardKey.meta
                : LogicalKeyboardKey.control,
            LogicalKeyboardKey.shift,
            LogicalKeyboardKey.keyZ,
          ): const _RedoIntent(),
          // Ctrl+Y / Cmd+Y 重做 (备选)
          LogicalKeySet(
            Platform.isMacOS
                ? LogicalKeyboardKey.meta
                : LogicalKeyboardKey.control,
            LogicalKeyboardKey.keyY,
          ): const _RedoIntent(),
          // Ctrl+S / Cmd+S 保存
          LogicalKeySet(
            Platform.isMacOS
                ? LogicalKeyboardKey.meta
                : LogicalKeyboardKey.control,
            LogicalKeyboardKey.keyS,
          ): const _SaveIntent(),
        },
        child: Actions(
          actions: {
            _UndoIntent: CallbackAction<_UndoIntent>(
              onInvoke: (_) {
                _undo();
                return null;
              },
            ),
            _RedoIntent: CallbackAction<_RedoIntent>(
              onInvoke: (_) {
                _redo();
                return null;
              },
            ),
            _SaveIntent: CallbackAction<_SaveIntent>(
              onInvoke: (_) {
                _save();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            canRequestFocus: true,
            child: DraggableScrollableSheet(
              initialChildSize: _isFullScreen ? 1.0 : 0.7,
              minChildSize: _isFullScreen ? 1.0 : 0.5,
              maxChildSize: _isFullScreen
                  ? 1.0
                  : availableHeightRatio(
                      totalHeight: screenSize.height,
                      reservedTop: topInsetWithMargin(statusBarHeight),
                    ),
              shouldCloseOnMinExtent: false,
              expand: false,
              builder: (context, scrollController) {
                return Container(
                  width: _isFullScreen ? screenSize.width : null,
                  padding: EdgeInsets.only(
                    top: _isFullScreen
                        ? topInsetWithMargin(statusBarHeight)
                        : 16,
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
                              pathParts: widget.pathParts,
                              cursorPath: _currentPath.isNotEmpty
                                  ? _currentPath
                                  : null,
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
                                      widget.onNavigate(
                                        startPath,
                                        currentValue,
                                      );
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
                            icon: Icons.save_outlined,
                            onPressed: () => _save(),
                            tooltip: context.t.common.save,
                          ),
                          _buildToolbarIconButton(
                            icon: Icons.undo,
                            onPressed: _currentEditPosition > 0 ? _undo : null,
                            tooltip: context.t.common.undo,
                          ),
                          _buildToolbarIconButton(
                            icon: Icons.redo,
                            onPressed:
                                _currentEditPosition < _undoStack.length - 1
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
                              _isFullScreen
                                  ? Icons.fullscreen_exit
                                  : Icons.fullscreen,
                              size: 20,
                            ),
                            tooltip: _isFullScreen
                                ? context.t.common.exitFullscreen
                                : context.t.common.fullscreen,
                            constraints: const BoxConstraints(
                              minWidth: 38,
                              minHeight: 38,
                            ),
                            padding: EdgeInsets.zero,
                            visualDensity: isDesktop
                                ? VisualDensity.standard
                                : VisualDensity.compact,
                          ),
                          IconButton(
                            onPressed: _attemptClose,
                            icon: const Icon(Icons.close, size: 20),
                            constraints: const BoxConstraints(
                              minWidth: 38,
                              minHeight: 38,
                            ),
                            padding: EdgeInsets.zero,
                            visualDensity: isDesktop
                                ? VisualDensity.standard
                                : VisualDensity.compact,
                          ),
                        ],
                      ),
                      if (_hasSyntaxError && _errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            context.t.entry.jsonErrorLabel(
                              error: _errorMessage!,
                            ),
                            style: TextStyle(
                              color: colorScheme.error,
                              fontSize: 12,
                            ),
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
                            toolbarController: _toolbarController,
                            chunkAnalyzer: const DefaultCodeChunkAnalyzer(),
                            style: CodeEditorStyle(
                              fontSize: 14,
                              fontFamily: 'Consolas',
                              backgroundColor: notePreviewBackground,
                              codeTheme: CodeHighlightTheme(
                                languages: {
                                  'json': CodeHighlightThemeMode(
                                    mode: langJson,
                                  ),
                                },
                                theme: isDark
                                    ? builtThemes['atom-one-dark']!
                                    : builtThemes['atom-one-light']!,
                              ),
                            ),
                            wordWrap: true,
                            indicatorBuilder:
                                (
                                  context,
                                  editingController,
                                  chunkController,
                                  notifier,
                                ) {
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbarIconButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
    Color? color,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop = Theme.of(context).platform.isDesktopLike;

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
      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
      visualDensity: isDesktop ? VisualDensity.standard : VisualDensity.compact,
    );
  }
}

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}

extension on TargetPlatform {
  bool get isDesktopLike =>
      this == TargetPlatform.windows ||
      this == TargetPlatform.macOS ||
      this == TargetPlatform.linux;
}
