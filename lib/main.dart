import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'pages/dictionary_search.dart';
import 'core/theme_provider.dart';
import 'core/locale_provider.dart';
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
import 'services/app_update_service.dart';
import 'services/zstd_service.dart';
import 'services/advanced_search_settings_service.dart';
import 'services/clipboard_watcher_service.dart';
import 'services/system_tray_service.dart';
import 'core/utils/toast_utils.dart';
import 'core/logger.dart';
import 'components/global_scale_wrapper.dart';
import 'i18n/strings.g.dart';

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

  // 初始化 slang 翻译（必须在所有 UI 创建之前）
  LocaleSettings.useDeviceLocaleSync();

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

  // 加载词典启用顺序和语言顺序到缓存（用于词典内容界面排序）
  try {
    await DictionaryManager().loadEnabledDictionariesToCache();
    Logger.i('词典启用顺序缓存加载完成', tag: 'Startup');
  } catch (e) {
    Logger.w('词典启用顺序缓存加载失败: $e', tag: 'Startup');
  }

  try {
    await AdvancedSearchSettingsService().loadLanguageOrderToCache();
    Logger.i('语言顺序缓存加载完成', tag: 'Startup');
  } catch (e) {
    Logger.w('语言顺序缓存加载失败: $e', tag: 'Startup');
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

  // 初始化语言设置（读取用户存储的偏好并应用）
  try {
    await LocaleProvider().initialize();
    Logger.i('语言设置初始化完成', tag: 'Startup');
  } catch (e) {
    Logger.w('语言设置初始化失败: $e', tag: 'Startup');
  }

  // 初始化窗口管理器（仅桌面平台）
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    try {
      await windowManager.ensureInitialized();
      final windowState = await WindowStateService().getWindowState();

      WindowOptions windowOptions = WindowOptions(
        size: Size(windowState['width']!, windowState['height']!),
        center: windowState['posX'] == null || windowState['posY'] == null,
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

      // 同步标题栏深浅色（跟随应用主题设置）
      final themeModeIndex = prefs.getInt('theme_mode');
      final savedIsDark = themeModeIndex == 1; // 1 = dark
      await windowManager.setBrightness(
        savedIsDark ? Brightness.dark : Brightness.light,
      );

      // 设置阻止窗口关闭（根据用户设置决定是否最小化到托盘）
      final prefsService = PreferencesService();
      final shouldMinimizeToTray = await prefsService.shouldMinimizeToTray();
      await windowManager.setPreventClose(shouldMinimizeToTray);

      Logger.i('窗口管理器初始化完成', tag: 'Startup');
    } catch (e) {
      Logger.e('窗口管理器初始化失败: $e', tag: 'Startup');
    }

    // 初始化系统托盘和剪切板监听（仅桌面平台）
    try {
      // 初始化系统托盘
      await SystemTrayService().initialize();
      Logger.i('系统托盘初始化完成', tag: 'Startup');

      // 初始化剪切板监听
      await ClipboardWatcherService().initialize();
      Logger.i('剪切板监听服务初始化完成', tag: 'Startup');

      // 根据设置启动剪切板监听
      final prefsService = PreferencesService();
      if (await prefsService.isClipboardWatchEnabled()) {
        await ClipboardWatcherService().startWatching();
        Logger.i('剪切板监听已启动', tag: 'Startup');
      }
    } catch (e) {
      Logger.e('系统托盘或剪切板监听初始化失败: $e', tag: 'Startup');
    }
  }

  runApp(
    TranslationProvider(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (context) => ThemeProvider(prefs!)),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ChangeNotifierProvider(create: (context) => DownloadManager()),
          ChangeNotifierProvider(create: (context) => UploadManager()),
          ChangeNotifierProvider(create: (context) => DictUpdateCheckService()),
          ChangeNotifierProvider(create: (context) => AppUpdateService()),
        ],
        child: const MyApp(),
      ),
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
  bool _isMultiWindow = false;
  // 缓存上次发给 Android 的 windowBackground 颜色，避免每帧都发 MethodChannel
  int? _lastWindowBgColor;
  // 缓存上次同步给桌面端标题栏的亮度，避免重复调用
  Brightness? _lastTitleBarBrightness;
  static const _windowChannel = MethodChannel('com.keskai.easydict/window');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    _windowChannel.setMethodCallHandler(_handleWindowChannelCall);
    Logger.i('MyApp initState', tag: 'MyApp');
  }

  Future<dynamic> _handleWindowChannelCall(MethodCall call) async {
    if (call.method != 'onMultiWindowModeChanged') return;
    final args = call.arguments as Map? ?? {};
    final isMultiWindow = args['isMultiWindow'] as bool? ?? false;
    Logger.i(
      '[WindowChannel] 收到小窗状态: isMultiWindow=$isMultiWindow '
      'captionBarHeight=${args["captionBarHeight"]} '
      'bottomBarHeight=${args["bottomBarHeight"]}',
      tag: 'EasyDictWindow',
    );
    if (!mounted) return;
    if (_isMultiWindow != isMultiWindow) {
      setState(() => _isMultiWindow = isMultiWindow);
      Logger.i(
        '[WindowChannel] setState: _isMultiWindow 更新为 $isMultiWindow',
        tag: 'EasyDictWindow',
      );
    } else {
      Logger.i(
        '[WindowChannel] _isMultiWindow 无变化，跳过 setState',
        tag: 'EasyDictWindow',
      );
    }
  }

  @override
  void dispose() {
    _windowChannel.setMethodCallHandler(null);
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
  Future<bool> onWindowClose() async {
    await _saveWindowState();

    // 检查是否应该最小化到托盘
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final prefs = PreferencesService();
      final shouldMinimizeToTray = await prefs.shouldMinimizeToTray();

      if (shouldMinimizeToTray) {
        // 最小化到托盘而不是关闭
        await windowManager.hide();
        Logger.i('窗口已最小化到托盘', tag: 'MyApp');
        // 返回 false 阻止窗口关闭
        return false;
      }
    }

    // 返回 true 允许窗口关闭
    return true;
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
      Logger.d(
        '保存窗口状态: size=${bounds.width.toInt()}x${bounds.height.toInt()}, '
        'pos=(${bounds.left.toInt()}, ${bounds.top.toInt()}), maximized=$isMaximized',
        tag: 'WindowState',
      );
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

  /// 把 Flutter 主题的 surface 颜色同步给 Android window background，
  /// 使小窗顶栏/底栏（由系统用 windowBackground 渲染）与 App 内容颜色精确匹配。
  /// 只在颜色真正变化时才发 MethodChannel，避免每帧都通信。
  /// 同步桌面端标题栏深浅色，跟随应用当前主题。
  void _syncTitleBarBrightness(bool isDark) {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;
    final brightness = isDark ? Brightness.dark : Brightness.light;
    if (_lastTitleBarBrightness == brightness) return;
    _lastTitleBarBrightness = brightness;
    windowManager.setBrightness(brightness).catchError((e) {
      Logger.w('同步标题栏亮度失败: $e', tag: 'MyApp');
    });
  }

  void _syncWindowBackground(Color color) {
    if (!Platform.isAndroid) return;
    final argb = color.toARGB32();
    if (_lastWindowBgColor == argb) return;
    _lastWindowBgColor = argb;
    _windowChannel
        .invokeMethod<void>('setWindowBackground', {'color': argb})
        .catchError((e) {
          Logger.w('setWindowBackground 失败: $e', tag: 'MyApp');
        });
  }

  @override
  Widget build(BuildContext context) {
    Logger.i('MyApp build 开始', tag: 'MyApp');
    try {
      return Consumer2<ThemeProvider, LocaleProvider>(
        builder: (context, themeProvider, localeProvider, child) {
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
            locale: localeProvider.flutterLocale,
            // supportedLocales 由 slang 自动维护，始终包含全部已配置语种
            supportedLocales: AppLocaleUtils.supportedLocales,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: theme,
            darkTheme: AppTheme.darkTheme(seedColor: themeProvider.seedColor),
            themeMode: themeMode,
            navigatorObservers: [toastRouteObserver],
            home: const MainScreen(),
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              final brightness = mq.platformBrightness;
              final isDark =
                  themeMode == ThemeMode.dark ||
                  (themeMode == ThemeMode.system &&
                      brightness == Brightness.dark);

              // Logger.i(
              //   '[WindowDebug] builder: _isMultiWindow=$_isMultiWindow '
              //   'padding.top=${mq.padding.top} padding.bottom=${mq.padding.bottom} '
              //   'viewPadding.top=${mq.viewPadding.top} viewPadding.bottom=${mq.viewPadding.bottom} '
              //   'size=${mq.size.width.toInt()}x${mq.size.height.toInt()}',
              //   tag: 'EasyDictWindow',
              // );

              final surfaceColor = Theme.of(context).colorScheme.surface;
              _syncWindowBackground(surfaceColor);
              _syncTitleBarBrightness(isDark);

              Widget content = ErrorBoundary(child: child ?? const SizedBox());
              if (_isMultiWindow) {
                Logger.i(
                  '[WindowDebug] 小窗模式激活：将 padding/viewPadding 顶底归零',
                  tag: 'EasyDictWindow',
                );
                content = MediaQuery(
                  data: mq.copyWith(
                    padding: mq.padding.copyWith(top: 0, bottom: 0),
                    viewPadding: mq.viewPadding.copyWith(top: 0, bottom: 0),
                  ),
                  child: content,
                );
              }

              // 全局 UI 缩放：在最顶层用 ScaleLayoutWrapper（RenderObject 变换）
              // 统一缩放所有 UI 元素（文字、图标、边距均等比缩放），
              // 无需在每个页面单独包裹。
              return ValueListenableBuilder<double>(
                valueListenable:
                    FontLoaderService().dictionaryContentScaleNotifier,
                builder: (context, scale, _) {
                  // 始终保持 ScaleLayoutWrapper 在树中，避免 scale 在 1.0/非1.0 间切换时
                  // 因子节点类型变化导致全局 widget 树（包括 _LazyImageLoader）被销毁重建
                  final scaledContent = ScaleLayoutWrapper(
                    scale: scale,
                    child: content,
                  );
                  return AnnotatedRegion<SystemUiOverlayStyle>(
                    value: isDark
                        ? AppTheme.darkSystemUiOverlayStyle()
                        : AppTheme.lightSystemUiOverlayStyle(),
                    child: scaledContent,
                  );
                },
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
    _initAppUpdateCheck();
  }

  Future<void> _initAppUpdateCheck() async {
    final appUpdateService = context.read<AppUpdateService>();
    appUpdateService.checkOnStartup();
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
    super.dispose();
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
    // showBadgeDot: 显示小红点（无数字）而不是数字标签
    final dotVisible = showBadgeDot && showBadge;
    final labelVisible = !showBadgeDot && showBadge;

    return NavigationDestination(
      icon: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Badge(
          isLabelVisible: dotVisible || labelVisible,
          label: labelVisible ? Text('$badgeCount') : null,
          smallSize: dotVisible ? 8 : null,
          child: Icon(icon),
        ),
      ),
      selectedIcon: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Badge(
          isLabelVisible: dotVisible || labelVisible,
          label: labelVisible ? Text('$badgeCount') : null,
          smallSize: dotVisible ? 8 : null,
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
    final appUpdateService = context.watch<AppUpdateService>();
    final dictUpdateCount = updateCheckService.updatableCount;
    // 字典更新或应用更新均在设置层tab显示小红点
    final hasAnyUpdate = dictUpdateCount > 0 || appUpdateService.hasUpdate;

    final bottomNav = NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: _onTabSelected,
      destinations: [
        _buildNavigationDestination(
          icon: Icons.search_outlined,
          selectedIcon: Icons.search,
          label: context.t.nav.search,
          index: 0,
        ),
        _buildNavigationDestination(
          icon: Icons.style_outlined,
          selectedIcon: Icons.style,
          label: context.t.nav.wordBank,
          index: 1,
        ),
        _buildNavigationDestination(
          icon: Icons.tune_outlined,
          selectedIcon: Icons.tune,
          label: context.t.nav.settings,
          index: 2,
          badgeCount: hasAnyUpdate ? 1 : null,
          showBadgeDot: true,
        ),
      ],
    );

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: bottomNav,
    );
  }
}
