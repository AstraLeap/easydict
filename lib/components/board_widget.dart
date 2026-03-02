import 'package:flutter/material.dart';
import 'dictionary_interaction_scope.dart';
import '../core/utils/toast_utils.dart';
import '../core/utils/dict_typography.dart';

class BoardWidget extends StatefulWidget {
  final Map<String, dynamic> board;
  final Widget Function(Map<String, dynamic> board, List<String> path)
  contentBuilder;
  final List<String> path;
  final void Function(String path, String label)? onElementTap;
  final bool forceNested;
  final bool hideTitle;
  final Map<String, Map<String, double>>? fontScales;
  final String? sourceLanguage;

  const BoardWidget({
    super.key,
    required this.board,
    required this.contentBuilder,
    required this.path,
    this.onElementTap,
    this.forceNested = false,
    this.hideTitle = false,
    this.fontScales,
    this.sourceLanguage,
  });

  @override
  State<BoardWidget> createState() => _BoardWidgetState();
}

class _BoardWidgetState extends State<BoardWidget> {
  bool _isCollapsed = false;

  /// 返回 nested board 标题完整决定的 TextStyle（包含字体族和缩放）
  TextStyle _getBoardTitleStyle(ColorScheme colorScheme) {
    return DictTypography.getScaledStyle(
      DictElementType.boardTitle,
      language: widget.sourceLanguage,
      fontScales: widget.fontScales ?? {},
      color: colorScheme.primary,
    );
  }

  /// 返回顶层 board header 完整决定的 TextStyle
  TextStyle _getBoardHeaderStyle(ColorScheme colorScheme) {
    return DictTypography.getScaledStyle(
      DictElementType.boardTitle,
      language: widget.sourceLanguage,
      fontScales: widget.fontScales ?? {},
      color: colorScheme.onSecondaryContainer,
    );
  }

  void _toggleCollapse() {
    setState(() {
      _isCollapsed = !_isCollapsed;
    });
  }

  void _showPath([Offset? position]) {
    final pathString = widget.path.join('.');

    // 优先尝试右键回调 (如果有位置信息)
    if (position != null) {
      final secondaryCallback = DictionaryInteractionScope.of(
        context,
      )?.onElementSecondaryTap;
      if (secondaryCallback != null) {
        secondaryCallback(pathString, 'Board', context, position);
        return;
      }
    }

    final callback =
        widget.onElementTap ??
        DictionaryInteractionScope.of(context)?.onElementTap;

    if (callback != null) {
      callback(pathString, 'Board');
    } else {
      showToast(context, 'Board: $pathString');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = widget.board['title'] as String? ?? '';

    final boardCount = widget.path.where((p) => p == 'board').length;
    final inDatas = widget.path.contains('datas');
    final isNested = boardCount >= 2 || inDatas || widget.forceNested;

    final contentBoard = Map<String, dynamic>.from(widget.board)
      ..remove('title')
      ..remove('display');

    if (isNested) {
      final boardTitleStyle = _getBoardTitleStyle(colorScheme);
      return Container(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty && !widget.hideTitle)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  title,
                  style: boardTitleStyle,
                ),
              ),
            widget.contentBuilder(contentBoard, widget.path),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _toggleCollapse,
            onLongPress: _showPath,
            borderRadius: _isCollapsed
                ? BorderRadius.circular(12)
                : const BorderRadius.vertical(top: Radius.circular(12)),
            mouseCursor: SystemMouseCursors.click,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
                borderRadius: _isCollapsed
                    ? BorderRadius.circular(12)
                    : const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
              ),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _isCollapsed ? -0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 16,
                      color: colorScheme.onSecondaryContainer.withValues(
                        alpha: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title,
                      style: _getBoardHeaderStyle(colorScheme).copyWith(
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!_isCollapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: widget.contentBuilder(contentBoard, widget.path),
            ),
        ],
      ),
    );
  }
}

class BoardInfo {
  final Map<String, dynamic> board;
  final List<String> path;

  BoardInfo({required this.board, required this.path});
}

List<BoardInfo> findBoards(
  dynamic data, {
  List<String> excludedFields = const [],
}) {
  final boards = <BoardInfo>[];
  _findBoardsRecursive(data, boards, [], excludedFields);
  return boards;
}

void _findBoardsRecursive(
  dynamic data,
  List<BoardInfo> boards,
  List<String> currentPath,
  List<String> excludedFields,
) {
  if (data is Map<String, dynamic>) {
    for (final entry in data.entries) {
      if (excludedFields.contains(entry.key)) continue;

      final value = entry.value;
      final newPath = [...currentPath, entry.key];

      if (value is Map<String, dynamic>) {
        boards.add(BoardInfo(board: value, path: newPath));
        _findBoardsRecursive(value, boards, newPath, excludedFields);
      } else if (value is List<dynamic>) {
        _findBoardsInList(value, boards, newPath, excludedFields);
      }
    }
  } else if (data is List<dynamic>) {
    _findBoardsInList(data, boards, currentPath, excludedFields);
  }
}

void _findBoardsInList(
  List<dynamic> list,
  List<BoardInfo> boards,
  List<String> currentPath,
  List<String> excludedFields,
) {
  for (int i = 0; i < list.length; i++) {
    final item = list[i];
    final itemPath = [...currentPath, '$i'];

    if (item is Map<String, dynamic>) {
      boards.add(BoardInfo(board: item, path: itemPath));
      _findBoardsRecursive(item, boards, itemPath, excludedFields);
    } else if (item is List<dynamic>) {
      _findBoardsInList(item, boards, itemPath, excludedFields);
    }
  }
}
