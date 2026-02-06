import 'package:flutter/foundation.dart';

class Logger {
  static const String _name = 'EasyDict';

  static String _getTimeString() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
  }

  static void d(String message, {String? tag}) {
    _log('🐛 DEBUG', message, tag: tag);
  }

  static void i(String message, {String? tag}) {
    _log('ℹ️ INFO', message, tag: tag);
  }

  static void w(String message, {String? tag}) {
    _log('⚠️ WARN', message, tag: tag);
  }

  static void e(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
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
  }

  static void _output(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }
}
