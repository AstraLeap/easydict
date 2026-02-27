import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'pages/dictionary_search.dart';
import 'core/theme_provider.dart';
import 'core/theme/app_theme.dart';
import 'pages/word_bank_page.dart';
import 'pages/dictionary_manager_page.dart';
import 'pages/font_config_page.dart';
import 'pages/help_page.dart';
import 'pages/llm_config_page.dart';
import 'pages/theme_color_page.dart';
import 'pages/cloud_service_page.dart';
import 'data/services/ai_chat_database_service.dart';
import 'services/dictionary_manager.dart';
import 'services/download_manager.dart';
import 'services/upload_manager.dart';
import 'services/english_db_service.dart';
import 'data/services/database_initializer.dart';
import 'services/preferences_service.dart';
import 'services/auth_service.dart';
import 'services/media_kit_manager.dart';
import 'services/font_loader_service.dart';
import 'services/window_state_service.dart';
import 'services/dict_update_check_service.dart';
import 'services/zstd_service.dart';
import 'core/utils/toast_utils.dart';
import 'core/logger.dart';
import 'components/global_scale_wrapper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  SystemChrome.setSystemUIOverlayStyle(AppTheme.lightSystemUiOverlayStyle());

  // 添加全局错误捕获，便于调试 Release 模式问题
  FlutterError.onError = (FlutterErrorDetails details) {
    Logger.e(
      'Flutter Error: ${details.exception}',
      tag: 'FlutterError',
      error: details.exception,
      stackTrace: details.stack,
    );
    FlutterError.presentError(details);
  };

  // 捕获异步错误
  PlatformDispatcher.instance.onError = (error, stack) {
    Logger.e(
      'Platform Error: $error',
      tag: 'PlatformError',
      error: error,
      stackTrace: stack,
    );
    return true;
  };

  Logger.i('========== 应用启动 ==========', tag: 'Startup');

  try {
    final appDir = await getApplicationSupportDirectory();
    Logger.i('用户配置文件夹: ${appDir.path}', tag: 'Startup');
  } catch (e) {
    Logger.w('获取用户配置文件夹失败: $e', tag: 'Startup');
  }

  try {
    await MediaKitManager().disposeAllPlayers();
    Logger.i('MediaKit 清理完成', tag: 'Startup');
  } catch (e) {
    Logger.w('MediaKit 清理失败: $e', tag: 'Startup');
  }

  await Future.delayed(const Duration(milliseconds: 100));

  try {
    MediaKit.ensureInitialized();
    Logger.i('MediaKit 初始化完成', tag: 'Startup');
  } catch (e) {
    Logger.e('MediaKit 初始化失败: $e', tag: 'Startup');
  }

  // ZstdService 在后台异步初始化，不阻塞应用启动
  Future.microtask(() {
    try {
      ZstdService();
      Logger.i('ZstdService 后台初始化完成', tag: 'Startup');
    } catch (e) {
      Logger.w('ZstdService 后台初始化失败: $e', tag: 'Startup');
    }
  });

  try {
    DatabaseInitializer().initialize();
    Logger.i('数据库初始化完成', tag: 'Startup');
  } catch (e) {
    Logger.e('数据库初始化失败: $e', tag: 'Startup');
  }

  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    Logger.i('SharedPreferences 初始化完成', tag: 'Startup');
  } catch (e) {
    Logger.e('SharedPreferences 初始化失败: $e', tag: 'Startup');
  }

  try {
    await FontLoaderService().initialize();
    Logger.i('字体服务初始化完成', tag: 'Startup');
  } catch (e) {
    Logger.e('字体服务初始化失败: $e', tag: 'Startup');
  }

  try {
    await DictionaryManager().preloadEnabledDictionariesMetadata();
    Logger.i('词典元数据预加载完成', tag: 'Startup');
  } catch (e) {
    Logger.e('词典元数据预加载失败: $e', tag: 'Startup');
  }

  try {
    DictionaryManager().preloadActiveLanguageDatabases();
    Logger.i('词典数据库预连接完成', tag: 'Startup');
  } catch (e) {
    Logger.e('词典数据库预连接失败: $e', tag: 'Startup');
  }

  Logger.i('========== 启动完成，准备运行应用 ==========', tag: 'Startup');
  Logger.i('日志文件路径: ${Logger.getLogFilePath() ?? "未启用文件日志"}', tag: 'Startup');

  try {
    final prefsService = PreferencesService();
    final token = await prefsService.getAuthToken();
    final userData = await prefsService.getAuthUserData();
    if (token != null && userData != null) {
      AuthService().restoreSession(token: token, userData: userData);
      Logger.i('自动恢复登录状态成功', tag: 'Startup');
    }
  } catch (e) {
    Logger.w('自动恢复登录状态失败: $e', tag: 'Startup');
  }

  if (prefs == null) {
    Logger.e('SharedPreferences 初始化失败，无法启动应用', tag: 'Startup');
    return;
  }

  // 初始化窗口管理器（仅桌面平台）
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    try {
      await windowManager.ensureInitialized();
      final windowState = await WindowStateService().getWindowState();

      WindowOptions windowOptions = WindowOptions(
        size: Size(windowState['width']!, windowState['height']!),
        center: windowState['posX'] == null || windowState['posY'] == null,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
      );

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();

        // 恢复窗口位置
        if (windowState['posX'] != null && windowState['posY'] != null) {
          await windowManager.setPosition(
            Offset(windowState['posX']!, windowState['posY']!),
          );
        }

        // 恢复最大化状态
        if (windowState['maximized'] == true) {
          await windowManager.maximize();
        }
      });

      Logger.i('窗口管理器初始化完成', tag: 'Startup');
    } catch (e) {
      Logger.e('窗口管理器初始化失败: $e', tag: 'Startup');
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeProvider(prefs!)),
        ChangeNotifierProvider(create: (context) => DownloadManager()),
        ChangeNotifierProvider(create: (context) => UploadManager()),
        ChangeNotifierProvider(create: (context) => DictUpdateCheckService()),
      ],
      child: const MyApp(),
    ),
  );
}

class ErrorBoundary extends StatefulWidget {
  final Widget child;
  const ErrorBoundary({super.key, required this.child});

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;
  StackTrace? _stackTrace;

  @override
  void initState() {
    super.initState();
    Logger.i('ErrorBoundary 初始化', tag: 'ErrorBoundary');
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Material(
        child: Container(
          color: Colors.red.shade50,
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  '应用发生错误',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_error',
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return widget.child;
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp>
    with WidgetsBindingObserver, WindowListener {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    Logger.i('MyApp initState', tag: 'MyApp');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      MediaKit.ensureInitialized();
      // 从后台恢复时重新应用 edge-to-edge，防止某些 ROM 切换小窗后失效
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // 窗口尺寸变化时（进入/退出多窗口、小窗模式）重新应用 edge-to-edge
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void onWindowClose() async {
    await _saveWindowState();
    await windowManager.destroy();
  }

  @override
  void onWindowResized() async {
    await _saveWindowState();
    await _updateSystemUIForWindowSize();
  }

  Future<void> _updateSystemUIForWindowSize() async {
    try {
      final size = await windowManager.getSize();
      final isSmallWindow = size.height < 600 || size.width < 400;

      if (isSmallWindow) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    } catch (e) {
      Logger.e('更新系统UI模式失败: $e', tag: 'MyApp');
    }
  }

  @override
  void onWindowMoved() async {
    await _saveWindowState();
  }

  Future<void> _saveWindowState() async {
    try {
      final isMaximized = await windowManager.isMaximized();
      final bounds = await windowManager.getBounds();
      await WindowStateService().saveWindowState(
        width: bounds.width,
        height: bounds.height,
        posX: bounds.left,
        posY: bounds.top,
        maximized: isMaximized,
      );
    } catch (e) {
      Logger.e('保存窗口状态失败: $e', tag: 'MyApp');
    }
  }

  void _handleHotRestart() {
    Logger.i('检测到热重启，开始清理 MediaKit 资源...', tag: 'MyApp');
    MediaKitManager().disposeAllPlayers();
  }

  @override
  Widget build(BuildContext context) {
    Logger.i('MyApp build 开始', tag: 'MyApp');
    try {
      return Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          Logger.i(
            'ThemeProvider Consumer build, themeMode: ${themeProvider.getThemeMode()}',
            tag: 'MyApp',
          );

          final themeMode = themeProvider.getThemeMode();
          final theme = themeMode == ThemeMode.dark
              ? AppTheme.darkTheme(seedColor: themeProvider.seedColor)
              : AppTheme.lightTheme(seedColor: themeProvider.seedColor);

          return MaterialApp(
            title: 'EasyDict',
            debugShowCheckedModeBanner: false,
            theme: theme,
            darkTheme: AppTheme.darkTheme(seedColor: themeProvider.seedColor),
            themeMode: themeMode,
            navigatorObservers: [toastRouteObserver],
            home: const MainScreen(),
            builder: (context, widget) {
              Logger.i('MaterialApp builder 被调用', tag: 'MyApp');
              final brightness = MediaQuery.of(context).platformBrightness;
              final isDark =
                  themeMode == ThemeMode.dark ||
                  (themeMode == ThemeMode.system &&
                      brightness == Brightness.dark);
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: isDark
                    ? AppTheme.darkSystemUiOverlayStyle()
                    : AppTheme.lightSystemUiOverlayStyle(),
                child: ErrorBoundary(child: widget ?? const SizedBox()),
              );
            },
          );
        },
      );
    } catch (e, stack) {
      Logger.e('MyApp build 错误: $e', tag: 'MyApp', error: e, stackTrace: stack);
      rethrow;
    }
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

  final ValueNotifier<double> _contentScaleNotifier = ValueNotifier<double>(
    FontLoaderService().getDictionaryContentScale(),
  );

  List<Widget> get _pages => [
    const DictionarySearchPage(),
    WordBankPage(key: _wordBankPageKey),
    const SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    Logger.i('MainScreen initState', tag: 'MainScreen');
    _initDictUpdateCheck();
  }

  Future<void> _initDictUpdateCheck() async {
    // 在 await 之前先获取 service，避免 context 在异步间隙后被销毁
    final updateCheckService = context.read<DictUpdateCheckService>();
    final dictManager = DictionaryManager();
    final baseUrl = await dictManager.onlineSubscriptionUrl;
    if (!mounted) return;
    if (baseUrl.isNotEmpty) {
      updateCheckService.setBaseUrl(baseUrl);
      // 将启动时检查作为独立 Future 运行，不阻塞主线程
      updateCheckService.startDailyCheck();
    }
  }

  @override
  void dispose() {
    _contentScaleNotifier.dispose();
    super.dispose();
  }

  void _refreshContentScale() {
    final newScale = FontLoaderService().getDictionaryContentScale();
    if (_contentScaleNotifier.value != newScale) {
      _contentScaleNotifier.value = newScale;
    }
  }

  void _onTabSelected(int index) {
    if (_selectedIndex != index) {
      setState(() {
        _selectedIndex = index;
      });
      // 切换页面时清除所有 toast，避免位置错乱
      clearAllToasts();
      if (index == 1) {
        _wordBankPageKey.currentState?.loadWordsIfNeeded();
      }
    }
  }

  Widget _buildNavigationDestination({
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required int index,
    int? badgeCount,
    bool showBadgeDot = false,
  }) {
    final showBadge = badgeCount != null && badgeCount > 0;

    return NavigationDestination(
      icon: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Badge(
          isLabelVisible: showBadge && !showBadgeDot,
          label: Text('$badgeCount'),
          smallSize: showBadgeDot ? 8 : null,
          child: Icon(icon),
        ),
      ),
      selectedIcon: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Badge(
          isLabelVisible: showBadge && !showBadgeDot,
          label: Text('$badgeCount'),
          smallSize: showBadgeDot ? 8 : null,
          child: Icon(selectedIcon),
        ),
      ),
      label: label,
    );
  }

  @override
  Widget build(BuildContext context) {
    Logger.i('MainScreen build 开始', tag: 'MainScreen');
    final updateCheckService = context.watch<DictUpdateCheckService>();
    final updateCount = updateCheckService.updatableCount;

    final bottomNav = NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: _onTabSelected,
      destinations: [
        _buildNavigationDestination(
          icon: Icons.search_outlined,
          selectedIcon: Icons.search,
          label: '查词',
          index: 0,
        ),
        _buildNavigationDestination(
          icon: Icons.style_outlined,
          selectedIcon: Icons.style,
          label: '单词本',
          index: 1,
        ),
        _buildNavigationDestination(
          icon: Icons.tune_outlined,
          selectedIcon: Icons.tune,
          label: '设置',
          index: 2,
          badgeCount: updateCount,
          showBadgeDot: true,
        ),
      ],
    );

    return ValueListenableBuilder<double>(
      valueListenable: _contentScaleNotifier,
      builder: (context, contentScale, child) {
        return Scaffold(
          body: IndexedStack(index: _selectedIndex, children: _pages),
          bottomNavigationBar: contentScale == 1.0
              ? bottomNav
              : MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(contentScale)),
                  child: bottomNav,
                ),
        );
      },
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
              padding: EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                top: 8,
                bottom: 8,
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

        if (contentScale == 1.0) {
          return dialog;
        }

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
    final topPadding = MediaQuery.of(context).viewPadding.top;

    return Scaffold(
      body: PageScaleWrapper(
        scale: contentScale,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: topPadding + 12,
              ),
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
                          // 从字体配置页返回后，刷新缩放值
                          if (mounted) {
                            final mainScreenState = context
                                .findAncestorStateOfType<_MainScreenState>();
                            mainScreenState?._refreshContentScale();
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

  /// 在子项之间添加分隔线
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

  /// 构建设置项
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
        style: const TextStyle(fontSize: 15),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
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
  bool _skipUserSettings = false;
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
    final skipSettings = await _preferencesService.getSkipUserSettings();
    setState(() {
      _recordCount = count;
      _autoCleanupDays = days;
      _neverAskAgain = neverAsk;
      _autoCheckDictUpdate = autoCheck;
      _skipUserSettings = skipSettings;
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
                        // AI聊天记录管理
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
                        // 英语词典数据库设置
                        _buildSectionTitle(context, '英语词典数据库设置'),
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
                        const SizedBox(height: 24),
                        // 调试设置
                        _buildSectionTitle(context, '调试设置'),
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
                              Icons.bug_report,
                              color: colorScheme.primary,
                            ),
                            title: const Text('不加载用户设置'),
                            subtitle: const Text('重新启动后生效，用于调试'),
                            trailing: Switch(
                              value: _skipUserSettings,
                              onChanged: (value) async {
                                await _preferencesService.setSkipUserSettings(
                                  value,
                                );
                                setState(() {
                                  _skipUserSettings = value;
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // 词典更新设置
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
                                setState(() {
                                  _autoCheckDictUpdate = value;
                                });
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
                        title: Text(_getActionLabel(_order[index])),
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

    if (contentScale == 1.0) {
      return dialog;
    }

    return PageScaleWrapper(scale: contentScale, child: dialog);
  }
}

// 底部工具栏设置弹窗
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

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

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

    if (contentScale == 1.0) {
      return dialog;
    }

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
          title: Icon(_getActionIcon(action), size: 20),
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
