import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class Logger {
  static const String _name = 'EasyDict';

  // 通过 dart-define 控制日志开关
  // 开发时运行: flutter run --dart-define=ENABLE_LOG=true
  // Release 调试: flutter build windows --dart-define=ENABLE_LOG=true
  static const bool _enableLog = bool.fromEnvironment(
    'ENABLE_LOG',
    defaultValue: false,
  );

  // 是否输出到文件（用于 Release 模式调试）
  static const bool _logToFile = bool.fromEnvironment(
    'LOG_TO_FILE',
    defaultValue: false,
  );

  static File? _logFile;
  static bool _fileInitialized = false;

  static String _getTimeString() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
  }

  static Future<void> _initLogFile() async {
    if (_fileInitialized) return;
    try {
      final appDir = await getApplicationSupportDirectory();
      final logDir = Directory('${appDir.path}\\logs');
      if (!logDir.existsSync()) {
        logDir.createSync(recursive: true);
      }
      final now = DateTime.now();
      final logPath =
          '${logDir.path}\\app_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.log';
      _logFile = File(logPath);
      _fileInitialized = true;
    } catch (e) {
      // 文件初始化失败不影响应用运行
    }
  }

  static void _writeToFile(String message) async {
    if (!_logToFile) return;
    try {
      await _initLogFile();
      if (_logFile != null) {
        final timestamp = DateTime.now().toIso8601String();
        _logFile!.writeAsStringSync(
          '$timestamp $message\n',
          mode: FileMode.append,
        );
      }
    } catch (e) {
      // 写入失败不影响应用运行
    }
  }

  static void d(String message, {String? tag}) {
    if (!_enableLog && !_logToFile) return;
    _log('🐛 DEBUG', message, tag: tag);
  }

  static void i(String message, {String? tag}) {
    if (!_enableLog && !_logToFile) return;
    _log('ℹ️ INFO', message, tag: tag);
  }

  static void w(String message, {String? tag}) {
    if (!_enableLog && !_logToFile) return;
    _log('⚠️ WARN', message, tag: tag);
  }

  static void e(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!_enableLog && !_logToFile) return;
    _log('❌ ERROR', message, tag: tag);
    if (error != null) {
      final errorMsg = 'Error: $error';
      _output(errorMsg);
      if (stackTrace != null) {
        _output('StackTrace: $stackTrace');
      }
    }
  }

  static void _log(String level, String message, {String? tag}) {
    final tagStr = tag != null ? '[$tag] ' : '';
    final logMessage = '${_getTimeString()} $level $tagStr$message';
    _output(logMessage);
    _writeToFile(logMessage);
  }

  static void _output(String message) {
    if (_enableLog) {
      debugPrint(message);
    }
  }

  /// 获取日志文件路径（用于调试）
  static String? getLogFilePath() {
    return _logFile?.path;
  }
}
