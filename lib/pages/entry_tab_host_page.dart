import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../data/database_service.dart';
import '../data/models/dictionary_entry_group.dart';
import '../models/browse_list.dart';
import '../services/entry_tab_service.dart';
import '../services/entry_tab_visibility_service.dart';
import '../services/search_history_service.dart';
import '../i18n/strings.g.dart';
import 'entry_detail_page.dart';

enum _TabMenuAction { closeAll, closeWordBankAll, closeRight, closeOthers }

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
    final isWordBankBrowse = browseList?.source == BrowseListSource.wordBank;
    if (!isWordBankBrowse) {
      SearchHistoryService().addSearchRecord(initialWord);
    }

    EntryTabService().openOrActivateTab(
      word: initialWord,
      entryGroup: entryGroup,
      dictResults: dictResults,
      browseList: browseList,
      preferExisting: preferExisting,
      insertToLeft: insertToLeft,
    );

    final visibilityService = EntryTabVisibilityService();
    visibilityService.show();

    // 第二阶段：主界面常驻宿主页后，打开详情仅切换可见性，不再 push 新路由。
    if (visibilityService.persistentMode) {
      return Future.value(null);
    }

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

  static Future<String> openLoading(
    BuildContext context, {
    required String word,
    BrowseList? browseList,
    bool preferExisting = true,
    bool insertToLeft = false,
  }) async {
    final isWordBankBrowse = browseList?.source == BrowseListSource.wordBank;
    if (!isWordBankBrowse) {
      SearchHistoryService().addSearchRecord(word);
    }

    final tabId = EntryTabService().openLoadingTab(
      word: word,
      browseList: browseList,
      preferExisting: preferExisting,
      insertToLeft: insertToLeft,
    );

    final visibilityService = EntryTabVisibilityService();
    visibilityService.show();

    if (!visibilityService.persistentMode &&
        context.findAncestorWidgetOfExactType<EntryTabHostPage>() == null) {
      unawaited(
        Navigator.of(context).push<void>(
          PageRouteBuilder<void>(
            opaque: false,
            barrierColor: Colors.transparent,
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (context, animation, secondaryAnimation) =>
                const EntryTabHostPage(),
          ),
        ),
      );
    }

    return tabId;
  }

  @override
  State<EntryTabHostPage> createState() => _EntryTabHostPageState();
}

class _EntryTabHostPageState extends State<EntryTabHostPage>
    with SingleTickerProviderStateMixin {
  final EntryTabService _tabService = EntryTabService();
  final EntryTabVisibilityService _visibilityService =
      EntryTabVisibilityService();
  final DatabaseService _dbService = DatabaseService();
  final ScrollController _tabScrollController = ScrollController();
  final Map<String, GlobalKey> _tabItemKeys = {};
  final FocusNode _hostKeyboardFocusNode = FocusNode(
    debugLabel: 'EntryTabHostKeyboardFocus',
  );

  late final AnimationController _dismissController;

  bool _shouldSkipDismissAnimation() {
    final isPhone =
        Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;
    if (!isPhone) return false;
    // 标签较多时，直接返回可显著降低整页变换导致的掉帧。
    return _tabService.tabs.length >= 3;
  }

  @override
  void initState() {
    super.initState();
    _dismissController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _tabService.addListener(_onTabsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestHostKeyboardFocus();
    });
  }

  @override
  void dispose() {
    _tabService.removeListener(_onTabsChanged);
    _dismissController.dispose();
    _tabScrollController.dispose();
    _hostKeyboardFocusNode.dispose();
    super.dispose();
  }

  bool _isPrimaryFocusOnEditableText() {
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null) return false;
    if ((focusedContext as Element).widget is EditableText) {
      return true;
    }

    var foundEditable = false;
    focusedContext.visitAncestorElements((ancestor) {
      if (ancestor.widget is EditableText) {
        foundEditable = true;
        return false;
      }
      return true;
    });
    return foundEditable;
  }

  void _requestHostKeyboardFocus() {
    if (!mounted) return;
    final isPhone =
        Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;
    if (isPhone) return;
    if (_isPrimaryFocusOnEditableText()) return;
    if (!_hostKeyboardFocusNode.hasFocus) {
      _hostKeyboardFocusNode.requestFocus();
    }
  }

  KeyEventResult _handleHostKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape && event is KeyDownEvent) {
      _dismissToHome();
      return KeyEventResult.handled;
    }

    final isArrowKey =
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
    final isArrowPressEvent =
        isArrowKey && (event is KeyDownEvent || event is KeyRepeatEvent);
    if (!isArrowPressEvent) {
      return KeyEventResult.ignored;
    }
    if (_isPrimaryFocusOnEditableText()) return KeyEventResult.ignored;

    final toLeft = key == LogicalKeyboardKey.arrowLeft;
    if (_tryHandleBrowseKeyAtHost(toLeft: toLeft)) {
      return KeyEventResult.handled;
    }

    _switchToAdjacentTab(toLeft: toLeft);
    return KeyEventResult.handled;
  }

  bool _tryHandleBrowseKeyAtHost({required bool toLeft}) {
    // 优先保持与 EntryDetailPage 的 browse 语义一致：
    // - searchHistory: 左右键按相邻标签切换
    // - wordBank: 左右键按单词列表前后词导航（边界无操作）
    final activeTab = _tabService.activeTab;
    final browseList = activeTab?.browseList;
    if (activeTab == null || browseList == null || browseList.words.isEmpty) {
      return false;
    }

    if (browseList.source == BrowseListSource.searchHistory) {
      _handleBrowseNavigate(activeTab.word, insertToLeft: toLeft);
      return true;
    }

    final currentIndex = browseList.words.indexWhere(
      (w) => w.trim().toLowerCase() == activeTab.word.trim().toLowerCase(),
    );
    if (currentIndex < 0) return false;

    if (toLeft && currentIndex > 0) {
      _handleBrowseNavigate(
        browseList.words[currentIndex - 1],
        insertToLeft: true,
      );
      return true;
    }
    if (!toLeft && currentIndex < browseList.words.length - 1) {
      _handleBrowseNavigate(
        browseList.words[currentIndex + 1],
        insertToLeft: false,
      );
      return true;
    }

    // 在 browseList 边界时吸收事件，和词条页行为保持一致（无操作）。
    return true;
  }

  void _switchToAdjacentTab({required bool toLeft}) {
    final tabs = _tabService.tabs;
    if (tabs.length <= 1) return;

    final current = _tabService.activeIndex.clamp(0, tabs.length - 1);
    final next = toLeft ? current - 1 : current + 1;
    if (next < 0 || next >= tabs.length) return;

    _tabService.setActiveIndex(next, directionHint: toLeft ? -1 : 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestHostKeyboardFocus();
    });
  }

  GlobalKey _tabKeyOf(String tabId) {
    return _tabItemKeys.putIfAbsent(tabId, () => GlobalKey());
  }

  void _syncTabKeysWithCurrentTabs() {
    final currentIds = _tabService.tabs.map((tab) => tab.id).toSet();
    _tabItemKeys.removeWhere((id, _) => !currentIds.contains(id));
  }

  void _ensureActiveTabVisible() {
    if (!mounted) return;
    if (!_tabScrollController.hasClients) return;
    final tabs = _tabService.tabs;
    if (tabs.isEmpty) return;

    final activeIndex = _tabService.activeIndex.clamp(0, tabs.length - 1);
    final activeTabId = tabs[activeIndex].id;
    final tabKey = _tabItemKeys[activeTabId];
    final tabContext = tabKey?.currentContext;
    if (tabContext == null) return;

    final tabRenderObject = tabContext.findRenderObject();
    if (tabRenderObject is! RenderBox) return;

    final scrollableState = Scrollable.of(tabContext);
    final viewportRenderObject = scrollableState.context.findRenderObject();
    if (viewportRenderObject is! RenderBox) return;

    final tabTopLeftInViewport = tabRenderObject.localToGlobal(
      Offset.zero,
      ancestor: viewportRenderObject,
    );
    final tabLeft = tabTopLeftInViewport.dx;
    final tabRight = tabLeft + tabRenderObject.size.width;
    final viewportWidth = viewportRenderObject.size.width;

    const edgePadding = 12.0;
    final minVisibleLeft = edgePadding;
    final maxVisibleRight = viewportWidth - edgePadding;

    double targetOffset = _tabScrollController.offset;
    if (tabLeft < minVisibleLeft) {
      targetOffset += tabLeft - minVisibleLeft;
    } else if (tabRight > maxVisibleRight) {
      targetOffset += tabRight - maxVisibleRight;
    } else {
      return;
    }

    final minOffset = _tabScrollController.position.minScrollExtent;
    final maxOffset = _tabScrollController.position.maxScrollExtent;
    targetOffset = targetOffset.clamp(minOffset, maxOffset);

    if ((targetOffset - _tabScrollController.offset).abs() < 0.5) return;

    _tabScrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _onTabsChanged() {
    if (!mounted) return;
    if (_tabService.tabs.isEmpty) {
      if (_visibilityService.persistentMode) {
        _visibilityService.hide();
      } else {
        Navigator.of(context).maybePop();
      }
      return;
    }

    _syncTabKeysWithCurrentTabs();

    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureActiveTabVisible();
      _requestHostKeyboardFocus();
    });
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

      if (wordBankIndices.length <= 1) return;

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
      _navigateSearchHistoryTab(insertToLeft: insertToLeft);
      return;
    }

    await _navigateWordBankTab(
      word: word,
      sourceBrowseList: sourceBrowseList,
      insertToLeft: insertToLeft,
    );
  }

  void _navigateSearchHistoryTab({required bool insertToLeft}) {
    final nextIndex = insertToLeft
        ? _tabService.activeIndex - 1
        : _tabService.activeIndex + 1;
    if (nextIndex < 0 || nextIndex >= _tabService.tabs.length) return;

    _tabService.setActiveIndex(nextIndex, directionHint: insertToLeft ? -1 : 1);
  }

  Future<void> _navigateWordBankTab({
    required String word,
    required BrowseList sourceBrowseList,
    required bool insertToLeft,
  }) async {
    // 单词本：若目标方向已有标签，则仅做普通标签切换；
    // 若该方向没有标签，再按单词本 browseList 扩展一个新词，并关闭另一端最远标签保持 1 个。
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
    if (_visibilityService.persistentMode) {
      FocusManager.instance.primaryFocus?.unfocus();
      _dismissController.stop();
      _dismissController.value = 0;
      _visibilityService.hide();
      return;
    }

    if (_dismissController.isAnimating || _dismissController.value > 0) return;

    FocusManager.instance.primaryFocus?.unfocus();
    if (_shouldSkipDismissAnimation()) {
      if (!mounted) return;
      Navigator.of(context).maybePop();
      return;
    }
    await _dismissController.forward();
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  void _showTabContextMenu(Offset globalPosition, int index) {
    if (!mounted) return;

    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodyMedium;

    showMenu<_TabMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      color: colorScheme.surface,
      elevation: 0,
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
              Text(context.t.entry.tabMenuCloseAll, style: textStyle),
            ],
          ),
        ),
        PopupMenuItem(
          value: _TabMenuAction.closeWordBankAll,
          child: Row(
            children: [
              Icon(
                Icons.style_outlined,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Text(context.t.entry.tabMenuCloseWordBankAll, style: textStyle),
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
              Text(context.t.entry.tabMenuCloseRight, style: textStyle),
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
              Text(context.t.entry.tabMenuCloseOthers, style: textStyle),
            ],
          ),
        ),
      ],
    ).then((selected) {
      if (!mounted || selected == null) return;

      switch (selected) {
        case _TabMenuAction.closeAll:
          _tabService.clearAllTabs();
          break;
        case _TabMenuAction.closeWordBankAll:
          for (int i = _tabService.tabs.length - 1; i >= 0; i--) {
            if (_tabService.tabs[i].browseList?.source ==
                BrowseListSource.wordBank) {
              _tabService.closeAt(i);
            }
          }
          break;
        case _TabMenuAction.closeRight:
          _tabService.closeTabsToRight(index);
          break;
        case _TabMenuAction.closeOthers:
          _tabService.closeOtherTabs(index);
          break;
      }
    });
  }

  Widget _buildTabBar(
    List<EntryTabItem> tabs,
    int activeIndex, {
    bool compact = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final surfaceColor = colorScheme.surface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tabBarOpacity = isDark ? 0.65 : 0.8;
    final barHeight = compact ? 34.0 : 36.0;
    final horizontalMargin = compact ? 10.0 : 12.0;

    Widget buildTabItem(int index, {required bool enableReorder}) {
      final tab = tabs[index];
      final tabKey = _tabKeyOf(tab.id);
      final isActive = index == activeIndex;
      final isWordBankTab = tab.browseList?.source == BrowseListSource.wordBank;
      final prevIsInactive = index > 0 && (index - 1) != activeIndex;
      final showLeadingSeparator = !isActive && prevIsInactive;

      // 生词本标签使用不同的颜色
      final activeBg = isWordBankTab
          ? colorScheme.tertiaryContainer.withOpacity(0.6)
          : colorScheme.primaryContainer.withOpacity(0.5);
      final activeFg = isWordBankTab
          ? colorScheme.onTertiaryContainer
          : colorScheme.onPrimaryContainer;
      final activeIndicatorColor = isWordBankTab
          ? colorScheme.tertiary.withOpacity(0.7)
          : colorScheme.primary.withOpacity(0.6);
      final separatorColor = colorScheme.outline.withOpacity(0.48);

      // 活跃标签样式：手机端和普通标签一致使用四角圆角；桌面端保留上方圆角。
      final tabRadius = isActive
          ? (compact
                ? BorderRadius.circular(9)
                : const BorderRadius.only(
                    topLeft: Radius.circular(9),
                    topRight: Radius.circular(9),
                  ))
          : BorderRadius.circular(9);
      final horizontalPadding = compact ? 10.0 : 12.0;

      Widget tabContent = SizedBox(
        height: barHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showLeadingSeparator)
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 1,
                  height: compact ? 16 : 18,
                  color: separatorColor,
                ),
              ),
            GestureDetector(
              onSecondaryTapDown: (details) {
                _showTabContextMenu(details.globalPosition, index);
              },
              // 只在移动端使用长按打开菜单，桌面端保留长按用于拖拽排序
              onLongPressStart: compact
                  ? (details) {
                      _showTabContextMenu(details.globalPosition, index);
                    }
                  : null,
              child: Container(
                decoration: BoxDecoration(
                  color: isActive ? activeBg : Colors.transparent,
                  borderRadius: tabRadius,
                  // 活跃标签：仅桌面端显示底部指示线；手机端不显示顶部线。
                  border: isActive
                      ? (compact
                            ? null
                            : Border(
                                bottom: BorderSide(
                                  color: activeIndicatorColor,
                                  width: 2.5,
                                ),
                              ))
                      : null,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    mouseCursor: SystemMouseCursors.click,
                    borderRadius: tabRadius,
                    canRequestFocus: false,
                    onTap: () {
                      HapticFeedback.vibrate();
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
                            mouseCursor: SystemMouseCursors.click,
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
          ],
        ),
      );

      // 桌面端使用 ReorderableDragStartListener 启用拖拽排序
      if (enableReorder) {
        return ReorderableDragStartListener(
          key: tabKey,
          index: index,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: tabContent,
          ),
        );
      }

      return MouseRegion(
        key: tabKey,
        cursor: SystemMouseCursors.click,
        child: tabContent,
      );
    }

    // 桌面端使用 ReorderableListView 支持拖拽排序
    if (!compact) {
      Widget tabBarContent = Container(
        padding: EdgeInsets.symmetric(horizontal: horizontalMargin),
        decoration: BoxDecoration(
          color: surfaceColor.withOpacity(tabBarOpacity),
          borderRadius: BorderRadius.circular(12),
        ),
        child: SizedBox(
          height: barHeight,
          child: Row(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.stylus,
                          PointerDeviceKind.invertedStylus,
                          PointerDeviceKind.unknown,
                        },
                      ),
                      child: ReorderableListView.builder(
                        scrollController: _tabScrollController,
                        scrollDirection: Axis.horizontal,
                        buildDefaultDragHandles: false,
                        itemCount: tabs.length,
                        onReorder: (oldIndex, newIndex) {
                          _tabService.moveTab(oldIndex, newIndex);
                        },
                        proxyDecorator: (child, index, animation) {
                          return AnimatedBuilder(
                            animation: animation,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: 1.05,
                                child: Opacity(opacity: 0.9, child: child),
                              );
                            },
                            child: child,
                          );
                        },
                        itemBuilder: (context, index) {
                          return buildTabItem(index, enableReorder: true);
                        },
                      ),
                    );
                  },
                ),
              ),
              Tooltip(
                message: context.t.entry.tabMenuCloseAll,
                child: InkWell(
                  mouseCursor: SystemMouseCursors.click,
                  borderRadius: BorderRadius.circular(8),
                  onTap: _tabService.clearAllTabs,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.highlight_off,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      return Container(
        margin: EdgeInsets.only(top: compact ? 0 : 4),
        child: tabBarContent,
      );
    }

    // 移动端使用普通的 SingleChildScrollView（不支持拖拽排序）
    Widget tabBarContent = Container(
      padding: EdgeInsets.symmetric(horizontal: horizontalMargin),
      decoration: BoxDecoration(
        color: surfaceColor.withOpacity(tabBarOpacity),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SizedBox(
        height: barHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.stylus,
                  PointerDeviceKind.invertedStylus,
                  PointerDeviceKind.unknown,
                },
              ),
              child: SingleChildScrollView(
                controller: _tabScrollController,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: List.generate(
                      tabs.length,
                      (index) => buildTabItem(index, enableReorder: false),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    return Container(
      margin: EdgeInsets.only(top: compact ? 2 : 4),
      child: tabBarContent,
    );
  }

  Widget _buildDetailPage(EntryTabItem tab) {
    if (tab.isLoading) {
      return _LoadingEntryPage(word: tab.word, onHomeRequested: _dismissToHome);
    }

    return EntryDetailPage(
      key: ValueKey('${tab.id}_${tab.revision}'),
      entryGroup: tab.entryGroup,
      initialWord: tab.word,
      dictResults: tab.dictResults,
      browseList: tab.browseList,
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
    );
  }

  Widget _buildEntryContentStack(List<EntryTabItem> tabs) {
    return IndexedStack(
      index: _tabService.activeIndex.clamp(0, tabs.length - 1),
      children: tabs
          .map((tab) => _buildDetailPage(tab))
          .toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabService.tabs;
    if (tabs.isEmpty) {
      return const SizedBox.shrink();
    }

    final isPhone =
        Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;
    final horizontalMargin = isPhone ? 10.0 : 12.0;
    final activeTab = _tabService.activeTab;
    final hideTabBarOnPhone = isPhone && (activeTab?.isLoading ?? false);

    // 手机端：标签栏悬浮在底部工具栏上方；桌面端：标签栏放在顶部
    final tabBar = tabs.length > 1 && !hideTabBarOnPhone
        ? _buildTabBar(tabs, _tabService.activeIndex, compact: isPhone)
        : null;

    Widget body;
    if (isPhone && tabBar != null) {
      // 手机端：使用 Stack 让标签栏悬浮在底部工具栏上方
      // 底部工具栏高度约 50-55px + 16px bottom padding = 约 70px
      const bottomToolbarHeight = 70.0;
      body = Stack(
        children: [
          _buildEntryContentStack(tabs),
          // 标签栏悬浮在底部工具栏上方，居中且占满宽度
          Positioned(
            left: horizontalMargin,
            right: horizontalMargin,
            bottom: bottomToolbarHeight,
            child: tabBar,
          ),
        ],
      );
    } else {
      // 桌面端：标签栏在顶部
      body = Column(
        children: [
          ?tabBar,
          Expanded(child: _buildEntryContentStack(tabs)),
        ],
      );
    }

    Widget mainContent = Focus(
      focusNode: _hostKeyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleHostKeyEvent,
      child: Listener(
        onPointerDown: (_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _requestHostKeyboardFocus();
          });
        },
        child: Scaffold(body: SafeArea(top: false, bottom: false, child: body)),
      ),
    );

    // 手机端：非常驻模式下返回时先关闭当前标签页（单标签也适用）。
    // 常驻模式由 MainScreen 统一处理返回，避免双重处理导致直接回主页。
    if (isPhone && !_visibilityService.persistentMode) {
      mainContent = PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          // 关闭当前活跃的标签页
          _tabService.closeAt(_tabService.activeIndex);
        },
        child: mainContent,
      );
    }

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
      child: mainContent,
    );
  }
}

class _LoadingEntryPage extends StatelessWidget {
  final String word;
  final VoidCallback onHomeRequested;

  const _LoadingEntryPage({required this.word, required this.onHomeRequested});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.6),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '正在打开 "$word" ...',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: IconButton(
                tooltip: context.t.common.back,
                onPressed: onHomeRequested,
                icon: const Icon(Icons.arrow_back),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
