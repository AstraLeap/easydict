import 'dart:async';
import 'dart:io';
import 'package:clipboard_watcher/clipboard_watcher.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../core/logger.dart';
import 'preferences_service.dart';
import 'entry_event_bus.dart';

/// 剪切板监听服务
/// 监听系统剪切板变化，当用户复制文本时自动弹出窗口并搜索
/// 
/// Linux平台说明：
/// 由于clipboard_watcher在Wayland环境下无法正常工作（监听的是PRIMARY选择区而非CLIPBOARD），
/// 在Linux上使用定时轮询方式检测剪贴板变化。
class ClipboardWatcherService with ClipboardListener {
  static final ClipboardWatcherService _instance =
      ClipboardWatcherService._internal();
  factory ClipboardWatcherService() => _instance;
  ClipboardWatcherService._internal();

  /// 是否已初始化
  bool _isInitialized = false;

  /// 是否正在监听
  bool _isWatching = false;

  /// 是否启用（用户设置）
  bool _isEnabled = false;

  /// 上次剪切板文本（防止重复处理）
  String? _lastClipboardText;

  /// 上次处理时间（防抖）
  DateTime? _lastProcessTime;

  /// 防抖间隔（毫秒）
  static const int _debounceInterval = 300;

  /// 最小文本长度
  static const int minTextLength = 2;

  /// 最大文本长度（按字符计算，中文算2个字符）
  static const int maxTextLength = 20;

  /// Linux轮询间隔（毫秒）
  static const int _linuxPollingInterval = 500;

  /// Linux轮询定时器
  Timer? _linuxPollingTimer;

  /// 搜索事件控制器
  final _searchEventController = StreamController<String>.broadcast();

  /// 搜索事件流（供外部监听）
  Stream<String> get onSearchRequested => _searchEventController.stream;

  /// 是否正在监听
  bool get isWatching => _isWatching;

  /// 是否启用
  bool get isEnabled => _isEnabled;

  /// 初始化服务
  Future<void> initialize() async {
    if (_isInitialized) return;

    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      Logger.i('剪切板监听仅支持桌面平台，当前平台不支持', tag: 'ClipboardWatcher');
      return;
    }

    try {
      // 读取用户设置
      final prefs = PreferencesService();
      _isEnabled = await prefs.isClipboardWatchEnabled();

      // 非Linux平台注册剪切板监听器
      if (!Platform.isLinux) {
        clipboardWatcher.addListener(this);
      }

      _isInitialized = true;
      Logger.i('剪切板监听服务初始化完成，启用状态: $_isEnabled，平台: ${Platform.operatingSystem}', tag: 'ClipboardWatcher');
    } catch (e) {
      Logger.e('剪切板监听服务初始化失败: $e', tag: 'ClipboardWatcher');
    }
  }

  /// 开始监听剪切板
  Future<void> startWatching() async {
    if (!_isInitialized) {
      Logger.w('剪切板监听服务未初始化', tag: 'ClipboardWatcher');
      return;
    }

    if (_isWatching) {
      Logger.d('剪切板监听已在运行', tag: 'ClipboardWatcher');
      return;
    }

    try {
      if (Platform.isLinux) {
        // Linux使用轮询方式（兼容Wayland）
        _startLinuxPolling();
        _isWatching = true;
        Logger.i('Linux剪切板轮询已启动（Wayland兼容模式）', tag: 'ClipboardWatcher');
      } else {
        // Windows/macOS使用事件监听
        await clipboardWatcher.start();
        _isWatching = true;
        Logger.i('剪切板监听已启动', tag: 'ClipboardWatcher');
      }
    } catch (e) {
      Logger.e('启动剪切板监听失败: $e', tag: 'ClipboardWatcher');
    }
  }

  /// 停止监听剪切板
  Future<void> stopWatching() async {
    if (!_isWatching) return;

    try {
      if (Platform.isLinux) {
        _stopLinuxPolling();
      } else {
        await clipboardWatcher.stop();
      }
      _isWatching = false;
      Logger.i('剪切板监听已停止', tag: 'ClipboardWatcher');
    } catch (e) {
      Logger.e('停止剪切板监听失败: $e', tag: 'ClipboardWatcher');
    }
  }

  /// 启动Linux轮询
  void _startLinuxPolling() {
    _stopLinuxPolling();
    _linuxPollingTimer = Timer.periodic(
      const Duration(milliseconds: _linuxPollingInterval),
      (_) => _linuxPollClipboard(),
    );
  }

  /// 停止Linux轮询
  void _stopLinuxPolling() {
    _linuxPollingTimer?.cancel();
    _linuxPollingTimer = null;
  }

  /// Linux轮询剪贴板
  Future<void> _linuxPollClipboard() async {
    if (!_isEnabled) return;
    await _processClipboard();
  }

  /// 设置启用状态
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;

    // 保存设置
    final prefs = PreferencesService();
    await prefs.setClipboardWatchEnabled(enabled);

    // 根据设置启动或停止监听
    if (enabled) {
      await startWatching();
    } else {
      await stopWatching();
    }

    Logger.i('剪切板监听启用状态已更新: $enabled', tag: 'ClipboardWatcher');
  }

  /// ClipboardListener 回调 - 剪切板变化
  @override
  void onClipboardChanged() {
    if (!_isEnabled) return;

    // 防抖检查
    final now = DateTime.now();
    if (_lastProcessTime != null &&
        now.difference(_lastProcessTime!).inMilliseconds < _debounceInterval) {
      return;
    }

    _processClipboard();
  }

  /// 处理剪切板内容
  Future<void> _processClipboard() async {
    try {
      // 读取剪切板文本
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipboardData?.text;

      if (text == null || text.isEmpty) {
        return;
      }

      // 过滤检查
      if (!_shouldProcessText(text)) {
        Logger.d('剪切板文本被过滤: ${text.length} 字符', tag: 'ClipboardWatcher');
        return;
      }

      // 更新状态
      _lastClipboardText = text;
      _lastProcessTime = DateTime.now();

      Logger.i('剪切板文本已捕获: ${text.length} 字符', tag: 'ClipboardWatcher');

      // 发送搜索事件
      _searchEventController.add(text);

      // 显示窗口
      await _showWindowAndSearch(text);
    } catch (e) {
      Logger.e('处理剪切板内容失败: $e', tag: 'ClipboardWatcher');
    }
  }

  /// 判断是否应该处理该文本
  bool _shouldProcessText(String text) {
    // 去除首尾空白
    final trimmedText = text.trim();

    // 1. 空白检查
    if (trimmedText.isEmpty) {
      return false;
    }

    // 2. 长度检查（使用字符权重计算，中文算2个字符）
    final weightedLength = _calculateWeightedLength(trimmedText);
    if (weightedLength < minTextLength) {
      return false;
    }

    if (weightedLength > maxTextLength) {
      return false;
    }

    // 3. 排除包含数字的文本
    if (RegExp(r'\d').hasMatch(trimmedText)) {
      return false;
    }

    // 4. 排除纯空白字符
    if (RegExp(r'^\s+$').hasMatch(text)) {
      return false;
    }

    // 5. 防重复处理
    if (text == _lastClipboardText) {
      return false;
    }

    return true;
  }

  /// 计算文本的加权长度（中文字符算2个，其他字符算1个）
  int _calculateWeightedLength(String text) {
    int length = 0;
    for (final codeUnit in text.codeUnits) {
      // 中文字符范围：0x4E00 - 0x9FFF（基本汉字）
      // 扩展汉字范围：0x3400 - 0x4DBF, 0x20000 - 0x2A6DF, 0x2A700 - 0x2B73F, 0x2B740 - 0x2B81F
      // 日文汉字等：0x2E80 - 0x9FFF
      if (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) {
        // 基本汉字
        length += 2;
      } else if (codeUnit >= 0x3400 && codeUnit <= 0x4DBF) {
        // 扩展A区汉字
        length += 2;
      } else if (codeUnit >= 0x3000 && codeUnit <= 0x303F) {
        // CJK符号和标点（中文标点）
        length += 2;
      } else if (codeUnit >= 0xFF00 && codeUnit <= 0xFFEF) {
        // 半角及全角字符（全角字母、数字、标点）
        length += 2;
      } else {
        // 其他字符（英文、数字、符号等）
        length += 1;
      }
    }
    return length;
  }

  /// 显示窗口并搜索
  Future<void> _showWindowAndSearch(String text) async {
    try {
      // 检查窗口是否可见
      final isVisible = await windowManager.isVisible();

      if (!isVisible) {
        // 显示窗口并置顶
        await windowManager.setAlwaysOnTop(true);
        await windowManager.show();
        await windowManager.focus();
        // 短暂延迟后取消置顶，让窗口显示在最前但不永久置顶
        Future.delayed(const Duration(milliseconds: 500), () async {
          await windowManager.setAlwaysOnTop(false);
        });
        Logger.i('窗口已显示并置顶', tag: 'ClipboardWatcher');
      } else {
        // 窗口已可见，临时置顶获得焦点
        await windowManager.setAlwaysOnTop(true);
        await windowManager.focus();
        Future.delayed(const Duration(milliseconds: 500), () async {
          await windowManager.setAlwaysOnTop(false);
        });
      }

      // 发送搜索事件（通过全局事件总线）
      EntryEventBus().emitClipboardSearch(ClipboardSearchEvent(text));
    } catch (e) {
      Logger.e('显示窗口失败: $e', tag: 'ClipboardWatcher');
    }
  }

  /// 释放资源
  void dispose() {
    stopWatching();
    _stopLinuxPolling();
    if (!Platform.isLinux) {
      clipboardWatcher.removeListener(this);
    }
    _searchEventController.close();
    _isInitialized = false;
  }
}
