import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// macOS 诊断脚本
/// 运行方式：flutter run -d macos diagnose_mac.dart
void main() async {
  print('\n========== EasyDict macOS 诊断报告 ==========\n');

  // 1. 检查平台
  print('1. 平台信息');
  print('   - 操作系统: ${Platform.operatingSystem}');
  print('   - 版本: ${Platform.operatingSystemVersion}');
  print('   - Dart版本: ${Platform.version}');

  // 2. 检查沙盒环境
  print('\n2. 沙盒环境检查');
  final homeDir = Platform.environment['HOME'] ?? '未知';
  print('   - HOME目录: $homeDir');
  
  try {
    final appSupportDir = await getApplicationSupportDirectory();
    print('   - Application Support目录: ${appSupportDir.path}');
    print('   - 目录是否存在: ${await appSupportDir.exists()}');
    
    // 测试写入权限
    final testFile = File('${appSupportDir.path}/.write_test');
    await testFile.writeAsString('test');
    await testFile.delete();
    print('   - Application Support写入权限: ✅ 有');
  } catch (e) {
    print('   - Application Support写入权限: ❌ 无 ($e)');
  }

  try {
    final appDocsDir = await getApplicationDocumentsDirectory();
    print('   - Documents目录: ${appDocsDir.path}');
    print('   - 目录是否存在: ${await appDocsDir.exists()}');
    
    // 测试写入权限
    final testFile = File('${appDocsDir.path}/.write_test');
    await testFile.writeAsString('test');
    await testFile.delete();
    print('   - Documents写入权限: ✅ 有');
  } catch (e) {
    print('   - Documents写入权限: ❌ 无 ($e)');
  }

  // 3. 检查SharedPreferences
  print('\n3. 配置存储检查');
  try {
    final prefs = await SharedPreferences.getInstance();
    final dictDir = prefs.getString('dictionaries_base_dir');
    print('   - 已保存的词典目录: ${dictDir ?? "未设置"}');
    print('   - 剪切板监听启用: ${prefs.getBool('clipboard_watch_enabled') ?? false}');
    print('   - 最小化到托盘: ${prefs.getBool('minimize_to_tray') ?? false}');
  } catch (e) {
    print('   - SharedPreferences错误: $e');
  }

  // 4. 检查词典目录
  print('\n4. 词典目录检查');
  try {
    final prefs = await SharedPreferences.getInstance();
    String? dictDir = prefs.getString('dictionaries_base_dir');
    
    if (dictDir == null) {
      // 使用默认目录
      final appDocsDir = await getApplicationDocumentsDirectory();
      dictDir = '${appDocsDir.path}/easydict';
    }
    
    print('   - 词典目录路径: $dictDir');
    
    final dictDirectory = Directory(dictDir);
    if (await dictDirectory.exists()) {
      print('   - 目录存在: ✅');
      
      // 列出子目录（词典）
      final entities = await dictDirectory.list().toList();
      final dirs = entities.whereType<Directory>().toList();
      print('   - 发现 ${dirs.length} 个词典:');
      
      for (final dir in dirs) {
        final dictName = dir.path.split('/').last;
        final dbFile = File('${dir.path}/dictionary.db');
        final metaFile = File('${dir.path}/metadata.json');
        
        print('     - $dictName:');
        print('       - dictionary.db: ${await dbFile.exists() ? "✅ 存在" : "❌ 不存在"}');
        print('       - metadata.json: ${await metaFile.exists() ? "✅ 存在" : "❌ 不存在"}');
      }
    } else {
      print('   - 目录存在: ❌ 不存在');
      print('   - 建议：请先导入词典或手动设置词典目录');
    }
  } catch (e) {
    print('   - 检查词典目录时出错: $e');
  }

  // 5. 检查entitlements配置
  print('\n5. Entitlements配置检查');
  try {
    final releaseEntitlements = File('macos/Runner/Release.entitlements');
    if (await releaseEntitlements.exists()) {
      final content = await releaseEntitlements.readAsString();
      print('   - Release.entitlements内容:');
      content.split('\n').forEach((line) {
        if (line.trim().isNotEmpty) {
          print('     $line');
        }
      });
    }
  } catch (e) {
    print('   - 读取entitlements失败: $e');
  }

  print('\n========== 诊断完成 ==========\n');
  print('建议操作：');
  print('1. 如果Documents目录无写入权限，考虑将词典目录改为Application Support');
  print('2. 如果词典目录不存在，请先导入词典');
  print('3. 如果entitlements缺少权限，请更新配置文件');
  
  exit(0);
}
