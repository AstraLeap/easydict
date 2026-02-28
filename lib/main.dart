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
import 'pages/settings_page.dart';
import 'services/dictionary_manager.dart';
import 'services/download_manager.dart';
import 'services/upload_manager.dart';
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
    await DictionaryManager().preloadActiveLanguageDatabases();
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
    SettingsPage(contentScaleNotifier: _contentScaleNotifier),
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

