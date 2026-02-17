import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core/logger.dart';

/// 数据库初始化管理器
/// 确保 sqflite FFI 只初始化一次
class DatabaseInitializer {
  static final DatabaseInitializer _instance = DatabaseInitializer._internal();
  factory DatabaseInitializer() => _instance;
  DatabaseInitializer._internal();

  bool _initialized = false;

  /// 初始化数据库工厂（线程安全，只执行一次）
  void initialize() {
    if (_initialized) {
      return;
    }

    if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _initialized = true;
    } else {
      _initialized = true;
    }
  }

  /// 获取初始化状态
  bool get isInitialized => _initialized;
}
