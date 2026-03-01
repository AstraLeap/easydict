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
  final DatabaseService _databaseService = DatabaseService();
  final ZstdService _zstdService = ZstdService();

  DictionaryStoreService? _service;
  List<RemoteDictionary> _availableDictionaries = [];

  bool _isLoggedIn = false;
  User? _currentUser;
  bool _isSyncing = false;
  bool _isPushing = false;

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
        // 通知各页面刷新受同步影响的内存状态（如查词历史）
        EntryEventBus().emitSettingsSynced(const SettingsSyncedEvent());
        if (mounted) showToast(context, '设置已从云端同步');
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

  void _showPushUpdatesDialog(UserDictionary dict) {
    showDialog(
      context: context,
      builder: (context) => PushUpdatesDialog(
        dictId: dict.dictId,
        dictName: dict.name,
        onPushSuccess: () {
          showToast(context, '推送更新成功');
        },
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

        // 去重：如果同一个 entry 被更新多次，只取最新的一次
        if (processedEntryIds.contains(entryId)) {
          continue;
        }
        processedEntryIds.add(entryId);

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
          widget.onPushSuccess();
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
      title: Text('推送更新 - ${widget.dictName}'),
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
                    final updateTime = DateTime.fromMillisecondsSinceEpoch(
                      record['update_time'] as int,
                    );
                    return ListTile(
                      dense: true,
                      title: Text(headword),
                      subtitle: Text(
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

  const EditDictionaryDialog({
    super.key,
    required this.dictId,
    required this.dictName,
    required this.onUpdateSuccess,
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
      title: Text('替换文件 - ${widget.dictName}'),
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
