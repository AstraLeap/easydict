# macOS 查词问题修复总结

## 问题描述
从 v1.5.0 开始，macOS 上应用能打开，但查词后显示 "word not found"。

## 根本原因
macOS 沙盒环境下，应用默认使用 `Documents` 目录存储词典数据，但沙盒应用对该目录访问受限，导致词典数据库无法正常加载。

## 已实施的修复

### 1. 修改词典默认目录 ✅

**文件**：`lib/services/dictionary_manager.dart`

**修改内容**：
- 将 macOS/iOS 的默认词典目录从 `Documents/easydict` 改为 `Application Support/dictionaries`
- Application Support 目录是沙盒应用可访问的标准目录，无需额外权限

**代码变更**：
```dart
// macOS/iOS: 使用 Application Support 目录（沙盒应用可访问）
if (Platform.isMacOS || Platform.isIOS) {
  final appDir = await getApplicationSupportDirectory();
  return path.join(appDir.path, 'dictionaries');
}

// Windows/Linux: 继续使用 Documents 目录
final appDir = await getApplicationDocumentsDirectory();
return path.join(appDir.path, 'easydict');
```

### 2. 更新 macOS 权限配置 ✅

**文件**：
- `macos/Runner/Release.entitlements`
- `macos/Runner/DebugProfile.entitlements`

**修改内容**：
添加用户选择的文件读写权限（用于导入词典）

**新增权限**：
```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

### 3. 添加数据迁移逻辑 ✅

**文件**：`lib/services/dictionary_manager.dart`

**功能**：
- 首次运行时自动检测旧词典目录（`Documents/easydict`）
- 将词典数据迁移到新目录（`Application Support/dictionaries`）
- 仅执行一次，避免重复迁移
- 迁移过程有完整日志记录

**迁移流程**：
1. 检查是否已迁移（通过 SharedPreferences 标记）
2. 检查旧目录是否存在
3. 检查新目录是否已存在
4. 复制所有词典文件到新目录
5. 标记迁移完成
6. 保留旧目录（安全考虑）

## 新的词典存储路径

修复后，各平台的词典默认存储位置：

| 平台 | 路径 |
|------|------|
| **macOS** | `~/Library/Containers/com.keskai.easydict/Data/Library/Application Support/dictionaries/` |
| **iOS** | `~/Library/Application Support/dictionaries/` |
| **Windows** | `~/Documents/easydict/` |
| **Linux** | `~/Documents/easydict/` |
| **Android** | 外部存储 `dictionaries/` |

## 测试步骤

### 1. 清理并重新构建
```bash
flutter clean
flutter pub get
flutter build macos --release
```

### 2. 运行应用（带日志）
```bash
flutter run -d macos --dart-define=ENABLE_LOG=true --dart-define=LOG_TO_FILE=true
```

### 3. 检查关键日志
启动时应该看到以下日志：
```
[DictionaryManager] 词典目录配置: dictionaries_base_dir = null
[DictionaryManager] 开始迁移词典数据: [旧路径] -> [新路径]
[DictionaryManager] 词典数据迁移完成，共迁移 X 个词典
```

### 4. 验证功能
1. **词典导入**：尝试导入新词典
2. **查词测试**：搜索单词，确认能正常显示结果
3. **设置检查**：查看词典管理页面，确认词典列表正常

### 5. 检查文件位置
```bash
# 查看新的词典存储位置
ls ~/Library/Containers/com.keskai.easydict/Data/Library/Application\ Support/dictionaries/

# 如果从旧版本升级，检查迁移是否成功
ls ~/Documents/easydict/  # 旧位置（应该仍然存在）
```

## 回退方案

如果修复后仍有问题，可以尝试：

### 方案 A：手动设置词典目录
1. 打开应用设置
2. 在词典管理页面手动选择词典目录
3. 重新导入词典

### 方案 B：清除应用数据
```bash
# 删除应用配置（会丢失所有设置）
rm -rf ~/Library/Containers/com.keskai.easydict/

# 重新运行应用
flutter run -d macos
```

### 方案 C：临时禁用沙盒（仅调试）
修改 `macos/Runner/Release.entitlements`：
```xml
<key>com.apple.security.app-sandbox</key>
<false/>
```
⚠️ 注意：这会影响 App Store 发布

## 预期效果

修复后应该能够：
1. ✅ 正常启动应用
2. ✅ 成功导入词典
3. ✅ 正常查词并显示结果
4. ✅ 自动迁移旧版本词典数据（如果有）
5. ✅ 系统托盘和剪切板监听功能正常

## 注意事项

1. **首次运行**：首次运行修复版本时，应用会自动迁移词典数据，可能需要几秒钟
2. **旧数据保留**：迁移后旧词典数据仍会保留在原位置，可以手动删除
3. **权限提示**：导入词典时可能会提示选择文件，这是正常的权限请求
4. **多平台兼容**：修改对其他平台（Windows/Linux/Android）无影响

## 相关文件

- `lib/services/dictionary_manager.dart` - 词典管理核心逻辑
- `macos/Runner/Release.entitlements` - macOS 发布版权限
- `macos/Runner/DebugProfile.entitlements` - macOS 调试版权限
- `diagnose_mac.dart` - macOS 诊断脚本
- `MACOS_TROUBLESHOOTING.md` - 详细排查指南

## 联系支持

如果问题仍未解决，请提供：
1. 应用日志文件（启用 LOG_TO_FILE）
2. 诊断脚本输出结果
3. macOS 版本信息
4. 问题复现步骤

---

修复完成时间：2026-03-20
修复版本：v1.5.8（建议发布）
