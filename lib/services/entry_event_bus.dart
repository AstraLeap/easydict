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

/// 词典启用/禁用状态变化事件
class DictionariesChangedEvent {
  const DictionariesChangedEvent();
}

/// 语言显示顺序变化事件（词典管理页拖拽排序后触发）
class LanguageOrderChangedEvent {
  const LanguageOrderChangedEvent();
}

/// 搜索历史变化事件（本地添加/删除历史记录时触发，供搜索页刷新列表）
class SearchHistoryChangedEvent {
  const SearchHistoryChangedEvent();
}

/// 剪切板搜索事件（剪切板监听捕获到文本时触发）
class ClipboardSearchEvent {
  final String text;
  const ClipboardSearchEvent(this.text);
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
  final _dictionariesChangedController =
      StreamController<DictionariesChangedEvent>.broadcast();
  final _languageOrderChangedController =
      StreamController<LanguageOrderChangedEvent>.broadcast();
  final _searchHistoryChangedController =
      StreamController<SearchHistoryChangedEvent>.broadcast();
  final _clipboardSearchController =
      StreamController<ClipboardSearchEvent>.broadcast();

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
  Stream<DictionariesChangedEvent> get dictionariesChanged =>
      _dictionariesChangedController.stream;
  Stream<LanguageOrderChangedEvent> get languageOrderChanged =>
      _languageOrderChangedController.stream;
  Stream<SearchHistoryChangedEvent> get searchHistoryChanged =>
      _searchHistoryChangedController.stream;
  Stream<ClipboardSearchEvent> get clipboardSearch =>
      _clipboardSearchController.stream;

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

  void emitDictionariesChanged() {
    _dictionariesChangedController.add(const DictionariesChangedEvent());
  }

  void emitLanguageOrderChanged() {
    _languageOrderChangedController.add(const LanguageOrderChangedEvent());
  }

  void emitSearchHistoryChanged() {
    _searchHistoryChangedController.add(const SearchHistoryChangedEvent());
  }

  void emitClipboardSearch(ClipboardSearchEvent event) {
    _clipboardSearchController.add(event);
  }

  void dispose() {
    _scrollToElementController.close();
    _translationInsertController.close();
    _toggleHiddenLanguageController.close();
    _batchToggleHiddenController.close();
    _settingsSyncedController.close();
    _dictionariesChangedController.close();
    _languageOrderChangedController.close();
    _searchHistoryChangedController.close();
    _clipboardSearchController.close();
  }
}
