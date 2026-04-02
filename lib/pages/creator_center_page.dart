import 'package:flutter/material.dart';
import 'cloud_service_page.dart'
    show
        PushUpdatesDialog,
        UploadDictionaryDialog,
        EditDictionaryDialog,
        UpdateJsonDialog;
import '../services/dictionary_manager.dart';
import '../services/dictionary_store_service.dart';
import '../services/user_dicts_service.dart';
import '../services/auth_service.dart';
import '../services/font_loader_service.dart';
import '../data/models/dictionary_metadata.dart';
import '../data/models/user_dictionary.dart';
import '../core/utils/toast_utils.dart';
import '../i18n/strings.g.dart';
import '../components/global_scale_wrapper.dart';
import '../components/transfer_progress_panel.dart';

class CreatorCenterPage extends StatefulWidget {
  final VoidCallback? onBack;

  const CreatorCenterPage({super.key, this.onBack});

  @override
  State<CreatorCenterPage> createState() => _CreatorCenterPageState();
}

class _CreatorCenterPageState extends State<CreatorCenterPage> {
  final DictionaryManager _dictManager = DictionaryManager();
  final UserDictsService _userDictsService = UserDictsService();
  final AuthService _authService = AuthService();

  List<UserDictionary> _userDictionaries = [];
  bool _isLoadingUserDicts = false;
  String? _userDictsError;
  List<DictionaryMetadata> _allDictionaries = [];
  DictionaryStoreService? _storeService;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _userDictsService.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final url = await _dictManager.onlineSubscriptionUrl;
    if (url.isNotEmpty) {
      _storeService = DictionaryStoreService(baseUrl: url);
      _userDictsService.setBaseUrl(url);
      _authService.setBaseUrl(url);

      final allDicts = await _dictManager.getAllDictionariesMetadata();

      setState(() {
        _allDictionaries = allDicts;
      });

      _loadUserDictionaries();
    }
  }

  Future<void> _loadUserDictionaries() async {
    if (_storeService == null) return;

    if (!mounted) return;
    setState(() {
      _isLoadingUserDicts = true;
      _userDictsError = null;
    });

    try {
      final dicts = await _userDictsService.fetchUserDicts();
      if (mounted) {
        setState(() {
          _userDictionaries = dicts;
          _isLoadingUserDicts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _userDictsError = e.toString();
          _isLoadingUserDicts = false;
        });
      }
    }
  }

  Future<void> _refreshLocalDictionaries() async {
    final allDicts = await _dictManager.getAllDictionariesMetadata();
    setState(() {
      _allDictionaries = allDicts;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scale = FontLoaderService().getDictionaryContentScale();
    final colorScheme = Theme.of(context).colorScheme;

    final content = Scaffold(
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : null,
        title: Text(context.t.dict.tabCreator),
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: _buildContent(colorScheme),
      floatingActionButton: !_isLoadingUserDicts && _userDictsError == null
          ? FloatingActionButton(
              onPressed: _showUploadDialog,
              child: const Icon(Icons.add),
            )
          : null,
      bottomSheet: const UploadProgressPanel(),
    );

    Widget result = content;
    if (scale != 1.0) {
      result = PageScaleWrapper(child: content);
    }

    // 如果有 onBack 回调，使用 PopScope 拦截系统返回
    if (widget.onBack != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, popResult) {
          if (!didPop) {
            widget.onBack!();
          }
        },
        child: result,
      );
    }

    return result;
  }

  Widget _buildContent(ColorScheme colorScheme) {
    return Stack(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_isLoadingUserDicts)
                          const Center(child: CircularProgressIndicator())
                        else if (_userDictsError != null)
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                                width: 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: colorScheme.error,
                                    size: 48,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    context.t.dict.loadFailed,
                                    style: TextStyle(color: colorScheme.error),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _userDictsError!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton.icon(
                                    onPressed: _loadUserDictionaries,
                                    icon: const Icon(Icons.refresh),
                                    label: Text(context.t.common.retry),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else if (_userDictionaries.isEmpty)
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                                width: 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.library_books_outlined,
                                      size: 48,
                                      color: colorScheme.outline,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      context.t.dict.noCreatorDicts,
                                      style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        else ...[
                          ..._userDictionaries.map(
                            (dict) => _buildCreatorCenterDictionaryCard(
                              dict,
                              colorScheme,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCreatorCenterDictionaryCard(
    UserDictionary dict,
    ColorScheme colorScheme,
  ) {
    final metadata = _allDictionaries
        .where((m) => m.id == dict.dictId)
        .firstOrNull;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dict.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  metadata != null ? 'v${metadata.version}' : '',
                  style: TextStyle(fontSize: 12, color: colorScheme.outline),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _showUpdateJsonDialog(dict),
                  icon: Icon(Icons.data_object, color: colorScheme.primary),
                  tooltip: context.t.dict.tooltipUpdateJson,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: () => _showPushUpdatesDialog(dict),
                  icon: Icon(
                    Icons.cloud_upload_outlined,
                    color: colorScheme.primary,
                  ),
                  tooltip: context.t.dict.tooltipPushUpdate,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: () => _showEditFilesDialog(dict),
                  icon: Icon(Icons.swap_horiz, color: colorScheme.primary),
                  tooltip: context.t.dict.tooltipReplaceFile,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: () => _handleDeleteDictionary(dict),
                  icon: Icon(Icons.delete_outline, color: colorScheme.error),
                  tooltip: context.t.dict.tooltipDelete,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showUploadDialog() {
    showDialog(
      context: context,
      builder: (_) => UploadDictionaryDialog(
        onUploadSuccess: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _loadUserDictionaries();
            _refreshLocalDictionaries();
            showToast(context, context.t.cloud.uploadSuccess);
          });
        },
      ),
    );
  }

  void _showUpdateJsonDialog(UserDictionary dict) {
    showDialog(
      context: context,
      builder: (_) => UpdateJsonDialog(
        dictId: dict.dictId,
        dictName: dict.name,
        onUpdateSuccess: () {
          _loadUserDictionaries();
          _refreshLocalDictionaries();
        },
      ),
    );
  }

  void _showPushUpdatesDialog(UserDictionary dict) {
    showDialog(
      context: context,
      builder: (_) => PushUpdatesDialog(
        dictId: dict.dictId,
        dictName: dict.name,
        onPushSuccess: () {
          _loadUserDictionaries();
          _refreshLocalDictionaries();
        },
      ),
    );
  }

  void _showEditFilesDialog(UserDictionary dict) {
    showDialog(
      context: context,
      builder: (_) => EditDictionaryDialog(
        dictId: dict.dictId,
        dictName: dict.name,
        onUpdateSuccess: () {
          _loadUserDictionaries();
          _refreshLocalDictionaries();
        },
      ),
    );
  }

  Future<void> _handleDeleteDictionary(UserDictionary dict) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t.dict.deleteConfirmTitle),
        content: Text(context.t.dict.deleteConfirmBody(name: dict.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.t.common.delete),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _userDictsService.deleteDictionary(dict.dictId);
        _loadUserDictionaries();
        if (mounted) showToast(context, context.t.dict.deleteSuccess);
      } catch (e) {
        if (mounted)
          showToast(context, context.t.dict.deleteFailed(error: '$e'));
      }
    }
  }
}
