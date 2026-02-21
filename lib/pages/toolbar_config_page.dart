import 'package:flutter/material.dart';
import '../services/preferences_service.dart';
import '../components/global_scale_wrapper.dart';
import '../services/font_loader_service.dart';
import '../core/utils/toast_utils.dart';

class ToolbarConfigPage extends StatefulWidget {
  const ToolbarConfigPage({super.key});

  @override
  State<ToolbarConfigPage> createState() => _ToolbarConfigPageState();
}

class _ToolbarConfigPageState extends State<ToolbarConfigPage> {
  final _preferencesService = PreferencesService();
  List<String> _allActions = [];
  int _dividerIndex = 4;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final (toolbarActions, overflowActions) = await _preferencesService
        .getToolbarAndOverflowActions();
    setState(() {
      _allActions = [...toolbarActions, ...overflowActions];
      _dividerIndex = toolbarActions.length;
      _isLoading = false;
    });
  }

  String _getActionLabel(String action) {
    return PreferencesService.getActionLabel(action);
  }

  IconData _getActionIcon(String action) {
    return PreferencesService.getActionIcon(action);
  }

  void _saveActions() {
    final toolbarActions = _allActions.sublist(0, _dividerIndex);
    final overflowActions = _allActions.sublist(_dividerIndex);
    _preferencesService.setToolbarAndOverflowActions(
      toolbarActions,
      overflowActions,
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    final oldIsInToolbar = oldIndex < _dividerIndex;
    final oldActualIndex = oldIndex > _dividerIndex ? oldIndex - 1 : oldIndex;

    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    final newIsInToolbar = newIndex < _dividerIndex;
    final newActualIndex = newIndex > _dividerIndex ? newIndex - 1 : newIndex;

    final movingToToolbar = !oldIsInToolbar && newIsInToolbar;

    if (movingToToolbar &&
        _dividerIndex >= PreferencesService.maxToolbarItems) {
      _showMaxItemsError();
      return;
    }

    setState(() {
      final item = _allActions.removeAt(oldActualIndex);
      _allActions.insert(newActualIndex, item);

      if (oldIsInToolbar && !newIsInToolbar) {
        _dividerIndex -= 1;
      } else if (!oldIsInToolbar && newIsInToolbar) {
        _dividerIndex += 1;
      }
    });
    _saveActions();
  }

  void _onDividerReorder(int newIndex) {
    if (newIndex > _dividerIndex) {
      newIndex -= 1;
    }

    if (newIndex > PreferencesService.maxToolbarItems) {
      _showMaxItemsError();
      return;
    }

    setState(() {
      _dividerIndex = newIndex;
    });
    _saveActions();
  }

  void _showMaxItemsError() {
    showToast(context, '工具栏最多只能有 ${PreferencesService.maxToolbarItems} 个功能');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final contentScale = FontLoaderService().getDictionaryContentScale();

    return Scaffold(
      appBar: AppBar(title: const Text('底部工具栏设置'), centerTitle: true),
      body: PageScaleWrapper(
        scale: contentScale,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildPreviewCard(colorScheme),
                  const SizedBox(height: 16),
                  _buildExplanationCard(colorScheme),
                  const SizedBox(height: 16),
                  _buildActionsList(colorScheme),
                ],
              ),
      ),
    );
  }

  Widget _buildPreviewCard(ColorScheme colorScheme) {
    final toolbarActions = _allActions.sublist(0, _dividerIndex);
    final overflowActions = _allActions.sublist(_dividerIndex);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.preview, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '预览',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ...toolbarActions.map(
                    (action) => _buildPreviewButton(action, colorScheme),
                  ),
                  if (overflowActions.isNotEmpty)
                    _buildOverflowPreviewButton(overflowActions, colorScheme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewButton(String action, ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            _getActionIcon(action),
            size: 20,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _getActionLabel(action),
          style: TextStyle(fontSize: 10, color: colorScheme.onSurface),
        ),
      ],
    );
  }

  Widget _buildOverflowPreviewButton(
    List<String> actions,
    ColorScheme colorScheme,
  ) {
    return PopupMenuButton<String>(
      onSelected: (_) {},
      icon: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.more_horiz,
              size: 20,
              color: colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '更多',
            style: TextStyle(fontSize: 10, color: colorScheme.onSurface),
          ),
        ],
      ),
      itemBuilder: (context) => actions
          .map(
            (action) => PopupMenuItem(
              value: action,
              child: Row(
                children: [
                  Icon(_getActionIcon(action), size: 20),
                  const SizedBox(width: 12),
                  Text(_getActionLabel(action)),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildExplanationCard(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '说明',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '• 分割线以上的功能直接显示在底部工具栏',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '• 分割线以下的功能折叠到"更多"菜单中',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '• 拖动功能或分割线可调整位置，工具栏最多 ${PreferencesService.maxToolbarItems} 个',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsList(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.reorder, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  '功能列表 (工具栏: $_dividerIndex/${PreferencesService.maxToolbarItems})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _allActions.length + 1,
            onReorder: (oldIndex, newIndex) {
              if (oldIndex == _dividerIndex) {
                _onDividerReorder(newIndex);
              } else {
                _onReorder(oldIndex, newIndex);
              }
            },
            itemBuilder: (context, index) {
              if (index == _dividerIndex) {
                return _buildDividerItem(index, colorScheme);
              }

              final actualIndex = index > _dividerIndex ? index - 1 : index;
              final action = _allActions[actualIndex];
              final isInToolbar = actualIndex < _dividerIndex;

              return _buildActionTile(
                action,
                actualIndex,
                index,
                colorScheme,
                isInToolbar: isInToolbar,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDividerItem(int index, ColorScheme colorScheme) {
    return Container(
      key: const ValueKey('__divider__'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ReorderableDragStartListener(
        index: index,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.drag_handle, color: colorScheme.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: Divider(color: colorScheme.primary)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '分割线 (拖动调整)',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: colorScheme.primary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile(
    String action,
    int actualIndex,
    int listIndex,
    ColorScheme colorScheme, {
    required bool isInToolbar,
  }) {
    return Container(
      key: ValueKey(action),
      color: isInToolbar
          ? colorScheme.primaryContainer.withValues(alpha: 0.1)
          : colorScheme.secondaryContainer.withValues(alpha: 0.1),
      child: ListTile(
        leading: ReorderableDragStartListener(
          index: listIndex,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.drag_handle, color: colorScheme.onSurfaceVariant),
          ),
        ),
        title: Row(
          children: [
            Icon(_getActionIcon(action), size: 20),
            const SizedBox(width: 12),
            Text(_getActionLabel(action)),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isInToolbar
                ? colorScheme.primaryContainer
                : colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            isInToolbar ? '工具栏' : '更多菜单',
            style: TextStyle(
              fontSize: 11,
              color: isInToolbar
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
