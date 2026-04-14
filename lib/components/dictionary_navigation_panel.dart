import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants/entry_keys.dart';
import '../data/models/dictionary_entry_group.dart';
import '../data/database_service.dart';
import 'dictionary_logo.dart';
import '../core/logger.dart';
import 'rendering/formatted_text_parser.dart';
import '../services/dictionary_manager.dart';
import '../core/utils/language_utils.dart';

class DictionaryNavigationPanel extends StatefulWidget {
  final DictionaryEntryGroup entryGroup;
  final VoidCallback? onDictionaryChanged;
  final VoidCallback? onPageChanged;
  final VoidCallback? onSectionChanged;
  final Function(DictionaryEntry entry, {String? targetPath})?
  onNavigateToEntry;
  final double maxHeight; // 最大高度，传入屏幕高度的 70%
  final void Function(bool isOverflow)? onOverflowChanged; // 溢出状态变化回调
  final Future<void> Function(String dictId)? onExpandDictionary; // 展开词典回调（异步）

  const DictionaryNavigationPanel({
    super.key,
    required this.entryGroup,
    this.onDictionaryChanged,
    this.onPageChanged,
    this.onSectionChanged,
    this.onNavigateToEntry,
    this.maxHeight = double.infinity,
    this.onOverflowChanged,
    this.onExpandDictionary,
  });

  @override
  DictionaryNavigationPanelState createState() =>
      DictionaryNavigationPanelState();
}

class _ArrowPainter extends CustomPainter {
  final Color color;
  final Color borderColor;

  _ArrowPainter({required this.color, required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final path = Path();
    // 绘制向右的三角形箭头
    path.moveTo(0, 0);
    path.lineTo(size.width, size.height / 2);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);

    // 绘制边框（只绘制右侧两条边）
    final borderPath = Path();
    borderPath.moveTo(0, 0);
    borderPath.lineTo(size.width, size.height / 2);
    borderPath.lineTo(0, size.height);
    canvas.drawPath(borderPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DictionaryNavigationPanelState extends State<DictionaryNavigationPanel> {
  final ScrollController _mainScrollController = ScrollController();
  bool _isPageListExpanded = false;
  bool _isDirectoryExpanded = false;
  int? _selectedSectionIndex;
  final GlobalKey _navPanelKey = GlobalKey();
  final LayerLink _layerLink = LayerLink();
  final LayerLink _directoryLayerLink = LayerLink();
  final GlobalKey _sectionButtonKey = GlobalKey(); // 用于获取选中 section 按钮的位置
  OverlayEntry? _overlayEntry;
  OverlayEntry? _directoryOverlayEntry;

  // 暴露 ScrollController 给父组件
  ScrollController get mainScrollController => _mainScrollController;

  @override
  void dispose() {
    _removeOverlay();
    _removeDirectoryOverlay();
    _mainScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(DictionaryNavigationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 导航栏固定在右侧，不需要处理位置变化

    // 如果目录列表应该是打开状态但 OverlayEntry 为 null，重新打开它
    // 这种情况发生在父组件重建时
    if (_isDirectoryExpanded && _directoryOverlayEntry == null) {
      final currentDict = widget.entryGroup.currentDictionaryGroup;
      final currentPage = currentDict.currentPageGroup;
      // 始终使用当前活跃的 section index，确保显示正确的目录
      final sectionIndex = currentDict.currentSectionIndex;

      if (sectionIndex >= 0 && sectionIndex < currentPage.sections.length) {
        // 更新 _selectedSectionIndex 为当前活跃的 section
        _selectedSectionIndex = sectionIndex;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // 再次检查状态，防止在回调执行前用户已关闭目录
          if (mounted &&
              _isDirectoryExpanded &&
              _directoryOverlayEntry == null) {
            _directoryOverlayEntry = _createDirectoryOverlayEntry(
              currentPage,
              sectionIndex,
            );
            Overlay.of(context).insert(_directoryOverlayEntry!);
          }
        });
      }
    }

    // 当导航栏位置变化时（父组件重建），延迟更新 Overlay 以重新计算遮罩位置
    // 必须使用 addPostFrameCallback 避免在 build 阶段调用 markNeedsBuild
    if (_isDirectoryExpanded && _directoryOverlayEntry != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _directoryOverlayEntry != null) {
          _directoryOverlayEntry!.markNeedsBuild();
        }
      });
    }
    if (_isPageListExpanded && _overlayEntry != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _overlayEntry != null) {
          _overlayEntry!.markNeedsBuild();
        }
      });
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _removeDirectoryOverlay() {
    _directoryOverlayEntry?.remove();
    _directoryOverlayEntry = null;
  }

  void _togglePageList() {
    // 关闭目录列表（如果打开）
    if (_isDirectoryExpanded) {
      _removeDirectoryOverlay();
      setState(() {
        _isDirectoryExpanded = false;
        _selectedSectionIndex = null;
      });
    }

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

  void _toggleDirectory(int sectionIndex) {
    // 关闭page列表（如果打开）
    if (_isPageListExpanded) {
      _removeOverlay();
      setState(() {
        _isPageListExpanded = false;
      });
    }

    if (_isDirectoryExpanded) {
      // 如果目录列表处于打开状态，关闭目录
      _removeDirectoryOverlay();
      setState(() {
        _isDirectoryExpanded = false;
        _selectedSectionIndex = null;
      });
    } else {
      // 打开目录
      _removeDirectoryOverlay();
      final currentDict = widget.entryGroup.currentDictionaryGroup;
      final currentPage = currentDict.currentPageGroup;
      _directoryOverlayEntry = _createDirectoryOverlayEntry(
        currentPage,
        sectionIndex,
      );
      Overlay.of(context).insert(_directoryOverlayEntry!);
      setState(() {
        _isDirectoryExpanded = true;
        _selectedSectionIndex = sectionIndex;
      });
    }
  }

  OverlayEntry _createOverlayEntry(DictionaryGroup dict) {
    const offset = Offset(-8, 0);
    const navBarWidth = 52.0;

    return OverlayEntry(
      builder: (context) {
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;

        // 获取导航栏的位置信息
        double navTop = 0;
        double navBottom = screenHeight;
        try {
          final renderBox =
              _navPanelKey.currentContext?.findRenderObject() as RenderBox?;
          if (renderBox != null && renderBox.hasSize) {
            final position = renderBox.localToGlobal(Offset.zero);
            navTop = position.dy;
            navBottom = navTop + renderBox.size.height;
          }
        } catch (e) {
          // 如果获取失败，使用默认值
        }

        return Stack(
          fit: StackFit.passthrough,
          clipBehavior: Clip.none,
          children: [
            // 左侧主内容区域的遮罩
            Positioned(
              left: 0,
              top: 0,
              width: screenWidth - navBarWidth,
              height: screenHeight,
              child: GestureDetector(
                onTap: _closePageList,
                onSecondaryTap: _closePageList,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),
            // 右侧导航栏上方区域的遮罩
            if (navTop > 0)
              Positioned(
                right: 0,
                top: 0,
                width: navBarWidth,
                height: navTop,
                child: GestureDetector(
                  onTap: _closePageList,
                  onSecondaryTap: _closePageList,
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox.expand(),
                ),
              ),
            // 右侧导航栏下方区域的遮罩
            if (navBottom < screenHeight)
              Positioned(
                right: 0,
                top: navBottom,
                width: navBarWidth,
                height: screenHeight - navBottom,
                child: GestureDetector(
                  onTap: _closePageList,
                  onSecondaryTap: _closePageList,
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox.expand(),
                ),
              ),
            // 页面列表
            Positioned(
              top: 0,
              left: 0,
              child: CompositedTransformFollower(
                link: _layerLink,
                showWhenUnlinked: false,
                targetAnchor: Alignment.centerLeft,
                followerAnchor: Alignment.centerRight,
                offset: offset,
                child: IntrinsicWidth(child: _buildPageList(context, dict)),
              ),
            ),
          ],
        );
      },
    );
  }

  void _closePageList() {
    if (_isPageListExpanded) {
      _removeOverlay();
      setState(() {
        _isPageListExpanded = false;
      });
    }
  }

  OverlayEntry _createDirectoryOverlayEntry(PageGroup page, int sectionIndex) {
    const navBarWidth = 52.0;
    const leftOffset = 22.0; // 目录列表左边距离导航栏右侧的距离
    const bottomMargin = 72.0; // 底部工具栏高度（与导航栏一致）

    return OverlayEntry(
      builder: (context) {
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        final topPadding = MediaQuery.of(context).padding.top; // 状态栏高度（与导航栏一致）
        final isMobile = screenWidth < 600;
        final directoryWidth = isMobile ? 260.0 : 300.0;

        // 获取导航栏的位置信息
        double navTop = 0;
        double navBottom = screenHeight;
        try {
          final renderBox =
              _navPanelKey.currentContext?.findRenderObject() as RenderBox?;
          if (renderBox != null && renderBox.hasSize) {
            final position = renderBox.localToGlobal(Offset.zero);
            navTop = position.dy;
            navBottom = navTop + renderBox.size.height;
          }
        } catch (e) {
          // 如果获取失败，使用默认值
        }

        // 获取 section 按钮的位置（用于目录列表定位）
        double sectionCenterY = screenHeight / 2;
        try {
          final renderBox =
              _sectionButtonKey.currentContext?.findRenderObject()
                  as RenderBox?;
          if (renderBox != null && renderBox.hasSize) {
            final position = renderBox.localToGlobal(Offset.zero);
            // section 按钮的垂直中心位置
            sectionCenterY = position.dy + renderBox.size.height / 2;
          }
        } catch (e) {
          // 如果获取失败，使用默认值
        }

        // 计算目录列表的水平位置
        // 目录列表右边缘距离导航栏右侧 leftOffset 像素
        final directoryLeft =
            screenWidth - navBarWidth - leftOffset - directoryWidth;

        // 计算目录列表的边界（与导航栏一致：顶部到状态栏，底部到工具栏顶部）
        final minTop = topPadding;
        final maxBottom = screenHeight - bottomMargin;

        return _DirectoryOverlayContent(
          directoryLeft: directoryLeft,
          directoryWidth: directoryWidth,
          sectionCenterY: sectionCenterY,
          minTop: minTop,
          maxBottom: maxBottom,
          navTop: navTop,
          navBottom: navBottom,
          navBarWidth: navBarWidth,
          screenWidth: screenWidth,
          screenHeight: screenHeight,
          onClose: _closeDirectory,
          bubbleChild: _buildDirectoryBubble(context, page, sectionIndex),
        );
      },
    );
  }

  void _closeDirectory() {
    if (_isDirectoryExpanded) {
      _removeDirectoryOverlay();
      setState(() {
        _isDirectoryExpanded = false;
        _selectedSectionIndex = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildMainNavigation(context);
  }

  Widget _buildMainNavigation(BuildContext context) {
    final allDicts = widget.entryGroup.dictionaryGroups;
    final currentDict = widget.entryGroup.currentDictionaryGroup;
    final currentDictIndex = widget.entryGroup.currentDictionaryIndex;
    final currentPageIndex = currentDict.currentPageIndex;

    final List<Widget> mixedItems = [];

    // 添加上方词典（只显示logo，不显示section按钮）
    for (int i = 0; i < currentDictIndex; i++) {
      final dict = allDicts[i];
      if (dict.pageGroups.isNotEmpty) {
        mixedItems.add(_buildDictionaryLogo(context, dict, false));
      }
    }

    // 添加当前词典
    if (currentDict.pageGroups.isNotEmpty) {
      mixedItems.add(_buildDictionaryLogo(context, currentDict, true));

      // 添加当前page的sections（即使只有一个section也显示）
      if (currentPageIndex < currentDict.pageGroups.length) {
        final currentPage = currentDict.pageGroups[currentPageIndex];
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

    // 添加下方词典（只显示logo，不显示section按钮）
    for (int i = currentDictIndex + 1; i < allDicts.length; i++) {
      final dict = allDicts[i];
      if (dict.pageGroups.isNotEmpty) {
        mixedItems.add(_buildDictionaryLogo(context, dict, false));
      }
    }

    // 构建主导航栏
    Widget content = SizedBox(
      key: _navPanelKey,
      width: 52,
      child: _buildFadeWrapper(
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: ListView(
            controller: _mainScrollController,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: mixedItems,
          ),
        ),
      ),
    );

    // 如果有最大高度限制，需要用 LayoutBuilder 判断是否需要限制
    if (widget.maxHeight != double.infinity) {
      content = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: content,
      );
    }

    return content;
  }

  /// 构建渐隐效果包裹层
  Widget _buildFadeWrapper({required Widget child}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 获取 ListView 的实际内容高度（通过 ScrollController）
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_mainScrollController.hasClients) {
            final contentHeight =
                _mainScrollController.position.maxScrollExtent +
                _mainScrollController.position.viewportDimension;
            final isOverflow = contentHeight > widget.maxHeight;

            // 通知父组件溢出状态
            if (widget.onOverflowChanged != null) {
              widget.onOverflowChanged!(isOverflow);
            }
          }
        });

        // 判断是否需要限制高度和渐隐
        final needsConstraint = widget.maxHeight != double.infinity;
        if (!needsConstraint) {
          return child;
        }

        // 获取内容高度
        double contentHeight = constraints.maxHeight;
        if (_mainScrollController.hasClients) {
          contentHeight =
              _mainScrollController.position.maxScrollExtent +
              _mainScrollController.position.viewportDimension;
        }

        final isOverflow = contentHeight > widget.maxHeight;

        // 如果内容未超过最大高度，不添加渐隐
        if (!isOverflow) {
          return child;
        }

        // 添加渐隐效果
        const fadeHeight = 20.0;
        final fadeRatio = (fadeHeight / widget.maxHeight).clamp(0.0, 0.15);

        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [
                Colors.transparent,
                Colors.white,
                Colors.white,
                Colors.transparent,
              ],
              stops: [0.0, fadeRatio, 1.0 - fadeRatio, 1.0],
            ).createShader(bounds);
          },
          blendMode: BlendMode.dstIn,
          child: child,
        );
      },
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

    Widget logoContent = InkWell(
      key: key,
      onTap: isCurrent
          ? (dict.pageGroups.length > 1 ? _togglePageList : null)
          : () => _onDictionarySelected(dict),
      borderRadius: BorderRadius.circular(4),
      mouseCursor: SystemMouseCursors.click,
      child: SizedBox(
        width: 36,
        height: 40,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              DictionaryLogo(
                dictionaryId: dict.dictionaryId,
                dictionaryName: dict.dictionaryName,
                size: 36,
                opacity: isCurrent ? 1.0 : 0.4,
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
      // 将 CompositedTransformTarget 包裹在内容区域，不包含 margin
      // 这样 page 列表的中心可以与 logo 内容的中心对齐
      logoContent = CompositedTransformTarget(
        link: _layerLink,
        child: logoContent,
      );
    }

    // 在外层添加 margin
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: logoContent,
    );
  }

  Widget _buildPageList(BuildContext context, DictionaryGroup dict) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
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
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(dict.pageGroups.length, (index) {
                final page = dict.pageGroups[index];
                final isSelected = index == dict.currentPageIndex;

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () => _onPageSelected(index),
                    borderRadius: BorderRadius.circular(6),
                    mouseCursor: SystemMouseCursors.click,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: isSelected
                          ? BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            )
                          : null,
                      child: Text(
                        page.page.isNotEmpty ? page.page : '${index + 1}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDirectoryBubble(
    BuildContext context,
    PageGroup page,
    int sectionIndex,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(maxHeight: 400),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _buildDirectoryItems(context, page),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDirectoryItems(BuildContext context, PageGroup page) {
    final colorScheme = Theme.of(context).colorScheme;
    final List<Widget> items = [];

    // 获取当前选中的 section 的 entry
    final currentSectionIndex =
        widget.entryGroup.currentDictionaryGroup.currentSectionIndex;
    if (currentSectionIndex >= page.sections.length) return items;

    final section = page.sections[currentSectionIndex];
    final entry = section.entry;

    // 1. 添加释义相关条目 (sense_group/sense)
    // 遍历 sense_group
    for (int i = 0; i < entry.senseGroup.length; i++) {
      final group = entry.senseGroup[i];
      final groupName = group['group_name'] as String? ?? '';
      if (groupName.isNotEmpty) {
        items.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: RichText(
              text: TextSpan(
                children: parseFormattedText(
                  groupName,
                  TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ).spans,
              ),
            ),
          ),
        );
      }

      // 遍历该组下的 sense
      final senses = group['sense'] as List<dynamic>? ?? [];
      for (int j = 0; j < senses.length; j++) {
        final sense = senses[j] as Map<String, dynamic>;
        // 构建路径：sense_group.[i].sense.[j]
        final path = 'sense_group.$i.sense.$j';
        _addSenseItem(
          context,
          items,
          sense,
          j + 1,
          colorScheme,
          section,
          path,
          currentSectionIndex,
          true,
        );
      }
    }

    // 如果没有 sense_group，直接显示 sense
    if (entry.senseGroup.isEmpty && entry.sense.isNotEmpty) {
      for (int i = 0; i < entry.sense.length; i++) {
        final sense = entry.sense[i];
        final path = 'sense.$i';
        _addSenseItem(
          context,
          items,
          sense,
          i + 1,
          colorScheme,
          section,
          path,
          currentSectionIndex,
          true,
        );
      }
    }

    // 2. 添加 phrases 章节（只显示标题，可点击跳转）
    if (entry.phrase.isNotEmpty) {
      items.add(
        InkWell(
          onTap: () {
            _onSectionTapped(
              section,
              section.entry.dictId ?? '',
              currentSectionIndex,
              true,
              targetPath: 'phrase',
            );
          },
          mouseCursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.format_quote, size: 16, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Phrases',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 3. 添加 child_xxxx 章节到目录
    final entryJson = entry.toJson();

    for (final jsonEntry in entryJson.entries) {
      final key = jsonEntry.key;
      final value = jsonEntry.value;

      // 跳过已渲染的key
      if (kExcludedEntryKeys.contains(key)) continue;
      // 跳过null值
      if (value == null) continue;
      // 跳过空列表
      if (value is List && value.isEmpty) continue;
      // 跳过空map
      if (value is Map && value.isEmpty) continue;

      // 特殊处理 child_xxxx 类型（支持 Map 和 List<Map> 两种格式）
      if (key.startsWith('child_')) {
        if (value is Map<String, dynamic>) {
          // 单个子词条（Map 格式）
          _addChildEntrySingleItem(
            context,
            items,
            key,
            value,
            colorScheme,
            section,
            currentSectionIndex,
          );
          continue;
        } else if (value is List<dynamic> && value.isNotEmpty) {
          // 多个子词条（List 格式）：一个标题，下面多个 headword
          _addChildEntryListItems(
            context,
            items,
            key,
            value,
            colorScheme,
            section,
            currentSectionIndex,
          );
          continue;
        }
      }

      final boardTitle = value is Map
          ? (value['title'] as String? ?? key)
          : key;
      final path = key;

      items.add(
        InkWell(
          onTap: () {
            _onSectionTapped(
              section,
              section.entry.dictId ?? '',
              currentSectionIndex,
              true,
              targetPath: path,
            );
          },
          mouseCursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.dashboard_outlined,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    boardTitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
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
    }

    return items;
  }

  /// 添加 child_xxxx 子词条到目录（单个 Map 格式）
  /// 标题为 xxxx（从键名提取），子项为 headword
  void _addChildEntrySingleItem(
    BuildContext context,
    List<Widget> items,
    String key,
    Map<String, dynamic> childData,
    ColorScheme colorScheme,
    DictionarySection section,
    int sectionIndex,
  ) {
    // 从 child_xxxx 提取标题 xxxx
    final title = key.length > 6 ? key.substring(6) : key;

    // 提取 headword
    final headword = childData['headword'] as String? ?? '';
    final headline = childData['headline'] as String?;
    final displayText = headword.isNotEmpty ? headword : (headline ?? '');

    // 添加子词条标题（可点击跳转到 child 元素）
    items.add(
      InkWell(
        onTap: () {
          _onSectionTapped(
            section,
            section.entry.dictId ?? '',
            sectionIndex,
            true,
            targetPath: key,
          );
        },
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.account_tree_outlined,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
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

    // 显示 headword 作为子项（占据整行）
    if (displayText.isNotEmpty) {
      items.add(
        InkWell(
          onTap: () {
            _onSectionTapped(
              section,
              section.entry.dictId ?? '',
              sectionIndex,
              true,
              targetPath: key, // 跳转到 child 元素本身
            );
          },
          mouseCursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 4, 12, 4),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                displayText,
                style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      );
    }
  }

  /// 添加多个 child_xxxx 子词条到目录（List 格式）
  /// 只显示一个标题 xxxx，下面有多个 headword 子项
  void _addChildEntryListItems(
    BuildContext context,
    List<Widget> items,
    String key,
    List<dynamic> children,
    ColorScheme colorScheme,
    DictionarySection section,
    int sectionIndex,
  ) {
    // 从 child_xxxx 提取标题 xxxx
    final title = key.length > 6 ? key.substring(6) : key;

    // 添加子词条标题（可点击跳转到 child 元素）
    items.add(
      InkWell(
        onTap: () {
          _onSectionTapped(
            section,
            section.entry.dictId ?? '',
            sectionIndex,
            true,
            targetPath: key,
          );
        },
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.account_tree_outlined,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
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

    // 添加每个 headword 作为子项
    for (int i = 0; i < children.length; i++) {
      final childData = children[i];
      if (childData is! Map<String, dynamic>) continue;

      final headword = childData['headword'] as String? ?? '';
      final headline = childData['headline'] as String?;
      final displayText = headword.isNotEmpty ? headword : (headline ?? '');

      if (displayText.isEmpty) continue;

      // 目标路径：child_xxxx.n 格式
      final targetPath = '$key.$i';

      items.add(
        InkWell(
          onTap: () {
            _onSectionTapped(
              section,
              section.entry.dictId ?? '',
              sectionIndex,
              true,
              targetPath: targetPath,
            );
          },
          mouseCursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 4, 12, 4),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                displayText,
                style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      );
    }
  }

  /// 根据词典元数据获取释义文本
  /// 优先级：目标语言列表中非源语言的语言 > 源语言 > 其他任意语言
  String _getDefinitionText(dynamic definition, String dictId) {
    if (definition is! Map) {
      return definition?.toString() ?? '';
    }
    final defMap = Map<String, dynamic>.from(definition);

    // 获取词典元数据
    final metadata = DictionaryManager().getCachedMetadata(dictId);
    if (metadata == null) {
      // 如果没有元数据，返回第一个非空值
      for (final value in defMap.values) {
        final text = value?.toString().trim() ?? '';
        if (text.isNotEmpty) {
          return text;
        }
      }
      return '';
    }

    String? valueForLanguage(String lang) {
      final normalizedLang = LanguageUtils.normalizeSourceLanguage(lang);
      final candidates = <String>{
        lang,
        lang.toLowerCase(),
        normalizedLang,
        normalizedLang.toLowerCase(),
      };

      for (final candidate in candidates) {
        final value = defMap[candidate];
        final text = value?.toString().trim() ?? '';
        if (text.isNotEmpty) {
          return text;
        }
      }
      return null;
    }

    final sourceLang = LanguageUtils.normalizeSourceLanguage(
      metadata.sourceLanguage,
    );
    final targetLangs = metadata.targetLanguages
        .map(LanguageUtils.normalizeSourceLanguage)
        .toList();

    // 优先级1：目标语言列表中非源语言的语言
    for (final lang in targetLangs) {
      if (lang != sourceLang) {
        final text = valueForLanguage(lang);
        if (text != null) {
          return text;
        }
      }
    }

    // 优先级2：源语言
    final sourceValue = valueForLanguage(sourceLang);
    if (sourceValue != null) {
      return sourceValue;
    }

    // 优先级3：其他任意非空语言
    for (final entry in defMap.entries) {
      final value = entry.value;
      if (value != null && value.toString().isNotEmpty) {
        return value.toString();
      }
    }

    return '';
  }

  void _addSenseItem(
    BuildContext context,
    List<Widget> items,
    Map<String, dynamic> sense,
    int index,
    ColorScheme colorScheme,
    DictionarySection section,
    String path,
    int sectionIndex,
    bool isSelected,
  ) {
    final definition = sense['definition'];
    String defText = '';

    if (definition is Map) {
      defText = _getDefinitionText(definition, section.entry.dictId ?? '');
    } else if (definition is String) {
      defText = definition;
    }

    // 显示序号，如果释义不为空则同时显示释义
    final bool showDefinition = defText.isNotEmpty;
    items.add(
      InkWell(
        onTap: () {
          Logger.d(
            'Directory item tapped: $defText, target section: ${section.section}, dictId: ${section.entry.dictId}, path: $path',
            tag: 'NavPanel',
          );
          // 复用 _onSectionTapped 的逻辑，确保跳转行为一致且健壮
          _onSectionTapped(
            section,
            section.entry.dictId ?? '',
            sectionIndex,
            isSelected,
            targetPath: path,
          );
        },
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 16),
                height: 16,
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 3),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$index',
                  style: TextStyle(
                    fontSize: index >= 100 ? 8 : 10,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (showDefinition) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      children: parseFormattedText(
                        defText,
                        TextStyle(fontSize: 13, color: colorScheme.onSurface),
                      ).spans,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    // 处理子释义
    final subSenses = sense['subsense'] as List<dynamic>?;
    if (subSenses != null && subSenses.isNotEmpty) {
      for (int j = 0; j < subSenses.length; j++) {
        final subSense = subSenses[j];
        final subDef = subSense['definition'];
        String subDefText = '';
        if (subDef is Map) {
          subDefText = _getDefinitionText(subDef, section.entry.dictId ?? '');
        } else if (subDef is String) {
          subDefText = subDef;
        }

        final bool showSubDefinition = subDefText.isNotEmpty;
        final subPath = '$path.subsense.$j';
        items.add(
          InkWell(
            onTap: () {
              Logger.d(
                'Directory sub-item tapped: $subDefText, target section: ${section.section}, dictId: ${section.entry.dictId}, path: $subPath',
                tag: 'NavPanel',
              );
              // 复用 _onSectionTapped 的逻辑，确保跳转行为一致且健壮
              _onSectionTapped(
                section,
                section.entry.dictId ?? '',
                sectionIndex,
                isSelected,
                targetPath: subPath,
              );
            },
            mouseCursor: SystemMouseCursors.click,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(36, 4, 12, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.only(top: 7),
                    decoration: BoxDecoration(
                      color: colorScheme.outline.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                  ),
                  if (showSubDefinition) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          children: parseFormattedText(
                            subDefText,
                            TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ).spans,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }
    }
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

    Widget sectionWidget = InkWell(
      onTap: () => _onSectionTapped(section, dictId, index, isSelected),
      borderRadius: BorderRadius.circular(12),
      mouseCursor: SystemMouseCursors.click,
      child: Container(
        width: 40,
        height: 32,
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? colorScheme.primaryContainer.withOpacity(0.65)
              : colorScheme.surfaceContainerLow,
          border: Border.all(
            color: isSelected
                ? colorScheme.primary.withOpacity(0.65)
                : colorScheme.outlineVariant.withOpacity(0.45),
            width: isSelected ? 1.5 : 1,
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
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withOpacity(0.75),
            ),
          ),
        ),
      ),
    );

    // 只有当前词典的活跃section才需要LayerLink来显示目录气泡
    if (isSelected && dictId == widget.entryGroup.currentDictionaryId) {
      return CompositedTransformTarget(
        link: _directoryLayerLink,
        child: Container(key: _sectionButtonKey, child: sectionWidget),
      );
    }

    return sectionWidget;
  }

  // 切换词典
  Future<void> _onDictionarySelected(DictionaryGroup dict) async {
    for (int i = 0; i < widget.entryGroup.dictionaryGroups.length; i++) {
      if (widget.entryGroup.dictionaryGroups[i].dictionaryId ==
          dict.dictionaryId) {
        // 词典切换时触发震动反馈（仅手机端，且切换到不同词典时）
        if (i != widget.entryGroup.currentDictionaryIndex &&
            (Platform.isAndroid || Platform.isIOS)) {
          HapticFeedback.vibrate();
        }

        // 先展开词典（如果处于折叠状态）
        await widget.onExpandDictionary?.call(dict.dictionaryId);

        widget.entryGroup.setCurrentDictionaryIndex(i);
        widget.entryGroup.dictionaryGroups[i].setCurrentPageIndex(0);
        widget.entryGroup.dictionaryGroups[i].setCurrentSectionIndex(0);

        widget.onDictionaryChanged?.call();
        widget.onPageChanged?.call();
        widget.onSectionChanged?.call();

        // 等待 UI 重建后再滚动
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          final newDict = widget.entryGroup.dictionaryGroups[i];
          if (newDict.pageGroups.isNotEmpty &&
              newDict.pageGroups[0].sections.isNotEmpty) {
            widget.onNavigateToEntry?.call(
              newDict.pageGroups[0].sections[0].entry,
            );
          }
        });

        // 关闭page列表的overlay
        _removeOverlay();
        // 关闭目录列表的overlay，didUpdateWidget 会负责重新打开
        _removeDirectoryOverlay();
        setState(() {
          _isPageListExpanded = false;
          // 保持 _isDirectoryExpanded 状态，让 didUpdateWidget 重新创建 overlay
          // 如果之前是展开的，_isDirectoryExpanded 保持 true
          // 如果之前是关闭的，_isDirectoryExpanded 保持 false
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

    // 3. 如果点击的是当前已经选中的page，只更新内容，不关闭列表
    if (currentDict.currentPageIndex == pageIndex) {
      return;
    }

    // 4. 更新模型状态
    currentDict.setCurrentPageIndex(pageIndex);
    // 切换page时，默认选中第一个section
    currentDict.setCurrentSectionIndex(0);

    // 5. 更新列表内容 (UI状态更新)
    if (_isPageListExpanded) {
      _removeOverlay();
      _overlayEntry = _createOverlayEntry(currentDict);
      Overlay.of(context).insert(_overlayEntry!);
    }

    // 6. 通知父组件 (EntryDetailPage) 进行重建和滚动
    widget.onPageChanged?.call();

    // 同时通知 section 变化，因为 section index 重置了
    widget.onSectionChanged?.call();

    // 导航到新页面的第一个section
    if (currentDict.currentPageGroup.sections.isNotEmpty) {
      widget.onNavigateToEntry?.call(
        currentDict.currentPageGroup.sections[0].entry,
      );
    }
  }

  // section点击处理
  // [isSelected] 表示当前section是否是活跃状态
  // [index] 是当前section在当前page中的索引
  void _onSectionTapped(
    DictionarySection section,
    String dictId,
    int index,
    bool isSelected, {
    String? targetPath,
  }) {
    Logger.d(
      'Section tapped: ${section.section}, dictId: $dictId, index: $index, isSelected: $isSelected, targetPath: $targetPath',
      tag: 'NavPanel',
    );

    // 关闭page列表（如果打开）
    if (_isPageListExpanded) {
      _removeOverlay();
      setState(() {
        _isPageListExpanded = false;
      });
    }

    // 1. 如果点击的是当前词典的活跃section
    if (isSelected &&
        dictId == widget.entryGroup.currentDictionaryId &&
        targetPath == null) {
      // 1.1 如果目录列表处于打开状态，关闭目录列表
      // 1.2 如果目录列表处于关闭状态，打开目录列表
      _toggleDirectory(index);
      return;
    }

    // 2. 如果点击的是非活跃section
    // 如果有 targetPath，说明是目录项点击，只需滚动不需要更新状态
    if (targetPath != null) {
      // 目录项点击：只执行滚动，不触发状态更新，保持目录列表打开
      widget.onNavigateToEntry?.call(section.entry, targetPath: targetPath);
      return;
    }

    // 没有 targetPath 的普通 section 切换
    _navigateToSection(section, dictId, targetPath);
  }

  // 导航到指定section
  void _navigateToSection(
    DictionarySection section,
    String dictId,
    String? targetPath,
  ) async {
    bool isCrossDictionary = false;
    bool isCrossPage = false;

    for (int i = 0; i < widget.entryGroup.dictionaryGroups.length; i++) {
      if (widget.entryGroup.dictionaryGroups[i].dictionaryId == dictId) {
        if (widget.entryGroup.currentDictionaryIndex != i) {
          isCrossDictionary = true;
        }

        // 先展开词典（如果处于折叠状态）
        await widget.onExpandDictionary?.call(dictId);

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
              Logger.d(
                'Found matching section at page $pageIndex, section $sectionIndex, isCrossDictionary: $isCrossDictionary, isCrossPage: $isCrossPage',
                tag: 'NavPanel',
              );

              if (dict.currentPageIndex != pageIndex) {
                isCrossPage = true;
              }

              dict.setCurrentPageIndex(pageIndex);
              dict.setCurrentSectionIndex(sectionIndex);

              final shouldOpenDirectory = _isDirectoryExpanded;
              if (_isDirectoryExpanded) {
                _removeDirectoryOverlay();
                setState(() {
                  _isDirectoryExpanded = false;
                  _selectedSectionIndex = null;
                });
              }

              if (isCrossDictionary) {
                widget.onDictionaryChanged?.call();
              } else if (isCrossPage) {
                widget.onPageChanged?.call();
              } else {
                widget.onSectionChanged?.call();
              }

              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;

                if (shouldOpenDirectory) {
                  _openDirectoryForCurrentSection();
                }

                widget.onNavigateToEntry?.call(
                  section.entry,
                  targetPath: targetPath,
                );
              });
              return;
            }
          }
        }
      }
    }

    Logger.w(
      'Section not found in structure, navigating directly',
      tag: 'NavPanel',
    );
    widget.onNavigateToEntry?.call(section.entry, targetPath: targetPath);
  }

  // 为当前活跃section打开目录列表
  void _openDirectoryForCurrentSection() {
    final currentDict = widget.entryGroup.currentDictionaryGroup;
    final currentSectionIndex = currentDict.currentSectionIndex;
    final currentPage = currentDict.currentPageGroup;

    _directoryOverlayEntry = _createDirectoryOverlayEntry(
      currentPage,
      currentSectionIndex,
    );
    Overlay.of(context).insert(_directoryOverlayEntry!);
    setState(() {
      _isDirectoryExpanded = true;
      _selectedSectionIndex = currentSectionIndex;
    });
  }

  void handleActiveSectionChanged() {
    if (_isDirectoryExpanded) {
      _removeDirectoryOverlay();
      setState(() {
        _isDirectoryExpanded = false;
        _selectedSectionIndex = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openDirectoryForCurrentSection();
        }
      });
    }
  }
}

/// 目录列表定位组件
/// 自动测量目录列表高度，并使其与 section 按钮垂直居中对齐
/// 仅在空间不足时调整位置
class _DirectoryBubblePositioner extends StatefulWidget {
  final double left;
  final double width;
  final double sectionCenterY;
  final double minTop;
  final double maxBottom;
  final void Function(double top, double height)? onPositioned;
  final Widget child;

  const _DirectoryBubblePositioner({
    required this.left,
    required this.width,
    required this.sectionCenterY,
    required this.minTop,
    required this.maxBottom,
    this.onPositioned,
    required this.child,
  });

  @override
  State<_DirectoryBubblePositioner> createState() =>
      _DirectoryBubblePositionerState();
}

class _DirectoryBubblePositionerState
    extends State<_DirectoryBubblePositioner> {
  final GlobalKey _childKey = GlobalKey();
  double? _bubbleHeight;

  @override
  void initState() {
    super.initState();
    // 在第一帧后获取高度
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureHeight();
    });
  }

  void _measureHeight() {
    final renderBox =
        _childKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final newHeight = renderBox.size.height;
      if (_bubbleHeight != newHeight) {
        setState(() {
          _bubbleHeight = newHeight;
        });
      }
    }
  }

  @override
  void didUpdateWidget(_DirectoryBubblePositioner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当参数变化时重新测量
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureHeight();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 使用已知高度或默认高度计算位置
    final bubbleHeight = _bubbleHeight ?? 200.0;

    // 理想位置：目录列表中心与 section 按钮中心对齐
    final idealTop = widget.sectionCenterY - bubbleHeight / 2;
    final idealBottom = idealTop + bubbleHeight;

    double top = idealTop;

    // 仅在空间不足时调整
    if (idealTop < widget.minTop) {
      // 上方空间不够，向下调整
      top = widget.minTop;
    } else if (idealBottom > widget.maxBottom) {
      // 下方空间不够，向上调整
      top = widget.maxBottom - bubbleHeight;
      // 确保不会超出顶部
      if (top < widget.minTop) {
        top = widget.minTop;
      }
    }

    // 通知父组件当前的位置和高度
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onPositioned?.call(top, bubbleHeight);
    });

    // 箭头始终与 section 按钮垂直对齐
    final arrowY = widget.sectionCenterY - top;

    return Positioned(
      left: widget.left,
      top: top,
      width: widget.width,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(key: _childKey, child: widget.child),
          // 箭头：始终与 section 按钮垂直对齐
          Positioned(
            right: -8, // 向右偏移，使箭头位于目录列表右边
            top: arrowY - 8, // 8 是箭头高度的一半，使箭头中心对齐
            child: CustomPaint(
              painter: _ArrowPainter(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.9),
                borderColor: colorScheme.outlineVariant.withOpacity(0.5),
              ),
              size: const Size(8, 16), // 增大箭头尺寸
            ),
          ),
        ],
      ),
    );
  }
}

/// 目录列表 Overlay 内容容器
/// 管理目录列表的位置和遮罩
class _DirectoryOverlayContent extends StatefulWidget {
  final double directoryLeft;
  final double directoryWidth;
  final double sectionCenterY;
  final double minTop;
  final double maxBottom;
  final double navTop;
  final double navBottom;
  final double navBarWidth;
  final double screenWidth;
  final double screenHeight;
  final VoidCallback onClose;
  final Widget bubbleChild;

  const _DirectoryOverlayContent({
    required this.directoryLeft,
    required this.directoryWidth,
    required this.sectionCenterY,
    required this.minTop,
    required this.maxBottom,
    required this.navTop,
    required this.navBottom,
    required this.navBarWidth,
    required this.screenWidth,
    required this.screenHeight,
    required this.onClose,
    required this.bubbleChild,
  });

  @override
  State<_DirectoryOverlayContent> createState() =>
      _DirectoryOverlayContentState();
}

class _DirectoryOverlayContentState extends State<_DirectoryOverlayContent> {
  double? _bubbleTop;
  double? _bubbleHeight;

  void _onBubblePositioned(double top, double height) {
    if (_bubbleTop != top || _bubbleHeight != height) {
      setState(() {
        _bubbleTop = top;
        _bubbleHeight = height;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        // 左侧主内容区域的遮罩（不包括目录列表区域）
        Positioned(
          left: 0,
          top: 0,
          width: widget.directoryLeft.clamp(0.0, widget.screenWidth),
          height: widget.screenHeight,
          child: GestureDetector(
            onTap: widget.onClose,
            onSecondaryTap: widget.onClose,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),
        // 右侧导航栏上方区域的遮罩
        if (widget.navTop > 0)
          Positioned(
            right: 0,
            top: 0,
            width: widget.navBarWidth,
            height: widget.navTop,
            child: GestureDetector(
              onTap: widget.onClose,
              onSecondaryTap: widget.onClose,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
        // 右侧导航栏下方区域的遮罩
        if (widget.navBottom < widget.screenHeight)
          Positioned(
            right: 0,
            top: widget.navBottom,
            width: widget.navBarWidth,
            height: widget.screenHeight - widget.navBottom,
            child: GestureDetector(
              onTap: widget.onClose,
              onSecondaryTap: widget.onClose,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
        // 目录列表上方的遮罩（目录列表区域上方）
        if (_bubbleTop != null &&
            _bubbleHeight != null &&
            _bubbleTop! > widget.minTop)
          Positioned(
            left: widget.directoryLeft,
            top: widget.minTop,
            width: widget.directoryWidth,
            height: _bubbleTop! - widget.minTop,
            child: GestureDetector(
              onTap: widget.onClose,
              onSecondaryTap: widget.onClose,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
        // 目录列表下方的遮罩（目录列表区域下方）
        if (_bubbleTop != null && _bubbleHeight != null)
          Positioned(
            left: widget.directoryLeft,
            top: _bubbleTop! + _bubbleHeight!,
            width: widget.directoryWidth,
            height: widget.maxBottom - _bubbleTop! - _bubbleHeight!,
            child: GestureDetector(
              onTap: widget.onClose,
              onSecondaryTap: widget.onClose,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
        // 目录列表
        _DirectoryBubblePositioner(
          left: widget.directoryLeft,
          width: widget.directoryWidth,
          sectionCenterY: widget.sectionCenterY,
          minTop: widget.minTop,
          maxBottom: widget.maxBottom,
          onPositioned: _onBubblePositioned,
          child: widget.bubbleChild,
        ),
      ],
    );
  }
}
