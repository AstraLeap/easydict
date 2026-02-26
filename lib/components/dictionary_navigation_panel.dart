import 'package:flutter/material.dart';
import '../data/models/dictionary_entry_group.dart';
import '../data/database_service.dart';
import 'dictionary_logo.dart';
import '../core/logger.dart';
import 'component_renderer.dart';
import '../services/dictionary_manager.dart';

class DictionaryNavigationPanel extends StatefulWidget {
  final DictionaryEntryGroup entryGroup;
  final VoidCallback? onDictionaryChanged;
  final VoidCallback? onPageChanged;
  final VoidCallback? onSectionChanged;
  final Function(DictionaryEntry entry, {String? targetPath})?
  onNavigateToEntry;

  const DictionaryNavigationPanel({
    super.key,
    required this.entryGroup,
    this.onDictionaryChanged,
    this.onPageChanged,
    this.onSectionChanged,
    this.onNavigateToEntry,
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
  OverlayEntry? _overlayEntry;
  OverlayEntry? _directoryOverlayEntry;

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
      final sectionIndex =
          _selectedSectionIndex ?? currentDict.currentSectionIndex;

      if (sectionIndex >= 0 && sectionIndex < currentPage.sections.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // 再次检查状态，防止在回调执行前用户已关闭目录
          if (mounted && _isDirectoryExpanded) {
            _directoryOverlayEntry = _createDirectoryOverlayEntry(
              currentPage,
              sectionIndex,
            );
            Overlay.of(context).insert(_directoryOverlayEntry!);
          }
        });
      }
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

        return Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: screenWidth - navBarWidth,
              height: screenHeight,
              child: GestureDetector(
                onTap: _closePageList,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),
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
    const offset = Offset(-12, 0);
    const navBarWidth = 52.0;

    return OverlayEntry(
      builder: (context) {
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        final isMobile = screenWidth < 600;
        final directoryWidth = isMobile ? 260.0 : 300.0;

        return Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: screenWidth - navBarWidth,
              height: screenHeight,
              child: GestureDetector(
                onTap: _closeDirectory,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              width: directoryWidth,
              child: CompositedTransformFollower(
                link: _directoryLayerLink,
                showWhenUnlinked: false,
                targetAnchor: Alignment.centerLeft,
                followerAnchor: Alignment.centerRight,
                offset: offset,
                child: _buildDirectoryBubble(context, page, sectionIndex),
              ),
            ),
          ],
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
        for (int j = 0; j < targetPage.sections.length; j++) {
          final section = targetPage.sections[j];
          mixedItems.add(
            _buildSectionItem(context, section, false, j, dict.dictionaryId),
          );
        }
      }
    }

    // 构建主导航栏
    return SizedBox(
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

    Widget logoContent = InkWell(
      key: key,
      onTap: isCurrent ? _togglePageList : () => _onDictionarySelected(dict),
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

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          constraints: const BoxConstraints(maxHeight: 400),
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
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _buildDirectoryItems(context, page),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerRight,
            child: Transform.translate(
              offset: const Offset(8, 0),
              child: CustomPaint(
                painter: _ArrowPainter(
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.95),
                  borderColor: colorScheme.outlineVariant.withOpacity(0.2),
                ),
                size: const Size(8, 16),
              ),
            ),
          ),
        ),
      ],
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
                    fontSize: 12,
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

    // 2. 添加 phrase 章节（只显示标题，可点击跳转）
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
                  'phrase',
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

    // 3. 添加 boards 章节（从 entryJson 中获取，排除已渲染的key）
    final entryJson = entry.toJson();
    final renderedKeys = const [
      'id',
      'entry_id',
      'dict_id',
      'version',
      'headword',
      'entry_type',
      'page',
      'section',
      'tags',
      'certifications',
      'frequency',
      'etymology',
      'pronunciation',
      'sense',
      'sense_group',
      'phrase',
      'datas',
      'hiddenLanguages',
      'hidden_languages',
    ];

    for (final jsonEntry in entryJson.entries) {
      final key = jsonEntry.key;
      final value = jsonEntry.value;

      // 跳过已渲染的key
      if (renderedKeys.contains(key)) continue;
      // 跳过null值
      if (value == null) continue;
      // 跳过空列表
      if (value is List && value.isEmpty) continue;
      // 跳过空map
      if (value is Map && value.isEmpty) continue;

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
        if (value != null && value.toString().isNotEmpty) {
          return value.toString();
        }
      }
      return '';
    }

    final sourceLang = metadata.sourceLanguage;
    final targetLangs = metadata.targetLanguages;

    // 优先级1：目标语言列表中非源语言的语言
    for (final lang in targetLangs) {
      if (lang != sourceLang) {
        final value = defMap[lang];
        if (value != null && value.toString().isNotEmpty) {
          return value.toString();
        }
      }
    }

    // 优先级2：源语言
    final sourceValue = defMap[sourceLang];
    if (sourceValue != null && sourceValue.toString().isNotEmpty) {
      return sourceValue.toString();
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
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$index',
                  style: TextStyle(
                    fontSize: 10,
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
      borderRadius: BorderRadius.circular(6),
      mouseCursor: SystemMouseCursors.click,
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
              ? colorScheme.primaryContainer.withOpacity(0.75)
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

    // 只有当前词典的活跃section才需要LayerLink来显示目录气泡
    if (isSelected && dictId == widget.entryGroup.currentDictionaryId) {
      return CompositedTransformTarget(
        link: _directoryLayerLink,
        child: sectionWidget,
      );
    }

    return sectionWidget;
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
  ) {
    bool isCrossDictionary = false;
    bool isCrossPage = false;

    for (int i = 0; i < widget.entryGroup.dictionaryGroups.length; i++) {
      if (widget.entryGroup.dictionaryGroups[i].dictionaryId == dictId) {
        if (widget.entryGroup.currentDictionaryIndex != i) {
          isCrossDictionary = true;
        }

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

              if (isCrossDictionary) {
                widget.onDictionaryChanged?.call();
              } else if (isCrossPage) {
                widget.onPageChanged?.call();
              } else {
                widget.onSectionChanged?.call();
              }

              final shouldOpenDirectory = _isDirectoryExpanded;
              if (_isDirectoryExpanded) {
                _removeDirectoryOverlay();
                setState(() {
                  _isDirectoryExpanded = false;
                  _selectedSectionIndex = null;
                });
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
