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

  const _DraggableNavPanel({
    required this.entryGroup,
    required this.onDictionaryChanged,
    required this.onPageChanged,
    required this.onSectionChanged,
    required this.onNavigateToEntry,
    required this.initialDy,
    this.navPanelKey,
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
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;
    double top;

    if (_dragY != null) {
      top = _dragY!;
    } else {
      top = screenSize.height * _dy;
      // 确保不超出屏幕底部
      if (top > screenSize.height - 100) {
        top = screenSize.height - 100;
      }
    }

    // 固定在右边缘，手机端更贴近边缘
    return Positioned(
      top: top,
      right: isMobile ? 4 : 16,
      child: GestureDetector(
        onPanStart: (details) {
          setState(() {
            _dragY = screenSize.height * _dy;
          });
        },
        onPanUpdate: (details) {
          setState(() {
            _dragY = _dragY! + details.delta.dy;
          });
        },
        onPanEnd: (details) {
          // 只保存垂直位置，固定在右侧
          final newDy = (_dragY! / screenSize.height).clamp(0.1, 0.8);

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
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
          h1: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
          h2: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
          h3: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
          h1Padding: const EdgeInsets.only(top: 16, bottom: 4),
          h2Padding: const EdgeInsets.only(top: 12, bottom: 4),
          h3Padding: const EdgeInsets.only(top: 8, bottom: 4),
          pPadding: const EdgeInsets.symmetric(vertical: 2),
          code: TextStyle(
            fontFamily: 'Consolas',
            fontSize:
                (Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14) * 0.9,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
          ),
          codeblockDecoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          codeblockPadding: const EdgeInsets.all(12),
          blockquote: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
            height: 1.6,
          ),
          blockquoteDecoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                width: 4,
              ),
            ),
            color: Theme.of(
              context,
            ).colorScheme.primaryContainer.withOpacity(0.15),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(4),
              bottomRight: Radius.circular(4),
            ),
          ),
          blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          listBullet: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(height: 1.6),
          listIndent: 20,
          strong: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.6,
          ),
          em: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontStyle: FontStyle.italic,
            height: 1.6,
          ),
          horizontalRuleDecoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 1,
              ),
            ),
          ),
          tableHead: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          tableBody: Theme.of(context).textTheme.bodyMedium,
          tableBorder: TableBorder.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
          tableColumnWidth: const FlexColumnWidth(),
          tableCellsPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
          tableHeadAlign: TextAlign.left,
        ),
      ),
    );
  }
}
