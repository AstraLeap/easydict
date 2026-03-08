import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/theme_provider.dart';
import '../core/utils/toast_utils.dart';
import '../core/utils/language_utils.dart';

import '../i18n/strings.g.dart';
import '../services/dict_update_check_service.dart';
import '../services/app_update_service.dart';
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
// Helpers
// ─────────────────────────────────────────────

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

  String _getThemeColorName(BuildContext context, Color color) {
    if (color.toARGB32() == ThemeProvider.systemAccentColor.toARGB32()) {
      return context.t.theme.systemAccent;
    }
    final n = context.t.theme.colorNames;
    final colorNames = {
      Colors.blue.toARGB32(): n.blue,
      Colors.indigo.toARGB32(): n.indigo,
      Colors.purple.toARGB32(): n.purple,
      Colors.deepPurple.toARGB32(): n.deepPurple,
      Colors.pink.toARGB32(): n.pink,
      Colors.red.toARGB32(): n.red,
      Colors.deepOrange.toARGB32(): n.deepOrange,
      Colors.orange.toARGB32(): n.orange,
      Colors.amber.toARGB32(): n.amber,
      Colors.yellow.toARGB32(): n.yellow,
      Colors.lime.toARGB32(): n.lime,
      Colors.lightGreen.toARGB32(): n.lightGreen,
      Colors.green.toARGB32(): n.green,
      Colors.teal.toARGB32(): n.teal,
      Colors.cyan.toARGB32(): n.cyan,
    };
    return colorNames[color.toARGB32()] ?? context.t.theme.custom;
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

  void _showLanguageDialog() {
    final localeProvider = context.read<LocaleProvider>();
    showDialog(
      context: context,
      builder: (ctx) {
        return _LanguagePickerDialog(
          currentOption: localeProvider.currentOption,
          onSelected: (option) {
            localeProvider.setLocaleOption(option);
          },
        );
      },
    );
  }

  void _showDictionaryContentScaleDialog() async {
    final oldScale = _dictionaryContentScale;
    final contentScale = FontLoaderService().getDictionaryContentScale();
    await showDialog(
      context: context,
      builder: (context) {
        final dialog = ScaleDialogWidget(
          title: context.t.settings.scaleDialog.title,
          subtitle: context.t.settings.scaleDialog.subtitle,
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
    // 如果用户更改了缩放，弹出10秒倒计时确认对话框
    if (mounted && (_dictionaryContentScale - oldScale).abs() > 0.001) {
      final newScale = _dictionaryContentScale;
      final confirmed = await _showScaleConfirmationDialog(newScale);
      if (!confirmed) {
        final prefs = PreferencesService();
        await prefs.setDictionaryContentScale(oldScale);
        await FontLoaderService().reloadDictionaryContentScale();
        if (mounted) {
          setState(() {
            _dictionaryContentScale = oldScale;
          });
        }
      }
    }
  }

  Future<bool> _showScaleConfirmationDialog(double newScale) async {
    int countdown = 10;
    Timer? timer;
    bool? dialogResult;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            timer ??= Timer.periodic(const Duration(seconds: 1), (t) {
              if (countdown <= 1) {
                t.cancel();
                dialogResult = false;
                Navigator.of(dialogContext).pop();
              } else {
                setDialogState(() => countdown--);
              }
            });
            return AlertDialog(
              title: Text(
                context.t.settings.scaleDialog.confirmTitle,
                locale: getFontLocale(),
              ),
              content: Text(
                context.t.settings.scaleDialog.confirmBody(
                  percent: (newScale * 100).round(),
                  seconds: countdown,
                ),
                locale: getFontLocale(),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    timer?.cancel();
                    dialogResult = false;
                    Navigator.of(dialogContext).pop();
                  },
                  child: Text(context.t.common.undo, locale: getFontLocale()),
                ),
                FilledButton(
                  onPressed: () {
                    timer?.cancel();
                    dialogResult = true;
                    Navigator.of(dialogContext).pop();
                  },
                  child: Text(
                    context.t.common.confirm,
                    locale: getFontLocale(),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    timer?.cancel();
    return dialogResult ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final updateCheckService = context.watch<DictUpdateCheckService>();
    final appUpdateService = context.watch<AppUpdateService>();
    // watch LocaleProvider so the language subtitle rebuilds on locale change
    context.watch<LocaleProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final contentScale = FontLoaderService().getDictionaryContentScale();
    return Scaffold(
      body: PageScaleWrapper(
        scale: contentScale,
        child: SafeArea(
          bottom: false,
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
                          title: context.t.settings.cloudService,
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
                          title: context.t.settings.dictionaryManager,
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
                          title: context.t.settings.aiConfig,
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
                          title: context.t.settings.fontConfig,
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
                          title: context.t.settings.appLanguage,
                          icon: Icons.language_outlined,
                          iconColor: colorScheme.primary,
                          onTap: _showLanguageDialog,
                        ),
                        _buildSettingsTile(
                          context,
                          title: context.t.settings.themeSettings,
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
                          title: context.t.settings.layoutScale,
                          icon: Icons.zoom_in,
                          iconColor: colorScheme.primary,
                          onTap: _showDictionaryContentScaleDialog,
                        ),
                        if (!_isLoading)
                          _buildSettingsTile(
                            context,
                            title: context.t.settings.clickAction,
                            icon: Icons.touch_app_outlined,
                            iconColor: colorScheme.primary,
                            onTap: _showClickActionDialog,
                          ),
                        _buildSettingsTile(
                          context,
                          title: context.t.settings.toolbar,
                          icon: Icons.apps,
                          iconColor: colorScheme.primary,
                          onTap: _showToolbarConfigDialog,
                        ),
                        _buildSettingsTile(
                          context,
                          title: context.t.settings.misc,
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
                          title: context.t.settings.about,
                          icon: Icons.help_outline,
                          iconColor: colorScheme.primary,
                          showArrow: true,
                          badgeCount: appUpdateService.hasUpdate ? 1 : null,
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
                    // const SizedBox(height: 22),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
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
// _LanguagePickerDialog
// ─────────────────────────────────────────────

class _LanguagePickerDialog extends StatefulWidget {
  const _LanguagePickerDialog({
    required this.currentOption,
    required this.onSelected,
  });

  final AppLocaleOption currentOption;
  final void Function(AppLocaleOption) onSelected;

  @override
  State<_LanguagePickerDialog> createState() => _LanguagePickerDialogState();
}

class _LanguagePickerDialogState extends State<_LanguagePickerDialog> {
  late AppLocaleOption _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentOption;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final options = [
      (AppLocaleOption.auto, t.language.auto),
      (AppLocaleOption.zh, t.language.zh),
      (AppLocaleOption.en, t.language.en),
    ];

    return AlertDialog(
      title: Text(t.language.dialogTitle),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: options.map((entry) {
          final (option, label) = entry;
          return RadioListTile<AppLocaleOption>(
            title: Text(label),
            value: option,
            groupValue: _selected,
            onChanged: (v) {
              if (v == null) return;
              setState(() => _selected = v);
              widget.onSelected(v);
              Navigator.of(context).pop();
            },
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.common.cancel),
        ),
      ],
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
  final _englishDbService = EnglishDbService();
  final _preferencesService = PreferencesService();
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
    final neverAsk = await _englishDbService.getNeverAskAgain();
    final autoCheck = await _preferencesService.getAutoCheckDictUpdate();
    final englishDbExists = await _englishDbService.dbExists();
    setState(() {
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
        title: Text(context.t.settings.misc_page.title),
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
                        _buildSectionTitle(
                          context,
                          context.t.settings.misc_page.auxDbTitle,
                        ),
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
                                title: Text(
                                  context.t.settings.misc_page.skipAskRedirect,
                                ),
                                subtitle: Text(
                                  _neverAskAgain
                                      ? context
                                            .t
                                            .settings
                                            .misc_page
                                            .skipAskEnabled
                                      : context
                                            .t
                                            .settings
                                            .misc_page
                                            .skipAskDisabled,
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
                                  context.t.settings.misc_page.deleteAuxDb,
                                  style: TextStyle(
                                    color: _englishDbExists
                                        ? colorScheme.error
                                        : colorScheme.outline,
                                  ),
                                ),
                                subtitle: Text(
                                  _englishDbExists
                                      ? context
                                            .t
                                            .settings
                                            .misc_page
                                            .auxDbInstalled
                                      : context
                                            .t
                                            .settings
                                            .misc_page
                                            .auxDbNotInstalled,
                                ),
                                onTap: _englishDbExists
                                    ? () => _showDeleteAuxDbDialog()
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildSectionTitle(
                          context,
                          context.t.settings.misc_page.dictUpdateTitle,
                        ),
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
                            title: Text(
                              context.t.settings.misc_page.autoCheckDictUpdate,
                            ),
                            subtitle: Text(
                              context
                                  .t
                                  .settings
                                  .misc_page
                                  .autoCheckDictUpdateSubtitle,
                            ),
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

  void _showDeleteAuxDbDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: colorScheme.error),
            const SizedBox(width: 8),
            Text(context.t.settings.misc_page.deleteAuxDbConfirmTitle),
          ],
        ),
        content: Text(context.t.settings.misc_page.deleteAuxDbConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.t.common.cancel),
          ),
          FilledButton(
            onPressed: () async {
              final deleted = await _englishDbService.deleteDb();
              if (mounted) {
                Navigator.pop(context);
                if (deleted) {
                  setState(() => _englishDbExists = false);
                  showToast(
                    context,
                    context.t.settings.misc_page.deleteAuxDbSuccess,
                  );
                } else {
                  showToast(
                    context,
                    context.t.settings.misc_page.deleteAuxDbNotExist,
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            child: Text(context.t.common.delete),
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
      title: Text(context.t.settings.clickActionDialog.title),
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
                context.t.settings.clickActionDialog.hint,
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
                          _getLocalizedActionLabel(context, _order[index]),
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
                                      context
                                          .t
                                          .settings
                                          .clickActionDialog
                                          .primaryLabel,
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
          child: Text(context.t.common.cancel),
        ),
        FilledButton(
          onPressed: () {
            widget.onSave(_order);
            Navigator.pop(context);
          },
          child: Text(context.t.common.save),
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
        width: 450,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                context.t.settings.toolbarDialog.hint(
                  max: PreferencesService.maxToolbarItems,
                ),
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
                        context.t.settings.toolbarDialog.dividerLabel,
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
              isInToolbar
                  ? context.t.settings.toolbarDialog.toolbar
                  : context.t.settings.toolbarDialog.overflow,
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
