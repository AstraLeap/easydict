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

  const _DraggableNavPanel({
    required this.entryGroup,
    required this.onDictionaryChanged,
    required this.onPageChanged,
    required this.onSectionChanged,
    required this.onNavigateToEntry,
    required this.initialDy,
    this.navPanelKey,
    this.navPanelVersionNotifier,
  });

  @override
  State<_DraggableNavPanel> createState() => _DraggableNavPanelState();
}

class _DraggableNavPanelState extends State<_DraggableNavPanel> {
  late double _dy;
  double? _dragY;

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

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;
    final scale = FontLoaderService().getDictionaryContentScale();
    double top;

    if (_dragY != null) {
      top = _dragY!;
    } else {
      top = screenSize.height * _dy / scale;
      // 确保不超出屏幕底部
      final maxTop = screenSize.height - 100 / scale;
      if (top > maxTop) {
        top = maxTop;
      }
    }

    final rightPosition = (isMobile ? 4 : 16) / scale;

    // 固定在右边缘，手机端更贴近边缘
    return Positioned(
      top: top,
      right: rightPosition,
      child: GestureDetector(
        onPanStart: (details) {
          setState(() {
            _dragY = screenSize.height * _dy / scale;
          });
        },
        onPanUpdate: (details) {
          setState(() {
            _dragY = _dragY! + details.delta.dy;
          });
        },
        onPanEnd: (details) {
          // 只保存垂直位置，固定在右侧
          // _dy 存储的是相对于原始屏幕高度的比例
          final newDy = (_dragY! * scale / screenSize.height).clamp(0.1, 0.8);

          setState(() {
            _dy = newDy;
            _dragY = null;
          });
          PreferencesService().setNavPanelPosition(true, _dy);
        },
        child: DictionaryNavigationPanel(
          key: widget.navPanelKey,
          entryGroup: widget.entryGroup,
          onDictionaryChanged: widget.onDictionaryChanged,
          onPageChanged: widget.onPageChanged,
          onSectionChanged: widget.onSectionChanged,
          onNavigateToEntry: widget.onNavigateToEntry,
        ),
      ),
    );
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

/// 缓存的 MarkdownStyleSheet 对象，避免每次调用都创建新对象
MarkdownStyleSheet? _cachedAiMarkdownStyleSheet;
ThemeData? _cachedAiMarkdownTheme;

/// 构建 AI 聊天内容用的 MarkdownStyleSheet。
///
/// AI 聊天内容统一使用系统默认字体（SourceSans3/SourceSerif4），
/// 不使用用户自定义字体，以保持界面一致性。
///
/// 修复"斜体太斜"问题：em 和 blockquote 的斜体改用带真实斜体字形的
/// SourceSans3 / SourceSerif4，避免合成斜体对 CJK 字形产生极端倾斜。
MarkdownStyleSheet _buildAiMarkdownStyleSheet(BuildContext context) {
  final theme = Theme.of(context);

  // 检查缓存：如果主题相同，直接返回缓存的样式表
  if (_cachedAiMarkdownStyleSheet != null &&
      identical(_cachedAiMarkdownTheme, theme)) {
    return _cachedAiMarkdownStyleSheet!;
  }

  final cs = theme.colorScheme;

  // AI 聊天内容使用系统默认字体，不使用用户自定义字体
  const firstFont = 'SourceSans3';

  final baseBody = theme.textTheme.bodyMedium?.copyWith(
    height: 1.6,
    fontFamily: firstFont,
  );

  final italicBody = baseBody?.copyWith(
    fontStyle: FontStyle.italic,
    fontFamily: firstFont,
  );

  final styleSheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: baseBody,
    h1: theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.4,
      fontFamily: firstFont,
    ),
    h2: theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.4,
      fontFamily: firstFont,
    ),
    h3: theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.4,
      fontFamily: firstFont,
    ),
    h1Padding: const EdgeInsets.only(top: 16, bottom: 4),
    h2Padding: const EdgeInsets.only(top: 12, bottom: 4),
    h3Padding: const EdgeInsets.only(top: 8, bottom: 4),
    pPadding: const EdgeInsets.symmetric(vertical: 2),
    code: TextStyle(
      fontFamily: 'Consolas',
      fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) * 0.9,
      color: cs.onSurfaceVariant,
      backgroundColor: cs.surfaceContainerHighest,
    ),
    codeblockDecoration: BoxDecoration(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
    ),
    codeblockPadding: const EdgeInsets.all(12),
    blockquote: italicBody?.copyWith(color: cs.onSurfaceVariant),
    blockquoteDecoration: BoxDecoration(
      border: Border(
        left: BorderSide(color: cs.primary.withOpacity(0.5), width: 4),
      ),
      color: cs.primaryContainer.withOpacity(0.15),
      borderRadius: const BorderRadius.only(
        topRight: Radius.circular(4),
        bottomRight: Radius.circular(4),
      ),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
    listBullet: baseBody,
    listIndent: 20,
    strong: baseBody?.copyWith(fontWeight: FontWeight.w700),
    em: italicBody,
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: cs.outlineVariant, width: 1)),
    ),
    tableHead: baseBody?.copyWith(fontWeight: FontWeight.w700),
    tableBody: baseBody,
    tableBorder: TableBorder.all(color: cs.outlineVariant, width: 1),
    tableColumnWidth: const FlexColumnWidth(),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    tableHeadAlign: TextAlign.left,
  );

  // 更新缓存
  _cachedAiMarkdownStyleSheet = styleSheet;
  _cachedAiMarkdownTheme = theme;

  return styleSheet;
}

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

  const _KeyboardAwareBottomBar({required this.child});

  @override
  State<_KeyboardAwareBottomBar> createState() =>
      _KeyboardAwareBottomBarState();
}

class _KeyboardAwareBottomBarState extends State<_KeyboardAwareBottomBar> {
  static const double _minBottomPadding = 16;

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = keyboardHeight + _minBottomPadding;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      left: 16,
      right: 16,
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
