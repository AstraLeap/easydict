import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dictionary_search.dart';
import 'theme_provider.dart';
import 'theme/app_theme.dart';
import 'word_bank_page.dart';
import 'pages/dictionary_manager_page.dart';
import 'pages/font_config_page.dart';
import 'pages/help_page.dart';
import 'pages/llm_config_page.dart';
import 'pages/theme_color_page.dart';
import 'services/ai_chat_database_service.dart';
import 'services/download_manager.dart';
import 'services/english_db_service.dart';
import 'services/database_initializer.dart';
import 'services/preferences_service.dart';
import 'services/media_kit_manager.dart';
import 'services/font_loader_service.dart';
import 'utils/toast_utils.dart';
import 'utils/dpi_utils.dart';
import 'logger.dart';
import 'components/window_buttons.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await MediaKitManager().disposeAllPlayers();
  } catch (e) {
    Logger.w('热重启清理 MediaKit 资源时出错: $e', tag: 'main');
  }

  await Future.delayed(const Duration(milliseconds: 100));

  MediaKit.ensureInitialized();

  DatabaseInitializer().initialize();

  try {
    final appDir = await getApplicationSupportDirectory();
    Logger.i('======================================', tag: 'Config');
    Logger.i('用户配置文件目录: ${appDir.path}', tag: 'Config');
    Logger.i('单词本数据库路径: ${appDir.path}\\word_list.db', tag: 'Config');
    Logger.i('======================================', tag: 'Config');
  } catch (e) {
    Logger.e('获取配置目录失败: $e', tag: 'Config');
  }

  final prefs = await SharedPreferences.getInstance();

  await FontLoaderService().initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeProvider(prefs)),
        ChangeNotifierProvider(create: (context) => DownloadManager()),
      ],
      child: const MyApp(),
    ),
  );

  doWhenWindowReady(() {
    appWindow.show();
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      MediaKit.ensureInitialized();
    }
  }

  /// 处理热重启前的清理工作
  ///
  /// 在热重启时，Flutter 会重新调用 main() 函数
  /// 我们需要确保所有 MediaKit Player 实例被正确释放
  /// 避免 "Callback invoked after it has been deleted" 错误
  void _handleHotRestart() {
    Logger.i('检测到热重启，开始清理 MediaKit 资源...', tag: 'MyApp');
    MediaKitManager().disposeAllPlayers();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: 'EasyDict',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme(seedColor: themeProvider.seedColor),
          darkTheme: AppTheme.darkTheme(seedColor: themeProvider.seedColor),
          themeMode: themeProvider.getThemeMode(),
          home: const MainScreen(),
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final GlobalKey<dynamic> _wordBankPageKey = GlobalKey();

  List<Widget> get _pages => [
    const DictionarySearchPage(),
    WordBankPage(key: _wordBankPageKey),
    const SettingsPage(),
  ];

  void _onTabSelected(int index) {
    if (_selectedIndex != index) {
      setState(() {
        _selectedIndex = index;
      });
      if (index == 1) {
        _wordBankPageKey.currentState?.loadWordsIfNeeded();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onTabSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: '查词',
          ),
          NavigationDestination(
            icon: Icon(Icons.style_outlined),
            selectedIcon: Icon(Icons.style),
            label: '单词本',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  SearchBar(
                    hintText: '搜索单词、短语...',
                    leading: const Icon(Icons.search),
                    elevation: WidgetStateProperty.all(0),
                    backgroundColor: WidgetStateProperty.all(
                      colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildSectionHeader(context, '今日概览'),
                  const SizedBox(height: 12),
                  Card(
                    color: colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Icon(
                                Icons.auto_stories,
                                color: colorScheme.onPrimaryContainer,
                              ),
                              Icon(
                                Icons.arrow_forward,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '每日单词',
                            style: TextStyle(
                              color: colorScheme.onPrimaryContainer.withOpacity(
                                0.7,
                              ),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Serendipity',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '意外发现珍宝的运气',
                            style: TextStyle(
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          color: colorScheme.secondaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.refresh,
                                  color: colorScheme.onSecondaryContainer,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '复习',
                                  style: TextStyle(
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                ),
                                Text(
                                  '24 个',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Card(
                          color: colorScheme.tertiaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.add_circle_outline,
                                  color: colorScheme.onTertiaryContainer,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '新词',
                                  style: TextStyle(
                                    color: colorScheme.onTertiaryContainer,
                                  ),
                                ),
                                Text(
                                  '12 个',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onTertiaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildSectionHeader(context, '学习统计'),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 0,
                    color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.calendar_today),
                          title: const Text('连续打卡'),
                          trailing: Text(
                            '12 天',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        ListTile(
                          leading: const Icon(Icons.timer_outlined),
                          title: const Text('累计学习'),
                          trailing: Text(
                            '45 小时',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        ListTile(
                          leading: const Icon(Icons.school_outlined),
                          title: const Text('掌握词汇'),
                          trailing: Text(
                            '1,204 个',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        TextButton(onPressed: () {}, child: const Text('查看全部')),
      ],
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _preferencesService = PreferencesService();
  String _clickAction = PreferencesService.actionAiTranslate;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final clickAction = await _preferencesService.getClickAction();
    setState(() {
      _clickAction = clickAction;
      _isLoading = false;
    });
  }

  String _getClickActionLabel(String action) {
    final label = PreferencesService.getActionLabel(action);
    return label == action ? '切换翻译' : label;
  }

  String _getThemeColorName(Color color) {
    // 检查是否是系统主题色
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

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
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
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DictionaryManagerPage(),
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
                      title: '显示与字体',
                      icon: Icons.font_download_outlined,
                      iconColor: colorScheme.primary,
                      showArrow: true,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const FontConfigPage(),
                          ),
                        );
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
                      subtitle: _getThemeColorName(themeProvider.seedColor),
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
                    if (!_isLoading)
                      _buildSettingsTile(
                        context,
                        title: '点击动作设置',
                        subtitle: _getClickActionLabel(_clickAction),
                        icon: Icons.touch_app_outlined,
                        iconColor: colorScheme.primary,
                        onTap: _showClickActionDialog,
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
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建设置分组卡片
  Widget _buildSettingsGroup(
    BuildContext context, {
    required List<Widget> children,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
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

  /// 在子项之间添加分隔线
  List<Widget> _addDividers(List<Widget> children, Color dividerColor) {
    final result = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      result.add(children[i]);
      if (i < children.length - 1) {
        result.add(Divider(height: 1, indent: 56, color: dividerColor));
      }
    }
    return result;
  }

  /// 构建设置项
  Widget _buildSettingsTile(
    BuildContext context, {
    required String title,
    String? subtitle,
    required IconData icon,
    Color? iconColor,
    bool showArrow = false,
    bool isExternal = false,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveIconColor = iconColor ?? colorScheme.onSurfaceVariant;

    return ListTile(
      contentPadding: EdgeInsets.symmetric(
        horizontal: DpiUtils.scale(context, 16),
        vertical: DpiUtils.scale(context, 4),
      ),
      leading: Icon(
        icon,
        color: effectiveIconColor,
        size: DpiUtils.scaleIconSize(context, 18),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: DpiUtils.scaleFontSize(context, 13),
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                fontSize: DpiUtils.scaleFontSize(context, 11.5),
                color: colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: showArrow
          ? Icon(
              Icons.chevron_right,
              color: colorScheme.outline,
              size: DpiUtils.scaleIconSize(context, 20),
            )
          : isExternal
          ? Icon(
              Icons.open_in_new,
              color: colorScheme.outline,
              size: DpiUtils.scaleIconSize(context, 18),
            )
          : null,
      onTap: onTap,
    );
  }
}

/// 其它设置页面
class MiscSettingsPage extends StatefulWidget {
  const MiscSettingsPage({super.key});

  @override
  State<MiscSettingsPage> createState() => _MiscSettingsPageState();
}

class _MiscSettingsPageState extends State<MiscSettingsPage> {
  final _chatService = AiChatDatabaseService();
  final _englishDbService = EnglishDbService();
  int _recordCount = 0;
  int _autoCleanupDays = 0;
  bool _neverAskAgain = false;
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
    setState(() {
      _recordCount = count;
      _autoCleanupDays = days;
      _neverAskAgain = neverAsk;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('其它设置'), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // AI聊天记录管理
                      _buildSectionTitle(context, 'AI 聊天记录管理'),
                      const SizedBox(height: 8),
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: colorScheme.outlineVariant.withOpacity(0.5),
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
                      // 英语词典数据库设置
                      _buildSectionTitle(context, '英语词典数据库设置'),
                      const SizedBox(height: 8),
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: colorScheme.outlineVariant.withOpacity(0.5),
                            width: 1,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: Icon(
                            Icons.translate,
                            color: colorScheme.primary,
                          ),
                          title: const Text('不询问查词重定向数据库'),
                          subtitle: Text(_neverAskAgain ? '已选择不再询问' : '已恢复询问'),
                          trailing: Switch(
                            value: _neverAskAgain,
                            onChanged: (value) async {
                              if (value) {
                                await _englishDbService.setNeverAskAgain(true);
                                setState(() {
                                  _neverAskAgain = true;
                                });
                              } else {
                                await _englishDbService.resetNeverAskAgain();
                                setState(() {
                                  _neverAskAgain = false;
                                });
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
      builder: (context) {
        return AlertDialog(
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
                    setState(() {
                      _autoCleanupDays = value;
                    });
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
        );
      },
    );
  }

  void _showClearAllConfirmDialog() {
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
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
                setState(() {
                  _recordCount = 0;
                });
                Navigator.pop(context);
                showToast(context, '已清除所有聊天记录');
              },
              style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
              child: const Text('清除'),
            ),
          ],
        );
      },
    );
  }
}

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

  String _getActionLabel(String action) {
    return PreferencesService.getActionLabel(action);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('点击动作设置'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                '拖动排序，列表第一项将作为点击时的默认动作',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Flexible(
              child: ReorderableListView(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                children: [
                  for (int index = 0; index < _order.length; index++)
                    ListTile(
                      key: ValueKey(_order[index]),
                      title: Text(_getActionLabel(_order[index])),
                      leading: ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_handle),
                      ),
                      trailing: index == 0
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '默认',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : null,
                    ),
                ],
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (oldIndex < newIndex) {
                      newIndex -= 1;
                    }
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
  }
}
