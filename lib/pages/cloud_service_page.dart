import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import '../services/dictionary_manager.dart';
import '../services/dictionary_store_service.dart';
import '../services/auth_service.dart';
import '../services/preferences_service.dart';
import '../services/settings_sync_service.dart';
import '../services/user_dicts_service.dart';
import '../services/entry_event_bus.dart';
import '../core/theme_provider.dart';
import '../services/zstd_service.dart';
import '../services/upload_manager.dart';
import '../data/models/remote_dictionary.dart';
import '../data/models/user.dart';
import '../data/models/user_dictionary.dart' hide DictionaryEntry;
import '../data/models/dictionary_metadata.dart';
import '../data/database_service.dart';
import '../core/utils/toast_utils.dart';
import '../core/logger.dart';
import '../components/global_scale_wrapper.dart';
import '../components/transfer_progress_panel.dart';

class CloudServicePage extends StatefulWidget {
  const CloudServicePage({super.key});

  @override
  State<CloudServicePage> createState() => _CloudServicePageState();
}

class _CloudServicePageState extends State<CloudServicePage> {
  final DictionaryManager _dictManager = DictionaryManager();
  final TextEditingController _urlController = TextEditingController();
  final AuthService _authService = AuthService();
  final PreferencesService _prefsService = PreferencesService();
  final SettingsSyncService _syncService = SettingsSyncService();
  final UserDictsService _userDictsService = UserDictsService();

  DictionaryStoreService? _service;
  List<RemoteDictionary> _availableDictionaries = [];

  bool _isLoggedIn = false;
  User? _currentUser;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _service?.dispose();
    super.dispose();
  }

  String? _currentBaseUrl;

  Future<void> _loadSettings() async {
    final url = await _dictManager.onlineSubscriptionUrl;
    if (url.isNotEmpty) {
      _urlController.text = url;
      // 只在 URL 发生变化时才设置 baseUrl
      if (_currentBaseUrl != url) {
        _currentBaseUrl = url;
        _authService.setBaseUrl(url);
        _userDictsService.setBaseUrl(url);
        _initializeService();
      }
    }

    // 如果已经登录，不需要重复恢复
    if (_authService.isLoggedIn) {
      setState(() {
        _isLoggedIn = true;
        _currentUser = _authService.currentUser;
      });
      return;
    }

    final token = await _prefsService.getAuthToken();
    final userData = await _prefsService.getAuthUserData();
    if (token != null && userData != null) {
      _authService.restoreSession(token: token, userData: userData);
      setState(() {
        _isLoggedIn = _authService.isLoggedIn;
        _currentUser = _authService.currentUser;
      });
    }
  }

  void _initializeService() {
    final url = _urlController.text.trim();
    if (url.isNotEmpty) {
      _service?.dispose();
      setState(() {
        _service = DictionaryStoreService(baseUrl: url);
      });
    }
  }

  Future<void> _saveSettings() async {
    var url = _urlController.text.trim();

    if (url.isNotEmpty &&
        !url.startsWith('http://') &&
        !url.startsWith('https://')) {
      url = 'https://$url';
      _urlController.text = url;
    }

    final oldUrl = await _dictManager.onlineSubscriptionUrl;

    if (oldUrl != url && _isLoggedIn) {
      _authService.logout();
      await _prefsService.clearAuthData();
      setState(() {
        _isLoggedIn = false;
        _currentUser = null;
      });
      if (mounted) {
        showToast(context, '订阅地址已变更，已退出当前账号');
      }
    }

    await _dictManager.setOnlineSubscriptionUrl(url);
    _authService.setBaseUrl(url);
    _userDictsService.setBaseUrl(url);

    if (url.isNotEmpty) {
      _service?.dispose();
      _service = DictionaryStoreService(baseUrl: url);
    } else {
      setState(() {
        _availableDictionaries = [];
      });
      _service?.dispose();
      _service = null;
    }

    _currentBaseUrl = url;

    if (mounted) {
      showToast(context, '在线订阅地址已保存');
    }
  }

  void _showLoginDialog() {
    final identifierController = TextEditingController();
    final passwordController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('登录'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: identifierController,
                decoration: const InputDecoration(
                  labelText: '用户名或邮箱',
                  prefixIcon: Icon(Icons.person_outlined),
                ),
                enabled: !isLoading,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(
                  labelText: '密码',
                  prefixIcon: Icon(Icons.lock_outlined),
                ),
                obscureText: true,
                autofillHints: const ['password'],
                enabled: !isLoading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      setDialogState(() => isLoading = true);
                      final result = await _handleLoginWithResult(
                        identifierController.text.trim(),
                        passwordController.text,
                      );
                      if (context.mounted) {
                        setDialogState(() => isLoading = false);
                        if (result) {
                          Navigator.pop(context);
                        }
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('登录'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRegisterDialog() {
    final usernameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('注册'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: '用户名',
                    prefixIcon: Icon(Icons.person_outlined),
                  ),
                  enabled: !isLoading,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: '邮箱',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const ['email'],
                  enabled: !isLoading,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    labelText: '密码',
                    prefixIcon: Icon(Icons.lock_outlined),
                  ),
                  obscureText: true,
                  enabled: !isLoading,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmPasswordController,
                  decoration: const InputDecoration(
                    labelText: '确认密码',
                    prefixIcon: Icon(Icons.lock_outlined),
                  ),
                  obscureText: true,
                  enabled: !isLoading,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (usernameController.text.trim().isEmpty) {
                        showToast(context, '请输入用户名');
                        return;
                      }
                      if (passwordController.text !=
                          confirmPasswordController.text) {
                        showToast(context, '两次输入的密码不一致');
                        return;
                      }
                      setDialogState(() => isLoading = true);
                      final result = await _handleRegisterWithResult(
                        emailController.text.trim(),
                        passwordController.text,
                        usernameController.text.trim(),
                      );
                      if (context.mounted) {
                        setDialogState(() => isLoading = false);
                        if (result) {
                          Navigator.pop(context);
                        }
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('注册'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _handleLoginWithResult(
    String identifier,
    String password,
  ) async {
    if (identifier.isEmpty || password.isEmpty) {
      showToast(context, '请输入用户名/邮箱和密码');
      return false;
    }

    final result = await _authService.login(
      identifier: identifier,
      password: password,
    );

    if (!mounted) return false;

    if (result.success) {
      await _prefsService.setAuthToken(result.token);
      if (result.user != null) {
        await _prefsService.setAuthUserData(result.user!.toJson());
      }
      if (!mounted) return false;
      setState(() {
        _isLoggedIn = true;
        _currentUser = result.user;
      });
      showToast(context, '登录成功');
      return true;
    } else {
      showToast(context, result.error ?? '登录失败');
      return false;
    }
  }

  Future<bool> _handleRegisterWithResult(
    String email,
    String password,
    String username,
  ) async {
    if (email.isEmpty || password.isEmpty || username.isEmpty) {
      showToast(context, '请输入邮箱、用户名和密码');
      return false;
    }

    final result = await _authService.register(
      email: email,
      password: password,
      username: username,
    );

    if (!mounted) return false;

    if (result.success) {
      await _prefsService.setAuthToken(result.token);
      if (result.user != null) {
        await _prefsService.setAuthUserData(result.user!.toJson());
      }
      if (!mounted) return false;
      setState(() {
        _isLoggedIn = true;
        _currentUser = result.user;
      });
      showToast(context, '注册成功');
      return true;
    } else {
      showToast(context, result.error ?? '注册失败');
      return false;
    }
  }

  Future<void> _handleLogout() async {
    _authService.logout();
    await _prefsService.clearAuthData();
    if (!mounted) return;
    setState(() {
      _isLoggedIn = false;
      _currentUser = null;
    });
    showToast(context, '已退出登录');
  }

  void _handleSyncToCloud() {
    if (!_isLoggedIn) {
      showToast(context, '请先登录');
      return;
    }
    _showUploadConfirmDialog();
  }

  void _showUploadConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('上传设置'),
        content: const Text('确定要将本地设置上传到云端吗？这将覆盖云端的设置数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _doUploadSettings();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _doUploadSettings() async {
    if (_isSyncing) return;

    setState(() => _isSyncing = true);

    try {
      final zipResult = await _syncService.createSettingsZip();
      if (!zipResult.success) {
        if (mounted) showToast(context, zipResult.error ?? '创建设置包失败');
        return;
      }

      final uploadResult = await _authService.uploadSettings(
        zipResult.filePath!,
      );

      await _syncService.cleanupTempZip(zipResult.filePath);

      if (!mounted) return;

      if (uploadResult.success) {
        showToast(context, '设置已上传到云端');
      } else {
        showToast(context, uploadResult.error ?? '上传失败');
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _handleSyncFromCloud() {
    if (!_isLoggedIn) {
      showToast(context, '请先登录');
      return;
    }
    _showDownloadConfirmDialog();
  }

  void _showDownloadConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('下载设置'),
        content: const Text('确定要从云端下载设置吗？这将覆盖本地的设置数据。'),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _doDownloadSettings();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _doDownloadSettings() async {
    if (_isSyncing) return;

    setState(() => _isSyncing = true);

    try {
      final downloadResult = await _authService.downloadSettings();

      if (!mounted) return;

      if (!downloadResult.success) {
        showToast(context, downloadResult.error ?? '下载失败');
        return;
      }

      if (downloadResult.data == null) {
        showToast(context, '云端暂无设置数据');
        return;
      }

      final extractResult = await _syncService.extractSettingsZipFromBytes(
        downloadResult.data!,
      );

      if (!mounted) return;

      if (extractResult.success) {
        // 直接解析 JSON 文件并逐键写入内存，确保 LLM 等配置即刻生效而无需重启
        await _syncService.applyPrefsFromFile();
        // 通知 ThemeProvider 立即应用新主题（深浅色模式、主题色）
        if (mounted) context.read<ThemeProvider>().reloadFromPrefs();
        // 通知各页面刷新受同步影响的内存状态（如查词历史）
        EntryEventBus().emitSettingsSynced(const SettingsSyncedEvent());
        // 等下一帧主题重建完成后再显示气泡，确保气泡使用新主题样式
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) showToast(context, '设置已从云端同步');
          });
        }
      } else {
        showToast(context, extractResult.error ?? '解压失败');
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageScaleWrapper(
        child: Stack(
          children: [
            CustomScrollView(
              slivers: [
                SliverAppBar(
                  title: const Text('云服务'),
                  centerTitle: true,
                  pinned: true,
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  surfaceTintColor: Colors.transparent,
                ),
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildSubscriptionCard(),
                            const SizedBox(height: 16),
                            _buildAccountCard(),
                            const SizedBox(height: 24),
                            if (_service != null &&
                                _availableDictionaries.isNotEmpty)
                              _buildDictionariesSummary(),
                            const SizedBox(height: 80),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: UploadProgressPanel(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud_outlined,
                  color: colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  '在线订阅地址',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '请输入词典订阅网址',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.primary, width: 2),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerLowest,
                prefixIcon: const Icon(Icons.link),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.save_outlined),
                  onPressed: _saveSettings,
                  tooltip: '保存',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '设置订阅地址后可查看和下载在线词典',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final canSync = _isLoggedIn && !_isSyncing;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(
                  Icons.person_outline,
                  color: colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  '账户管理',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                if (_isSyncing) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withOpacity(0.3),
          ),
          // 登录/登出区域
          if (_isLoggedIn && _currentUser != null) ...[
            ListTile(
              leading: CircleAvatar(
                backgroundColor: colorScheme.primaryContainer,
                child: Icon(
                  Icons.person,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              title: Text(_currentUser!.displayName),
              subtitle: Text(_currentUser!.email),
              trailing: TextButton.icon(
                onPressed: _handleLogout,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('退出'),
                style: TextButton.styleFrom(foregroundColor: colorScheme.error),
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _urlController.text.trim().isNotEmpty
                          ? _showLoginDialog
                          : null,
                      icon: const Icon(Icons.login, size: 18),
                      label: const Text('登录'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _urlController.text.trim().isNotEmpty
                          ? _showRegisterDialog
                          : null,
                      icon: const Icon(Icons.person_add, size: 18),
                      label: const Text('注册'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // 同步到云端 - 始终显示
          Divider(
            height: 1,
            indent: 56,
            color: colorScheme.outlineVariant.withOpacity(0.3),
          ),
          ListTile(
            leading: Icon(
              Icons.cloud_upload_outlined,
              color: canSync ? colorScheme.primary : colorScheme.outline,
            ),
            title: Text(
              '同步到云端',
              style: TextStyle(color: canSync ? null : colorScheme.outline),
            ),
            subtitle: const Text('将本地设置上传到云端'),
            trailing: const Icon(Icons.chevron_right),
            onTap: canSync ? _handleSyncToCloud : null,
          ),
          // 从云端同步 - 始终显示
          Divider(
            height: 1,
            indent: 56,
            color: colorScheme.outlineVariant.withOpacity(0.3),
          ),
          ListTile(
            leading: Icon(
              Icons.cloud_download_outlined,
              color: canSync ? colorScheme.primary : colorScheme.outline,
            ),
            title: Text(
              '从云端同步',
              style: TextStyle(color: canSync ? null : colorScheme.outline),
            ),
            subtitle: const Text('从云端下载设置到本地'),
            trailing: const Icon(Icons.chevron_right),
            onTap: canSync ? _handleSyncFromCloud : null,
          ),
        ],
      ),
    );
  }

  Widget _buildDictionariesSummary() {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.library_books_outlined,
                  color: colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '在线词典 (${_availableDictionaries.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '已连接到订阅源，可在"词典管理"中查看和下载词典',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PushUpdatesDialog extends StatefulWidget {
  final String dictId;
  final String dictName;
  final VoidCallback onPushSuccess;

  const PushUpdatesDialog({
    super.key,
    required this.dictId,
    required this.dictName,
    required this.onPushSuccess,
  });

  @override
  State<PushUpdatesDialog> createState() => _PushUpdatesDialogState();
}

class _PushUpdatesDialogState extends State<PushUpdatesDialog> {
  final DatabaseService _databaseService = DatabaseService();
  final UserDictsService _userDictsService = UserDictsService();
  final DictionaryManager _dictManager = DictionaryManager();
  final ZstdService _zstdService = ZstdService();
  final TextEditingController _messageController = TextEditingController(
    text: '更新条目',
  );

  List<Map<String, dynamic>> _updateRecords = [];
  bool _isLoading = true;
  bool _isPushing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initBaseUrl();
    _loadUpdateRecords();
  }

  Future<void> _initBaseUrl() async {
    final url = await _dictManager.onlineSubscriptionUrl;
    if (url.isNotEmpty) {
      _userDictsService.setBaseUrl(url);
    }
  }

  Future<void> _loadUpdateRecords() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final records = await _databaseService.getUpdateRecords(widget.dictId);
      setState(() {
        _updateRecords = records;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = '加载更新记录失败: $e';
        _isLoading = false;
      });
    }
  }

  /// 递归删除包含 (ai) 的字段
  void _removeAiFields(Map<String, dynamic> json) {
    final keysToRemove = <String>[];

    for (final entry in json.entries) {
      final value = entry.value;

      if (value is String && value.contains('(ai)')) {
        keysToRemove.add(entry.key);
      } else if (value is Map<String, dynamic>) {
        _removeAiFields(value);
      } else if (value is List) {
        for (final item in value) {
          if (item is Map<String, dynamic>) {
            _removeAiFields(item);
          }
        }
      }
    }

    for (final key in keysToRemove) {
      json.remove(key);
    }
  }

  Future<void> _pushUpdates() async {
    if (_updateRecords.isEmpty) {
      showToast(context, '没有需要推送的更新');
      return;
    }

    setState(() => _isPushing = true);

    try {
      // 1. 获取每个更新的 entry 并合并为 jsonl 格式
      final processedEntryIds = <String>{};
      final jsonLines = <String>[];

      for (final record in _updateRecords) {
        final entryId = record['id'] as String;
        final opType = record['operation_type'] as String? ?? 'update';
        final isDelete = opType == 'delete';

        // 去重：如果同一个 entry 被更新多次，只取最新的一次
        if (processedEntryIds.contains(entryId)) {
          continue;
        }
        processedEntryIds.add(entryId);

        if (isDelete) {
          // 删除记录：只需 {"entry_id": <int>, "_delete": true}
          // 从 entryId 字符串中提取纯数字部分
          int? numericId = int.tryParse(entryId);
          if (numericId == null && entryId.contains('_')) {
            final parts = entryId.split('_');
            numericId = int.tryParse(parts.last);
          }
          if (numericId != null) {
            jsonLines.add(jsonEncode({'entry_id': numericId, '_delete': true}));
          }
          continue;
        }

        // 获取完整的 entry JSON
        final entryJson = await _databaseService.getEntryJsonById(
          widget.dictId,
          entryId,
        );

        if (entryJson == null) {
          continue;
        }

        // 过滤掉包含 (ai) 的字段
        _removeAiFields(entryJson);

        // 将 json 转换为单行字符串（jsonl 格式）
        jsonLines.add(jsonEncode(entryJson));
      }

      if (jsonLines.isEmpty) {
        if (mounted) {
          showToast(context, '没有有效的条目需要推送');
          setState(() => _isPushing = false);
        }
        return;
      }

      // 2. 合并为 jsonl 内容（每行一个 json 对象，用换行符分隔）
      final jsonlContent = jsonLines.join('\n');
      final jsonlBytes = utf8.encode(jsonlContent);

      // 3. 使用 zstd 压缩 jsonl 文件（level=3）
      final compressedData = _zstdService.compressWithoutDict(
        Uint8List.fromList(jsonlBytes),
        level: 3,
      );

      // 4. 保存为 entries.zst 文件
      final tempDir = await getTemporaryDirectory();
      final zstPath = path.join(tempDir.path, 'entries_${widget.dictId}.zst');
      final zstFile = File(zstPath);
      await zstFile.writeAsBytes(compressedData);

      // 打印文件路径供调试
      Logger.i('ZST file saved to: $zstPath', tag: 'PushUpdates');
      Logger.i(
        'ZST file size: ${await zstFile.length()} bytes',
        tag: 'PushUpdates',
      );

      // 5. 调用 API 推送更新
      final result = await _userDictsService.pushEntryUpdates(
        widget.dictId,
        zstFile: zstFile,
        message: _messageController.text.trim().isEmpty
            ? '更新条目'
            : _messageController.text.trim(),
      );

      if (result.success) {
        // 6. 清除 update 表
        await _databaseService.clearUpdateRecords(widget.dictId);

        // 7. 更新 metadata.json 的 version
        if (result.version != null) {
          final metadataFile = await _dictManager.getMetadataFile(
            widget.dictId,
          );
          if (await metadataFile.exists()) {
            final metadataJson = jsonDecode(await metadataFile.readAsString());
            final updatedMetadata = DictionaryMetadata.fromJson(metadataJson);
            final newMetadata = DictionaryMetadata(
              id: updatedMetadata.id,
              name: updatedMetadata.name,
              version: result.version!,
              description: updatedMetadata.description,
              sourceLanguage: updatedMetadata.sourceLanguage,
              targetLanguages: updatedMetadata.targetLanguages,
              publisher: updatedMetadata.publisher,
              maintainer: updatedMetadata.maintainer,
              contactMaintainer: updatedMetadata.contactMaintainer,
              updatedAt: DateTime.now(),
            );
            await _dictManager.saveDictionaryMetadata(newMetadata);
          }
        }

        // 8. 清理临时文件
        if (await zstFile.exists()) {
          await zstFile.delete();
        }

        if (mounted) {
          Navigator.pop(context);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onPushSuccess();
          });
        }
      } else {
        if (mounted) {
          showToast(context, result.error ?? '推送失败');
        }
      }
    } catch (e) {
      if (mounted) {
        showToast(context, '推送失败: $e');
        Logger.i('推送失败: $e', tag: 'PushUpdates');
      }
    } finally {
      if (mounted) {
        setState(() => _isPushing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('推送更新'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Text(_error!, style: TextStyle(color: colorScheme.error))
            else if (_updateRecords.isEmpty)
              const Text('没有需要推送的更新记录')
            else ...[
              Text('发现 ${_updateRecords.length} 条更新记录：'),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                decoration: BoxDecoration(
                  border: Border.all(color: colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _updateRecords.length,
                  itemBuilder: (context, index) {
                    final record = _updateRecords[index];
                    final headword = record['headword'] as String;
                    final opType = record['operation_type'] as String? ?? 'update';
                    final isDelete = opType == 'delete';
                    final isInsert = opType == 'insert';
                    final updateTime = DateTime.fromMillisecondsSinceEpoch(
                      record['update_time'] as int,
                    );
                    IconData opIcon;
                    Color opColor;
                    String opLabel;
                    if (isDelete) {
                      opIcon = Icons.delete_outline;
                      opColor = colorScheme.error;
                      opLabel = '[删除] ';
                    } else if (isInsert) {
                      opIcon = Icons.add_circle_outline;
                      opColor = colorScheme.tertiary;
                      opLabel = '[新增] ';
                    } else {
                      opIcon = Icons.edit_outlined;
                      opColor = colorScheme.primary;
                      opLabel = '';
                    }
                    return ListTile(
                      dense: true,
                      leading: Icon(opIcon, size: 18, color: opColor),
                      title: Text(
                        headword,
                        style: TextStyle(color: isDelete ? colorScheme.error : null),
                      ),
                      subtitle: Text(
                        '$opLabel'
                        '${updateTime.year}-${updateTime.month.toString().padLeft(2, '0')}-${updateTime.day.toString().padLeft(2, '0')} '
                        '${updateTime.hour.toString().padLeft(2, '0')}:${updateTime.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _messageController,
                decoration: const InputDecoration(
                  labelText: '更新消息',
                  hintText: '请输入更新说明',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isPushing ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        if (_updateRecords.isNotEmpty)
          FilledButton(
            onPressed: _isPushing ? null : _pushUpdates,
            child: _isPushing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('确认推送'),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }
}

class UploadDictionaryDialog extends StatefulWidget {
  final VoidCallback onUploadSuccess;

  const UploadDictionaryDialog({super.key, required this.onUploadSuccess});

  @override
  State<UploadDictionaryDialog> createState() => _UploadDictionaryDialogState();
}

class _UploadDictionaryDialogState extends State<UploadDictionaryDialog> {
  final UserDictsService _userDictsService = UserDictsService();
  final DictionaryManager _dictManager = DictionaryManager();

  File? _metadataFile;
  File? _dictionaryFile;
  File? _logoFile;
  File? _mediaFile;

  @override
  void initState() {
    super.initState();
    _initBaseUrl();
  }

  Future<void> _initBaseUrl() async {
    final url = await _dictManager.onlineSubscriptionUrl;
    if (url.isNotEmpty) {
      _userDictsService.setBaseUrl(url);
    }
  }

  Future<void> _pickFile(String type) async {
    String? extension;
    switch (type) {
      case 'metadata':
        extension = 'json';
        break;
      case 'dictionary':
      case 'media':
        extension = 'db';
        break;
      case 'logo':
        extension = 'png';
        break;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extension != null ? [extension] : null,
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        final file = File(result.files.single.path!);
        switch (type) {
          case 'metadata':
            _metadataFile = file;
            break;
          case 'dictionary':
            _dictionaryFile = file;
            break;
          case 'logo':
            _logoFile = file;
            break;
          case 'media':
            _mediaFile = file;
            break;
        }
      });
    }
  }

  Future<void> _upload() async {
    if (_metadataFile == null || _dictionaryFile == null || _logoFile == null) {
      showToast(context, '请选择所有必填文件');
      return;
    }

    final uploadManager = context.read<UploadManager>();
    final totalFiles = 3 + (_mediaFile != null ? 1 : 0);
    final dictName = _metadataFile!.path
        .split(Platform.pathSeparator)
        .last
        .replaceAll('.json', '');

    // 在关闭对话框前保存回调引用
    final onUploadSuccess = widget.onUploadSuccess;

    Navigator.pop(context);

    // 等待 Navigator 完成 pop 并从树中移除对话框，
    // 避免 UploadManager.notifyListeners() 触发对话框 context 的 rebuild
    await Future.delayed(Duration.zero);

    await uploadManager.startUpload(
      'new_dict_$dictName',
      dictName,
      totalFiles,
      (onProgress) async {
        final result = await _userDictsService.uploadDictionary(
          metadataFile: _metadataFile!,
          dictionaryFile: _dictionaryFile!,
          logoFile: _logoFile!,
          mediaFile: _mediaFile,
          message: '初始上传',
          onProgress: onProgress,
        );

        if (!result.success) {
          throw Exception(result.error ?? '上传失败');
        }

        // 上传成功后，用服务器返回的 version 更新本地 metadata 文件
        if (result.dictId != null && result.version != null) {
          final metadataFile = await _dictManager.getMetadataFile(
            result.dictId!,
          );
          if (await metadataFile.exists()) {
            final metadataJson =
                jsonDecode(await metadataFile.readAsString());
            final updatedMetadata =
                DictionaryMetadata.fromJson(metadataJson);
            final newMetadata = DictionaryMetadata(
              id: updatedMetadata.id,
              name: updatedMetadata.name,
              version: result.version!,
              description: updatedMetadata.description,
              sourceLanguage: updatedMetadata.sourceLanguage,
              targetLanguages: updatedMetadata.targetLanguages,
              publisher: updatedMetadata.publisher,
              maintainer: updatedMetadata.maintainer,
              contactMaintainer: updatedMetadata.contactMaintainer,
              updatedAt: DateTime.now(),
            );
            await _dictManager.saveDictionaryMetadata(newMetadata);
          }
        }
      },
      onComplete: () {
        onUploadSuccess();
      },
      onError: (error) {
        // 错误已在 UploadManager 中处理
      },
    );
  }

  Widget _buildFileSelector(
    String label,
    String type,
    File? file,
    bool required,
    bool isUploading,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: isUploading ? null : () => _pickFile(type),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: file != null
                ? colorScheme.primary
                : colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(12),
          color: file != null
              ? colorScheme.primaryContainer.withOpacity(0.3)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              file != null ? Icons.check_circle : Icons.file_upload_outlined,
              color: file != null ? colorScheme.primary : colorScheme.outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$label${required ? ' (必填)' : ' (可选)'}',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (file != null)
                    Text(
                      file.path.split('/').last,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (file != null)
              IconButton(
                onPressed: isUploading
                    ? null
                    : () {
                        setState(() {
                          switch (type) {
                            case 'metadata':
                              _metadataFile = null;
                              break;
                            case 'dictionary':
                              _dictionaryFile = null;
                              break;
                            case 'logo':
                              _logoFile = null;
                              break;
                            case 'media':
                              _mediaFile = null;
                              break;
                          }
                        });
                      },
                icon: const Icon(Icons.close, size: 18),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final uploadManager = context.watch<UploadManager>();
    final isUploading = uploadManager.isUploading;

    return AlertDialog(
      title: const Text('上传新词典'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFileSelector(
              'metadata.json',
              'metadata',
              _metadataFile,
              true,
              isUploading,
            ),
            const SizedBox(height: 12),
            _buildFileSelector(
              'dictionary.db',
              'dictionary',
              _dictionaryFile,
              true,
              isUploading,
            ),
            const SizedBox(height: 12),
            _buildFileSelector(
              'logo.png',
              'logo',
              _logoFile,
              true,
              isUploading,
            ),
            const SizedBox(height: 12),
            _buildFileSelector(
              'media.db',
              'media',
              _mediaFile,
              false,
              isUploading,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: isUploading ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: isUploading ? null : _upload,
          child: isUploading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('上传'),
        ),
      ],
    );
  }
}

class EditDictionaryDialog extends StatefulWidget {
  final String dictId;
  final String dictName;
  final VoidCallback onUpdateSuccess;
  final String? localPath;

  const EditDictionaryDialog({
    super.key,
    required this.dictId,
    required this.dictName,
    required this.onUpdateSuccess,
    this.localPath,
  });

  @override
  State<EditDictionaryDialog> createState() => _EditDictionaryDialogState();
}

class _EditDictionaryDialogState extends State<EditDictionaryDialog> {
  final UserDictsService _userDictsService = UserDictsService();
  final DictionaryManager _dictManager = DictionaryManager();
  final TextEditingController _messageController = TextEditingController();

  File? _metadataFile;
  File? _dictionaryFile;
  File? _logoFile;
  File? _mediaFile;

  @override
  void initState() {
    super.initState();
    _initBaseUrl();
  }

  Future<void> _initBaseUrl() async {
    final url = await _dictManager.onlineSubscriptionUrl;
    if (url.isNotEmpty) {
      _userDictsService.setBaseUrl(url);
    }
  }

  Future<void> _pickFile(String type) async {
    String? extension;
    switch (type) {
      case 'metadata':
        extension = 'json';
        break;
      case 'dictionary':
      case 'media':
        extension = 'db';
        break;
      case 'logo':
        extension = 'png';
        break;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extension != null ? [extension] : null,
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        final file = File(result.files.single.path!);
        switch (type) {
          case 'metadata':
            _metadataFile = file;
            break;
          case 'dictionary':
            _dictionaryFile = file;
            break;
          case 'logo':
            _logoFile = file;
            break;
          case 'media':
            _mediaFile = file;
            break;
        }
      });
    }
  }

  Future<void> _update() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      showToast(context, '请输入更新说明');
      return;
    }

    if (_metadataFile == null &&
        _dictionaryFile == null &&
        _logoFile == null &&
        _mediaFile == null) {
      showToast(context, '请至少选择一个文件进行更新');
      return;
    }

    final uploadManager = context.read<UploadManager>();
    final totalFiles = [
      _metadataFile,
      _dictionaryFile,
      _logoFile,
      _mediaFile,
    ].where((f) => f != null).length;

    final dictId = widget.dictId;
    final dictName = widget.dictName;
    final metadataFile = _metadataFile;
    final dictionaryFile = _dictionaryFile;
    final logoFile = _logoFile;
    final mediaFile = _mediaFile;

    Navigator.pop(context);

    // 等待 Navigator 完成 pop，避免 notifyListeners 触发已销毁元素的重建
    await Future.delayed(Duration.zero);

    await uploadManager.startUpload(
      dictId,
      dictName,
      totalFiles,
      (onProgress) async {
        final result = await _userDictsService.updateDictionary(
          dictId,
          message: message,
          metadataFile: metadataFile,
          dictionaryFile: dictionaryFile,
          logoFile: logoFile,
          mediaFile: mediaFile,
          onProgress: onProgress,
        );

        if (!result.success) {
          throw Exception(result.error ?? '更新失败');
        }

        if (result.version != null) {
          final metadataFile = await _dictManager.getMetadataFile(dictId);
          if (await metadataFile.exists()) {
            final metadataJson =
                jsonDecode(await metadataFile.readAsString());
            final updatedMetadata =
                DictionaryMetadata.fromJson(metadataJson);
            final newMetadata = DictionaryMetadata(
              id: updatedMetadata.id,
              name: updatedMetadata.name,
              version: result.version!,
              description: updatedMetadata.description,
              sourceLanguage: updatedMetadata.sourceLanguage,
              targetLanguages: updatedMetadata.targetLanguages,
              publisher: updatedMetadata.publisher,
              maintainer: updatedMetadata.maintainer,
              contactMaintainer: updatedMetadata.contactMaintainer,
              updatedAt: DateTime.now(),
            );
            await _dictManager.saveDictionaryMetadata(newMetadata);
          }
        }
      },
      onComplete: () {
        widget.onUpdateSuccess();
      },
      onError: (error) {},
    );
  }

  Widget _buildFileSelector(
    String label,
    String type,
    File? file,
    bool isUploading,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: isUploading ? null : () => _pickFile(type),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: file != null
                ? colorScheme.primary
                : colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(12),
          color: file != null
              ? colorScheme.primaryContainer.withOpacity(0.3)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              file != null ? Icons.check_circle : Icons.file_upload_outlined,
              color: file != null ? colorScheme.primary : colorScheme.outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$label（可选）',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (file != null)
                    Text(
                      file.path.split('/').last,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (file != null)
              IconButton(
                onPressed: isUploading
                    ? null
                    : () {
                        setState(() {
                          switch (type) {
                            case 'metadata':
                              _metadataFile = null;
                              break;
                            case 'dictionary':
                              _dictionaryFile = null;
                              break;
                            case 'logo':
                              _logoFile = null;
                              break;
                            case 'media':
                              _mediaFile = null;
                              break;
                          }
                        });
                      },
                icon: const Icon(Icons.close, size: 18),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final uploadManager = context.watch<UploadManager>();
    final isUploading = uploadManager.isUploading;

    return AlertDialog(
      title: const Text('替换文件'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFileSelector(
              'metadata.json',
              'metadata',
              _metadataFile,
              isUploading,
            ),
            const SizedBox(height: 12),
            _buildFileSelector(
              'dictionary.db',
              'dictionary',
              _dictionaryFile,
              isUploading,
            ),
            const SizedBox(height: 12),
            _buildFileSelector('logo.png', 'logo', _logoFile, isUploading),
            const SizedBox(height: 12),
            _buildFileSelector('media.db', 'media', _mediaFile, isUploading),
            const SizedBox(height: 16),
            TextField(
              controller: _messageController,
              decoration: InputDecoration(
                labelText: '版本备注（必填）',
                hintText: '例如：更新logo、修复词条等',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              enabled: !isUploading,
            ),
            const SizedBox(height: 8),
            Text(
              '提示：请至少选择一个文件进行更新',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: isUploading ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: isUploading ? null : _update,
          child: isUploading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('更新'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// UpdateJsonDialog — 导入 JSON/JSONL 以及按 entry_id 删除条目
// ─────────────────────────────────────────────────────────────────────────────

class UpdateJsonDialog extends StatefulWidget {
  final String dictId;
  final String dictName;
  final VoidCallback onUpdateSuccess;

  const UpdateJsonDialog({
    super.key,
    required this.dictId,
    required this.dictName,
    required this.onUpdateSuccess,
  });

  @override
  State<UpdateJsonDialog> createState() => _UpdateJsonDialogState();
}

class _UpdateJsonDialogState extends State<UpdateJsonDialog>
    with SingleTickerProviderStateMixin {
  final DatabaseService _databaseService = DatabaseService();
  late TabController _tabController;

  // ── 导入 tab ──
  final TextEditingController _jsonController = TextEditingController();
  bool _isImporting = false;
  String? _importResult;
  bool _importHasError = false;

  // ── 删除 tab ──
  final TextEditingController _searchController = TextEditingController();
  String _searchMode = 'id'; // 'id' | 'headword'
  bool _isSearching = false;
  bool _isDeleting = false;
  // 单条结果（by ID 或 headword 精确匹配唯一条）
  Map<String, dynamic>? _foundEntry;
  String? _foundEntryId;
  // 多条结果（headword 匹配多条时）
  List<Map<String, dynamic>> _foundEntries = [];
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _jsonController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── 导入逻辑 ───────────────────────────────────────────────────────────────

  Future<void> _importJson() async {
    final text = _jsonController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _importResult = '请输入 JSON 内容';
        _importHasError = true;
      });
      return;
    }

    setState(() {
      _isImporting = true;
      _importResult = null;
      _importHasError = false;
    });

    try {
      // ① 先尝试整段解析为 JSON（处理格式化 JSON 对象或数组）
      // ② 若失败再按 JSONL（每行一个 JSON 对象）处理
      List<Map<String, dynamic>> objectsToParse = [];
      bool usedJsonMode = false;

      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          objectsToParse = [decoded];
          usedJsonMode = true;
        } else if (decoded is List) {
          objectsToParse = decoded
              .whereType<Map<String, dynamic>>()
              .toList();
          usedJsonMode = true;
        }
      } catch (_) {
        // 整段解析失败 → JSONL 模式
      }

      if (!usedJsonMode) {
        final lines = text
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        for (int i = 0; i < lines.length; i++) {
          try {
            final decoded = jsonDecode(lines[i]);
            if (decoded is Map<String, dynamic>) {
              objectsToParse.add(decoded);
            }
          } catch (_) {
            // 单行解析失败时忽略（下面的循环会统计错误）
          }
        }
        // 若 JSONL 也完全无法解析，报错
        if (objectsToParse.isEmpty) {
          // 重新逐行以收集错误信息
          final lines2 = text
              .split('\n')
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .toList();
          final errorMessages2 = <String>[];
          for (int i = 0; i < lines2.length; i++) {
            try {
              jsonDecode(lines2[i]);
            } catch (e) {
              final preview = lines2[i].length > 50
                  ? '${lines2[i].substring(0, 50)}…'
                  : lines2[i];
              errorMessages2.add('第 ${i + 1} 行: $preview');
              if (errorMessages2.length >= 3) break;
            }
          }
          setState(() {
            _importResult =
                'JSON 解析失败，请检查格式（格式化 JSON 或每行一个对象的 JSONL）。\n'
                '${errorMessages2.join("\n")}';
            _importHasError = true;
          });
          return;
        }
      }

      int successCount = 0;
      int errorCount = 0;
      final errorMessages = <String>[];

      for (int i = 0; i < objectsToParse.length; i++) {
        final decoded = objectsToParse[i];
        try {
          if (decoded is! Map<String, dynamic>) {
            errorCount++;
            errorMessages.add('第 ${i + 1} 条不是 JSON 对象');
            continue;
          }

          final json = Map<String, dynamic>.from(decoded);
          // 注入当前词典 ID（以便 insertOrUpdateEntry 找到正确的数据库）
          json['dict_id'] = widget.dictId;

          final entry = DictionaryEntry.fromJson(json);
          if (entry.id.isEmpty) {
            errorCount++;
            errorMessages.add('第 ${i + 1} 条缺少 entry_id');
            continue;
          }

          final success = await _databaseService.insertOrUpdateEntry(entry);
          if (success) {
            successCount++;
          } else {
            errorCount++;
            errorMessages.add(
              '第 ${i + 1} 条写入失败 (entry_id: ${entry.id}, headword: ${entry.headword})',
            );
          }
        } catch (e) {
          errorCount++;
          errorMessages.add('第 ${i + 1} 条处理失败: $e');
        }
      }

      final buf = StringBuffer('成功导入 $successCount 条');
      if (errorCount > 0) {
        buf.write('，失败 $errorCount 条');
        for (final msg in errorMessages.take(5)) {
          buf.write('\n• $msg');
        }
        if (errorMessages.length > 5) {
          buf.write('\n… 还有 ${errorMessages.length - 5} 条错误');
        }
      }

      setState(() {
        _importResult = buf.toString();
        _importHasError = errorCount > 0 && successCount == 0;
      });

      if (successCount > 0) widget.onUpdateSuccess();
    } catch (e) {
      setState(() {
        _importResult = '导入失败: $e';
        _importHasError = true;
      });
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  // ── 删除逻辑 ───────────────────────────────────────────────────────────────

  Future<void> _searchEntry() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() => _searchError =
          _searchMode == 'id' ? '请输入 entry_id' : '请输入词头');
      return;
    }

    setState(() {
      _isSearching = true;
      _foundEntry = null;
      _foundEntryId = null;
      _foundEntries = [];
      _searchError = null;
    });

    try {
      if (_searchMode == 'id') {
        final entry =
            await _databaseService.getEntryJsonById(widget.dictId, query);
        if (entry == null) {
          setState(() => _searchError = '未找到 entry_id 为 $query 的条目');
        } else {
          // 从 entry JSON 中提取 entry_id
          final eid = (entry['entry_id'] ?? entry['id'])?.toString() ?? query;
          setState(() {
            _foundEntry = entry;
            _foundEntryId = eid;
          });
        }
      } else {
        // headword 搜索
        final entries = await _databaseService.searchEntriesByHeadword(
          widget.dictId,
          query,
        );
        if (entries.isEmpty) {
          setState(() => _searchError = '未找到词头为「$query」的条目');
        } else if (entries.length == 1) {
          final entry = entries.first;
          final eid =
              (entry['entry_id'] ?? entry['id'])?.toString() ?? query;
          setState(() {
            _foundEntry = entry;
            _foundEntryId = eid;
          });
        } else {
          setState(() => _foundEntries = entries);
        }
      }
    } catch (e) {
      setState(() => _searchError = '搜索失败: $e');
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _deleteEntry() async {
    if (_foundEntryId == null || _foundEntry == null) return;

    final headword =
        _foundEntry!['headword']?.toString() ?? _foundEntryId!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(
          '确定要删除条目「$headword」（entry_id: $_foundEntryId）吗？\n\n'
          '此操作会将删除记录写入 commit 表，推送更新后服务器端的该条目也将被删除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isDeleting = true);
    try {
      final success = await _databaseService.deleteEntryById(
        widget.dictId,
        _foundEntryId!,
      );
      if (success) {
        setState(() {
          _foundEntry = null;
          _foundEntryId = null;
          _foundEntries = [];
          _searchController.clear();
          _searchError = null;
        });
        if (mounted) {
          showToast(context, '条目已删除，已记录到 commit 表');
          widget.onUpdateSuccess();
        }
      } else {
        if (mounted) showToast(context, '删除失败，条目可能不存在');
      }
    } catch (e) {
      if (mounted) showToast(context, '删除失败: $e');
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('更新 JSON'),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(
        width: 560,
        height: 520,
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: _tabController,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                indicatorPadding: const EdgeInsets.all(3),
                labelColor: colorScheme.primary,
                unselectedLabelColor: colorScheme.onSurfaceVariant,
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontSize: 13),
                tabs: const [
                  Tab(text: '导入 JSON / JSONL'),
                  Tab(text: '搜索删除条目'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildImportTab(),
                  _buildDeleteTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildImportTab() {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: TextField(
              controller: _jsonController,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText:
                    '粘贴 JSON 或 JSONL（每行一个 JSON 对象）\n\n注意：每条 JSON 必须含有 entry_id 字段',
                hintStyle: TextStyle(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                border: InputBorder.none,
                alignLabelWithHint: true,
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ),
        ),
        if (_importResult != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _importHasError
                  ? colorScheme.errorContainer
                  : colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _importHasError
                      ? Icons.error_outline
                      : Icons.check_circle_outline,
                  size: 16,
                  color: _importHasError
                      ? colorScheme.onErrorContainer
                      : colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _importResult!,
                    style: TextStyle(
                      fontSize: 12,
                      color: _importHasError
                          ? colorScheme.onErrorContainer
                          : colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            if (_jsonController.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: OutlinedButton.icon(
                  onPressed: _isImporting
                      ? null
                      : () {
                          setState(() {
                            _jsonController.clear();
                            _importResult = null;
                            _importHasError = false;
                          });
                        },
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('清空'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            Expanded(
              child: FilledButton.icon(
                onPressed: _isImporting ? null : _importJson,
                icon: _isImporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_outlined, size: 18),
                label: Text(_isImporting ? '导入中…' : '写入数据库'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildDeleteTab() {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 搜索模式切换
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'id',
              label: Text('ID 搜索'),
              icon: Icon(Icons.tag, size: 15),
            ),
            ButtonSegment(
              value: 'headword',
              label: Text('词头搜索'),
              icon: Icon(Icons.search, size: 15),
            ),
          ],
          selected: {_searchMode},
          onSelectionChanged: (sel) {
            setState(() {
              _searchMode = sel.first;
              _foundEntry = null;
              _foundEntryId = null;
              _foundEntries = [];
              _searchError = null;
            });
          },
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStateProperty.all(
              const TextStyle(fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // 搜索栏
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                keyboardType: _searchMode == 'id'
                    ? TextInputType.number
                    : TextInputType.text,
                decoration: InputDecoration(
                  labelText: _searchMode == 'id' ? 'entry_id' : '词头',
                  hintText: _searchMode == 'id'
                      ? '输入整数 entry_id'
                      : '输入词头（自动规范化匹配）',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        BorderSide(color: colorScheme.outlineVariant),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  isDense: true,
                ),
                onSubmitted: (_) => _searchEntry(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _isSearching ? null : _searchEntry,
              child: _isSearching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('搜索'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // 错误提示
        if (_searchError != null)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline,
                    size: 16, color: colorScheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _searchError!,
                    style: TextStyle(
                        color: colorScheme.onErrorContainer, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        // 多条匹配结果列表
        if (_foundEntries.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '找到 ${_foundEntries.length} 条匹配条目，点击选择要删除的条目：',
              style:
                  TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListView.separated(
                padding: const EdgeInsets.all(4),
                itemCount: _foundEntries.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: colorScheme.outlineVariant),
                itemBuilder: (context, index) {
                  final e = _foundEntries[index];
                  final hw = e['headword']?.toString() ?? '';
                  final eid =
                      (e['entry_id'] ?? e['id'])?.toString() ?? '';
                  return ListTile(
                    dense: true,
                    title: Text(hw, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                      'entry_id: $eid',
                      style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant),
                    ),
                    trailing: Icon(Icons.chevron_right,
                        size: 18, color: colorScheme.outline),
                    onTap: () {
                      setState(() {
                        _foundEntry = e;
                        _foundEntryId = eid;
                        _foundEntries = [];
                      });
                    },
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        // 单条结果预览
        if (_foundEntry != null) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SingleChildScrollView(
                child: Text(
                  const JsonEncoder.withIndent('  ').convert(_foundEntry),
                  style: const TextStyle(
                      fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _foundEntry = null;
                    _foundEntryId = null;
                  });
                },
                icon: const Icon(Icons.arrow_back, size: 15),
                label: const Text('返回'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _isDeleting ? null : _deleteEntry,
                icon: _isDeleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline, size: 18),
                label: Text(_isDeleting ? '删除中…' : '删除此条目'),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}