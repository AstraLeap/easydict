import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../core/locale_provider.dart';
import '../core/theme_provider.dart';
import '../core/utils/toast_utils.dart';

import '../i18n/strings.g.dart';
import '../services/dict_update_check_service.dart';
import '../services/app_update_service.dart';
import '../services/english_db_service.dart';
import '../services/font_loader_service.dart';
import '../services/preferences_service.dart';
import '../services/clipboard_watcher_service.dart';
import '../services/system_tray_service.dart';
import '../services/dictionary_manager.dart';
import '../services/auth_service.dart';
import '../services/entry_event_bus.dart';
import '../components/global_scale_wrapper.dart';
import 'cloud_service_page.dart';
import 'dictionary_manager_page.dart';
import 'dictionary_source_page.dart';
import 'creator_center_page.dart';
import 'display_settings_page.dart';
import 'font_config_page.dart';
import 'help_page.dart';
import 'llm_config_page.dart';
import 'theme_color_page.dart';
import 'settings/menu_item.dart';
import 'settings/wide_layout.dart';

// ─────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────

// ─────────────────────────────────────────────
// SettingsPage
// ─────────────────────────────────────────────

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.contentScaleNotifier, this.onSubPageChanged});

  /// 通知父级刷新内容缩放比例（从字体配置页返回时使用）
  final ValueNotifier<double>? contentScaleNotifier;

  /// 子页面状态变化回调（true=主页，false=子页面）
  final ValueChanged<bool>? onSubPageChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _preferencesService = PreferencesService();
  final _dictManager = DictionaryManager();
  final _authService = AuthService();
  final _eventBus = EntryEventBus();
  bool _isLoading = true;

  /// 云服务器URL是否已设置
  bool _hasCloudServer = false;

  /// 用户是否已登录
  bool _isLoggedIn = false;

  /// 当前选中的菜单索引
  /// -1 表示未选中（宽屏模式下右侧留空，窄屏模式下显示主页）
  int _selectedMenuIndex = -1;

  /// 上一次的宽屏状态（用于检测布局切换）
  bool? _lastIsWideLayout;

  /// 宽屏布局阈值
  static const double _wideLayoutThreshold = 800.0;

  /// 菜单项配置列表
  List<SettingsMenuItem>? _menuItems;

  /// 菜单分组配置列表
  List<SettingsMenuGroup>? _menuGroups;

  @override
  void initState() {
    super.initState();
    _loadData();
    _listenEvents();
  }

  void _listenEvents() {
    // 监听订阅链接变化
    _eventBus.subscriptionUrlChanged.listen((_) {
      _refreshCloudStatus();
    });

    // 监听登录状态变化
    _eventBus.authStateChanged.listen((event) {
      setState(() {
        _isLoggedIn = event.isLoggedIn;
      });
    });
  }

  /// 刷新云服务器和登录状态
  Future<void> _refreshCloudStatus() async {
    final cloudUrl = await _dictManager.onlineSubscriptionUrl;
    final hasCloudServer = cloudUrl.isNotEmpty;

    bool isLoggedIn = false;
    if (hasCloudServer) {
      _authService.setBaseUrl(cloudUrl);
      final token = await _preferencesService.getAuthToken();
      final userData = await _preferencesService.getAuthUserData();
      if (token != null && userData != null) {
        _authService.restoreSession(token: token, userData: userData);
        isLoggedIn = _authService.isLoggedIn;
      }
    }

    // 只有状态变化时才更新
    if (_hasCloudServer != hasCloudServer || _isLoggedIn != isLoggedIn) {
      setState(() {
        _hasCloudServer = hasCloudServer;
        _isLoggedIn = isLoggedIn;
      });
    }
  }

  Future<void> _loadData() async {
    // 检查云服务器是否设置
    final cloudUrl = await _dictManager.onlineSubscriptionUrl;
    final hasCloudServer = cloudUrl.isNotEmpty;

    // 检查登录状态
    if (hasCloudServer) {
      _authService.setBaseUrl(cloudUrl);
      // 尝试恢复登录状态
      final token = await _preferencesService.getAuthToken();
      final userData = await _preferencesService.getAuthUserData();
      if (token != null && userData != null) {
        _authService.restoreSession(token: token, userData: userData);
      }
    }

    setState(() {
      _hasCloudServer = hasCloudServer;
      _isLoggedIn = _authService.isLoggedIn;
      _isLoading = false;
    });
  }

  /// 初始化菜单项配置
  void _initMenuItems(BuildContext context) {
    if (_menuItems != null) return;

    final updateCheckService = context.read<DictUpdateCheckService>();
    final appUpdateService = context.read<AppUpdateService>();
    final colorScheme = Theme.of(context).colorScheme;

    _menuItems = [
      // 设置主页（窄屏模式下的默认页）
      SettingsMenuItem(
        id: 'home',
        titleBuilder: (t) => t.settings.title,
        icon: Icons.settings,
        type: SettingsContentType.homePage,
        group: 'home',
      ),

      // 云服务
      SettingsMenuItem(
        id: 'cloud_service',
        titleBuilder: (t) => t.settings.cloudService,
        icon: Icons.cloud_outlined,
        type: SettingsContentType.subPage,
        subPageBuilder: ({onBack}) => CloudServicePage(onBack: onBack),
        group: 'cloud',
      ),

      // 词典商店（只有设置了云服务器才显示）
      SettingsMenuItem(
        id: 'dictionary_store',
        titleBuilder: (t) => t.settings.dictionaryStore,
        icon: Icons.store_outlined,
        type: SettingsContentType.subPage,
        subPageBuilder: ({onBack}) => DictionarySourcePage(onBack: onBack),
        badgeCountProvider: () => updateCheckService.updatableCount,
        group: 'cloud',
        visibilityCondition: () => _hasCloudServer,
      ),

      // 创作者中心（只有登录了账号才显示）
      SettingsMenuItem(
        id: 'creator_center',
        titleBuilder: (t) => t.settings.creatorCenter,
        icon: Icons.edit_note,
        type: SettingsContentType.subPage,
        subPageBuilder: ({onBack}) => CreatorCenterPage(onBack: onBack),
        group: 'cloud',
        visibilityCondition: () => _isLoggedIn,
      ),

      // 核心功能组
      SettingsMenuItem(
        id: 'dictionary_manager',
        titleBuilder: (t) => t.settings.dictionaryManager,
        icon: Icons.folder_outlined,
        type: SettingsContentType.subPage,
        subPageBuilder: ({onBack}) => DictionaryManagerPage(onBack: onBack),
        group: 'core',
      ),
      SettingsMenuItem(
        id: 'font_config',
        titleBuilder: (t) => t.settings.fontConfig,
        icon: Icons.font_download_outlined,
        type: SettingsContentType.subPage,
        subPageBuilder: ({onBack}) => FontConfigPage(onBack: onBack),
        group: 'core',
      ),
      SettingsMenuItem(
        id: 'ai_config',
        titleBuilder: (t) => t.settings.aiConfig,
        icon: Icons.auto_awesome,
        type: SettingsContentType.subPage,
        subPageBuilder: ({onBack}) => LLMConfigPage(onBack: onBack),
        group: 'core',
      ),

      // 外观设置组
      SettingsMenuItem(
        id: 'theme_settings',
        titleBuilder: (t) => t.settings.themeSettings,
        icon: Icons.palette_outlined,
        type: SettingsContentType.subPage,
        subPageBuilder: ({onBack}) => ThemeColorPage(onBack: onBack),
        group: 'appearance',
      ),
      SettingsMenuItem(
        id: 'display_settings',
        titleBuilder: (t) => t.settings.displaySettings,
        icon: Icons.display_settings_outlined,
        type: SettingsContentType.subPage,
        subPageBuilder: ({onBack}) => DisplaySettingsPage(onBack: onBack),
        group: 'appearance',
      ),
      SettingsMenuItem(
        id: 'misc',
        titleBuilder: (t) => t.settings.misc,
        icon: Icons.settings_suggest_outlined,
        type: SettingsContentType.subPage,
        subPageBuilder: ({onBack}) => MiscSettingsPage(onBack: onBack),
        group: 'appearance',
      ),

      // 帮助与支持组
      SettingsMenuItem(
        id: 'about',
        titleBuilder: (t) => t.settings.about,
        icon: Icons.help_outline,
        type: SettingsContentType.subPage,
        subPageBuilder: ({onBack}) => HelpPage(onBack: onBack),
        badgeCountProvider: () => appUpdateService.hasUpdate ? 1 : null,
        group: 'help',
      ),
    ];

    _menuGroups = [
      // 主页组（仅窄屏模式显示）
      SettingsMenuGroup(
        id: 'home',
        items: _menuItems!.where((item) => item.group == 'home').toList(),
      ),
      SettingsMenuGroup(
        id: 'cloud',
        items: _menuItems!.where((item) => item.group == 'cloud').toList(),
      ),
      SettingsMenuGroup(
        id: 'core',
        titleBuilder: (t) => t.settings.coreFeatures,
        items: _menuItems!.where((item) => item.group == 'core').toList(),
      ),
      SettingsMenuGroup(
        id: 'appearance',
        titleBuilder: (t) => t.settings.appearance,
        items: _menuItems!.where((item) => item.group == 'appearance').toList(),
      ),
      SettingsMenuGroup(
        id: 'help',
        items: _menuItems!.where((item) => item.group == 'help').toList(),
      ),
    ];
  }

  /// 处理菜单选中
  void _onMenuSelected(int index) {
    if (index == -2) {
      // 宽屏模式下返回：显示空白占位
      setState(() => _selectedMenuIndex = -1);
      return;
    }
    if (index < 0) {
      // 窄屏模式下返回主页
      setState(() => _selectedMenuIndex = 0);
      return;
    }

    final item = _menuItems![index];
    if (item.type == SettingsContentType.dialog) {
      // 对话框类型直接弹出对话框
      item.showDialog?.call(context);
    } else {
      // 子页面/内嵌类型切换右侧内容
      setState(() => _selectedMenuIndex = index);
    }

    // 通知父组件 tab 可见性
    _notifySubPageState();
  }

  /// 通知父组件子页面状态（用于控制底部 tab 栏可见性）
  void _notifySubPageState() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideLayout = screenWidth >= _wideLayoutThreshold;

    if (isWideLayout) {
      // 宽屏模式始终显示 tab
      widget.onSubPageChanged?.call(true);
      return;
    }

    // 窄屏模式：主页显示 tab，子页面隐藏 tab
    // _selectedMenuIndex <= 0 表示主页，> 0 表示子页面
    final isHomePage = _selectedMenuIndex <= 0 ||
        (_menuItems != null &&
         _selectedMenuIndex < _menuItems!.length &&
         _menuItems![_selectedMenuIndex].type == SettingsContentType.homePage);
    widget.onSubPageChanged?.call(isHomePage);
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

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideLayout = screenWidth >= _wideLayoutThreshold;

    // 初始化菜单项
    _initMenuItems(context);

    // 处理布局切换
    if (_lastIsWideLayout != null && _lastIsWideLayout != isWideLayout) {
      // 布局发生变化
      if (!isWideLayout) {
        // 从宽屏切换到窄屏：如果当前未选中，显示主页
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _selectedMenuIndex == -1) {
            setState(() => _selectedMenuIndex = 0);
          }
          _notifySubPageState();
        });
      } else {
        // 从窄屏切换到宽屏：如果当前是主页，显示空白占位
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _selectedMenuIndex == 0) {
            setState(() => _selectedMenuIndex = -1);
          }
          _notifySubPageState();
        });
      }
    }
    _lastIsWideLayout = isWideLayout;

    // 宽屏模式下，主页(index 0) 显示空白占位；窄屏模式下，未选中时显示主页
    final effectiveSelectedIndex = isWideLayout
        ? (_selectedMenuIndex == 0 ? -1 : _selectedMenuIndex)
        : (_selectedMenuIndex == -1 ? 0 : _selectedMenuIndex);

    // 统一使用 WideSettingsLayout，通过 showMenuPanel 控制是否显示左侧菜单
    return WideSettingsLayout(
      menuItems: _menuItems!,
      menuGroups: _menuGroups!,
      selectedIndex: effectiveSelectedIndex,
      onMenuSelected: _onMenuSelected,
      contentScaleNotifier: widget.contentScaleNotifier,
      showMenuPanel: isWideLayout,
    );
  }
}

// ─────────────────────────────────────────────
// MiscSettingsPage
// ─────────────────────────────────────────────

/// 其它设置页面
class MiscSettingsPage extends StatefulWidget {
  final VoidCallback? onBack;

  const MiscSettingsPage({super.key, this.onBack});

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
  // 桌面功能设置
  bool _clipboardWatchEnabled = false;
  bool _minimizeToTray = false;
  // 笔记设置
  bool _noteDefaultExpanded = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final neverAsk = await _englishDbService.getNeverAskAgain();
    final autoCheck = await _preferencesService.getAutoCheckDictUpdate();
    final englishDbExists = await _englishDbService.dbExists();
    final clipboardWatchEnabled = await _preferencesService
        .isClipboardWatchEnabled();
    final minimizeToTray = await _preferencesService.shouldMinimizeToTray();
    final noteDefaultExpanded = await _preferencesService.getNoteDefaultExpanded();
    setState(() {
      _neverAskAgain = neverAsk;
      _autoCheckDictUpdate = autoCheck;
      _englishDbExists = englishDbExists;
      _clipboardWatchEnabled = clipboardWatchEnabled;
      _minimizeToTray = minimizeToTray;
      _noteDefaultExpanded = noteDefaultExpanded;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final content = Scaffold(
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : null,
        title: Text(context.t.settings.misc_page.title),
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : PageScaleWrapper(
              scale: _contentScale,
              child: _buildContent(context, colorScheme),
            ),
    );

    // 如果有 onBack 回调，使用 PopScope 拦截系统返回
    if (widget.onBack != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, popResult) {
          if (!didPop) {
            widget.onBack!();
          }
        },
        child: content,
      );
    }

    return content;
  }

  Widget _buildContent(BuildContext context, ColorScheme colorScheme) {
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      children: [
        // 跳过询问跳转
        ListTile(
          leading: const Icon(Icons.translate),
          title: Text(context.t.settings.misc_page.skipAskRedirect),
          trailing: Switch(
            value: _neverAskAgain,
            onChanged: (value) async {
              if (value) {
                await _englishDbService.setNeverAskAgain(true);
                setState(() => _neverAskAgain = true);
              } else {
                await _englishDbService.resetNeverAskAgain();
                setState(() => _neverAskAgain = false);
              }
            },
          ),
          onTap: () async {
            final newValue = !_neverAskAgain;
            if (newValue) {
              await _englishDbService.setNeverAskAgain(true);
            } else {
              await _englishDbService.resetNeverAskAgain();
            }
            setState(() => _neverAskAgain = newValue);
          },
        ),
        // 删除辅助词典
        ListTile(
          leading: Icon(
            Icons.storage_outlined,
            color: _englishDbExists ? colorScheme.error : colorScheme.outline,
          ),
          title: Text(
            context.t.settings.misc_page.deleteAuxDb,
            style: TextStyle(
              color: _englishDbExists
                  ? colorScheme.error
                  : colorScheme.outline,
            ),
          ),
          trailing: _englishDbExists
              ? const Icon(Icons.chevron_right, size: 20)
              : null,
          onTap: _englishDbExists ? () => _showDeleteAuxDbDialog() : null,
        ),
        // 自动检查词典更新
        ListTile(
          leading: const Icon(Icons.update),
          title: Text(context.t.settings.misc_page.autoCheckDictUpdate),
          trailing: Switch(
            value: _autoCheckDictUpdate,
            onChanged: (value) async {
              await _preferencesService.setAutoCheckDictUpdate(value);
              setState(() => _autoCheckDictUpdate = value);
              final updateCheckService = context.read<DictUpdateCheckService>();
              if (value) {
                updateCheckService.startDailyCheck();
              } else {
                updateCheckService.stopDailyCheck();
                updateCheckService.clearAllUpdates();
              }
            },
          ),
          onTap: () async {
            final newValue = !_autoCheckDictUpdate;
            await _preferencesService.setAutoCheckDictUpdate(newValue);
            setState(() => _autoCheckDictUpdate = newValue);
            final updateCheckService = context.read<DictUpdateCheckService>();
            if (newValue) {
              updateCheckService.startDailyCheck();
            } else {
              updateCheckService.stopDailyCheck();
              updateCheckService.clearAllUpdates();
            }
          },
        ),
        // 桌面功能设置（仅桌面平台显示）
        if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) ...[
          ListTile(
            leading: const Icon(Icons.content_paste_search),
            title: Text(context.t.settings.clipboardWatch),
            trailing: Switch(
              value: _clipboardWatchEnabled,
              onChanged: (value) async {
                await _preferencesService.setClipboardWatchEnabled(value);
                await ClipboardWatcherService().setEnabled(value);
                await SystemTrayService().updateClipboardWatchState(value);
                setState(() => _clipboardWatchEnabled = value);
              },
            ),
            onTap: () async {
              final newValue = !_clipboardWatchEnabled;
              await _preferencesService.setClipboardWatchEnabled(newValue);
              await ClipboardWatcherService().setEnabled(newValue);
              await SystemTrayService().updateClipboardWatchState(newValue);
              setState(() => _clipboardWatchEnabled = newValue);
            },
          ),
          ListTile(
            leading: const Icon(Icons.remove_circle_outline),
            title: Text(context.t.settings.minimizeToTray),
            trailing: Switch(
              value: _minimizeToTray,
              onChanged: (value) async {
                await _preferencesService.setMinimizeToTray(value);
                await windowManager.setPreventClose(value);
                await SystemTrayService().updateMinimizeToTrayState(value);
                setState(() => _minimizeToTray = value);
              },
            ),
            onTap: () async {
              final newValue = !_minimizeToTray;
              await _preferencesService.setMinimizeToTray(newValue);
              await windowManager.setPreventClose(newValue);
              await SystemTrayService().updateMinimizeToTrayState(newValue);
              setState(() => _minimizeToTray = newValue);
            },
          ),
        ],
        // 笔记默认展开
        ListTile(
          leading: const Icon(Icons.sticky_note_2_outlined),
          title: Text(context.t.note.defaultExpanded),
          trailing: Switch(
            value: _noteDefaultExpanded,
            onChanged: (value) async {
              await _preferencesService.setNoteDefaultExpanded(value);
              setState(() => _noteDefaultExpanded = value);
            },
          ),
          onTap: () async {
            final newValue = !_noteDefaultExpanded;
            await _preferencesService.setNoteDefaultExpanded(newValue);
            setState(() => _noteDefaultExpanded = newValue);
          },
        ),
      ],
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
