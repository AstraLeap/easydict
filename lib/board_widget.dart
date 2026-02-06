import 'package:flutter/material.dart';
import 'components/dictionary_interaction_scope.dart';
import 'logger.dart';
import 'utils/toast_utils.dart';

class BoardWidget extends StatefulWidget {
  final Map<String, dynamic> board;
  final Widget Function(Map<String, dynamic> board, List<String> path)
  contentBuilder;
  final List<String> path;
  final void Function(String path, String label)? onElementTap;

  const BoardWidget({
    super.key,
    required this.board,
    required this.contentBuilder,
    required this.path,
    this.onElementTap,
  });

  @override
  State<BoardWidget> createState() => _BoardWidgetState();
}

class _BoardWidgetState extends State<BoardWidget> {
  bool _isCollapsed = false;

  void _toggleCollapse() {
    setState(() {
      _isCollapsed = !_isCollapsed;
    });
  }

  void _showPath([Offset? position]) {
    final pathString = widget.path.join('.');
    Logger.d(
      'Board interaction: path=$pathString, position=$position',
      tag: 'BoardWidget',
    );

    // 优先尝试右键回调 (如果有位置信息)
    if (position != null) {
      final secondaryCallback = DictionaryInteractionScope.of(
        context,
      )?.onElementSecondaryTap;
      if (secondaryCallback != null) {
        Logger.d('Triggering secondary tap callback', tag: 'BoardWidget');
        secondaryCallback(pathString, 'Board', context, position);
        return;
      } else {
        Logger.d(
          'No secondary tap callback found in scope',
          tag: 'BoardWidget',
        );
      }
    }

    final callback =
        widget.onElementTap ??
        DictionaryInteractionScope.of(context)?.onElementTap;

    if (callback != null) {
      Logger.d('Triggering primary tap callback', tag: 'BoardWidget');
      callback(pathString, 'Board');
    } else {
      Logger.d('Showing toast fallback', tag: 'BoardWidget');
      showToast(context, 'Board: $pathString');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Logger.d('Rendering board at path: ${widget.path.join('/')}');

    final colorScheme = Theme.of(context).colorScheme;
    final title = widget.board['title'] as String? ?? '';

    // 计算路径中包含多少个 "board"
    final boardCount = widget.path.where((p) => p == 'board').length;
    final isNested = boardCount >= 2;

    final contentBoard = Map<String, dynamic>.from(widget.board)
      ..remove('title')
      ..remove('display');

    // 如果是嵌套的 board（路径中包含两个或更多 "board"），不设置样式，也不可折叠
    if (isNested) {
      return widget.contentBuilder(contentBoard, widget.path);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Listener(
            onPointerDown: (event) {
              if (event.buttons == 2) {
                _showPath();
              }
            },
            child: GestureDetector(
              onTap: _toggleCollapse,
              onLongPress: _showPath,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(7),
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
                        size: 20,
                        color: colorScheme.onSecondaryContainer.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSecondaryContainer,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!_isCollapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
