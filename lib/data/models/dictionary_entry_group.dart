import '../database_service.dart';
import '../../services/advanced_search_settings_service.dart';
import '../../services/dictionary_manager.dart';
import '../../core/utils/language_utils.dart';

class DictionarySection {
  final String section;
  final DictionaryEntry entry;

  DictionarySection({required this.section, required this.entry});
}

class PageGroup {
  final String page;
  final List<DictionarySection> sections;

  PageGroup({required this.page, required List<DictionarySection> sections})
    : sections = List.from(sections);
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
    if (index >= 0 && index < pageGroups.length) {
      _currentPageIndex = index;
      _currentSectionIndex = 0;
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
        final pageEntries = pageEntry.value
          ..sort((a, b) => a.id.compareTo(b.id));
        return PageGroup(
          page: pageEntry.key,
          sections: pageEntries
              .map((e) => DictionarySection(section: e.section ?? '', entry: e))
              .toList(),
        );
      }).toList()..sort((a, b) => a.page.compareTo(b.page));

      if (pageGroups.isEmpty) continue;

      dictionaryGroups.add(
        DictionaryGroup(
          dictionaryId: dictId,
          dictionaryName: dictId.isEmpty
              ? 'Unknown'
              : dictId[0].toUpperCase() + dictId.substring(1),
          pageGroups: pageGroups,
        ),
      );
    }

    // 按照词典排序界面的顺序排序：语言顺序为主体，语言内部按词典启用顺序
    _sortDictionaryGroups(dictionaryGroups);

    return DictionaryEntryGroup(
      headword: headword,
      dictionaryGroups: dictionaryGroups,
    );
  }

  /// 按照词典排序界面的顺序排序词典组
  /// 排序规则：语言顺序为主体，各语言内部按词典启用顺序
  static void _sortDictionaryGroups(List<DictionaryGroup> groups) {
    if (groups.isEmpty) return;

    final dictManager = DictionaryManager();
    final advancedSettingsService = AdvancedSearchSettingsService();

    // 获取语言顺序（同步从缓存获取，如果没有则使用默认顺序）
    final languageOrder = advancedSettingsService.getLanguageOrderSync();

    // 获取词典启用顺序
    final enabledDictIds = dictManager.getEnabledDictionariesSync();

    // 获取每个词典的源语言
    final Map<String, String> dictToLang = {};
    for (final group in groups) {
      final metadata = dictManager.getCachedMetadata(group.dictionaryId);
      if (metadata != null) {
        dictToLang[group.dictionaryId] = LanguageUtils.normalizeSourceLanguage(
          metadata.sourceLanguage,
        );
      } else {
        dictToLang[group.dictionaryId] = '';
      }
    }

    // 排序：语言顺序为主体，语言内部按词典启用顺序
    groups.sort((a, b) {
      final langA = dictToLang[a.dictionaryId] ?? '';
      final langB = dictToLang[b.dictionaryId] ?? '';

      // 首先按语言顺序排序
      final langIndexA = languageOrder.indexOf(langA);
      final langIndexB = languageOrder.indexOf(langB);

      // 如果两个语言都在保存的顺序中，按语言顺序排序
      if (langIndexA != -1 && langIndexB != -1) {
        if (langIndexA != langIndexB) {
          return langIndexA.compareTo(langIndexB);
        }
        // 同一语言内部，按词典启用顺序排序
        final dictIndexA = enabledDictIds.indexOf(a.dictionaryId);
        final dictIndexB = enabledDictIds.indexOf(b.dictionaryId);
        if (dictIndexA != -1 && dictIndexB != -1) {
          return dictIndexA.compareTo(dictIndexB);
        } else if (dictIndexA != -1) {
          return -1;
        } else if (dictIndexB != -1) {
          return 1;
        }
        return a.dictionaryId.compareTo(b.dictionaryId);
      }

      // 如果只有一个语言在保存的顺序中，有顺序的排前面
      if (langIndexA != -1) return -1;
      if (langIndexB != -1) return 1;

      // 如果两个语言都不在保存的顺序中，按字母顺序排序
      if (langA != langB) {
        return langA.compareTo(langB);
      }

      // 同一语言内部，按词典启用顺序排序
      final dictIndexA = enabledDictIds.indexOf(a.dictionaryId);
      final dictIndexB = enabledDictIds.indexOf(b.dictionaryId);
      if (dictIndexA != -1 && dictIndexB != -1) {
        return dictIndexA.compareTo(dictIndexB);
      } else if (dictIndexA != -1) {
        return -1;
      } else if (dictIndexB != -1) {
        return 1;
      }
      return a.dictionaryId.compareTo(b.dictionaryId);
    });
  }
}
