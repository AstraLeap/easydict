import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../data/database_service.dart';
import '../data/models/dictionary_entry_group.dart';
import '../models/browse_list.dart';

class EntryTabItem {
  final String id;
  final String word;
  final DictionaryEntryGroup entryGroup;
  final List<DictSearchResult>? dictResults;
  final BrowseList? browseList;
  final bool isLoading;
  final int revision;

  const EntryTabItem({
    required this.id,
    required this.word,
    required this.entryGroup,
    this.dictResults,
    this.browseList,
    this.isLoading = false,
    this.revision = 0,
  });

  EntryTabItem copyWith({
    String? word,
    DictionaryEntryGroup? entryGroup,
    List<DictSearchResult>? dictResults,
    BrowseList? browseList,
    bool? isLoading,
    int? revision,
  }) {
    return EntryTabItem(
      id: id,
      word: word ?? this.word,
      entryGroup: entryGroup ?? this.entryGroup,
      dictResults: dictResults ?? this.dictResults,
      browseList: browseList ?? this.browseList,
      isLoading: isLoading ?? this.isLoading,
      revision: revision ?? this.revision,
    );
  }
}

class EntryTabService extends ChangeNotifier {
  EntryTabService._internal();
  static final EntryTabService _instance = EntryTabService._internal();
  factory EntryTabService() => _instance;

  final List<EntryTabItem> _tabs = <EntryTabItem>[];
  int _activeIndex = -1;
  int _lastSwitchDirection = 1;
  int _idCounter = 0;

  UnmodifiableListView<EntryTabItem> get tabs => UnmodifiableListView(_tabs);
  int get activeIndex => _activeIndex;
  int get lastSwitchDirection => _lastSwitchDirection;
  EntryTabItem? get activeTab =>
      (_activeIndex >= 0 && _activeIndex < _tabs.length)
      ? _tabs[_activeIndex]
      : null;

  Set<String> get activeWords => _tabs.map((t) => t.word).toSet();

  int _indexOfWord(String word) {
    final normalized = word.trim().toLowerCase();
    for (int i = 0; i < _tabs.length; i++) {
      if (_tabs[i].word.trim().toLowerCase() == normalized) {
        return i;
      }
    }
    return -1;
  }

  bool _isSameBrowseSource(BrowseList? a, BrowseList? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.source != b.source) return false;

    if (a.source == BrowseListSource.wordBank) {
      return a.language == b.language && a.listName == b.listName;
    }

    return true;
  }

  int _indexOfWordByBrowseSource(String word, BrowseList? browseList) {
    final normalized = word.trim().toLowerCase();
    for (int i = 0; i < _tabs.length; i++) {
      final tab = _tabs[i];
      if (tab.word.trim().toLowerCase() != normalized) continue;
      if (_isSameBrowseSource(tab.browseList, browseList)) {
        return i;
      }
    }
    return -1;
  }

  bool isWordActive(String word) => _indexOfWord(word) != -1;

  int _indexOfTabId(String tabId) {
    for (int i = 0; i < _tabs.length; i++) {
      if (_tabs[i].id == tabId) return i;
    }
    return -1;
  }

  void setActiveIndex(int index, {int? directionHint}) {
    if (index < 0 || index >= _tabs.length || _activeIndex == index) return;
    _lastSwitchDirection = directionHint ?? (index > _activeIndex ? 1 : -1);
    _activeIndex = index;
    notifyListeners();
  }

  void openOrActivateTab({
    required String word,
    required DictionaryEntryGroup entryGroup,
    List<DictSearchResult>? dictResults,
    BrowseList? browseList,
    bool preferExisting = true,
    bool insertToLeft = false,
  }) {
    int existingIndex = -1;
    if (preferExisting) {
      // 优先复用同来源标签，避免单词本与普通查词在同词时互相串用或重复创建。
      existingIndex = _indexOfWordByBrowseSource(word, browseList);
      if (existingIndex == -1 && browseList == null) {
        existingIndex = _indexOfWord(word);
      }
    }

    if (existingIndex != -1) {
      setActiveIndex(existingIndex);
      return;
    }

    final tab = EntryTabItem(
      id: 'tab_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}',
      word: word,
      entryGroup: entryGroup,
      dictResults: dictResults,
      browseList: browseList,
    );

    if (_tabs.isEmpty) {
      _tabs.add(tab);
      _activeIndex = 0;
      _lastSwitchDirection = 1;
      notifyListeners();
      return;
    }

    int insertIndex;
    if (insertToLeft) {
      insertIndex = 0;
      _lastSwitchDirection = -1;
    } else {
      insertIndex = _tabs.length;
      _lastSwitchDirection = 1;
    }

    _tabs.insert(insertIndex, tab);
    _activeIndex = insertIndex;
    notifyListeners();
  }

  String openLoadingTab({
    required String word,
    BrowseList? browseList,
    bool preferExisting = true,
    bool insertToLeft = false,
  }) {
    final placeholderGroup = DictionaryEntryGroup(
      headword: word,
      dictionaryGroups: const [],
    );

    int existingIndex = -1;
    if (preferExisting) {
      existingIndex = _indexOfWordByBrowseSource(word, browseList);
      if (existingIndex == -1 && browseList == null) {
        existingIndex = _indexOfWord(word);
      }
    }

    if (existingIndex != -1) {
      final existing = _tabs[existingIndex];
      _tabs[existingIndex] = existing.copyWith(
        isLoading: true,
        revision: existing.revision + 1,
      );
      setActiveIndex(existingIndex);
      return existing.id;
    }

    final tab = EntryTabItem(
      id: 'tab_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}',
      word: word,
      entryGroup: placeholderGroup,
      dictResults: null,
      browseList: browseList,
      isLoading: true,
      revision: 0,
    );

    if (_tabs.isEmpty) {
      _tabs.add(tab);
      _activeIndex = 0;
      _lastSwitchDirection = 1;
      notifyListeners();
      return tab.id;
    }

    final insertIndex = insertToLeft ? 0 : _tabs.length;
    _lastSwitchDirection = insertToLeft ? -1 : 1;
    _tabs.insert(insertIndex, tab);
    _activeIndex = insertIndex;
    notifyListeners();
    return tab.id;
  }

  bool replaceLoadingTabContent({
    required String tabId,
    required String word,
    required DictionaryEntryGroup entryGroup,
    List<DictSearchResult>? dictResults,
    BrowseList? browseList,
  }) {
    final index = _indexOfTabId(tabId);
    if (index == -1) return false;

    final oldTab = _tabs[index];
    _tabs[index] = oldTab.copyWith(
      word: word,
      entryGroup: entryGroup,
      dictResults: dictResults,
      browseList: browseList,
      isLoading: false,
      revision: oldTab.revision + 1,
    );
    notifyListeners();
    return true;
  }

  void closeById(String tabId) {
    final index = _indexOfTabId(tabId);
    if (index != -1) {
      closeAt(index);
    }
  }

  void closeAt(int index) {
    if (index < 0 || index >= _tabs.length) return;

    _tabs.removeAt(index);
    if (_tabs.isEmpty) {
      _activeIndex = -1;
      notifyListeners();
      return;
    }

    if (_activeIndex >= _tabs.length) {
      _activeIndex = _tabs.length - 1;
    } else if (index < _activeIndex) {
      _activeIndex -= 1;
    }

    notifyListeners();
  }

  void closeByWord(String word) {
    final index = _indexOfWord(word);
    if (index != -1) {
      closeAt(index);
    }
  }

  void moveTab(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _tabs.length) return;
    if (newIndex < 0 || newIndex > _tabs.length) return;
    if (oldIndex == newIndex) return;

    var targetIndex = newIndex;
    if (targetIndex > oldIndex) {
      targetIndex -= 1;
    }
    if (targetIndex == oldIndex) return;

    final moved = _tabs.removeAt(oldIndex);
    _tabs.insert(targetIndex, moved);

    if (_activeIndex == oldIndex) {
      _activeIndex = targetIndex;
    } else if (oldIndex < _activeIndex && targetIndex >= _activeIndex) {
      _activeIndex -= 1;
    } else if (oldIndex > _activeIndex && targetIndex <= _activeIndex) {
      _activeIndex += 1;
    }

    _lastSwitchDirection = targetIndex > oldIndex ? 1 : -1;
    notifyListeners();
  }

  void closeTabsToRight(int index) {
    if (index < 0 || index >= _tabs.length) return;
    for (int i = _tabs.length - 1; i > index; i--) {
      closeAt(i);
    }
  }

  void closeOtherTabs(int index) {
    if (index < 0 || index >= _tabs.length) return;
    for (int i = _tabs.length - 1; i >= 0; i--) {
      if (i == index) continue;
      closeAt(i);
    }
  }

  void closeTabsOutsideWordsWindow(
    List<String> orderedWords,
    int centerIndex, {
    int maxDistance = 5,
    BrowseListSource? sourceFilter,
  }) {
    if (orderedWords.isEmpty || _tabs.isEmpty) return;

    final normalizedWords = orderedWords
        .asMap()
        .entries
        .map((entry) => MapEntry(entry.value.trim().toLowerCase(), entry.key))
        .toList();

    final allowedWords = <String>{};
    for (final entry in normalizedWords) {
      if ((entry.value - centerIndex).abs() < maxDistance) {
        allowedWords.add(entry.key);
      }
    }

    final indicesToClose = <int>[];
    for (int i = 0; i < _tabs.length; i++) {
      if (sourceFilter != null && _tabs[i].browseList?.source != sourceFilter) {
        continue;
      }
      final tabWord = _tabs[i].word.trim().toLowerCase();
      if (orderedWords.isEmpty) continue;
      if (allowedWords.contains(tabWord)) continue;
      if (normalizedWords.any((entry) => entry.key == tabWord)) {
        indicesToClose.add(i);
      }
    }

    for (int i = indicesToClose.length - 1; i >= 0; i--) {
      closeAt(indicesToClose[i]);
    }
  }

  void clearAllTabs() {
    if (_tabs.isEmpty) return;
    _tabs.clear();
    _activeIndex = -1;
    notifyListeners();
  }
}
