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
import '../i18n/strings.g.dart';
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
        showToast(context, context.t.cloud.subscriptionChanged);
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
      showToast(context, context.t.cloud.subscriptionSaved);
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
          title: Text(context.t.cloud.loginDialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: identifierController,
                decoration: InputDecoration(
                  labelText: context.t.cloud.usernameOrEmail,
                  prefixIcon: const Icon(Icons.person_outlined),
                ),
                enabled: !isLoading,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                decoration: InputDecoration(
                  labelText: context.t.cloud.passwordLabel,
                  prefixIcon: const Icon(Icons.lock_outlined),
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
              child: Text(context.t.common.cancel),
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
                  : Text(context.t.cloud.loginBtn),
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
          title: Text(context.t.cloud.registerDialogTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: usernameController,
                  decoration: InputDecoration(
                    labelText: context.t.cloud.usernameLabel,
                    prefixIcon: const Icon(Icons.person_outlined),
                  ),
                  enabled: !isLoading,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: context.t.cloud.emailLabel,
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const ['email'],
                  enabled: !isLoading,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  decoration: InputDecoration(
                    labelText: context.t.cloud.passwordLabel,
                    prefixIcon: const Icon(Icons.lock_outlined),
                  ),
                  obscureText: true,
                  enabled: !isLoading,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmPasswordController,
                  decoration: InputDecoration(
                    labelText: context.t.cloud.confirmPasswordLabel,
                    prefixIcon: const Icon(Icons.lock_outlined),
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
              child: Text(context.t.common.cancel),
            ),
            FilledButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (usernameController.text.trim().isEmpty) {
                        showToast(
                          context,
                          context.t.cloud.registerUsernameRequired,
                        );
                        return;
                      }
                      if (passwordController.text !=
                          confirmPasswordController.text) {
                        showToast(
                          context,
                          context.t.cloud.registerPasswordMismatch,
                        );
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
                  : Text(context.t.cloud.registerBtn),
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
      showToast(context, context.t.cloud.loginRequired);
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
      showToast(context, context.t.cloud.loginSuccess);
      return true;
    } else {
      showToast(context, result.error ?? context.t.cloud.loginFailed);
      return false;
    }
  }

  Future<bool> _handleRegisterWithResult(
    String email,
    String password,
    String username,
  ) async {
    if (email.isEmpty || password.isEmpty || username.isEmpty) {
      showToast(context, context.t.cloud.registerRequired);
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
      showToast(context, context.t.cloud.registerSuccess);
      return true;
    } else {
      showToast(context, result.error ?? context.t.cloud.registerFailed);
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
    showToast(context, context.t.cloud.loggedOut);
  }

  void _handleSyncToCloud() {
    if (!_isLoggedIn) {
      showToast(context, context.t.cloud.loginFirst);
      return;
    }
    _showUploadConfirmDialog();
  }

  void _showUploadConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t.cloud.uploadTitle),
        content: Text(context.t.cloud.uploadConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.t.common.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _doUploadSettings();
            },
            child: Text(context.t.common.ok),
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
        if (mounted)
          showToast(
            context,
            zipResult.error ?? context.t.cloud.createPackageFailed,
          );
        return;
      }

      final uploadResult = await _authService.uploadSettings(
        zipResult.filePath!,
      );

      await _syncService.cleanupTempZip(zipResult.filePath);

      if (!mounted) return;

      if (uploadResult.success) {
        showToast(context, context.t.cloud.uploadSuccess);
      } else {
        showToast(context, uploadResult.error ?? context.t.cloud.uploadFailed);
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _handleSyncFromCloud() {
    if (!_isLoggedIn) {
      showToast(context, context.t.cloud.loginFirst);
      return;
    }
    _showDownloadConfirmDialog();
  }

  void _showDownloadConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t.cloud.downloadTitle),
        content: Text(context.t.cloud.downloadConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.t.common.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _doDownloadSettings();
            },
            child: Text(context.t.common.ok),
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
        showToast(
          context,
          downloadResult.error ?? context.t.cloud.downloadFailed,
        );
        return;
      }

      if (downloadResult.data == null) {
        showToast(context, context.t.cloud.downloadEmpty);
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
            if (mounted) showToast(context, context.t.cloud.downloadSuccess);
          });
        }
      } else {
        showToast(
          context,
          extractResult.error ?? context.t.cloud.extractFailed,
        );
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
                  title: Text(context.t.cloud.title),
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
                Text(
                  context.t.cloud.subscriptionLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: context.t.cloud.subscriptionHint,
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
                fillColor: colorScheme.surfaceContainerLow,
                prefixIcon: const Icon(Icons.link),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.save_outlined),
                  onPressed: _saveSettings,
                  tooltip: context.t.cloud.subscriptionSaveTooltip,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.t.cloud.subscriptionHint2,
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
                Text(
                  context.t.cloud.accountTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
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
                label: Text(context.t.cloud.logoutBtn),
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
                      label: Text(context.t.cloud.loginBtn),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _urlController.text.trim().isNotEmpty
                          ? _showRegisterDialog
                          : null,
                      icon: const Icon(Icons.person_add, size: 18),
                      label: Text(context.t.cloud.registerBtn),
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
              context.t.cloud.syncToCloud,
              style: TextStyle(color: canSync ? null : colorScheme.outline),
            ),
            subtitle: Text(context.t.cloud.syncToCloudSubtitle),
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
              context.t.cloud.syncFromCloud,
              style: TextStyle(color: canSync ? null : colorScheme.outline),
            ),
            subtitle: Text(context.t.cloud.syncFromCloudSubtitle),
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
                  context.t.cloud.onlineDicts(
                    count: _availableDictionaries.length,
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              context.t.cloud.onlineDictsConnected,
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
    text: t.cloud.updateEntry,
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
        _error = context.t.cloud.loadUpdatesFailed(error: '$e');
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
      showToast(context, context.t.cloud.noNeedToPushUpdates);
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
          showToast(context, context.t.cloud.noValidEntries);
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
            ? t.cloud.updateEntry
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
          showToast(context, result.error ?? context.t.cloud.pushFailedGeneral);
        }
      }
    } catch (e) {
      if (mounted) {
        showToast(context, context.t.cloud.pushFailed(error: '$e'));
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
      title: Text(context.t.cloud.pushUpdatesTitle),
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
              Text(context.t.cloud.noPushUpdates)
            else ...[
              Text(
                context.t.cloud.pushUpdateCount(count: _updateRecords.length),
              ),
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
                    final opType =
                        record['operation_type'] as String? ?? 'update';
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
                      opLabel = context.t.cloud.opDelete;
                    } else if (isInsert) {
                      opIcon = Icons.add_circle_outline;
                      opColor = colorScheme.tertiary;
                      opLabel = context.t.cloud.opInsert;
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
                        style: TextStyle(
                          color: isDelete ? colorScheme.error : null,
                        ),
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
                decoration: InputDecoration(
                  labelText: context.t.cloud.pushMessageLabel,
                  hintText: context.t.cloud.pushMessageHint,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isPushing ? null : () => Navigator.pop(context),
          child: Text(context.t.common.cancel),
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
                : Text(context.t.cloud.updateEntry),
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

  /// 获取期望的文件名
  String _getExpectedFileName(String type) {
    switch (type) {
      case 'metadata':
        return 'metadata.json';
      case 'dictionary':
        return 'dictionary.db';
      case 'logo':
        return 'logo.png';
      case 'media':
        return 'media.db';
      default:
        return '';
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

    // 在移动端使用 any 类型以避免文件选择器过滤问题
    // 某些设备上 .db 文件可能被系统隐藏或无法识别
    final result = await FilePicker.platform.pickFiles(
      type: Platform.isAndroid || Platform.isIOS
          ? FileType.any
          : FileType.custom,
      allowedExtensions: (Platform.isAndroid || Platform.isIOS)
          ? null
          : (extension != null ? [extension] : null),
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final fileName = path.basename(file.path);
      final expectedFileName = _getExpectedFileName(type);

      // 校验文件名是否正确
      if (fileName != expectedFileName) {
        if (mounted) {
          showToast(
            context,
            context.t.cloud.fileNameMismatch(
              expected: expectedFileName,
              actual: fileName,
            ),
          );
        }
        return;
      }

      setState(() {
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
      showToast(context, context.t.cloud.selectAllRequiredFiles);
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
          message: t.cloud.updateEntry,
          onProgress: onProgress,
        );

        if (!result.success) {
          throw Exception(result.error ?? t.cloud.uploadFailed);
        }

        // 上传成功后，用服务器返回的 version 更新本地 metadata 文件
        if (result.dictId != null && result.version != null) {
          final metadataFile = await _dictManager.getMetadataFile(
            result.dictId!,
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
                    '$label${required ? context.t.cloud.requiredField : context.t.cloud.optionalField}',
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
      title: Text(context.t.cloud.uploadNewDict),
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
          child: Text(context.t.common.cancel),
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
              : Text(context.t.common.upload),
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

  /// 获取期望的文件名
  String _getExpectedFileName(String type) {
    switch (type) {
      case 'metadata':
        return 'metadata.json';
      case 'dictionary':
        return 'dictionary.db';
      case 'logo':
        return 'logo.png';
      case 'media':
        return 'media.db';
      default:
        return '';
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

    // 在移动端使用 any 类型以避免文件选择器过滤问题
    // 某些设备上 .db 文件可能被系统隐藏或无法识别
    final result = await FilePicker.platform.pickFiles(
      type: Platform.isAndroid || Platform.isIOS
          ? FileType.any
          : FileType.custom,
      allowedExtensions: (Platform.isAndroid || Platform.isIOS)
          ? null
          : (extension != null ? [extension] : null),
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final fileName = path.basename(file.path);
      final expectedFileName = _getExpectedFileName(type);

      // 校验文件名是否正确
      if (fileName != expectedFileName) {
        if (mounted) {
          showToast(
            context,
            context.t.cloud.fileNameMismatch(
              expected: expectedFileName,
              actual: fileName,
            ),
          );
        }
        return;
      }

      setState(() {
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
      showToast(context, context.t.cloud.pushMessageHint);
      return;
    }

    if (_metadataFile == null &&
        _dictionaryFile == null &&
        _logoFile == null &&
        _mediaFile == null) {
      showToast(context, context.t.cloud.selectAtLeastOneFileToUpdate);
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
          throw Exception(result.error ?? t.dict.statusUpdateFailed);
        }

        if (result.version != null) {
          final metadataFile = await _dictManager.getMetadataFile(dictId);
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
                    '$label${context.t.cloud.optionalField}',
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
      title: Text(context.t.dict.tooltipReplaceFile),
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
                labelText: context.t.cloud.versionNoteLabel,
                hintText: context.t.cloud.replaceFileHint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              enabled: !isUploading,
            ),
            const SizedBox(height: 8),
            Text(
              context.t.cloud.replaceFileTip,
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
          child: Text(context.t.common.cancel),
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
              : Text(context.t.common.update),
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

/// JSON 提取结果类
class _JsonExtractResult {
  final List<Map<String, dynamic>> objects;
  final List<String> errors;

  _JsonExtractResult({required this.objects, required this.errors});
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

  // ── 智能提取 JSON 对象 ─────────────────────────────────────────────────────
  /// 从文本中智能提取多个 JSON 对象
  /// 支持跨行 JSONL 格式，通过匹配大括号来识别每个独立的 JSON 对象
  _JsonExtractResult _extractJsonObjects(String text) {
    final objects = <Map<String, dynamic>>[];
    final errors = <String>[];
    int i = 0;
    int objectIndex = 0;

    while (i < text.length) {
      // 跳过空白字符
      while (i < text.length && _isWhitespace(text[i])) {
        i++;
      }

      if (i >= text.length) break;

      // 找到下一个 JSON 对象的起始位置
      if (text[i] == '{') {
        int start = i;
        int depth = 0;
        bool inString = false;
        bool escaped = false;

        while (i < text.length) {
          final char = text[i];

          if (escaped) {
            escaped = false;
            i++;
            continue;
          }

          if (char == '\\' && inString) {
            escaped = true;
            i++;
            continue;
          }

          if (char == '"') {
            inString = !inString;
          } else if (!inString) {
            if (char == '{') {
              depth++;
            } else if (char == '}') {
              depth--;
              if (depth == 0) {
                // 找到完整的 JSON 对象
                final jsonStr = text.substring(start, i + 1);
                try {
                  final decoded = jsonDecode(jsonStr);
                  if (decoded is Map<String, dynamic>) {
                    objects.add(decoded);
                    objectIndex++;
                  } else {
                    errors.add('对象 #${objectIndex + 1}: 不是有效的 JSON 对象');
                    objectIndex++;
                  }
                } catch (e) {
                  final preview = jsonStr.length > 80
                      ? '${jsonStr.substring(0, 80)}…'
                      : jsonStr;
                  errors.add('对象 #${objectIndex + 1} 解析失败: $e\n预览: $preview');
                  objectIndex++;
                }
                i++;
                break;
              }
            }
          }
          i++;
        }

        // 如果到达文本末尾但大括号未闭合
        if (i >= text.length && depth > 0) {
          final jsonStr = text.substring(start);
          final preview = jsonStr.length > 80
              ? '${jsonStr.substring(0, 80)}…'
              : jsonStr;
          errors.add('对象 #${objectIndex + 1}: 大括号未闭合\n预览: $preview');
        }
      } else {
        i++;
      }
    }

    return _JsonExtractResult(objects: objects, errors: errors);
  }

  /// 判断字符是否为空白字符
  bool _isWhitespace(String char) {
    return char == ' ' || char == '\t' || char == '\n' || char == '\r';
  }

  // ── 导入逻辑 ───────────────────────────────────────────────────────────────

  Future<void> _importJson() async {
    final text = _jsonController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _importResult = context.t.cloud.enterJsonContent;
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
      // 解析策略：
      // ① 先尝试整段解析为 JSON（处理格式化 JSON 对象或数组）
      // ② 若失败，尝试智能提取多个 JSON 对象（支持跨行 JSONL）
      List<Map<String, dynamic>> objectsToParse = [];
      bool usedJsonMode = false;

      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          objectsToParse = [decoded];
          usedJsonMode = true;
        } else if (decoded is List) {
          objectsToParse = decoded.whereType<Map<String, dynamic>>().toList();
          usedJsonMode = true;
        }
      } catch (_) {
        // 整段解析失败 → 尝试智能提取多个 JSON 对象
      }

      if (!usedJsonMode) {
        // 智能提取：找到所有完整的 JSON 对象
        // 通过匹配大括号来识别每个独立的 JSON 对象
        final extractResult = _extractJsonObjects(text);
        objectsToParse = extractResult.objects;

        // 若无法提取任何 JSON 对象，显示错误信息
        if (objectsToParse.isEmpty) {
          final errorMsg = StringBuffer(context.t.cloud.jsonParseError);
          if (extractResult.errors.isNotEmpty) {
            errorMsg.writeln();
            errorMsg.writeln();
            errorMsg.writeln('解析错误详情:');
            for (final err in extractResult.errors.take(5)) {
              errorMsg.writeln('\n• $err');
            }
            if (extractResult.errors.length > 5) {
              errorMsg.writeln(
                '\n... 还有 ${extractResult.errors.length - 5} 个错误',
              );
            }
          }
          setState(() {
            _importResult = errorMsg.toString();
            _importHasError = true;
          });
          return;
        }

        // 如果有部分解析失败，记录警告
        if (extractResult.errors.isNotEmpty) {
          Logger.w(
            'JSON解析有 ${extractResult.errors.length} 个错误',
            tag: 'ImportJson',
          );
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
            errorMessages.add(
              context.t.cloud.importItemNotObject(item: (i + 1).toString()),
            );
            continue;
          }

          final json = Map<String, dynamic>.from(decoded);
          // 注入当前词典 ID（以便 insertOrUpdateEntry 找到正确的数据库）
          json['dict_id'] = widget.dictId;

          final entry = DictionaryEntry.fromJson(json);
          if (entry.id.isEmpty) {
            errorCount++;
            errorMessages.add(
              context.t.cloud.importItemMissingId(item: (i + 1).toString()),
            );
            continue;
          }

          final success = await _databaseService.insertOrUpdateEntry(entry);
          if (success) {
            successCount++;
          } else {
            errorCount++;
            errorMessages.add(
              context.t.cloud.importItemWriteFailed(
                item: (i + 1).toString(),
                id: entry.id,
                word: entry.headword,
              ),
            );
          }
        } catch (e) {
          errorCount++;
          errorMessages.add(
            context.t.cloud.importItemFailed(
              item: (i + 1).toString(),
              error: e.toString(),
            ),
          );
        }
      }

      final buf = StringBuffer(
        context.t.cloud.importSuccessCount(count: successCount.toString()),
      );
      if (errorCount > 0) {
        buf.write(
          context.t.cloud.importFailedCount(count: errorCount.toString()),
        );
        for (final msg in errorMessages.take(5)) {
          buf.write('\n\u2022 $msg');
        }
        if (errorMessages.length > 5) {
          buf.write(
            '\n${context.t.cloud.importMoreErrors(count: (errorMessages.length - 5).toString())}',
          );
        }
      }

      setState(() {
        _importResult = buf.toString();
        _importHasError = errorCount > 0 && successCount == 0;
      });

      if (successCount > 0) widget.onUpdateSuccess();
    } catch (e) {
      setState(() {
        _importResult = context.t.cloud.importFailedError(error: '$e');
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
      setState(
        () => _searchError = _searchMode == 'id'
            ? context.t.cloud.enterEntryId
            : context.t.cloud.enterHeadword,
      );
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
        final entry = await _databaseService.getEntryJsonById(
          widget.dictId,
          query,
        );
        if (entry == null) {
          setState(
            () => _searchError = context.t.cloud.entryIdNotFound(id: query),
          );
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
          setState(
            () => _searchError = context.t.cloud.headwordNotFound(word: query),
          );
        } else if (entries.length == 1) {
          final entry = entries.first;
          final eid = (entry['entry_id'] ?? entry['id'])?.toString() ?? query;
          setState(() {
            _foundEntry = entry;
            _foundEntryId = eid;
          });
        } else {
          setState(() => _foundEntries = entries);
        }
      }
    } catch (e) {
      setState(() => _searchError = context.t.cloud.searchFailed(error: '$e'));
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _deleteEntry() async {
    if (_foundEntryId == null || _foundEntry == null) return;

    final headword = _foundEntry!['headword']?.toString() ?? _foundEntryId!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.t.dict.deleteConfirmTitle),
        content: Text(
          context.t.cloud.deleteEntryConfirmContent(
            headword: headword,
            id: _foundEntryId!,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(context.t.dict.deleteConfirmTitle),
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
          showToast(context, context.t.cloud.entryDeleted);
          widget.onUpdateSuccess();
        }
      } else {
        if (mounted) showToast(context, context.t.cloud.entryDeleteFailed);
      }
    } catch (e) {
      if (mounted)
        showToast(
          context,
          context.t.cloud.deleteFailedError(error: e.toString()),
        );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrowScreen = screenWidth < 600;
    final dialogWidth = isNarrowScreen ? screenWidth - 32 : 600.0;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.data_object, size: 22, color: colorScheme.primary),
          const SizedBox(width: 10),
          Text(context.t.cloud.updateJsonTitle),
        ],
      ),
      contentPadding: isNarrowScreen
          ? const EdgeInsets.fromLTRB(16, 12, 16, 0)
          : const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(
        width: dialogWidth,
        height: 560,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              child: TabBar(
                controller: _tabController,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: EdgeInsets.zero,
                labelColor: colorScheme.primary,
                unselectedLabelColor: colorScheme.onSurfaceVariant,
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                tabs: [
                  Tab(
                    height: 42,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.download_outlined, size: 18),
                        const SizedBox(width: 6),
                        Text(context.t.cloud.importTab),
                      ],
                    ),
                  ),
                  Tab(
                    height: 42,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.delete_outline, size: 18),
                        const SizedBox(width: 6),
                        Text(context.t.cloud.deleteSearchTab),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_buildImportTab(), _buildDeleteTab()],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.t.common.close),
        ),
      ],
    );
  }

  Widget _buildImportTab() {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // JSON输入框
        Expanded(
          child: TextField(
            controller: _jsonController,
            maxLines: null,
            expands: true,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: context.t.cloud.importJsonPlaceholder,
              hintStyle: TextStyle(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                fontSize: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
              ),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.3,
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
        ),
        // 导入结果
        if (_importResult != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _importHasError
                  ? colorScheme.errorContainer.withValues(alpha: 0.5)
                  : colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
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
                      ? colorScheme.error
                      : colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _importResult!,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: _importHasError
                          ? colorScheme.onErrorContainer
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        // 操作按钮
        Row(
          children: [
            if (_jsonController.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton(
                  onPressed: _isImporting
                      ? null
                      : () {
                          setState(() {
                            _jsonController.clear();
                            _importResult = null;
                            _importHasError = false;
                          });
                        },
                  child: Text(context.t.cloud.clearLabel),
                ),
              ),
            Expanded(
              child: FilledButton(
                onPressed: _isImporting ? null : _importJson,
                child: _isImporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(context.t.cloud.writingToDb),
              ),
            ),
          ],
        ),
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
          segments: [
            ButtonSegment(
              value: 'headword',
              label: Text(context.t.cloud.prefixSearch),
            ),
            ButtonSegment(value: 'id', label: Text(context.t.cloud.idSearch)),
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
        ),
        const SizedBox(height: 12),
        // 搜索栏
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                keyboardType: _searchMode == 'id'
                    ? TextInputType.number
                    : TextInputType.text,
                decoration: InputDecoration(
                  hintText: _searchMode == 'id'
                      ? context.t.cloud.searchIdHint
                      : context.t.cloud.searchHeadwordHint,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.primary,
                      width: 1.5,
                    ),
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.3,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
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
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(context.t.search.searchBtn),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 错误提示
        if (_searchError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _searchError!,
              style: TextStyle(color: colorScheme.error, fontSize: 13),
            ),
          ),
        // 多条匹配结果列表
        if (_foundEntries.isNotEmpty) ...[
          Text(
            context.t.cloud.matchedEntries(count: _foundEntries.length),
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: _foundEntries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final e = _foundEntries[index];
                final hw = e['headword']?.toString() ?? '';
                final eid = (e['entry_id'] ?? e['id'])?.toString() ?? '';
                return ListTile(
                  dense: true,
                  title: Text(hw),
                  subtitle: Text(
                    'ID: $eid',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20),
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
        ],
        // 单条结果预览
        if (_foundEntry != null) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.3,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Text(
                  const JsonEncoder.withIndent('  ').convert(_foundEntry),
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _foundEntry = null;
                    _foundEntryId = null;
                  });
                },
                child: Text(context.t.common.back),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _isDeleting ? null : _deleteEntry,
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                ),
                child: _isDeleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(context.t.cloud.deleteEntry),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
