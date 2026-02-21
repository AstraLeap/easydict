import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/user_dicts_service.dart';
import '../services/dictionary_manager.dart';
import '../core/utils/toast_utils.dart';
import '../components/global_scale_wrapper.dart';

class UserDictEntryPage extends StatefulWidget {
  final String dictId;
  final String dictName;

  const UserDictEntryPage({
    super.key,
    required this.dictId,
    required this.dictName,
  });

  @override
  State<UserDictEntryPage> createState() => _UserDictEntryPageState();
}

class _UserDictEntryPageState extends State<UserDictEntryPage> {
  final UserDictsService _userDictsService = UserDictsService();
  final DictionaryManager _dictManager = DictionaryManager();

  final TextEditingController _jsonController = TextEditingController();
  final TextEditingController _messageController = TextEditingController(
    text: '更新条目',
  );

  bool _isSaving = false;

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

  Future<void> _saveEntry() async {
    final jsonText = _jsonController.text.trim();
    final message = _messageController.text.trim();

    if (jsonText.isEmpty) {
      showToast(context, '请输入JSON数据');
      return;
    }

    // 解析JSON
    Map<String, dynamic> data;
    try {
      data = jsonDecode(jsonText) as Map<String, dynamic>;
    } catch (e) {
      showToast(context, 'JSON格式错误: $e');
      return;
    }

    // 检查必需字段
    final entryId = data['entry_id']?.toString();
    final headword = data['headword']?.toString();
    final entryType = data['entry_type']?.toString() ?? 'word';
    final definition = data['definition']?.toString();
    final version = data['version'] is int
        ? data['version'] as int
        : int.tryParse(data['version']?.toString() ?? '1') ?? 1;

    if (entryId == null || entryId.isEmpty) {
      showToast(context, 'JSON中缺少 entry_id 字段');
      return;
    }
    if (headword == null || headword.isEmpty) {
      showToast(context, 'JSON中缺少 headword 字段');
      return;
    }
    if (definition == null || definition.isEmpty) {
      showToast(context, 'JSON中缺少 definition 字段');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final result = await _userDictsService.updateEntry(
        widget.dictId,
        entryId: entryId,
        headword: headword,
        entryType: entryType,
        definition: definition,
        version: version,
        message: message.isEmpty ? '更新条目' : message,
      );

      if (mounted) {
        if (result.success) {
          showToast(context, result.action == 'inserted' ? '条目已添加' : '条目已更新');
          // 清空表单以便继续添加
          _jsonController.clear();
        } else {
          showToast(context, result.error ?? '保存失败');
        }
      }
    } catch (e) {
      if (mounted) {
        showToast(context, '保存失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('编辑条目 - ${widget.dictName}'),
        centerTitle: true,
      ),
      body: PageScaleWrapper(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.code,
                            color: colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'JSON 数据',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '粘贴包含 entry_id、headword、definition 的 JSON',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _jsonController,
                        decoration: InputDecoration(
                          hintText: '{\n  "entry_id": "hello_001",\n  "headword": "hello",\n  "entry_type": "word",\n  "definition": "你好；您好",\n  "version": 1\n}',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: colorScheme.outlineVariant,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: colorScheme.primary,
                              width: 2,
                            ),
                          ),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerLowest,
                        ),
                        maxLines: 10,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                        enabled: !_isSaving,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.comment_outlined,
                            color: colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '版本备注',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: '如：更新条目',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: colorScheme.outlineVariant,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: colorScheme.primary,
                              width: 2,
                            ),
                          ),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerLowest,
                        ),
                        enabled: !_isSaving,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isSaving ? null : _saveEntry,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(_isSaving ? '保存中...' : '保存条目'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '提示：如果 entry_id 已存在，将更新该条目；否则将创建新条目。',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _jsonController.dispose();
    _messageController.dispose();
    super.dispose();
  }
}
