import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/utils/toast_utils.dart';
import '../services/font_loader_service.dart';
import '../services/preferences_service.dart';
import '../components/global_scale_wrapper.dart';
import '../i18n/strings.g.dart';

class DisplaySettingsPage extends StatefulWidget {
  final VoidCallback? onBack;

  const DisplaySettingsPage({super.key, this.onBack});

  @override
  State<DisplaySettingsPage> createState() => _DisplaySettingsPageState();
}

class _DisplaySettingsPageState extends State<DisplaySettingsPage> {
  final _preferencesService = PreferencesService();
  String _clickAction = PreferencesService.actionAiTranslate;
  double _dictionaryContentScale = 1.0;
  bool _showHeadwordSyllableByDefault = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final clickAction = await _preferencesService.getClickAction();
    final dictionaryContentScale = FontLoaderService().getDictionaryContentScale();
    final showHeadwordSyllableByDefault =
        await _preferencesService.getShowHeadwordSyllableByDefault();
    setState(() {
      _clickAction = clickAction;
      _dictionaryContentScale = dictionaryContentScale;
      _showHeadwordSyllableByDefault = showHeadwordSyllableByDefault;
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = Scaffold(
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : null,
        title: Text(context.t.settings.displaySettings),
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: _buildBody(),
    );

    final scale = FontLoaderService().getDictionaryContentScale();
    Widget result = content;
    if (scale != 1.0) {
      result = PageScaleWrapper(child: content);
    }

    // 如果有 onBack 回调，使用 PopScope 拦截系统返回
    if (widget.onBack != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, popResult) {
          if (!didPop) {
            widget.onBack!();
          }
        },
        child: result,
      );
    }

    return result;
  }

  Widget _buildBody() {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      children: [
        // 应用语言
        _buildSettingsTile(
          icon: Icons.language_outlined,
          title: context.t.settings.appLanguage,
          subtitle: _getLocaleLabel(context),
          onTap: () => _showLanguageDialog(),
        ),

        // 软件布局缩放
        _buildSettingsTile(
          icon: Icons.zoom_in,
          title: context.t.settings.layoutScale,
          subtitle: '${(_dictionaryContentScale * 100).round()}%',
          onTap: () => _showDictionaryContentScaleDialog(),
        ),

        // 默认显示音节形式
        _buildSwitchTile(
          icon: Icons.text_fields,
          title: context.t.settings.showHeadwordSyllable,
          subtitle: context.t.settings.showHeadwordSyllableSubtitle,
          value: _showHeadwordSyllableByDefault,
          onChanged: (value) async {
            await _preferencesService.setShowHeadwordSyllableByDefault(value);
            setState(() {
              _showHeadwordSyllableByDefault = value;
            });
          },
        ),

        // 点击动作设置
        _buildSettingsTile(
          icon: Icons.touch_app_outlined,
          title: context.t.settings.clickAction,
          subtitle: _getLocalizedActionLabel(context, _clickAction),
          onTap: () => _showClickActionDialog(),
        ),

        // 底部工具栏设置
        _buildSettingsTile(
          icon: Icons.apps_outlined,
          title: context.t.settings.toolbar,
          onTap: () => _showToolbarConfigDialog(),
        ),
      ],
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
      ),
      onTap: () => onChanged(!value),
    );
  }

  String _getLocaleLabel(BuildContext context) {
    final localeProvider = context.read<LocaleProvider>();
    switch (localeProvider.currentOption) {
      case AppLocaleOption.auto:
        return context.t.language.auto;
      case AppLocaleOption.zh:
        return context.t.language.zh;
      case AppLocaleOption.en:
        return context.t.language.en;
    }
  }

  void _showLanguageDialog() {
    final localeProvider = context.read<LocaleProvider>();
    showDialog(
      context: context,
      builder: (ctx) => _LanguagePickerDialog(
        currentOption: localeProvider.currentOption,
        onSelected: (option) {
          localeProvider.setLocaleOption(option);
        },
      ),
    );
  }

  void _showDictionaryContentScaleDialog() async {
    final oldScale = _dictionaryContentScale;
    final contentScale = FontLoaderService().getDictionaryContentScale();
    await showDialog(
      context: context,
      builder: (context) {
        final dialog = _ScaleDialog(
          currentValue: (_dictionaryContentScale * 100).round().toDouble(),
          onSave: (value) async {
            final prefs = PreferencesService();
            await prefs.setDictionaryContentScale(value / 100);
            await FontLoaderService().reloadDictionaryContentScale();
            if (mounted) {
              setState(() {
                _dictionaryContentScale = value / 100;
              });
            }
          },
        );
        if (contentScale == 1.0) return dialog;
        return PageScaleWrapper(scale: contentScale, child: dialog);
      },
    );
    // 如果用户更改了缩放，弹出确认对话框
    if (mounted && (_dictionaryContentScale - oldScale).abs() > 0.001) {
      final newScale = _dictionaryContentScale;
      final confirmed = await _showScaleConfirmationDialog(newScale);
      if (!confirmed) {
        await _preferencesService.setDictionaryContentScale(oldScale);
        await FontLoaderService().reloadDictionaryContentScale();
        if (mounted) {
          setState(() {
            _dictionaryContentScale = oldScale;
          });
        }
      }
    }
  }

  Future<bool> _showScaleConfirmationDialog(double scale) async {
    int countdown = 10;
    bool confirmed = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future.delayed(const Duration(seconds: 1), () {
              if (countdown > 0 && mounted) {
                setState(() => countdown--);
                if (countdown == 0) {
                  Navigator.of(context).pop();
                }
              }
            });

            return AlertDialog(
              title: Text(context.t.settings.scaleDialog.confirmTitle),
              content: Text(
                context.t.settings.scaleDialog.confirmBody(
                  percent: (scale * 100).round(),
                  seconds: countdown,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    confirmed = false;
                    Navigator.of(context).pop();
                  },
                  child: Text(context.t.common.cancel),
                ),
                FilledButton(
                  onPressed: () {
                    confirmed = true;
                    Navigator.of(context).pop();
                  },
                  child: Text(context.t.common.confirm),
                ),
              ],
            );
          },
        );
      },
    );

    return confirmed;
  }

  void _showClickActionDialog() async {
    final currentOrder = await _preferencesService.getClickActionOrder();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => _ClickActionOrderDialog(
        initialOrder: currentOrder,
        onSave: (newOrder) async {
          await _preferencesService.setClickActionOrder(newOrder);
          setState(() {
            _clickAction = newOrder.first;
          });
        },
      ),
    );
  }

  void _showToolbarConfigDialog() {
    showDialog(
      context: context,
      builder: (context) => const _ToolbarConfigDialog(),
    );
  }

  String _getLocalizedActionLabel(BuildContext context, String action) {
    final t = context.t.settings.actionLabel;
    switch (action) {
      case PreferencesService.actionAiTranslate:
        return t.aiTranslate;
      case PreferencesService.actionCopy:
        return t.copy;
      case PreferencesService.actionAskAi:
        return t.askAi;
      case PreferencesService.actionEdit:
        return t.edit;
      case PreferencesService.actionSpeak:
        return t.speak;
      case PreferencesService.actionBack:
        return t.back;
      case PreferencesService.actionSearch:
        return t.search;
      case PreferencesService.actionFavorite:
        return t.favorite;
      case PreferencesService.actionToggleTranslate:
        return t.toggleTranslate;
      case PreferencesService.actionAiHistory:
        return t.aiHistory;
      case PreferencesService.actionResetEntry:
        return t.resetEntry;
      default:
        return action;
    }
  }
}

/// 语言选择对话框
class _LanguagePickerDialog extends StatelessWidget {
  final AppLocaleOption currentOption;
  final ValueChanged<AppLocaleOption> onSelected;

  const _LanguagePickerDialog({
    required this.currentOption,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.t.settings.appLanguage),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioListTile<AppLocaleOption>(
            title: Text(context.t.language.auto),
            value: AppLocaleOption.auto,
            groupValue: currentOption,
            onChanged: (value) {
              Navigator.pop(context);
              if (value != null) onSelected(value);
            },
          ),
          RadioListTile<AppLocaleOption>(
            title: Text(context.t.language.zh),
            value: AppLocaleOption.zh,
            groupValue: currentOption,
            onChanged: (value) {
              Navigator.pop(context);
              if (value != null) onSelected(value);
            },
          ),
          RadioListTile<AppLocaleOption>(
            title: Text(context.t.language.en),
            value: AppLocaleOption.en,
            groupValue: currentOption,
            onChanged: (value) {
              Navigator.pop(context);
              if (value != null) onSelected(value);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.t.common.cancel),
        ),
      ],
    );
  }
}

/// 缩放设置对话框
class _ScaleDialog extends StatefulWidget {
  final double currentValue;
  final Future<void> Function(double value) onSave;

  const _ScaleDialog({
    required this.currentValue,
    required this.onSave,
  });

  @override
  State<_ScaleDialog> createState() => _ScaleDialogState();
}

class _ScaleDialogState extends State<_ScaleDialog> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.currentValue;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.t.settings.scaleDialog.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(context.t.settings.scaleDialog.subtitle),
          const SizedBox(height: 24),
          Slider(
            value: _value,
            min: 50,
            max: 200,
            divisions: 15,
            label: '${_value.round()}%',
            onChanged: (value) => setState(() => _value = value),
          ),
          const SizedBox(height: 8),
          Text(
            '${_value.round()}%',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.t.common.cancel),
        ),
        FilledButton(
          onPressed: () async {
            await widget.onSave(_value);
            if (mounted) Navigator.pop(context);
          },
          child: Text(context.t.common.confirm),
        ),
      ],
    );
  }
}

/// 点击动作排序对话框
class _ClickActionOrderDialog extends StatefulWidget {
  final List<String> initialOrder;
  final Future<void> Function(List<String> order) onSave;

  const _ClickActionOrderDialog({
    required this.initialOrder,
    required this.onSave,
  });

  @override
  State<_ClickActionOrderDialog> createState() => _ClickActionOrderDialogState();
}

class _ClickActionOrderDialogState extends State<_ClickActionOrderDialog> {
  late List<String> _order;

  @override
  void initState() {
    super.initState();
    _order = List.from(widget.initialOrder);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t.settings;
    return AlertDialog(
      title: Text(t.clickActionDialog.title),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.clickActionDialog.hint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              itemCount: _order.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = _order.removeAt(oldIndex);
                  _order.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final action = _order[index];
                return ListTile(
                  key: ValueKey(action),
                  leading: ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle),
                  ),
                  title: Text(_getLocalizedActionLabel(context, action)),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.t.common.cancel),
        ),
        FilledButton(
          onPressed: () async {
            await widget.onSave(_order);
            if (mounted) Navigator.pop(context);
          },
          child: Text(context.t.common.confirm),
        ),
      ],
    );
  }

  String _getLocalizedActionLabel(BuildContext context, String action) {
    final t = context.t.settings.actionLabel;
    switch (action) {
      case PreferencesService.actionAiTranslate:
        return t.aiTranslate;
      case PreferencesService.actionCopy:
        return t.copy;
      case PreferencesService.actionAskAi:
        return t.askAi;
      case PreferencesService.actionEdit:
        return t.edit;
      case PreferencesService.actionSpeak:
        return t.speak;
      case PreferencesService.actionBack:
        return t.back;
      case PreferencesService.actionSearch:
        return t.search;
      case PreferencesService.actionFavorite:
        return t.favorite;
      case PreferencesService.actionToggleTranslate:
        return t.toggleTranslate;
      case PreferencesService.actionAiHistory:
        return t.aiHistory;
      case PreferencesService.actionResetEntry:
        return t.resetEntry;
      default:
        return action;
    }
  }
}

/// 工具栏配置对话框
class _ToolbarConfigDialog extends StatefulWidget {
  const _ToolbarConfigDialog();

  @override
  State<_ToolbarConfigDialog> createState() => _ToolbarConfigDialogState();
}

class _ToolbarConfigDialogState extends State<_ToolbarConfigDialog> {
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
    final (toolbarActions, overflowActions) =
        await _preferencesService.getToolbarAndOverflowActions();
    setState(() {
      _allActions = [...toolbarActions, ...overflowActions];
      _dividerIndex = toolbarActions.length;
      _isLoading = false;
    });
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
    // Calculate actual indices in _allActions (visual list includes divider)
    final oldIsInToolbar = oldIndex < _dividerIndex;
    final oldActualIndex = oldIndex >= _dividerIndex ? oldIndex - 1 : oldIndex;
    if (newIndex > oldIndex) newIndex -= 1;
    final newIsInToolbar = newIndex < _dividerIndex;
    final newActualIndex = newIndex >= _dividerIndex ? newIndex - 1 : newIndex;
    if (!oldIsInToolbar &&
        newIsInToolbar &&
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
    if (newIndex > _dividerIndex) newIndex -= 1;
    if (newIndex > PreferencesService.maxToolbarItems) {
      _showMaxItemsError();
      return;
    }
    setState(() => _dividerIndex = newIndex);
    _saveActions();
  }

  void _showMaxItemsError() {
    showToast(
      context,
      context.t.settings.toolbarDialog.maxItemsError(
        max: PreferencesService.maxToolbarItems,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final contentScale = FontLoaderService().getDictionaryContentScale();

    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final dialog = AlertDialog(
      title: Text(context.t.settings.toolbarDialog.title),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SizedBox(
        width: 400,
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t.settings.toolbarDialog.hint(
                max: PreferencesService.maxToolbarItems,
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                padding: EdgeInsets.zero,
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
                  return _buildActionTile(
                    action,
                    actualIndex,
                    index,
                    colorScheme,
                    isInToolbar: actualIndex < _dividerIndex,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.t.common.done),
        ),
      ],
    );

    if (contentScale == 1.0) return dialog;
    return PageScaleWrapper(scale: contentScale, child: dialog);
  }

  Widget _buildDividerItem(int index, ColorScheme colorScheme) {
    return ReorderableDragStartListener(
      index: index,
      key: ValueKey('__divider__$index'),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.drag_handle, color: colorScheme.outline, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.t.settings.toolbarDialog.dividerLabel,
                style: TextStyle(
                  color: colorScheme.outline,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ),
          ],
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
    return ReorderableDragStartListener(
      index: listIndex,
      key: ValueKey('action_$action'),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: isInToolbar
              ? colorScheme.primaryContainer.withValues(alpha: 0.3)
              : colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          minLeadingWidth: 24,
          leading: Icon(
            Icons.drag_handle,
            color: colorScheme.onSurfaceVariant,
            size: 18,
          ),
          title: Icon(PreferencesService.getActionIcon(action), size: 20),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isInToolbar
                  ? colorScheme.primaryContainer
                  : colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              isInToolbar
                  ? context.t.settings.toolbarDialog.toolbar
                  : context.t.settings.toolbarDialog.overflow,
              style: TextStyle(
                fontSize: 10,
                color: isInToolbar
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
