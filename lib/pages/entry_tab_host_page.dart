import 'package:flutter/material.dart';

import '../data/database_service.dart';
import '../data/models/dictionary_entry_group.dart';
import '../models/browse_list.dart';
import '../services/entry_tab_service.dart';
import 'entry_detail_page.dart';

enum _TabMenuAction { closeAll, closeRight, closeOthers }

class EntryTabHostPage extends StatefulWidget {
  const EntryTabHostPage({super.key});

  static Future<T?> open<T>(
    BuildContext context, {
    required DictionaryEntryGroup entryGroup,
    required String initialWord,
    List<DictSearchResult>? dictResults,
    BrowseList? browseList,
    bool preferExisting = true,
    bool insertToLeft = false,
  }) {
    EntryTabService().openOrActivateTab(
      word: initialWord,
      entryGroup: entryGroup,
      dictResults: dictResults,
      browseList: browseList,
      preferExisting: preferExisting,
      insertToLeft: insertToLeft,
    );

    // 如果当前已经在宿主页内，只更新标签状态，不再 push 新页面。
    if (context.findAncestorWidgetOfExactType<EntryTabHostPage>() != null) {
      return Future.value(null);
    }

    return Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            const EntryTabHostPage(),
      ),
    );
  }

  @override
  State<EntryTabHostPage> createState() => _EntryTabHostPageState();
}

class _EntryTabHostPageState extends State<EntryTabHostPage>
    with SingleTickerProviderStateMixin {
  final EntryTabService _tabService = EntryTabService();
  final DatabaseService _dbService = DatabaseService();

  late final AnimationController _dismissController;

  @override
  void initState() {
    super.initState();
    _dismissController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _tabService.addListener(_onTabsChanged);
  }

  @override
  void dispose() {
    _tabService.removeListener(_onTabsChanged);
    _dismissController.dispose();
    super.dispose();
  }

  void _onTabsChanged() {
    if (!mounted) return;
    if (_tabService.tabs.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
  }

  void _trimWordBankTabs({required bool closeFromLeft}) {
    while (true) {
      final wordBankIndices = <int>[];
      for (int i = 0; i < _tabService.tabs.length; i++) {
        if (_tabService.tabs[i].browseList?.source ==
            BrowseListSource.wordBank) {
          wordBankIndices.add(i);
        }
      }

      if (wordBankIndices.length <= 5) return;

      int indexToClose = closeFromLeft
          ? wordBankIndices.first
          : wordBankIndices.last;

      if (indexToClose == _tabService.activeIndex &&
          wordBankIndices.length > 1) {
        indexToClose = closeFromLeft
            ? wordBankIndices[1]
            : wordBankIndices[wordBankIndices.length - 2];
      }

      _tabService.closeAt(indexToClose);
    }
  }

  Future<void> _handleBrowseNavigate(
    String word, {
    required bool insertToLeft,
  }) async {
    final activeTab = _tabService.activeTab;
    final sourceBrowseList = activeTab?.browseList;
    if (sourceBrowseList == null) return;

    if (sourceBrowseList.source == BrowseListSource.searchHistory) {
      final nextIndex = insertToLeft
          ? _tabService.activeIndex - 1
          : _tabService.activeIndex + 1;
      if (nextIndex < 0 || nextIndex >= _tabService.tabs.length) return;

      _tabService.setActiveIndex(
        nextIndex,
        directionHint: insertToLeft ? -1 : 1,
      );
      return;
    }

    // 单词本：若目标方向已有标签，则仅做普通标签切换；
    // 若该方向没有标签，再按单词本 browseList 扩展一个新词，并关闭另一端最远标签保持 5 个。
    final adjacentIndex = insertToLeft
        ? _tabService.activeIndex - 1
        : _tabService.activeIndex + 1;
    if (adjacentIndex >= 0 && adjacentIndex < _tabService.tabs.length) {
      _tabService.setActiveIndex(
        adjacentIndex,
        directionHint: insertToLeft ? -1 : 1,
      );
      return;
    }

    final existingIndex = _tabService.tabs.indexWhere(
      (tab) =>
          tab.word.toLowerCase() == word.toLowerCase() &&
          tab.browseList?.source == BrowseListSource.wordBank,
    );
    if (existingIndex != -1) {
      _tabService.setActiveIndex(existingIndex);
      return;
    }

    final searchResult = await _dbService.getAllEntries(word);
    if (!mounted || searchResult.entries.isEmpty) return;

    final index = sourceBrowseList.words.indexOf(word);
    final nextBrowseList = BrowseList(
      source: sourceBrowseList.source,
      words: sourceBrowseList.words,
      initialIndex: index >= 0 ? index : 0,
      language: sourceBrowseList.language,
      listName: sourceBrowseList.listName,
    );

    _tabService.openOrActivateTab(
      word: word,
      entryGroup: DictionaryEntryGroup.groupEntries(searchResult.entries),
      dictResults: searchResult.dictResults,
      browseList: nextBrowseList,
      preferExisting: true,
      insertToLeft: insertToLeft,
    );

    _trimWordBankTabs(closeFromLeft: !insertToLeft);
  }

  Future<void> _handleOpenEntryRequested({
    required DictionaryEntryGroup entryGroup,
    required String initialWord,
    List<DictSearchResult>? dictResults,
    BrowseList? browseList,
    bool insertToLeft = false,
    bool preferExisting = true,
  }) async {
    _tabService.openOrActivateTab(
      word: initialWord,
      entryGroup: entryGroup,
      dictResults: dictResults,
      browseList: browseList,
      preferExisting: preferExisting,
      insertToLeft: insertToLeft,
    );
  }

  Future<void> _dismissToHome() async {
    if (_dismissController.isAnimating || _dismissController.value > 0) return;

    FocusManager.instance.primaryFocus?.unfocus();
    await _dismissController.forward();
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _showTabContextMenu(Offset globalPosition, int index) async {
    if (!mounted) return;

    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodyMedium;

    final selected = await showMenu<_TabMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      color: colorScheme.surface,
      elevation: 4,
      shadowColor: colorScheme.shadow.withOpacity(0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.primary.withOpacity(0.18),
          width: 1,
        ),
      ),
      items: [
        PopupMenuItem(
          value: _TabMenuAction.closeAll,
          child: Row(
            children: [
              Icon(
                Icons.tab_unselected,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Text('Close all tabs', style: textStyle),
            ],
          ),
        ),
        PopupMenuItem(
          value: _TabMenuAction.closeRight,
          child: Row(
            children: [
              Icon(
                Icons.keyboard_double_arrow_right,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Text('Close tabs to the right', style: textStyle),
            ],
          ),
        ),
        PopupMenuItem(
          value: _TabMenuAction.closeOthers,
          child: Row(
            children: [
              Icon(
                Icons.filter_none,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Text('Close other tabs', style: textStyle),
            ],
          ),
        ),
      ],
    );

    if (selected == null) return;

    switch (selected) {
      case _TabMenuAction.closeAll:
        _tabService.clearAllTabs();
        break;
      case _TabMenuAction.closeRight:
        _tabService.closeTabsToRight(index);
        break;
      case _TabMenuAction.closeOthers:
        _tabService.closeOtherTabs(index);
        break;
    }
  }

  Widget _buildTabBar(
    List<EntryTabItem> tabs,
    int activeIndex, {
    bool compact = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final surfaceColor = colorScheme.surface;
    final barHeight = compact ? 34.0 : 36.0;
    final horizontalMargin = compact ? 10.0 : 12.0;
    final verticalMargin = compact ? 4.0 : 6.0;

    return Container(
      margin: EdgeInsets.fromLTRB(
        horizontalMargin,
        compact ? 6 : 8,
        horizontalMargin,
        verticalMargin,
      ),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            surfaceColor.withOpacity(0.96),
            colorScheme.primaryContainer.withOpacity(0.36),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        // boxShadow: [
        //   BoxShadow(
        //     color: colorScheme.shadow.withOpacity(0.06),
        //     blurRadius: 10,
        //     offset: const Offset(0, 2),
        //   ),
        // ],
      ),
      child: SizedBox(
        height: barHeight,
        child: ReorderableListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 1),
          buildDefaultDragHandles: false,
          proxyDecorator: (child, index, animation) {
            // 保持拖拽前外形：不加阴影、不加额外背景填充。
            return child;
          },
          onReorder: (oldIndex, newIndex) {
            _tabService.moveTab(oldIndex, newIndex);
          },
          itemCount: tabs.length,
          itemBuilder: (context, index) {
            final tab = tabs[index];
            final isActive = index == activeIndex;
            final isWordBankTab =
                tab.browseList?.source == BrowseListSource.wordBank;
            final activeBg = colorScheme.primaryContainer.withOpacity(0.96);
            final activeFg = colorScheme.onPrimaryContainer;
            final activeBorder = colorScheme.primary.withOpacity(0.95);
            final tabRadius = BorderRadius.circular(isWordBankTab ? 999 : 9);
            final horizontalPadding = isWordBankTab
                ? (compact ? 12.0 : 14.0)
                : (compact ? 10.0 : 12.0);

            return ReorderableDragStartListener(
              key: ValueKey(tab.id),
              index: index,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  margin: const EdgeInsets.only(right: 4),
                  child: GestureDetector(
                    onSecondaryTapDown: (details) {
                      _showTabContextMenu(details.globalPosition, index);
                    },
                    onLongPressStart: (details) {
                      _showTabContextMenu(details.globalPosition, index);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        color: isActive
                            ? activeBg
                            : colorScheme.secondaryContainer.withOpacity(0.42),
                        borderRadius: tabRadius,
                        border: Border.all(
                          color: isActive
                              ? activeBorder
                              : colorScheme.outline.withOpacity(0.35),
                          width: isActive ? 1.3 : 1.0,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: tabRadius,
                          canRequestFocus: false,
                          onTap: () {
                            _tabService.setActiveIndex(
                              index,
                              directionHint: index > activeIndex ? 1 : -1,
                            );
                          },
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: horizontalPadding,
                              right: 5,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: compact ? 140 : 170,
                                  ),
                                  child: Text(
                                    tab.word,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: compact ? 12.5 : 13.5,
                                      fontWeight: isActive
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: isActive
                                          ? activeFg
                                          : colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 3),
                                InkWell(
                                  borderRadius: BorderRadius.circular(999),
                                  canRequestFocus: false,
                                  onTap: () => _tabService.closeAt(index),
                                  child: Padding(
                                    padding: const EdgeInsets.all(3),
                                    child: Icon(
                                      Icons.close,
                                      size: compact ? 12 : 13,
                                      color: isActive
                                          ? activeFg
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAnimatedEntryContent(EntryTabItem activeTab) {
    final switchDirection = _tabService.lastSwitchDirection;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) {
        final beginOffset = switchDirection < 0
            ? const Offset(-0.16, 0)
            : const Offset(0.16, 0);
        final slide = Tween<Offset>(
          begin: beginOffset,
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(activeTab.id),
        child: EntryDetailPage(
          key: ValueKey('detail_${activeTab.id}'),
          entryGroup: activeTab.entryGroup,
          initialWord: activeTab.word,
          dictResults: activeTab.dictResults,
          browseList: activeTab.browseList,
          bottomToolbarAboveWidget:
              (Theme.of(context).platform == TargetPlatform.android ||
                      Theme.of(context).platform == TargetPlatform.iOS) &&
                  _tabService.tabs.length > 1
              ? _buildTabBar(
                  _tabService.tabs,
                  _tabService.activeIndex,
                  compact: true,
                )
              : null,
          onBrowseWordRequested: ({required word, required insertToLeft}) {
            return _handleBrowseNavigate(word, insertToLeft: insertToLeft);
          },
          onOpenEntryRequested:
              ({
                required entryGroup,
                required initialWord,
                dictResults,
                browseList,
                insertToLeft = false,
                preferExisting = true,
              }) {
                return _handleOpenEntryRequested(
                  entryGroup: entryGroup,
                  initialWord: initialWord,
                  dictResults: dictResults,
                  browseList: browseList,
                  insertToLeft: insertToLeft,
                  preferExisting: preferExisting,
                );
              },
          onHomeRequested: _dismissToHome,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabService.tabs;
    if (tabs.isEmpty) {
      return const SizedBox.shrink();
    }

    final activeTab = _tabService.activeTab ?? tabs.first;
    final isPhone =
        Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;
    final body = Column(
      children: [
        if (!isPhone && tabs.length > 1)
          _buildTabBar(tabs, _tabService.activeIndex),
        Expanded(child: _buildAnimatedEntryContent(activeTab)),
      ],
    );

    return AnimatedBuilder(
      animation: _dismissController,
      builder: (context, child) {
        final t = Curves.easeInOutCubic.transform(_dismissController.value);
        return Transform.translate(
          offset: Offset(0, -60 * t),
          child: Transform.scale(
            scale: 1 - 0.12 * t,
            alignment: Alignment.center,
            child: Opacity(opacity: 1 - t, child: child),
          ),
        );
      },
      child: Scaffold(body: SafeArea(top: false, bottom: false, child: body)),
    );
  }
}
