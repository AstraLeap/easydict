part of 'entry_detail_page.dart';

// ==================== 私有辅助 Widget ====================

/// 可拖拽的导航面板（固定在右侧，可垂直拖动）
class _DraggableNavPanel extends StatefulWidget {
  final DictionaryEntryGroup entryGroup;
  final VoidCallback onDictionaryChanged;
  final VoidCallback onPageChanged;
  final VoidCallback onSectionChanged;
  final Function(DictionaryEntry entry, {String? targetPath})?
  onNavigateToEntry;
  final double initialDy;
  final GlobalKey<DictionaryNavigationPanelState>? navPanelKey;
  final ValueNotifier<int>? navPanelVersionNotifier;
  final Future<void> Function(String dictId)? onExpandDictionary;

  const _DraggableNavPanel({
    required this.entryGroup,
    required this.onDictionaryChanged,
    required this.onPageChanged,
    required this.onSectionChanged,
    required this.onNavigateToEntry,
    required this.initialDy,
    this.navPanelKey,
    this.navPanelVersionNotifier,
    this.onExpandDictionary,
  });

  @override
  State<_DraggableNavPanel> createState() => _DraggableNavPanelState();
}

class _DraggableNavPanelState extends State<_DraggableNavPanel> {
  late double _dy;
  double? _dragY;

  // 导航栏高度限制相关状态
  double _maxNavHeight = 0;
  bool _isOverflow = false;

  // 导航面板实际高度
  double _navPanelActualHeight = 0;

  // 导航栏位置边界约束
  static const double _topMargin = 0.0; // 上界距离屏幕顶部的距离
  static const double _bottomToolbarReservedHeight = 72.0; // 底部工具栏总预留高度（含底部间距）
  static const double _mobileTabBarReservedHeight = 44.0; // 手机端额外标签栏预留高度

  @override
  void initState() {
    super.initState();
    _dy = widget.initialDy;
    widget.navPanelVersionNotifier?.addListener(_onNavPanelVersionChanged);
  }

  @override
  void didUpdateWidget(_DraggableNavPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.navPanelVersionNotifier != oldWidget.navPanelVersionNotifier) {
      oldWidget.navPanelVersionNotifier?.removeListener(
        _onNavPanelVersionChanged,
      );
      widget.navPanelVersionNotifier?.addListener(_onNavPanelVersionChanged);
    }
  }

  void _onNavPanelVersionChanged() {
    // 当 notifier 变化时，只重建导航面板，不重建整个页面
    setState(() {});
  }

  @override
  void dispose() {
    widget.navPanelVersionNotifier?.removeListener(_onNavPanelVersionChanged);
    super.dispose();
  }

  /// 处理溢出状态变化
  void _onOverflowChanged(bool isOverflow) {
    if (_isOverflow != isOverflow) {
      setState(() {
        _isOverflow = isOverflow;
        if (isOverflow && _maxNavHeight == 0) {
          final screenSize = MediaQuery.of(context).size;
          _maxNavHeight = screenSize.height * 0.7;
        }
      });
    }
  }

  /// 计算导航栏的允许范围
  /// 返回 (minTop, maxTop)
  (double, double) _getNavPanelBounds(
    double screenHeight,
    double navPanelHeight,
    double topPadding,
    double bottomReserved,
  ) {
    // 上界：导航栏顶部距离屏幕顶部至少 _topMargin + 状态栏高度
    final minTop = _topMargin + topPadding;

    // 下界：导航栏底部距离底部工具栏顶部至少 bottomReserved
    // 即：top + navPanelHeight <= screenHeight - bottomReserved
    // 所以：top <= screenHeight - _bottomMargin - navPanelHeight
    final maxTop = (screenHeight - bottomReserved - navPanelHeight).clamp(
      minTop,
      double.infinity,
    );

    return (minTop, maxTop);
  }

  /// 将 top 位置约束在允许范围内
  double _clampTop(
    double top,
    double screenHeight,
    double navPanelHeight,
    double topPadding,
    double bottomReserved,
  ) {
    final (minTop, maxTop) = _getNavPanelBounds(
      screenHeight,
      navPanelHeight,
      topPadding,
      bottomReserved,
    );
    return top.clamp(minTop, maxTop);
  }

  double _getBottomReservedHeight(bool isMobile) {
    double reserved = _bottomToolbarReservedHeight;
    final hasEntryTabHost =
        context.findAncestorWidgetOfExactType<EntryTabHostPage>() != null;
    final hasFloatingTabBar =
        isMobile && hasEntryTabHost && EntryTabService().tabs.length > 1;
    if (hasFloatingTabBar) {
      reserved += _mobileTabBarReservedHeight;
    }
    return reserved;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;
    final topPadding = MediaQuery.of(context).padding.top; // 状态栏高度
    final bottomReserved = _getBottomReservedHeight(isMobile);

    // 计算最大高度
    final maxNavHeight = screenSize.height * 0.7;
    if (_maxNavHeight == 0) {
      _maxNavHeight = maxNavHeight;
    }

    // 导航面板高度（用于计算边界）
    final navPanelHeight = _navPanelActualHeight > 0
        ? _navPanelActualHeight
        : 200.0;

    // 计算导航栏位置
    double top;
    if (_isOverflow) {
      // 溢出模式：固定居中
      top = (screenSize.height - _maxNavHeight) / 2;
    } else if (_dragY != null) {
      // 拖动中：不限制位置，允许自由拖动
      top = _dragY!;
    } else {
      // 非拖动状态：使用存储的位置，并约束在边界内
      top = screenSize.height * _dy;
      top = _clampTop(
        top,
        screenSize.height,
        navPanelHeight,
        topPadding,
        bottomReserved,
      );
    }

    final rightPosition = isMobile ? 4.0 : 16.0;

    // 构建导航面板内容
    final navPanel = DictionaryNavigationPanel(
      key: widget.navPanelKey,
      entryGroup: widget.entryGroup,
      onDictionaryChanged: widget.onDictionaryChanged,
      onPageChanged: widget.onPageChanged,
      onSectionChanged: widget.onSectionChanged,
      onNavigateToEntry: widget.onNavigateToEntry,
      maxHeight: maxNavHeight,
      onOverflowChanged: _onOverflowChanged,
      onExpandDictionary: widget.onExpandDictionary,
    );

    // 固定在右边缘，手机端更贴近边缘
    return Positioned(
      top: top,
      right: rightPosition,
      child: _isOverflow
          ? navPanel
          : GestureDetector(
              onPanStart: (details) {
                setState(() {
                  _dragY = screenSize.height * _dy;
                });
              },
              onPanUpdate: (details) {
                setState(() {
                  // 拖动时不限制位置，允许拖到任意位置
                  _dragY = _dragY! + details.delta.dy;
                });
              },
              onPanEnd: (details) {
                // 拖动结束后，回弹到边界范围内
                final clampedTop = _clampTop(
                  _dragY!,
                  screenSize.height,
                  navPanelHeight,
                  topPadding,
                  bottomReserved,
                );

                // 将位置转换为比例并保存
                final newDy = clampedTop / screenSize.height;

                setState(() {
                  _dy = newDy;
                  _dragY = null;
                });
                PreferencesService().setNavPanelPosition(true, _dy);
              },
              child: MeasuredSize(
                onChange: (size) {
                  if (size.height != _navPanelActualHeight) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _navPanelActualHeight = size.height;
                        });
                      }
                    });
                  }
                },
                child: navPanel,
              ),
            ),
    );
  }
}

/// 测量子组件尺寸的 Widget
class MeasuredSize extends StatefulWidget {
  final Widget child;
  final void Function(Size size) onChange;

  const MeasuredSize({super.key, required this.child, required this.onChange});

  @override
  State<MeasuredSize> createState() => _MeasuredSizeState();
}

class _MeasuredSizeState extends State<MeasuredSize> {
  Size? _oldSize;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize) {
        final newSize = renderBox.size;
        if (_oldSize != newSize) {
          _oldSize = newSize;
          widget.onChange(newSize);
        }
      }
    });
    return widget.child;
  }
}

// ==================== 工具栏 AI 按钮闪烁动画 ====================

/// 工具栏 AI 按钮闪烁动画小部件
class _BlinkingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final bool isBlinking;

  const _BlinkingIcon({
    required this.icon,
    required this.color,
    required this.isBlinking,
  });

  @override
  State<_BlinkingIcon> createState() => _BlinkingIconState();
}

class _BlinkingIconState extends State<_BlinkingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 1.0,
      end: 0.25,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    if (widget.isBlinking) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_BlinkingIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isBlinking != oldWidget.isBlinking) {
      if (widget.isBlinking) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.value = 1.0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isBlinking) {
      return Icon(widget.icon, size: 24, color: widget.color);
    }
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: Icon(widget.icon, size: 24, color: widget.color),
        );
      },
    );
  }
}

// ==================== 共享 Markdown 样式表工具函数 ====================

/// 构建 AI 聊天内容用的 MarkdownStyleSheet。
/// 使用共享的样式表函数，保持与用户笔记一致的样式。
MarkdownStyleSheet _buildAiMarkdownStyleSheet(BuildContext context) =>
    buildMarkdownStyleSheet(context);

// ==================== 延迟渲染 Markdown ====================

/// 延迟渲染 MarkdownBody，避免在 ExpansionTile 展开动画期间带来卡顿
class _LazyMarkdownBody extends StatefulWidget {
  final String data;

  const _LazyMarkdownBody({required this.data});

  @override
  State<_LazyMarkdownBody> createState() => _LazyMarkdownBodyState();
}

class _LazyMarkdownBodyState extends State<_LazyMarkdownBody> {
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    // 延迟 300ms 渲染 Markdown，避免在 ExpansionTile 展开动画期间带来卡顿
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isReady = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: MarkdownBody(
        data: widget.data,
        selectable: true,
        styleSheet: _buildAiMarkdownStyleSheet(context),
      ),
    );
  }
}

// ==================== AI 聊天详情内容（嵌入式）====================

/// AI 聊天详情内容区，嵌入底部弹窗使用（不含 Scaffold / AppBar）
class _AiChatDetailContent extends StatefulWidget {
  final AiChatRecord record;
  final ValueNotifier<(String, String?, bool)>? streamingNotifier;
  final ScrollController? scrollController;

  const _AiChatDetailContent({
    super.key,
    required this.record,
    this.streamingNotifier,
    this.scrollController,
  });

  @override
  State<_AiChatDetailContent> createState() => _AiChatDetailContentState();
}

class _AiChatDetailContentState extends State<_AiChatDetailContent> {
  late String _answer;
  late String? _thinking;
  late bool _isComplete;
  bool _listenerAttached = false;

  @override
  void initState() {
    super.initState();
    _answer = widget.record.answer;
    _thinking = widget.record.thinkingContent;
    if (widget.streamingNotifier != null) {
      _isComplete = false;
      widget.streamingNotifier!.addListener(_onStreamingUpdate);
      _listenerAttached = true;
      final existing = widget.streamingNotifier!.value;
      if (existing.$1.isNotEmpty) _answer = existing.$1;
      if (existing.$2 != null) _thinking = existing.$2;
      _isComplete = existing.$3;
    } else {
      _isComplete = true;
    }
  }

  @override
  void didUpdateWidget(_AiChatDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.streamingNotifier != oldWidget.streamingNotifier) {
      if (_listenerAttached) {
        try {
          oldWidget.streamingNotifier!.removeListener(_onStreamingUpdate);
        } catch (_) {}
        _listenerAttached = false;
      }
      if (widget.streamingNotifier != null) {
        widget.streamingNotifier!.addListener(_onStreamingUpdate);
        _listenerAttached = true;
        final existing = widget.streamingNotifier!.value;
        if (existing.$1.isNotEmpty) _answer = existing.$1;
        if (existing.$2 != null) _thinking = existing.$2;
        _isComplete = existing.$3;
      }
    }
  }

  void _onStreamingUpdate() {
    final data = widget.streamingNotifier?.value;
    if (data == null || !mounted) return;
    setState(() {
      _answer = data.$1;
      _thinking = data.$2;
      _isComplete = data.$3;
    });
    if (data.$3 && _listenerAttached) {
      try {
        widget.streamingNotifier!.removeListener(_onStreamingUpdate);
      } catch (_) {}
      _listenerAttached = false;
    }
  }

  @override
  void dispose() {
    if (_listenerAttached) {
      try {
        widget.streamingNotifier!.removeListener(_onStreamingUpdate);
      } catch (_) {}
      _listenerAttached = false;
    }
    super.dispose();
  }

  String get currentAnswer => _answer;

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inMinutes < 1) return context.t.entry.justNow;
    if (diff.inHours < 1) return context.t.entry.minutesAgo(n: diff.inMinutes);
    if (diff.inDays < 1) return context.t.entry.hoursAgo(n: diff.inHours);
    if (diff.inDays < 7) return context.t.entry.daysAgo(n: diff.inDays);
    return '${timestamp.month}/${timestamp.day} '
        '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  /// 根据聊天类型构建标题（不显示词头名以避免与第二行重复）
  String _buildDetailTitle(AiChatRecord record) {
    final path = record.path;
    if (path == '__summary__') {
      final dictId =
          record.dictionaryId ?? _parseSummaryDictId(record.elementJson);
      final page = _parseSummaryPage(record.elementJson);
      final dictLabel = (dictId != null && dictId.isNotEmpty)
          ? dictId
          : record.word;
      if (page != null && page.isNotEmpty) {
        return context.t.entry.chatStartSummary(dict: dictLabel, page: page);
      }
      return context.t.entry.summaryTitle;
    } else if (path != null) {
      // 元素询问：显示词典名而不是词头名
      final dictId = record.dictionaryId;
      final dictLabel = (dictId != null && dictId.isNotEmpty)
          ? dictId
          : record.word;
      return context.t.entry.chatStartElement(dict: dictLabel, path: path);
    } else {
      // 自由聊天：显示词头
      return context.t.entry.chatStartFreeChat(word: record.word);
    }
  }

  String? _parseSummaryDictId(String? elementJson) {
    if (elementJson == null) return null;
    try {
      final data = jsonDecode(elementJson) as Map<String, dynamic>?;
      return data?['dictionary'] as String?;
    } catch (_) {
      return null;
    }
  }

  String? _parseSummaryPage(String? elementJson) {
    if (elementJson == null) return null;
    try {
      final data = jsonDecode(elementJson) as Map<String, dynamic>?;
      return data?['page'] as String?;
    } catch (_) {
      return null;
    }
  }

  MarkdownStyleSheet _buildMarkdownStyleSheet(BuildContext context) =>
      _buildAiMarkdownStyleSheet(context);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final record = widget.record;
    final isLoading = _answer.isEmpty && !_isComplete;
    final isError = _answer.startsWith(context.t.entry.aiRequestFailedShort);

    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 问题标题（根据聊天类型显示）
          Text(
            _buildDetailTitle(record),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          // 词条和时间戳（仅对总结类型显示词条名，其他类型只显示时间）
          Row(
            children: [
              Icon(Icons.access_time, size: 13, color: colorScheme.outline),
              const SizedBox(width: 4),
              Text(
                record.path == '__summary__'
                    ? '${record.word} · ${_formatTime(record.timestamp)}'
                    : _formatTime(record.timestamp),
                style: TextStyle(fontSize: 12, color: colorScheme.outline),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 关联词典内容（JSON）
          if (record.elementJson != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                record.elementJson!,
                style: const TextStyle(fontSize: 12, fontFamily: 'Consolas'),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 12),
          ],
          // 思考过程
          if (_thinking != null && _thinking!.isNotEmpty) ...[
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                collapsedShape: const RoundedRectangleBorder(
                  side: BorderSide.none,
                ),
                shape: const RoundedRectangleBorder(side: BorderSide.none),
                title: Row(
                  children: [
                    Icon(
                      Icons.psychology_outlined,
                      size: 14,
                      color: colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      context.t.entry.thinkingProcess,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.outline,
                      ),
                    ),
                    if (!_isComplete)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: colorScheme.outline,
                          ),
                        ),
                      ),
                  ],
                ),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withOpacity(
                        0.5,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(
                      _thinking!,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          // 加载中 / 错误 / 内容
          if (isLoading)
            Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  context.t.entry.aiThinking,
                  style: TextStyle(color: colorScheme.outline),
                ),
              ],
            )
          else if (isError)
            Text(_answer, style: TextStyle(color: colorScheme.error))
          else ...[
            RepaintBoundary(
              child: MarkdownBody(
                data: _answer,
                selectable: true,
                styleSheet: _buildMarkdownStyleSheet(context),
              ),
            ),
            if (!_isComplete)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      context.t.entry.outputting,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ==================== AI 聊天详情页 ====================

/// AI 聊天记录详情页（全屏页面，替代原来的 ExpansionTile 展开方式）
class _AiChatDetailPage extends StatefulWidget {
  final AiChatRecord initialRecord;
  final ValueNotifier<(String, String?, bool)>? streamingNotifier;
  final Future<void> Function(String recordId) onDeleteConfirmed;
  final void Function(String message)? onSendContinueChat;

  const _AiChatDetailPage({
    required this.initialRecord,
    this.streamingNotifier,
    required this.onDeleteConfirmed,
    this.onSendContinueChat,
  });

  @override
  State<_AiChatDetailPage> createState() => _AiChatDetailPageState();
}

class _AiChatDetailPageState extends State<_AiChatDetailPage> {
  late String _answer;
  late String? _thinking;
  late bool _isComplete;
  bool _listenerAttached = false;

  @override
  void initState() {
    super.initState();
    _answer = widget.initialRecord.answer;
    _thinking = widget.initialRecord.thinkingContent;
    if (widget.streamingNotifier != null) {
      _isComplete = false;
      widget.streamingNotifier!.addListener(_onStreamingUpdate);
      _listenerAttached = true;
      // Sync any existing streaming content
      final existing = widget.streamingNotifier!.value;
      if (existing.$1.isNotEmpty) _answer = existing.$1;
      if (existing.$2 != null) _thinking = existing.$2;
      _isComplete = existing.$3;
    } else {
      _isComplete = true;
    }
  }

  void _onStreamingUpdate() {
    final data = widget.streamingNotifier?.value;
    if (data == null) return;
    if (!mounted) return;
    setState(() {
      _answer = data.$1;
      _thinking = data.$2;
      _isComplete = data.$3;
    });
    if (data.$3 && _listenerAttached) {
      try {
        widget.streamingNotifier!.removeListener(_onStreamingUpdate);
      } catch (_) {}
      _listenerAttached = false;
    }
  }

  @override
  void dispose() {
    if (_listenerAttached) {
      try {
        widget.streamingNotifier!.removeListener(_onStreamingUpdate);
      } catch (_) {}
      _listenerAttached = false;
    }
    super.dispose();
  }

  Future<void> _handleDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.t.entry.deleteRecord),
        content: Text(context.t.entry.deleteRecordConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.t.common.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(context.t.common.delete),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await widget.onDeleteConfirmed(widget.initialRecord.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _handleContinueChat() async {
    final controller = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.t.entry.continueAsk),
        content: Shortcuts(
          shortcuts: {
            LogicalKeySet(LogicalKeyboardKey.enter): const _SendIntent(),
            LogicalKeySet(LogicalKeyboardKey.shift, LogicalKeyboardKey.enter):
                const _NewLineIntent(),
            LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.enter):
                const _NewLineIntent(),
            LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.enter):
                const _NewLineIntent(),
          },
          child: Actions(
            actions: {
              _SendIntent: _SendAction(
                onSend: () => Navigator.pop(ctx, controller.text.trim()),
              ),
              _NewLineIntent: _NewLineAction(controller: controller),
            },
            child: TextField(
              controller: controller,
              maxLines: 4,
              minLines: 1,
              autofocus: true,
              decoration: InputDecoration(
                hintText: context.t.entry.continueAskHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.t.common.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(context.t.common.continue_),
          ),
        ],
      ),
    );
    if (message != null && message.isNotEmpty && mounted) {
      widget.onSendContinueChat?.call(message);
      if (mounted) Navigator.of(context).pop();
    }
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inMinutes < 1) return context.t.entry.justNow;
    if (diff.inHours < 1) return context.t.entry.minutesAgo(n: diff.inMinutes);
    if (diff.inDays < 1) return context.t.entry.hoursAgo(n: diff.inHours);
    if (diff.inDays < 7) return context.t.entry.daysAgo(n: diff.inDays);
    return '${timestamp.month}/${timestamp.day} '
        '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  /// 根据聊天类型构建标题（不显示词头名以避免与下方重复）
  String _buildDetailTitle(AiChatRecord record) {
    final path = record.path;
    if (path == '__summary__') {
      final dictId =
          record.dictionaryId ?? _parseSummaryDictId(record.elementJson);
      final page = _parseSummaryPage(record.elementJson);
      final dictLabel = (dictId != null && dictId.isNotEmpty)
          ? dictId
          : record.word;
      if (page != null && page.isNotEmpty) {
        return context.t.entry.chatStartSummary(dict: dictLabel, page: page);
      }
      return context.t.entry.summaryTitle;
    } else if (path != null) {
      // 元素询问：显示词典名而不是词头名
      final dictId = record.dictionaryId;
      final dictLabel = (dictId != null && dictId.isNotEmpty)
          ? dictId
          : record.word;
      return context.t.entry.chatStartElement(dict: dictLabel, path: path);
    } else {
      // 自由聊天：显示词头
      return context.t.entry.chatStartFreeChat(word: record.word);
    }
  }

  String? _parseSummaryDictId(String? elementJson) {
    if (elementJson == null) return null;
    try {
      final data = jsonDecode(elementJson) as Map<String, dynamic>?;
      return data?['dictionary'] as String?;
    } catch (_) {
      return null;
    }
  }

  String? _parseSummaryPage(String? elementJson) {
    if (elementJson == null) return null;
    try {
      final data = jsonDecode(elementJson) as Map<String, dynamic>?;
      return data?['page'] as String?;
    } catch (_) {
      return null;
    }
  }

  MarkdownStyleSheet _buildMarkdownStyleSheet(BuildContext context) =>
      _buildAiMarkdownStyleSheet(context);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final record = widget.initialRecord;
    final isLoading = _answer.isEmpty && !_isComplete;
    final isError = _answer.startsWith(context.t.entry.aiRequestFailedShort);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _buildDetailTitle(record),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          if (!isLoading && !isError)
            IconButton(
              icon: const Icon(Icons.copy_outlined),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _answer));
                showToast(context, context.t.entry.copiedToClipboard);
              },
              tooltip: context.t.common.copy,
            ),
          if (!isLoading && !isError && widget.onSendContinueChat != null)
            IconButton(
              icon: const Icon(Icons.chat_outlined),
              onPressed: _handleContinueChat,
              tooltip: context.t.entry.continueAsk,
            ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              color: colorScheme.error.withOpacity(0.7),
            ),
            onPressed: _handleDelete,
            tooltip: context.t.common.delete,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 词条和时间戳（仅对总结类型显示词条名，其他类型只显示时间）
            Row(
              children: [
                Icon(Icons.access_time, size: 13, color: colorScheme.outline),
                const SizedBox(width: 4),
                Text(
                  record.path == '__summary__'
                      ? '${record.word} · ${_formatTime(record.timestamp)}'
                      : _formatTime(record.timestamp),
                  style: TextStyle(fontSize: 12, color: colorScheme.outline),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 关联的词典内容（JSON）
            if (record.elementJson != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  record.elementJson!,
                  style: const TextStyle(fontSize: 12, fontFamily: 'Consolas'),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 12),
            ],
            // 思考过程
            if (_thinking != null && _thinking!.isNotEmpty) ...[
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  collapsedShape: const RoundedRectangleBorder(
                    side: BorderSide.none,
                  ),
                  shape: const RoundedRectangleBorder(side: BorderSide.none),
                  title: Row(
                    children: [
                      Icon(
                        Icons.psychology_outlined,
                        size: 14,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        context.t.entry.thinkingProcess,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
                        ),
                      ),
                      if (!_isComplete)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: colorScheme.outline,
                            ),
                          ),
                        ),
                    ],
                  ),
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withOpacity(
                          0.5,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SelectableText(
                        _thinking!,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            // 加载中
            if (isLoading)
              Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.t.entry.aiThinking,
                    style: TextStyle(color: colorScheme.outline),
                  ),
                ],
              )
            else if (isError)
              Text(_answer, style: TextStyle(color: colorScheme.error))
            else ...[
              RepaintBoundary(
                child: MarkdownBody(
                  data: _answer,
                  selectable: true,
                  styleSheet: _buildMarkdownStyleSheet(context),
                ),
              ),
              if (!_isComplete)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        context.t.entry.outputting,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

/// 键盘感知的底部工具栏容器
/// 使用 AnimatedPositioned 实现平滑的键盘跟随动画
class _KeyboardAwareBottomBar extends StatefulWidget {
  final Widget child;
  final bool ignoreKeyboardInsets;

  const _KeyboardAwareBottomBar({
    required this.child,
    this.ignoreKeyboardInsets = false,
  });

  @override
  State<_KeyboardAwareBottomBar> createState() =>
      _KeyboardAwareBottomBarState();
}

class _KeyboardAwareBottomBarState extends State<_KeyboardAwareBottomBar> {
  static const double _minBottomPadding = 16;

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = widget.ignoreKeyboardInsets
        ? 0.0
        : MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = keyboardHeight + _minBottomPadding;
    final isPhone =
        Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;
    // 手机端使用更小的边距，与标签栏对齐
    final horizontalPadding = isPhone ? 10.0 : 16.0;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      left: horizontalPadding,
      right: horizontalPadding,
      bottom: bottomPadding,
      child: widget.child,
    );
  }
}

/// 面包屑项数据
class _BreadcrumbItem {
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  const _BreadcrumbItem({
    required this.label,
    required this.isActive,
    this.onTap,
  });
}

/// 统一的组面包屑导航栏组件
class _GroupBreadcrumbBar extends StatelessWidget {
  final EdgeInsets margin;
  final List<_BreadcrumbItem> items;
  final bool showCloseButton;
  final String? trailingEntryHeadword;
  final VoidCallback? onClose;

  const _GroupBreadcrumbBar({
    required this.margin,
    required this.items,
    this.showCloseButton = true,
    this.trailingEntryHeadword,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: margin,
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  if (i > 0)
                    Icon(
                      Icons.chevron_right,
                      size: 14,
                      color: colorScheme.outline,
                    ),
                  _buildBreadcrumbChip(items[i], colorScheme),
                ],
                if (trailingEntryHeadword != null) ...[
                  Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: colorScheme.outline,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outline.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      trailingEntryHeadword!,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (showCloseButton)
            GestureDetector(
              onTap: onClose,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.arrow_back,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbChip(_BreadcrumbItem item, ColorScheme colorScheme) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: item.isActive
                ? colorScheme.primaryContainer.withOpacity(0.7)
                : colorScheme.secondaryContainer.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outline.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Text(
            item.label,
            style: TextStyle(
              fontSize: 12,
              color: item.isActive
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSecondaryContainer,
              fontWeight: item.isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
