import 'dart:io';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../core/logger.dart';
import 'preferences_service.dart';
import 'clipboard_watcher_service.dart';

/// 系统托盘服务
/// 管理系统托盘图标和菜单
class SystemTrayService with TrayListener {
  static final SystemTrayService _instance = SystemTrayService._internal();
  factory SystemTrayService() => _instance;
  SystemTrayService._internal();

  /// 是否已初始化
  bool _isInitialized = false;

  /// 剪切板监听是否启用（用于菜单状态）
  bool _clipboardWatchEnabled = false;

  /// 最小化到托盘是否启用
  bool _minimizeToTrayEnabled = true;

  /// 菜单项 ID
  static const String _menuIdShowWindow = 'show_window';
  static const String _menuIdClipboardWatch = 'clipboard_watch';
  static const String _menuIdMinimizeToTray = 'minimize_to_tray';
  static const String _menuIdExit = 'exit';

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 初始化系统托盘
  Future<void> initialize() async {
    if (_isInitialized) return;

    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      Logger.i('系统托盘仅支持桌面平台，当前平台不支持', tag: 'SystemTray');
      return;
    }

    try {
      // 读取设置状态
      final prefs = PreferencesService();
      _clipboardWatchEnabled = await prefs.isClipboardWatchEnabled();
      _minimizeToTrayEnabled = await prefs.shouldMinimizeToTray();

      // 设置托盘图标
      await _setTrayIcon();

      // 设置托盘提示文本
      await trayManager.setToolTip('EasyDict');

      // 设置托盘菜单
      await _updateMenu();

      // 添加监听器
      trayManager.addListener(this);

      _isInitialized = true;
      Logger.i('系统托盘初始化完成', tag: 'SystemTray');
    } catch (e, stackTrace) {
      Logger.e('系统托盘初始化失败: $e', tag: 'SystemTray', stackTrace: stackTrace);
    }
  }

  /// 设置托盘图标
  Future<void> _setTrayIcon() async {
    try {
      if (Platform.isWindows) {
        // Windows: 必须使用 .ico 文件
        final iconPath = await _getWindowsIconPath();
        await trayManager.setIcon(iconPath);
        Logger.i('Windows 托盘图标设置成功: $iconPath', tag: 'SystemTray');
      } else if (Platform.isMacOS) {
        // macOS: 需要将图标复制到文件系统使用绝对路径
        final iconPath = await _getMacOSIconPath();
        await trayManager.setIcon(iconPath);
        Logger.i('macOS 托盘图标设置成功: $iconPath', tag: 'SystemTray');
      } else if (Platform.isLinux) {
        // Linux: 使用绝对路径
        final iconPath = await _getLinuxIconPath();
        await trayManager.setIcon(iconPath);
        Logger.i('Linux 托盘图标设置成功: $iconPath', tag: 'SystemTray');
      }
    } catch (e, stackTrace) {
      Logger.e('设置托盘图标失败: $e', tag: 'SystemTray', stackTrace: stackTrace);
    }
  }

  /// 获取 Windows 平台的图标路径
  /// 将 assets 中的 .ico 文件复制到文件系统
  Future<String> _getWindowsIconPath() async {
    try {
      // 获取应用支持目录
      final appDir = await getApplicationSupportDirectory();
      final iconFile = File('${appDir.path}/tray_icon.ico');

      // 如果图标文件不存在，从 assets 复制
      if (!await iconFile.exists()) {
        final byteData = await rootBundle.load('assets/icon/app_icon.ico');
        final buffer = byteData.buffer;
        await iconFile.create(recursive: true);
        await iconFile.writeAsBytes(
          buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
        );
        Logger.i('托盘图标(.ico)已复制到: ${iconFile.path}', tag: 'SystemTray');
      }

      return iconFile.path;
    } catch (e) {
      Logger.e('获取 Windows 托盘图标路径失败: $e', tag: 'SystemTray');
      rethrow;
    }
  }

  /// 获取 macOS 平台的图标路径
  /// 将 assets 中的 .png 文件复制到文件系统
  Future<String> _getMacOSIconPath() async {
    try {
      // 获取应用支持目录
      final appDir = await getApplicationSupportDirectory();
      final iconFile = File('${appDir.path}/tray_icon.png');

      // 如果图标文件不存在，从 assets 复制
      if (!await iconFile.exists()) {
        final byteData = await rootBundle.load('assets/icon/app_icon.png');
        final buffer = byteData.buffer;
        await iconFile.create(recursive: true);
        await iconFile.writeAsBytes(
          buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
        );
        Logger.i('托盘图标(.png)已复制到: ${iconFile.path}', tag: 'SystemTray');
      }

      return iconFile.path;
    } catch (e) {
      Logger.e('获取 macOS 托盘图标路径失败: $e', tag: 'SystemTray');
      rethrow;
    }
  }

  /// 获取 Linux 平台的图标路径
  Future<String> _getLinuxIconPath() async {
    try {
      // 获取应用支持目录
      final appDir = await getApplicationSupportDirectory();
      final iconFile = File('${appDir.path}/tray_icon.png');

      // 如果图标文件不存在，从 assets 复制
      if (!await iconFile.exists()) {
        final byteData = await rootBundle.load('assets/icon/app_icon.png');
        final buffer = byteData.buffer;
        await iconFile.create(recursive: true);
        await iconFile.writeAsBytes(
          buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
        );
        Logger.i('托盘图标(.png)已复制到: ${iconFile.path}', tag: 'SystemTray');
      }

      return iconFile.path;
    } catch (e) {
      Logger.e('获取 Linux 托盘图标路径失败: $e', tag: 'SystemTray');
      rethrow;
    }
  }

  /// 更新托盘菜单
  Future<void> _updateMenu() async {
    final menu = Menu(
      items: [
        MenuItem(key: _menuIdShowWindow, label: '显示窗口'),
        MenuItem.separator(),
        MenuItem.checkbox(
          key: _menuIdClipboardWatch,
          label: '剪切板监听',
          checked: _clipboardWatchEnabled,
        ),
        MenuItem.checkbox(
          key: _menuIdMinimizeToTray,
          label: '最小化到托盘',
          checked: _minimizeToTrayEnabled,
        ),
        MenuItem.separator(),
        MenuItem(key: _menuIdExit, label: '退出'),
      ],
    );

    await trayManager.setContextMenu(menu);
  }

  /// 更新剪切板监听菜单状态
  Future<void> updateClipboardWatchState(bool enabled) async {
    _clipboardWatchEnabled = enabled;
    await _updateMenu();
  }

  /// 更新最小化到托盘菜单状态
  Future<void> updateMinimizeToTrayState(bool enabled) async {
    _minimizeToTrayEnabled = enabled;
    await _updateMenu();
  }

  /// 显示窗口
  Future<void> showWindow() async {
    try {
      await windowManager.show();
      await windowManager.focus();
      Logger.i('窗口已显示', tag: 'SystemTray');
    } catch (e) {
      Logger.e('显示窗口失败: $e', tag: 'SystemTray');
    }
  }

  /// 隐藏窗口（最小化到托盘）
  Future<void> hideWindow() async {
    try {
      await windowManager.hide();
      Logger.i('窗口已隐藏到托盘', tag: 'SystemTray');
    } catch (e) {
      Logger.e('隐藏窗口失败: $e', tag: 'SystemTray');
    }
  }

  /// 托盘图标点击事件（左键）
  @override
  void onTrayIconMouseDown() {
    // 左键点击：显示窗口并置顶
    _showWindowAndFocus();
  }

  /// 托盘图标右键点击事件
  @override
  void onTrayIconRightMouseDown() {
    // 右键点击：弹出菜单
    trayManager.popUpContextMenu();
  }

  /// 托盘图标鼠标进入事件（macOS 特有）
  @override
  void onTrayIconMouseEnter() {
    // macOS: 鼠标进入托盘图标
  }

  /// 托盘图标鼠标离开事件（macOS 特有）
  @override
  void onTrayIconMouseExit() {
    // macOS: 鼠标离开托盘图标
  }

  /// 显示窗口并置顶（与剪贴板触发行为一致）
  Future<void> _showWindowAndFocus() async {
    try {
      final isVisible = await windowManager.isVisible();

      if (!isVisible) {
        // 显示窗口并置顶
        await windowManager.setAlwaysOnTop(true);
        await windowManager.show();
        await windowManager.focus();
        // 短暂延迟后取消置顶
        Future.delayed(const Duration(milliseconds: 500), () async {
          await windowManager.setAlwaysOnTop(false);
        });
        Logger.i('窗口已显示并置顶', tag: 'SystemTray');
      } else {
        // 窗口已可见，临时置顶获得焦点
        await windowManager.setAlwaysOnTop(true);
        await windowManager.focus();
        Future.delayed(const Duration(milliseconds: 500), () async {
          await windowManager.setAlwaysOnTop(false);
        });
      }
    } catch (e) {
      Logger.e('显示窗口失败: $e', tag: 'SystemTray');
    }
  }

  /// 托盘菜单项点击事件
  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    Logger.d('菜单项点击: ${menuItem.key}', tag: 'SystemTray');
    switch (menuItem.key) {
      case _menuIdShowWindow:
        showWindow();
        break;
      case _menuIdClipboardWatch:
        _toggleClipboardWatch();
        break;
      case _menuIdMinimizeToTray:
        _toggleMinimizeToTray();
        break;
      case _menuIdExit:
        _exitApp();
        break;
    }
  }

  /// 切换剪切板监听状态
  Future<void> _toggleClipboardWatch() async {
    final newState = !_clipboardWatchEnabled;
    _clipboardWatchEnabled = newState;

    // 更新设置
    final prefs = PreferencesService();
    await prefs.setClipboardWatchEnabled(newState);

    // 更新剪切板监听服务
    await ClipboardWatcherService().setEnabled(newState);

    // 更新菜单
    await _updateMenu();

    Logger.i('剪切板监听状态已切换: $newState', tag: 'SystemTray');
  }

  /// 切换最小化到托盘状态
  Future<void> _toggleMinimizeToTray() async {
    final newState = !_minimizeToTrayEnabled;
    _minimizeToTrayEnabled = newState;

    // 更新设置
    final prefs = PreferencesService();
    await prefs.setMinimizeToTray(newState);

    // 更新窗口管理器的 preventClose 设置
    await windowManager.setPreventClose(newState);

    // 更新菜单
    await _updateMenu();

    Logger.i('最小化到托盘状态已切换: $newState', tag: 'SystemTray');
  }

  /// 退出应用
  Future<void> _exitApp() async {
    Logger.i('用户从托盘退出应用', tag: 'SystemTray');

    // 清理资源
    await trayManager.destroy();

    // 退出应用
    SystemNavigator.pop();
  }

  /// 释放资源
  Future<void> dispose() async {
    trayManager.removeListener(this);
    await trayManager.destroy();
    _isInitialized = false;
  }
}
