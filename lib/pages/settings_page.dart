import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme_provider.dart';
import '../core/utils/toast_utils.dart';
import '../data/services/ai_chat_database_service.dart';
import '../services/dict_update_check_service.dart';
import '../services/english_db_service.dart';
import '../services/font_loader_service.dart';
import '../services/preferences_service.dart';
import '../components/global_scale_wrapper.dart';
import 'cloud_service_page.dart';
import 'dictionary_manager_page.dart';
import 'font_config_page.dart';
import 'help_page.dart';
import 'llm_config_page.dart';
import 'theme_color_page.dart';

// ─────────────────────────────────────────────
// SettingsPage
// ─────────────────────────────────────────────

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.contentScaleNotifier});

  /// 通知父级刷新内容缩放比例（从字体配置页返回时使用）
  final ValueNotifier<double>? contentScaleNotifier;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _preferencesService = PreferencesService();
  String _clickAction = PreferencesService.actionAiTranslate;
  bool _isLoading = true;
  double _dictionaryContentScale = 1.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    FontLoaderService().reloadDictionaryContentScale();
  }

  Future<void> _loadData() async {
    final clickAction = await _preferencesService.getClickAction();
    final dictionaryContentScale = FontLoaderService()
        .getDictionaryContentScale();
    setState(() {
      _clickAction = clickAction;
      _dictionaryContentScale = dictionaryContentScale;
      _isLoading = false;
    });
  }

  String _getClickActionLabel(String action) {
    final label = PreferencesService.getActionLabel(action);
    return label == action ? '切换翻译' : label;
  }

  String _getThemeColorName(Color color) {
    if (color.toARGB32() == ThemeProvider.systemAccentColor.toARGB32()) {
      return '系统主题色';
    }
    final colorNames = {
      Colors.blue.toARGB32(): '蓝色',
      Colors.indigo.toARGB32(): '靛蓝色',
      Colors.purple.toARGB32(): '紫色',
      Colors.deepPurple.toARGB32(): '深紫色',
      Colors.pink.toARGB32(): '粉色',
      Colors.red.toARGB32(): '红色',
      Colors.deepOrange.toARGB32(): '深橙色',
      Colors.orange.toARGB32(): '橙色',
      Colors.amber.toARGB32(): '琥珀色',
      Colors.yellow.toARGB32(): '黄色',
      Colors.lime.toARGB32(): '青柠色',
      Colors.lightGreen.toARGB32(): '浅绿色',
      Colors.green.toARGB32(): '绿色',
      Colors.teal.toARGB32(): '青色',
      Colors.cyan.toARGB32(): '天蓝色',
    };
    return colorNames[color.toARGB32()] ?? '自定义';
  }

  void _showClickActionDialog() async {
    final currentOrder = await _preferencesService.getClickActionOrder();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) {
        return _ClickActionOrderDialog(
          initialOrder: currentOrder,
          onSave: (newOrder) async {
            await _preferencesService.setClickActionOrder(newOrder);
            setState(() {
              _clickAction = newOrder.first;
            });
          },
        );
      },
    );
  }

  void _showToolbarConfigDialog() {
    showDialog(
      context: context,
      builder: (context) => const _ToolbarConfigDialog(),
    );
  }

  void _showDictionaryContentScaleDialog() async {
    final contentScale = FontLoaderService().getDictionaryContentScale();
    await showDialog(
      context: context,
      builder: (context) {
        final dialog = ScaleDialogWidget(
          title: '软件布局缩放',
          subtitle: '调整词典内容显示的整体缩放比例',
          currentValue: (_dictionaryContentScale * 100).round().toDouble(),
          min: 50,
          max: 200,
          divisions: 5,
          unit: '%',
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
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final updateCheckService = context.watch<DictUpdateCheckService>();
    final colorScheme = Theme.of(context).colorScheme;
    final contentScale = FontLoaderService().getDictionaryContentScale();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: PageScaleWrapper(
          scale: contentScale,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.only(left: 16, right: 16, top: 12),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // 云服务组
                    _buildSettingsGroup(
                      context,
                      children: [
                        _buildSettingsTile(
                          context,
                          title: '云服务',
                          icon: Icons.cloud_outlined,
                          iconColor: colorScheme.primary,
                          showArrow: true,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const CloudServicePage(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 核心功能组
                    _buildSettingsGroup(
                      context,
                      children: [
                        _buildSettingsTile(
                          context,
                          title: '词典管理',
                          icon: Icons.folder_outlined,
                          iconColor: colorScheme.primary,
                          showArrow: true,
                          badgeCount: updateCheckService.updatableCount,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const DictionaryManagerPage(),
                              ),
                            );
                          },
                        ),
                        _buildSettingsTile(
                          context,
                          title: 'AI 配置',
                          icon: Icons.auto_awesome,
                          iconColor: colorScheme.primary,
                          showArrow: true,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const LLMConfigPage(),
                              ),
                            );
                          },
                        ),
                        _buildSettingsTile(
                          context,
                          title: '字体配置',
                          icon: Icons.font_download_outlined,
                          iconColor: colorScheme.primary,
                          showArrow: true,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const FontConfigPage(),
                              ),
                            );
                            // 从字体配置页返回后，刷新父级的缩放值
                            if (mounted) {
                              final newScale = FontLoaderService()
                                  .getDictionaryContentScale();
                              widget.contentScaleNotifier?.value = newScale;
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 外观设置组
                    _buildSettingsGroup(
                      context,
                      children: [
                        _buildSettingsTile(
                          context,
                          title: '主题设置',
                          icon: Icons.palette_outlined,
                          iconColor: colorScheme.primary,
                          showArrow: true,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ThemeColorPage(),
                              ),
                            );
                          },
                        ),
                        _buildSettingsTile(
                          context,
                          title: '软件布局缩放',
                          icon: Icons.zoom_in,
                          iconColor: colorScheme.primary,
                          onTap: _showDictionaryContentScaleDialog,
                        ),
                        if (!_isLoading)
                          _buildSettingsTile(
                            context,
                            title: '点击动作设置',
                            icon: Icons.touch_app_outlined,
                            iconColor: colorScheme.primary,
                            onTap: _showClickActionDialog,
                          ),
                        _buildSettingsTile(
                          context,
                          title: '底部工具栏设置',
                          icon: Icons.apps,
                          iconColor: colorScheme.primary,
                          onTap: _showToolbarConfigDialog,
                        ),
                        _buildSettingsTile(
                          context,
                          title: '其他设置',
                          icon: Icons.settings_suggest_outlined,
                          iconColor: colorScheme.primary,
                          showArrow: true,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const MiscSettingsPage(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 帮助与支持组
                    _buildSettingsGroup(
                      context,
                      children: [
                        _buildSettingsTile(
                          context,
                          title: '帮助与反馈',
                          icon: Icons.help_outline,
                          iconColor: colorScheme.primary,
                          showArrow: true,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const HelpPage(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 52),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsGroup(
    BuildContext context, {
    required List<Widget> children,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Column(
        children: _addDividers(
          children,
          colorScheme.outlineVariant.withOpacity(0.3),
        ),
      ),
    );
  }

  List<Widget> _addDividers(List<Widget> children, Color dividerColor) {
    final result = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      result.add(children[i]);
      if (i < children.length - 1) {
        result.add(Divider(height: 1, indent: 52, color: dividerColor));
      }
    }
    return result;
  }

  Widget _buildSettingsTile(
    BuildContext context, {
    required String title,
    String? subtitle,
    required IconData icon,
    Color? iconColor,
    bool showArrow = false,
    bool isExternal = false,
    int? badgeCount,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveIconColor = iconColor ?? colorScheme.onSurfaceVariant;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Icon(icon, color: effectiveIconColor, size: 24),
      title: Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badgeCount != null && badgeCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: colorScheme.error,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$badgeCount',
                style: TextStyle(
                  color: colorScheme.onError,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (showArrow)
            Icon(Icons.chevron_right, color: colorScheme.outline, size: 20)
          else if (isExternal)
            Icon(Icons.open_in_new, color: colorScheme.outline, size: 18),
        ],
      ),
      onTap: onTap,
    );
  }
}

// ─────────────────────────────────────────────
// MiscSettingsPage
// ─────────────────────────────────────────────

/// 其它设置页面
class MiscSettingsPage extends StatefulWidget {
  const MiscSettingsPage({super.key});

  @override
  State<MiscSettingsPage> createState() => _MiscSettingsPageState();
}

class _MiscSettingsPageState extends State<MiscSettingsPage> {
  final double _contentScale = FontLoaderService().getDictionaryContentScale();
  final _chatService = AiChatDatabaseService();
  final _englishDbService = EnglishDbService();
  final _preferencesService = PreferencesService();
  int _recordCount = 0;
  int _autoCleanupDays = 0;
  bool _neverAskAgain = false;
  bool _autoCheckDictUpdate = true;
  bool _englishDbExists = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final count = await _chatService.getRecordCount();
    final days = await _chatService.getAutoCleanupDays();
    final neverAsk = await _englishDbService.getNeverAskAgain();
    final autoCheck = await _preferencesService.getAutoCheckDictUpdate();
    final englishDbExists = await _englishDbService.dbExists();
    setState(() {
      _recordCount = count;
      _autoCleanupDays = days;
      _neverAskAgain = neverAsk;
      _autoCheckDictUpdate = autoCheck;
      _englishDbExists = englishDbExists;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('其它设置'),
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : PageScaleWrapper(
              scale: _contentScale,
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _buildSectionTitle(context, 'AI 聊天记录管理'),
                        const SizedBox(height: 8),
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: colorScheme.outlineVariant.withOpacity(
                                0.5,
                              ),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                leading: Icon(
                                  Icons.chat_bubble_outline,
                                  color: colorScheme.primary,
                                ),
                                title: const Text('聊天记录总数'),
                                subtitle: Text('$_recordCount 条记录'),
                              ),
                              Divider(
                                height: 1,
                                indent: 56,
                                color: colorScheme.outlineVariant.withOpacity(
                                  0.3,
                                ),
                              ),
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                leading: Icon(
                                  Icons.auto_delete_outlined,
                                  color: colorScheme.primary,
                                ),
                                title: const Text('自动清理设置'),
                                subtitle: Text(
                                  _autoCleanupDays == 0
                                      ? '不自动清理'
                                      : '保留最近 $_autoCleanupDays 天的记录',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: _showAutoCleanupDialog,
                              ),
                              Divider(
                                height: 1,
                                indent: 56,
                                color: colorScheme.outlineVariant.withOpacity(
                                  0.3,
                                ),
                              ),
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                leading: Icon(
                                  Icons.delete_forever_outlined,
                                  color: colorScheme.error,
                                ),
                                title: Text(
                                  '清除所有聊天记录',
                                  style: TextStyle(color: colorScheme.error),
                                ),
                                subtitle: const Text('此操作不可恢复'),
                                onTap: _showClearAllConfirmDialog,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildSectionTitle(context, '辅助查词数据库设置'),
                        const SizedBox(height: 8),
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: colorScheme.outlineVariant.withOpacity(
                                0.5,
                              ),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                leading: Icon(
                                  Icons.translate,
                                  color: colorScheme.primary,
                                ),
                                title: const Text('不询问查词重定向数据库'),
                                subtitle: Text(
                                  _neverAskAgain ? '已选择不再询问' : '已恢复询问',
                                ),
                                trailing: Switch(
                                  value: _neverAskAgain,
                                  onChanged: (value) async {
                                    if (value) {
                                      await _englishDbService.setNeverAskAgain(
                                        true,
                                      );
                                      setState(() => _neverAskAgain = true);
                                    } else {
                                      await _englishDbService
                                          .resetNeverAskAgain();
                                      setState(() => _neverAskAgain = false);
                                    }
                                  },
                                ),
                              ),
                              Divider(
                                height: 1,
                                indent: 56,
                                color: colorScheme.outlineVariant.withOpacity(
                                  0.3,
                                ),
                              ),
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                leading: Icon(
                                  Icons.storage_outlined,
                                  color: _englishDbExists
                                      ? colorScheme.error
                                      : colorScheme.outline,
                                ),
                                title: Text(
                                  '删除辅助查词数据库',
                                  style: TextStyle(
                                    color: _englishDbExists
                                        ? colorScheme.error
                                        : colorScheme.outline,
                                  ),
                                ),
                                subtitle: Text(
                                  _englishDbExists
                                      ? '英语数据库已安装，点击删除'
                                      : '暂未安裁任何辅助查词数据库',
                                ),
                                onTap: _englishDbExists
                                    ? () => _showDeleteAuxDbDialog()
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildSectionTitle(context, '词典更新设置'),
                        const SizedBox(height: 8),
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: colorScheme.outlineVariant.withOpacity(
                                0.5,
                              ),
                              width: 1,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: Icon(
                              Icons.update,
                              color: colorScheme.primary,
                            ),
                            title: const Text('自动检查词典更新'),
                            subtitle: const Text('每天检查本地词典是否有更新'),
                            trailing: Switch(
                              value: _autoCheckDictUpdate,
                              onChanged: (value) async {
                                await _preferencesService
                                    .setAutoCheckDictUpdate(value);
                                setState(() => _autoCheckDictUpdate = value);
                                final updateCheckService = context
                                    .read<DictUpdateCheckService>();
                                if (value) {
                                  updateCheckService.startDailyCheck();
                                } else {
                                  updateCheckService.stopDailyCheck();
                                  updateCheckService.clearAllUpdates();
                                }
                              },
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _showAutoCleanupDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    final options = [
      (0, '不自动清理'),
      (7, '保留最近 7 天'),
      (30, '保留最近 30 天'),
      (90, '保留最近 90 天'),
    ];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自动清理设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((option) {
            final (days, label) = option;
            return RadioListTile<int>(
              title: Text(label),
              value: days,
              groupValue: _autoCleanupDays,
              activeColor: colorScheme.primary,
              onChanged: (value) async {
                if (value != null) {
                  await _chatService.setAutoCleanupDays(value);
                  setState(() => _autoCleanupDays = value);
                  Navigator.pop(context);
                }
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  void _showClearAllConfirmDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: colorScheme.error),
            const SizedBox(width: 8),
            const Text('确认清除'),
          ],
        ),
        content: const Text('确定要清除所有 AI 聊天记录吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await _chatService.clearAllRecords();
              setState(() => _recordCount = 0);
              Navigator.pop(context);
              showToast(context, '已清除所有聊天记录');
            },
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAuxDbDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: colorScheme.error),
            const SizedBox(width: 8),
            const Text('删除数据库'),
          ],
        ),
        content: const Text('确定要删除辅助查词数据库吗？删除后可重新下载。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final deleted = await _englishDbService.deleteDb();
              if (mounted) {
                Navigator.pop(context);
                if (deleted) {
                  setState(() => _englishDbExists = false);
                  showToast(context, '辅助查词数据库已删除');
                } else {
                  showToast(context, '数据库文件不存在');
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// _ClickActionOrderDialog
// ─────────────────────────────────────────────

class _ClickActionOrderDialog extends StatefulWidget {
  final List<String> initialOrder;
  final Function(List<String>) onSave;

  const _ClickActionOrderDialog({
    required this.initialOrder,
    required this.onSave,
  });

  @override
  State<_ClickActionOrderDialog> createState() =>
      _ClickActionOrderDialogState();
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
    final colorScheme = Theme.of(context).colorScheme;
    final contentScale = FontLoaderService().getDictionaryContentScale();

    final dialog = AlertDialog(
      title: const Text('点击动作设置'),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SizedBox(
        width: 450,
        height: 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '列表第一项将作为点击时的功能，其它通过右键/长按触发',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: ReorderableListView(
                buildDefaultDragHandles: false,
                children: [
                  for (int index = 0; index < _order.length; index++)
                    ReorderableDragStartListener(
                      index: index,
                      key: ValueKey(_order[index]),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        title: Text(
                          PreferencesService.getActionLabel(_order[index]),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (index == 0)
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    height: 1,
                                    color: colorScheme.primary,
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    color: colorScheme.surface,
                                    child: Text(
                                      '点击功能',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(width: 4),
                            const Icon(Icons.drag_handle, size: 20),
                          ],
                        ),
                      ),
                    ),
                ],
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (oldIndex < newIndex) newIndex -= 1;
                    final item = _order.removeAt(oldIndex);
                    _order.insert(newIndex, item);
                  });
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            widget.onSave(_order);
            Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    );

    if (contentScale == 1.0) return dialog;
    return PageScaleWrapper(scale: contentScale, child: dialog);
  }
}

// ─────────────────────────────────────────────
// _ToolbarConfigDialog
// ─────────────────────────────────────────────

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
    final (toolbarActions, overflowActions) = await _preferencesService
        .getToolbarAndOverflowActions();
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
    final oldIsInToolbar = oldIndex < _dividerIndex;
    final oldActualIndex = oldIndex > _dividerIndex ? oldIndex - 1 : oldIndex;
    if (newIndex > oldIndex) newIndex -= 1;
    final newIsInToolbar = newIndex < _dividerIndex;
    final newActualIndex = newIndex > _dividerIndex ? newIndex - 1 : newIndex;
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
    showToast(context, '工具栏最多只能有 ${PreferencesService.maxToolbarItems} 个功能');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final contentScale = FontLoaderService().getDictionaryContentScale();

    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final dialog = AlertDialog(
      title: const Text('底部工具栏设置'),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SizedBox(
        width: 450,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '拖动调整，分割线以下合并到菜单中，工具栏至多${PreferencesService.maxToolbarItems}个图标',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
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
          child: const Text('完成'),
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
        margin: const EdgeInsets.symmetric(vertical: 2),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.3),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.drag_handle, color: colorScheme.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: Divider(color: colorScheme.primary)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '分割线 (拖动调整)',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
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
    return ReorderableDragStartListener(
      index: listIndex,
      key: ValueKey('action_$action'),
      child: Container(
        color: isInToolbar
            ? colorScheme.primaryContainer.withValues(alpha: 0.1)
            : colorScheme.secondaryContainer.withValues(alpha: 0.1),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          minLeadingWidth: 32,
          leading: Icon(
            Icons.drag_handle,
            color: colorScheme.onSurfaceVariant,
            size: 18,
          ),
          title: Icon(PreferencesService.getActionIcon(action), size: 20),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isInToolbar
                  ? colorScheme.primaryContainer
                  : colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isInToolbar ? '工具栏' : '更多菜单',
              style: TextStyle(
                fontSize: 10,
                color: isInToolbar
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
