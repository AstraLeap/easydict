import 'package:flutter/material.dart';
import '../database_service.dart';

/// 编辑状态管理
class EditState extends ChangeNotifier {
  bool _isEditing = false;
  DictionaryEntry? _originalEntry;
  DictionaryEntry? _editedEntry;

  bool get isEditing => _isEditing;
  DictionaryEntry? get originalEntry => _originalEntry;
  DictionaryEntry? get editedEntry => _editedEntry;
  bool get hasChanges => _editedEntry != _originalEntry;

  void startEditing(DictionaryEntry entry) {
    _isEditing = true;
    _originalEntry = entry;
    _editedEntry = entry;
    notifyListeners();
  }

  void cancelEditing() {
    _isEditing = false;
    _editedEntry = _originalEntry;
    notifyListeners();
  }

  /// 更新整个条目（用于 JSON 编辑器）
  void updateEntry(DictionaryEntry newEntry) {
    if (_editedEntry == null) return;

    _editedEntry = newEntry;
    notifyListeners();
  }

  Future<bool> saveChanges() async {
    if (_editedEntry == null || !hasChanges) return false;

    try {
      final dbService = DatabaseService();
      final success = await dbService.updateEntry(_editedEntry!);
      if (success) {
        _originalEntry = _editedEntry;
        _isEditing = false;
        notifyListeners();
      }
      return success;
    } catch (e) {
      debugPrint('保存失败: $e');
      return false;
    }
  }
}
