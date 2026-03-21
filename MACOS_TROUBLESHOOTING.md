# macOS 无法查词问题排查指南

## 问题描述
从 v1.5.0 开始，macOS 上应用能打开，但查词后显示 "word not found"

## 排查步骤

### 1. 运行诊断脚本
```bash
cd /mnt/f/Codes/easydict
flutter run -d macos diagnose_mac.dart
```

这将输出：
- Documents 和 Application Support 目录权限
- 词典目录路径和文件状态
- SharedPreferences 配置
- Entitlements 配置

### 2. 检查应用日志
启用日志功能运行应用：
```bash
flutter run -d macos --dart-define=ENABLE_LOG=true --dart-define=LOG_TO_FILE=true
```

关键日志检查点：
- "词典目录配置: dictionaries_base_dir = ..."
- "词典数据库预连接完成"
- "正在搜索词典: ..."
- "成功打开词典数据库: ..."

### 3. 检查词典文件位置
macOS 上默认词典路径应为：
- **沙盒环境**：`~/Library/Containers/com.keskai.easydict/Data/Documents/easydict/`
- **非沙盒环境**：`~/Documents/easydict/`

检查该目录下是否有词典文件夹，每个词典应包含：
- `metadata.json`
- `dictionary.db`

## 可能的原因及解决方案

### 原因 1: 词典目录路径问题（最可能）

**症状**：应用启动正常，但查词时找不到词典文件

**解决方案**：修改默认词典目录为 Application Support

修改文件：`lib/services/dictionary_manager.dart`

```dart
Future<String> _getDefaultDirectory() async {
  if (kIsWeb) {
    return 'easydict';
  }

  if (Platform.isAndroid) {
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        return path.join(extDir.path, 'dictionaries');
      }
    } catch (e) {
      Logger.w('获取外部存储目录失败: $e', tag: 'DictionaryManager');
    }
  }

  // macOS/iOS/Linux/Windows: 使用 Application Support 目录
  // 这是沙盒应用可访问的目录，无需额外权限
  if (Platform.isMacOS || Platform.isIOS) {
    final appDir = await getApplicationSupportDirectory();
    return path.join(appDir.path, 'dictionaries');
  }
  
  // 其他平台继续使用 Documents 目录
  final appDir = await getApplicationDocumentsDirectory();
  return path.join(appDir.path, 'easydict');
}
```

### 原因 2: Entitlements 权限不足

**症状**：无法访问 Documents 目录或读取剪切板

**解决方案**：更新 entitlements 文件

修改文件：`macos/Runner/Release.entitlements` 和 `macos/Runner/DebugProfile.entitlements`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <!-- 允许用户选择的文件读写（用于导入词典） -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
```

### 原因 3: 数据迁移问题

如果用户之前使用 Documents 目录存储词典，需要迁移数据。

**解决方案**：添加数据迁移逻辑

```dart
// 在 DictionaryManager 初始化时检查并迁移
Future<void> _migrateIfNeeded() async {
  final prefs = await SharedPreferences.getInstance();
  final alreadyMigrated = prefs.getBool('dicts_migrated_to_app_support') ?? false;
  
  if (alreadyMigrated || !Platform.isMacOS) return;
  
  final oldDir = Directory('${(await getApplicationDocumentsDirectory()).path}/easydict');
  final newDir = Directory('${(await getApplicationSupportDirectory()).path}/dictionaries');
  
  if (await oldDir.exists() && !await newDir.exists()) {
    Logger.i('迁移词典数据: ${oldDir.path} -> ${newDir.path}', tag: 'DictionaryManager');
    await newDir.create(recursive: true);
    
    await for (final entity in oldDir.list(recursive: true)) {
      if (entity is File) {
        final relativePath = entity.path.substring(oldDir.path.length);
        final newFile = File('${newDir.path}$relativePath');
        await newFile.parent.create(recursive: true);
        await entity.copy(newFile.path);
      }
    }
    
    await prefs.setBool('dicts_migrated_to_app_support', true);
    Logger.i('词典数据迁移完成', tag: 'DictionaryManager');
  }
}
```

### 原因 4: 剪切板/托盘功能影响（可能性较小）

**症状**：新功能初始化失败影响应用流程

**临时验证**：注释掉新功能初始化

修改文件：`lib/main.dart`

```dart
// 临时注释，用于测试
/*
try {
  await SystemTrayService().initialize();
  await ClipboardWatcherService().initialize();
  if (await prefsService.isClipboardWatchEnabled()) {
    await ClipboardWatcherService().startWatching();
  }
} catch (e) {
  Logger.e('系统托盘或剪切板监听初始化失败: $e', tag: 'Startup');
}
*/
```

## 推荐修复步骤

1. **立即修复**：修改默认词典目录为 Application Support（原因 1）
2. **完善权限**：更新 entitlements 配置（原因 2）
3. **数据迁移**：添加迁移逻辑，兼容旧版本数据（原因 3）
4. **验证测试**：在 macOS 上完整测试所有功能

## 验证修复是否成功

修复后运行：
```bash
flutter clean
flutter pub get
flutter build macos --release
```

然后打开应用：
1. 检查设置页面，词典管理是否正常
2. 尝试导入词典
3. 进行查词测试
4. 检查日志确认无错误

## 需要用户提供的信息

如果以上步骤仍无法解决，请提供：
1. 诊断脚本的完整输出
2. 应用日志文件（启用 LOG_TO_FILE 后）
3. 词典文件实际存储路径
4. macOS 版本信息
5. 是否是首次安装或从旧版本升级
