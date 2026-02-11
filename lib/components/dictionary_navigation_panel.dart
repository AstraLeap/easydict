import 'package:flutter/material.dart';
import '../models/dictionary_entry_group.dart';
import '../database_service.dart';
import 'dictionary_logo.dart';

class DictionaryNavigationPanel extends StatefulWidget {
  final DictionaryEntryGroup entryGroup;
  final VoidCallback? onDictionaryChanged;
  final VoidCallback? onPageChanged;
  final VoidCallback? onSectionChanged;
  final Function(DictionaryEntry entry)? onNavigateToEntry;
  final bool isRight; // 新增：导航栏是否在右侧

  const DictionaryNavigationPanel({
    super.key,
    required this.entryGroup,
    this.onDictionaryChanged,
    this.onPageChanged,
    this.onSectionChanged,
    this.onNavigateToEntry,
    this.isRight = true, // 默认为右侧
  });

  @override
  State<DictionaryNavigationPanel> createState() =>
      _DictionaryNavigationPanelState();
}

class _DictionaryNavigationPanelState extends State<DictionaryNavigationPanel> {
  final ScrollController _mainScrollController = ScrollController();
  bool _isPageListExpanded = false;
  final GlobalKey _navPanelKey = GlobalKey();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _removeOverlay();
    _mainScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(DictionaryNavigationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当导航栏位置改变时，如果 page 列表已展开，则更新其位置
    if (oldWidget.isRight != widget.isRight && _isPageListExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isPageListExpanded) {
          _removeOverlay();
          final currentDict = widget.entryGroup.currentDictionaryGroup;
          _overlayEntry = _createOverlayEntry(currentDict);
          Overlay.of(context).insert(_overlayEntry!);
        }
      });
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _togglePageList() {
    if (_isPageListExpanded) {
      _removeOverlay();
      setState(() {
        _isPageListExpanded = false;
      });
    } else {
      final currentDict = widget.entryGroup.currentDictionaryGroup;
      _overlayEntry = _createOverlayEntry(currentDict);
      Overlay.of(context).insert(_overlayEntry!);
      setState(() {
        _isPageListExpanded = true;
      });
    }
  }

  OverlayEntry _createOverlayEntry(DictionaryGroup dict) {
    // 如果导航栏在右侧，列表向左展开；如果在左侧，列表向右展开
    final offset = widget.isRight
        ? const Offset(-108, 0) // 向左偏移 (100宽度 + 8间距)
        : const Offset(52, 0); // 向右偏移 (52宽度)

    return OverlayEntry(
      builder: (context) => Positioned(
        width: 100,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: offset,
          child: _buildPageList(context, dict),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildMainNavigation(context);
  }

  // 计算当前词典logo在导航栏中的偏移量
  double _calculateCurrentDictLogoOffset() {
    final allDicts = widget.entryGroup.dictionaryGroups;
    final currentDictIndex = widget.entryGroup.currentDictionaryIndex;

    double offset = 0;
    // logo高度36 + margin 4 (上下各2)
    const double itemHeight = 40;

    // 计算当前词典logo之前的所有items高度
    for (int i = 0; i < currentDictIndex; i++) {
      final dict = allDicts[i];
      if (dict.pageGroups.isNotEmpty) {
        offset += itemHeight; // logo
        // 使用当前显示的page的sections（对于非当前词典，使用第一个page）
        final pageIndex = dict.currentPageIndex;
        int sectionCount = 0;
        if (pageIndex < dict.pageGroups.length) {
          sectionCount = dict.pageGroups[pageIndex].sections.length;
        } else {
          sectionCount = dict.pageGroups[0].sections.length;
        }

        if (sectionCount > 1) {
          offset += sectionCount * itemHeight;
        }
      }
    }
    // 当前词典的logo
    offset += itemHeight;

    return offset - itemHeight; // 返回logo顶部位置
  }

  // 主导航栏 - 包含词典logo（可展开page列表）和section列表
  Widget _buildMainNavigation(BuildContext context) {
    final allDicts = widget.entryGroup.dictionaryGroups;
    final currentDict = widget.entryGroup.currentDictionaryGroup;
    final currentDictIndex = widget.entryGroup.currentDictionaryIndex;
    final currentPageIndex = currentDict.currentPageIndex;

    final List<Widget> mixedItems = [];

    // 添加上方词典
    for (int i = 0; i < currentDictIndex; i++) {
      final dict = allDicts[i];
      if (dict.pageGroups.isNotEmpty) {
        mixedItems.add(_buildDictionaryLogo(context, dict, false));

        // 使用该词典当前选中的page
        final pageIndex = dict.currentPageIndex < dict.pageGroups.length
            ? dict.currentPageIndex
            : 0;
        final targetPage = dict.pageGroups[pageIndex];
        for (int j = 0; j < targetPage.sections.length; j++) {
          final section = targetPage.sections[j];
          mixedItems.add(
            _buildSectionItem(context, section, false, j, dict.dictionaryId),
          );
        }
      }
    }

    // 添加当前词典
    if (currentDict.pageGroups.isNotEmpty) {
      mixedItems.add(_buildDictionaryLogo(context, currentDict, true));

      // 添加当前page的sections
      if (currentPageIndex < currentDict.pageGroups.length) {
        final currentPage = currentDict.pageGroups[currentPageIndex];
        if (currentPage.sections.length > 1) {
          for (int i = 0; i < currentPage.sections.length; i++) {
            final section = currentPage.sections[i];
            final isSelected = i == currentDict.currentSectionIndex;
            mixedItems.add(
              _buildSectionItem(
                context,
                section,
                isSelected,
                i,
                currentDict.dictionaryId,
              ),
            );
          }
        }
      }
    }

    // 添加下方词典
    for (int i = currentDictIndex + 1; i < allDicts.length; i++) {
      final dict = allDicts[i];
      if (dict.pageGroups.isNotEmpty) {
        mixedItems.add(_buildDictionaryLogo(context, dict, false));

        // 使用该词典当前选中的page
        final pageIndex = dict.currentPageIndex < dict.pageGroups.length
            ? dict.currentPageIndex
            : 0;
        final targetPage = dict.pageGroups[pageIndex];
        if (targetPage.sections.length > 1) {
          for (int j = 0; j < targetPage.sections.length; j++) {
            final section = targetPage.sections[j];
            mixedItems.add(
              _buildSectionItem(context, section, false, j, dict.dictionaryId),
            );
          }
        }
      }
    }

    // 构建主导航栏
    return Container(
      key: _navPanelKey,
      width: 52,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView(
          controller: _mainScrollController,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: mixedItems,
        ),
      ),
    );
  }

  // 构建词典logo（方形无边框，所有词典都显示）
  Widget _buildDictionaryLogo(
    BuildContext context,
    DictionaryGroup dict,
    bool isCurrent, {
    Key? key,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget logoWidget = GestureDetector(
      key: key,
      onTap: isCurrent ? _togglePageList : () => _onDictionarySelected(dict),
      child: Container(
        width: 36,
        height: 40, // 增加高度
        margin: const EdgeInsets.symmetric(
          vertical: 4,
          horizontal: 8,
        ), // 增加垂直间距
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              DictionaryLogo(
                dictionaryId: dict.dictionaryId,
                dictionaryName: dict.dictionaryName,
                size: 36,
              ),
              if (isCurrent && dict.pageGroups.length > 1)
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${dict.pageGroups.length}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimary,
                        height: 0.9,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (isCurrent) {
      return CompositedTransformTarget(link: _layerLink, child: logoWidget);
    }

    return logoWidget;
  }

  // 构建page列表（普通列表样式）
  Widget _buildPageList(BuildContext context, DictionaryGroup dict) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 100,
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(dict.pageGroups.length, (index) {
              final isSelected = index == dict.currentPageIndex;
              final page = dict.pageGroups[index];

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _onPageSelected(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    decoration: isSelected
                        ? BoxDecoration(
                            color: colorScheme.primaryContainer.withOpacity(
                              0.5,
                            ),
                            border: Border(
                              left: BorderSide(
                                color: colorScheme.primary,
                                width: 3,
                              ),
                            ),
                          )
                        : null,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            page.page.isNotEmpty ? page.page : '${index + 1}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // 构建section项（扁的圆角矩形）
  Widget _buildSectionItem(
    BuildContext context,
    DictionarySection section,
    bool isSelected,
    int index,
    String dictId,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _onSectionTapped(section, dictId),
      child: Container(
        width: 40,
        height: 32, // 增加高度
        margin: const EdgeInsets.symmetric(
          vertical: 3,
          horizontal: 6,
        ), // 增加垂直间距
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainer,
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant.withOpacity(0.5),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            section.section.isNotEmpty
                ? section.section[0].toUpperCase()
                : '${index + 1}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isSelected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  // 切换词典
  void _onDictionarySelected(DictionaryGroup dict) {
    for (int i = 0; i < widget.entryGroup.dictionaryGroups.length; i++) {
      if (widget.entryGroup.dictionaryGroups[i].dictionaryId ==
          dict.dictionaryId) {
        widget.entryGroup.setCurrentDictionaryIndex(i);
        widget.entryGroup.dictionaryGroups[i].setCurrentPageIndex(0);
        widget.entryGroup.dictionaryGroups[i].setCurrentSectionIndex(0);

        widget.onDictionaryChanged?.call();
        widget.onPageChanged?.call();
        widget.onSectionChanged?.call();

        final newDict = widget.entryGroup.dictionaryGroups[i];
        if (newDict.pageGroups.isNotEmpty &&
            newDict.pageGroups[0].sections.isNotEmpty) {
          widget.onNavigateToEntry?.call(
            newDict.pageGroups[0].sections[0].entry,
          );
        }

        _removeOverlay();
        setState(() {
          _isPageListExpanded = false;
        });
        break;
      }
    }
  }

  // 切换 page
  void _onPageSelected(int pageIndex) {
    // 1. 获取当前词典组
    final currentDict = widget.entryGroup.currentDictionaryGroup;

    // 2. 边界检查
    if (pageIndex < 0 || pageIndex >= currentDict.pageGroups.length) {
      return;
    }

    // 3. 如果点击的是当前已经选中的page，只关闭列表即可
    if (currentDict.currentPageIndex == pageIndex) {
      _removeOverlay();
      setState(() {
        _isPageListExpanded = false;
      });
      return;
    }

    // 4. 更新模型状态
    currentDict.setCurrentPageIndex(pageIndex);
    // 切换page时，默认选中第一个section
    currentDict.setCurrentSectionIndex(0);

    // 5. 关闭列表 (UI状态更新)
    _removeOverlay();
    setState(() {
      _isPageListExpanded = false;
    });

    // 6. 通知父组件 (EntryDetailPage) 进行重建和滚动
    widget.onPageChanged?.call();

    // 同时通知 section 变化，因为 section index 重置了
    widget.onSectionChanged?.call();
  }

  // section点击处理
  void _onSectionTapped(DictionarySection section, String dictId) {
    widget.onNavigateToEntry?.call(section.entry);

    for (int i = 0; i < widget.entryGroup.dictionaryGroups.length; i++) {
      if (widget.entryGroup.dictionaryGroups[i].dictionaryId == dictId) {
        widget.entryGroup.setCurrentDictionaryIndex(i);

        final dict = widget.entryGroup.dictionaryGroups[i];
        for (
          int pageIndex = 0;
          pageIndex < dict.pageGroups.length;
          pageIndex++
        ) {
          final page = dict.pageGroups[pageIndex];
          for (
            int sectionIndex = 0;
            sectionIndex < page.sections.length;
            sectionIndex++
          ) {
            if (page.sections[sectionIndex] == section) {
              dict.setCurrentPageIndex(pageIndex);
              dict.setCurrentSectionIndex(sectionIndex);

              widget.onDictionaryChanged?.call();
              widget.onPageChanged?.call();
              widget.onSectionChanged?.call();

              _removeOverlay();
              setState(() {
                _isPageListExpanded = false;
              });
              return;
            }
          }
        }
      }
    }
  }
}
