import '../database_service.dart';

class DictionarySection {
  final String section;
  final DictionaryEntry entry;

  DictionarySection({required this.section, required this.entry});
}

class PageGroup {
  final String page;
  final List<DictionarySection> sections;

  PageGroup({required this.page, required this.sections});
}

class DictionaryGroup {
  final String dictionaryId;
  final String dictionaryName;
  final List<PageGroup> pageGroups;
  int _currentPageIndex;
  int _currentSectionIndex;

  DictionaryGroup({
    required this.dictionaryId,
    required this.dictionaryName,
    required this.pageGroups,
  }) : _currentPageIndex = 0,
       _currentSectionIndex = 0;

  int get currentPageIndex => _currentPageIndex;
  int get currentSectionIndex => _currentSectionIndex;

  String get currentPage {
    if (pageGroups.isEmpty) return '';
    return pageGroups[_currentPageIndex].page;
  }

  PageGroup get currentPageGroup {
    if (pageGroups.isEmpty) {
      return PageGroup(page: '', sections: []);
    }
    return pageGroups[_currentPageIndex];
  }

  DictionaryEntry? get currentEntry {
    final page = currentPageGroup;
    if (page.sections.isEmpty) return null;
    if (_currentSectionIndex >= page.sections.length) {
      return page.sections.first.entry;
    }
    return page.sections[_currentSectionIndex].entry;
  }

  int get totalPageCount => pageGroups.length;

  int get currentPageSectionCount => currentPageGroup.sections.length;

  void setCurrentPageIndex(int index) {
    print('[DEBUG] DictionaryGroup.setCurrentPageIndex: $index (current: $_currentPageIndex)');
    if (index >= 0 && index < pageGroups.length) {
      _currentPageIndex = index;
      _currentSectionIndex = 0;
    } else {
      print('[DEBUG] DictionaryGroup.setCurrentPageIndex: Index out of bounds');
    }
  }

  void setCurrentSectionIndex(int index) {
    final page = currentPageGroup;
    if (index >= 0 && index < page.sections.length) {
      _currentSectionIndex = index;
    }
  }

  bool get hasMultiplePages => pageGroups.length > 1;

  bool get hasMultipleSections {
    final page = currentPageGroup;
    return page.sections.length > 1;
  }
}

class DictionaryEntryGroup {
  final String headword;
  final List<DictionaryGroup> dictionaryGroups;
  int _currentDictionaryIndex;

  DictionaryEntryGroup({required this.headword, required this.dictionaryGroups})
    : _currentDictionaryIndex = 0;

  int get currentDictionaryIndex => _currentDictionaryIndex;

  String get currentDictionaryId {
    if (dictionaryGroups.isEmpty) return '';
    return dictionaryGroups[_currentDictionaryIndex].dictionaryId;
  }

  String get currentDictionaryName {
    if (dictionaryGroups.isEmpty) return '';
    return dictionaryGroups[_currentDictionaryIndex].dictionaryName;
  }

  DictionaryGroup get currentDictionaryGroup {
    if (dictionaryGroups.isEmpty) {
      return DictionaryGroup(
        dictionaryId: '',
        dictionaryName: '',
        pageGroups: [],
      );
    }
    return dictionaryGroups[_currentDictionaryIndex];
  }

  DictionaryEntry? get currentEntry {
    if (dictionaryGroups.isEmpty) return null;
    return currentDictionaryGroup.currentEntry;
  }

  int get totalDictionaryCount => dictionaryGroups.length;

  void setCurrentDictionaryIndex(int index) {
    if (index >= 0 && index < dictionaryGroups.length) {
      _currentDictionaryIndex = index;
    }
  }

  bool get hasMultipleDictionaries => dictionaryGroups.length > 1;

  static DictionaryEntryGroup groupEntries(List<DictionaryEntry> entries) {
    if (entries.isEmpty) {
      return DictionaryEntryGroup(headword: '', dictionaryGroups: []);
    }

    final headword = entries.first.headword;

    // 使用 dict_id 分组（优先使用 dict_id，否则从 entry_id 提取）
    final Map<String, List<DictionaryEntry>> dictMap = {};
    for (final entry in entries) {
      final dictId = entry.dictId ?? entry.id.split('_')[0];
      dictMap.putIfAbsent(dictId, () => []).add(entry);
    }

    final dictionaryGroups = <DictionaryGroup>[];

    for (final dictEntry in dictMap.entries) {
      final dictId = dictEntry.key;
      final dictEntries = dictEntry.value;

      // 按 page 分组
      final Map<String, List<DictionaryEntry>> pageMap = {};
      for (final entry in dictEntries) {
        final page = entry.page ?? '';
        pageMap.putIfAbsent(page, () => []).add(entry);
      }

      // 构建 pageGroups
      final pageGroups = pageMap.entries.map((pageEntry) {
        final pageEntries = pageEntry.value..sort((a, b) => a.id.compareTo(b.id));
        return PageGroup(
          page: pageEntry.key,
          sections: pageEntries.map((e) => DictionarySection(section: e.section ?? '', entry: e)).toList(),
        );
      }).toList()..sort((a, b) => a.page.compareTo(b.page));

      if (pageGroups.isEmpty) continue;

      dictionaryGroups.add(DictionaryGroup(
        dictionaryId: dictId,
        dictionaryName: dictId.isEmpty ? 'Unknown' : dictId[0].toUpperCase() + dictId.substring(1),
        pageGroups: pageGroups,
      ));
    }

    dictionaryGroups.sort((a, b) => a.dictionaryId.compareTo(b.dictionaryId));

    return DictionaryEntryGroup(headword: headword, dictionaryGroups: dictionaryGroups);
  }
}
