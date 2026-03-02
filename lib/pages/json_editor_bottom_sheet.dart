import 'dart:convert';
import 'package:flutter/material.dart';
import '../data/database_service.dart';
import '../core/utils/toast_utils.dart';

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
  });

  @override
  State<JsonEditorBottomSheet> createState() => _JsonEditorBottomSheetState();
}

class _JsonEditorBottomSheetState extends State<JsonEditorBottomSheet> {
  late TextEditingController _controller;
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  int _currentEditPosition = 0;
  bool _hasSyntaxError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _undoStack.add(widget.initialText);
    _controller.addListener(_trackChanges);
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
        _errorMessage = '格式化失败: $e';
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
      showToast(context, 'JSON 格式错误: $_errorMessage');
      return;
    }

    try {
      final newValue = jsonDecode(_controller.text);
      await widget.onSave(newValue);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      showToast(context, '保存失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildPathNavigator(
                  context,
                  widget.pathParts,
                  (newPathParts) {
                    Navigator.pop(context);
                    final json = widget.entry.toJson();
                    dynamic currentValue = json;
                    for (final part in newPathParts) {
                      if (currentValue is Map) {
                        currentValue = currentValue[part];
                      } else if (currentValue is List) {
                        int? index = int.tryParse(part);
                        if (index != null) currentValue = currentValue[index];
                      }
                    }
                    widget.onNavigate(newPathParts, currentValue);
                  },
                  onHomeTap: () {
                    Navigator.pop(context);
                    final json = widget.entry.toJson();
                    widget.onNavigate([], json);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (widget.initialPath != null &&
                  widget.pathParts.join('.') != widget.initialPath!.join('.'))
                _buildToolbarIconButton(
                  icon: Icons.first_page,
                  onPressed: () {
                    Navigator.pop(context);
                    final startPath = widget.initialPath!;
                    final json = widget.entry.toJson();
                    dynamic currentValue = json;
                    for (final part in startPath) {
                      if (currentValue is Map) {
                        currentValue = currentValue[part];
                      } else if (currentValue is List) {
                        int? index = int.tryParse(part);
                        if (index != null) currentValue = currentValue[index];
                      }
                    }
                    widget.onNavigate(startPath, currentValue);
                  },
                  tooltip: '返回初始路径',
                  color: colorScheme.primary,
                ),
              _buildToolbarIconButton(
                icon: Icons.undo,
                onPressed: _currentEditPosition > 0 ? _undo : null,
                tooltip: '撤销',
              ),
              _buildToolbarIconButton(
                icon: Icons.redo,
                onPressed: _currentEditPosition < _undoStack.length - 1
                    ? _redo
                    : null,
                tooltip: '重做',
              ),
              _buildToolbarIconButton(
                icon: Icons.format_align_left,
                onPressed: _formatJson,
                tooltip: '格式化',
              ),
              _buildToolbarIconButton(
                icon: _hasSyntaxError
                    ? Icons.error
                    : Icons.check_circle_outline,
                onPressed: _validateJson,
                tooltip: _hasSyntaxError ? '语法错误' : '语法检测',
                color: _hasSyntaxError ? colorScheme.error : null,
              ),
            ],
          ),
          if (_hasSyntaxError && _errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '错误: $_errorMessage',
                style: TextStyle(color: colorScheme.error, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: TextField(
              controller: _controller,
              maxLines: 10,
              minLines: 3,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: '输入 JSON 内容',
                errorText: _hasSyntaxError ? ' ' : null,
              ),
              style: const TextStyle(fontFamily: 'Consolas'),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _hasSyntaxError ? null : _handleSave,
                child: const Text('保存'),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
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

  Widget _buildPathNavigator(
    BuildContext context,
    List<String> pathParts,
    Function(List<String>) onPathSelected, {
    VoidCallback? onHomeTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (onHomeTap != null)
          InkWell(
            onTap: onHomeTap,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(Icons.home, size: 18, color: colorScheme.primary),
            ),
          ),
        ...pathParts.asMap().entries.expand((entry) {
          final index = entry.key;
          final part = entry.value;
          final currentPath = pathParts.sublist(0, index + 1);

          final widgets = <Widget>[];

          if (index > 0) {
            widgets.add(
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '>',
                  style: TextStyle(
                    color: colorScheme.outline,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }

          final isLast = index == pathParts.length - 1;
          widgets.add(
            InkWell(
              onTap: isLast ? null : () => onPathSelected(currentPath),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  part,
                  style: TextStyle(
                    color: isLast
                        ? colorScheme.primary
                        : colorScheme.primary.withValues(alpha: 0.8),
                    fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );

          return widgets;
        }),
      ],
    );
  }
}
