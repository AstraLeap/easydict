import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'dictionary_search.dart';
import 'theme_provider.dart';
import 'word_bank_page.dart';
import 'pages/dictionary_manager_page.dart';
import 'pages/help_page.dart';
import 'pages/llm_config_page.dart';
import 'services/ai_chat_history_service.dart';
import 'services/download_manager.dart';
import 'services/dictionary_store_service.dart';
import 'services/english_db_service.dart';
import 'services/database_initializer.dart';
import 'utils/toast_utils.dart';
import 'utils/dpi_utils.dart';
import 'logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 media_kit
  MediaKit.ensureInitialized();

  // 初始化数据库（只执行一次）
  DatabaseInitializer().initialize();

  // 初始化 DownloadManager 并设置 DictionaryStoreService
  final downloadManager = DownloadManager();
  downloadManager.setStoreService(
    DictionaryStoreService(baseUrl: 'https://dict.dxde.de'),
  );

  // 打印用户配置文件目录
  try {
    final appDir = await getApplicationSupportDirectory();
    Logger.i('======================================', tag: 'Config');
    Logger.i('用户配置文件目录: ${appDir.path}', tag: 'Config');
    Logger.i('单词本数据库路径: ${appDir.path}\\word_list.db', tag: 'Config');
    Logger.i('======================================', tag: 'Config');
  } catch (e) {
    Logger.e('获取配置目录失败: $e', tag: 'Config');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeProvider()),
        ChangeNotifierProvider(create: (context) => DownloadManager()),
      ],
      child: const MyApp(),
    ),
  );

  doWhenWindowReady(() {
    appWindow.show();
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: 'EasyDict',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
            fontFamily: 'Segoe UI',
            fontFamilyFallback: const [
              // 优先使用西文字体，确保英文数字显示美观
              'SF Pro Text',
              'Helvetica Neue',
              'Roboto',
              'Ubuntu',
              'Arial',
              // 后备中文字体
              'Microsoft YaHei',
              'SimHei',
              'SimSun',
              'KaiTi',
              'FangSong',
              'Microsoft YaHei UI',
              'PingFang SC',
              'Noto Sans CJK SC',
              'Noto Sans SC',
            ],
            splashFactory: NoSplash.splashFactory,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            fontFamily: 'Segoe UI',
            fontFamilyFallback: const [
              // 优先使用西文字体，确保英文数字显示美观
              'SF Pro Text',
              'Helvetica Neue',
              'Roboto',
              'Ubuntu',
              'Arial',
              // 后备中文字体
              'Microsoft YaHei',
              'SimHei',
              'SimSun',
              'KaiTi',
              'FangSong',
              'Microsoft YaHei UI',
              'PingFang SC',
              'Noto Sans CJK SC',
              'Noto Sans SC',
            ],
            splashFactory: NoSplash.splashFactory,
          ),
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

  final List<Widget> _pages = const [
    DictionarySearchPage(),
    WordBankPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
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

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

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
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LLMConfigPage(),
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
                      title: '主题模式',
                      icon: Icons.dark_mode_outlined,
                      iconColor: colorScheme.primary,
                      showArrow: true,
                      onTap: () => _showThemeModeDialog(context),
                    ),
                    _buildSettingsTile(
                      context,
                      title: '杂项设置',
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
                      title: '使用帮助',
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
                    _buildSettingsTile(
                      context,
                      title: '词典反馈',
                      icon: Icons.feedback,
                      iconColor: colorScheme.primary,
                      onTap: () async {},
                    ),
                    _buildSettingsTile(
                      context,
                      title: 'GitHub',
                      icon: Icons.code,
                      iconColor: colorScheme.primary,
                      isExternal: true,
                      onTap: () async {
                        final url = Uri.parse(
                          'https://github.com/AstraLeap/easydict',
                        );
                        if (await canLaunchUrl(url)) {
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                    ),
                    _buildSettingsTile(
                      context,
                      title: '爱发电',
                      icon: Icons.favorite,
                      iconColor: colorScheme.primary,
                      isExternal: true,
                      onTap: () async {
                        final url = Uri.parse('https://afdian.com/a/karx_');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                // 版本信息
                Center(
                  child: Text(
                    'EasyDict v1.0.0',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                  ),
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

  void _showThemeModeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('选择主题模式'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildThemeModeOption(
                context,
                ThemeModeOption.light,
                Icons.light_mode,
                '浅色',
                '简洁明亮的界面',
              ),
              _buildThemeModeOption(
                context,
                ThemeModeOption.dark,
                Icons.dark_mode,
                '深色',
                '护眼暗色界面',
              ),
              _buildThemeModeOption(
                context,
                ThemeModeOption.system,
                Icons.brightness_auto,
                '跟随系统',
                '跟随设备设置',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildThemeModeOption(
    BuildContext context,
    ThemeModeOption mode,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isSelected = themeProvider.themeMode == mode;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          themeProvider.setThemeMode(mode);
          Navigator.pop(context);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(
              DpiUtils.scaleBorderRadius(context, 12),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(DpiUtils.scale(context, 8)),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(
                    DpiUtils.scaleBorderRadius(context, 8),
                  ),
                ),
                child: Icon(
                  icon,
                  size: DpiUtils.scaleIconSize(context, 24),
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(width: DpiUtils.scale(context, 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: DpiUtils.scaleFontSize(context, 16),
                        fontWeight: FontWeight.w500,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: DpiUtils.scaleFontSize(context, 12),
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  size: DpiUtils.scaleIconSize(context, 24),
                  color: Theme.of(context).colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 杂项设置页面
class MiscSettingsPage extends StatefulWidget {
  const MiscSettingsPage({super.key});

  @override
  State<MiscSettingsPage> createState() => _MiscSettingsPageState();
}

class _MiscSettingsPageState extends State<MiscSettingsPage> {
  final _chatService = AiChatHistoryService();
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
      appBar: AppBar(title: const Text('杂项设置'), centerTitle: true),
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
              final isSelected = _autoCleanupDays == days;
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
