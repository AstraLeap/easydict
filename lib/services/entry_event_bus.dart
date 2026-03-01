import 'dart:async';

class ScrollToElementEvent {
  final String entryId;
  final String path;

  ScrollToElementEvent({required this.entryId, required this.path});
}

class TranslationInsertEvent {
  final String entryId;
  final String path;
  final Map<String, dynamic> newEntry;

  TranslationInsertEvent({
    required this.entryId,
    required this.path,
    required this.newEntry,
  });
}

class ToggleHiddenLanguageEvent {
  final String entryId;
  final String languageKey;

  ToggleHiddenLanguageEvent({required this.entryId, required this.languageKey});
}

class BatchToggleHiddenLanguagesEvent {
  final List<String> pathsToHide;
  final List<String> pathsToShow;

  BatchToggleHiddenLanguagesEvent({
    required this.pathsToHide,
    required this.pathsToShow,
  });
}

/// 云端设置同步完成事件，携带本次同步涉及的数据类型
class SettingsSyncedEvent {
  /// 是否包含查词历史
  final bool includesHistory;

  const SettingsSyncedEvent({this.includesHistory = true});
}

class EntryEventBus {
  static final EntryEventBus _instance = EntryEventBus._internal();
  factory EntryEventBus() => _instance;
  EntryEventBus._internal();

  final _scrollToElementController =
      StreamController<ScrollToElementEvent>.broadcast();
  final _translationInsertController =
      StreamController<TranslationInsertEvent>.broadcast();
  final _toggleHiddenLanguageController =
      StreamController<ToggleHiddenLanguageEvent>.broadcast();
  final _batchToggleHiddenController =
      StreamController<BatchToggleHiddenLanguagesEvent>.broadcast();
  final _settingsSyncedController =
      StreamController<SettingsSyncedEvent>.broadcast();

  Stream<ScrollToElementEvent> get scrollToElement =>
      _scrollToElementController.stream;
  Stream<TranslationInsertEvent> get translationInsert =>
      _translationInsertController.stream;
  Stream<ToggleHiddenLanguageEvent> get toggleHiddenLanguage =>
      _toggleHiddenLanguageController.stream;
  Stream<BatchToggleHiddenLanguagesEvent> get batchToggleHidden =>
      _batchToggleHiddenController.stream;
  Stream<SettingsSyncedEvent> get settingsSynced =>
      _settingsSyncedController.stream;

  void emitScrollToElement(ScrollToElementEvent event) {
    _scrollToElementController.add(event);
  }

  void emitTranslationInsert(TranslationInsertEvent event) {
    _translationInsertController.add(event);
  }

  void emitToggleHiddenLanguage(ToggleHiddenLanguageEvent event) {
    _toggleHiddenLanguageController.add(event);
  }

  void emitBatchToggleHiddenLanguages(BatchToggleHiddenLanguagesEvent event) {
    _batchToggleHiddenController.add(event);
  }

  void emitSettingsSynced(SettingsSyncedEvent event) {
    _settingsSyncedController.add(event);
  }

  void dispose() {
    _scrollToElementController.close();
    _translationInsertController.close();
    _toggleHiddenLanguageController.close();
    _batchToggleHiddenController.close();
    _settingsSyncedController.close();
  }
}
