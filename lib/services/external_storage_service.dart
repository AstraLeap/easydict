import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

import '../core/logger.dart';

/// 安卓外部存储权限与路径辅助服务。
/// 用于支持用户选择应用沙盒之外的目录存放词典，
/// 使词典文件在软件卸载/更新后仍然保留。
class ExternalStorageService {
  static final ExternalStorageService _instance =
      ExternalStorageService._internal();
  factory ExternalStorageService() => _instance;
  ExternalStorageService._internal();

  /// 默认的跨重装持久化词典目录（/sdcard/EasyDict/dictionaries）。
  static const String defaultPersistentDir =
      '/storage/emulated/0/EasyDict/dictionaries';

  // ─── 权限查询 ───────────────────────────────────────────────

  /// 是否已获得「所有文件访问」权限（MANAGE_EXTERNAL_STORAGE，Android 11+）。
  Future<bool> hasManageStoragePermission() async {
    if (!Platform.isAndroid) return false;
    return await Permission.manageExternalStorage.isGranted;
  }

  /// 当前「所有文件访问」权限状态（Android 11+）。
  Future<PermissionStatus> manageStorageStatus() async {
    if (!Platform.isAndroid) return PermissionStatus.granted;
    return await Permission.manageExternalStorage.status;
  }

  // ─── 权限请求 ───────────────────────────────────────────────

  /// 请求「所有文件访问」权限（Android 11+）。
  /// 系统会弹出跳转到"管理所有文件"设置页的指引，用户需手动开启。
  /// 返回请求结果 [PermissionStatus]。
  Future<PermissionStatus> requestManageStoragePermission() async {
    if (!Platform.isAndroid) return PermissionStatus.granted;
    return await Permission.manageExternalStorage.request();
  }

  /// 打开系统应用设置页，引导用户手动授权。
  Future<void> openSettings() => openAppSettings();

  // ─── 路径可写性检测 ─────────────────────────────────────────

  /// 检测指定路径是否可读写。
  /// 目录不存在时会尝试递归创建。
  /// 成功可写返回 `true`，否则返回 `false`。
  Future<bool> isPathWritable(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final testFile = File('$dirPath/.easydict_write_test');
      await testFile.writeAsString('ok');
      await testFile.delete();
      return true;
    } catch (e) {
      Logger.w('目录不可写: $dirPath ($e)', tag: 'ExternalStorage');
      return false;
    }
  }
}
