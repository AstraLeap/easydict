import 'package:flutter/material.dart';
import '../components/dictionary_logo.dart';
import '../core/utils/json_path_utils.dart';
import '../core/utils/scroll_safe_utils.dart';
import '../data/database_service.dart';
import '../services/dictionary_manager.dart';

/// 笔记链接预览弹窗
///
/// 显示目标内容的预览，并提供跳转按钮
class NoteLinkPreviewPopup {
  /// 显示链接预览弹窗
  ///
  /// [context] - BuildContext
  /// [dictId] - 词典ID
  /// [entryId] - 词条ID
  /// [jsonPath] - JSON路径
  /// [position] - 点击位置
  /// [onNavigate] - 跳转回调
  ///
  /// 返回一个闭包，调用它可以关闭弹窗
  static VoidCallback show({
    required BuildContext context,
    required String dictId,
    required String entryId,
    required String jsonPath,
    required Offset position,
    required VoidCallback onNavigate,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final overlay = Overlay.of(context);

    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;

    double overlayWidth;
    double dx;

    if (isMobile) {
      overlayWidth = screenSize.width - 32;
      dx = 16;
    } else {
      overlayWidth = 380.0;
      dx = position.dx;

      if (dx + overlayWidth > screenSize.width) {
        dx = screenSize.width - overlayWidth - 16;
      }
      if (dx < 16) {
        dx = 16;
      }
    }

    final maxHeight = (screenSize.height * 0.5).clamp(150.0, 400.0);

    OverlayEntry? barrierEntry;
    OverlayEntry? contentEntry;

    void removeOverlay() {
      barrierEntry?.remove();
      contentEntry?.remove();
      barrierEntry = null;
      contentEntry = null;
    }

    // Barrier overlay
    barrierEntry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: removeOverlay,
          onSecondaryTapDown: (_) => removeOverlay(),
          child: Container(color: Colors.transparent),
        ),
      ),
    );

    // Content overlay
    contentEntry = OverlayEntry(
      builder: (ctx) {
        final safeTopOffset = mobileTopSafeOffset(ctx, useViewPadding: true);
        final safeBottom = MediaQuery.of(ctx).viewPadding.bottom;
        final effectiveDy = (position.dy + 20).clamp(
          safeTopOffset,
          screenSize.height - maxHeight - safeBottom - 8.0,
        );
        final effectiveDx = dx.clamp(
          8.0,
          screenSize.width - overlayWidth - 8.0,
        );

        return Positioned(
          left: effectiveDx,
          top: effectiveDy,
          width: overlayWidth,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: BoxConstraints(maxHeight: maxHeight),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.75),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 24,
                    spreadRadius: 2,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _LinkPreviewContent(
                  dictId: dictId,
                  entryId: entryId,
                  jsonPath: jsonPath,
                  onNavigate: () {
                    removeOverlay();
                    onNavigate();
                  },
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(barrierEntry!);
    overlay.insert(contentEntry!);

    // 返回关闭函数
    return removeOverlay;
  }
}

/// 链接预览内容组件
class _LinkPreviewContent extends StatefulWidget {
  final String dictId;
  final String entryId;
  final String jsonPath;
  final VoidCallback onNavigate;

  const _LinkPreviewContent({
    required this.dictId,
    required this.entryId,
    required this.jsonPath,
    required this.onNavigate,
  });

  @override
  State<_LinkPreviewContent> createState() => _LinkPreviewContentState();
}

class _LinkPreviewContentState extends State<_LinkPreviewContent> {
  bool _isLoading = true;
  String? _content;
  String? _dictName;
  String? _headword;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    try {
      // 1. 获取 entry JSON
      final json = await DatabaseService().getEntryJsonById(
        widget.dictId,
        widget.entryId,
      );

      if (json == null) {
        if (mounted) {
          setState(() {
            _error = 'Entry not found';
            _isLoading = false;
          });
        }
        return;
      }

      // 2. 获取 headword
      _headword = json['headword'] as String?;

      // 3. 解析 jsonPath 获取目标值
      String? targetContent;
      if (widget.jsonPath.isNotEmpty) {
        final value = JsonPathUtils.getValueByPath(json, widget.jsonPath);
        targetContent = JsonPathUtils.formatValue(value);
      }

      // 4. 获取词典名称
      final metadata = await DictionaryManager().getDictionaryMetadata(
        widget.dictId,
      );

      if (mounted) {
        setState(() {
          _content = targetContent;
          _dictName = metadata?.name ?? widget.dictId;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colorScheme.error, size: 24),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: colorScheme.error, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏：词典 logo + 名称 + headword
          Row(
            children: [
              DictionaryLogo(
                dictionaryId: widget.dictId,
                dictionaryName: _dictName ?? widget.dictId,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _dictName ?? widget.dictId,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_headword != null) ...[
                const SizedBox(width: 4),
                Text(
                  _headword!,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),

          // 分隔线
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),

          // 内容预览
          if (_content != null && _content!.isNotEmpty)
            Flexible(
              child: SingleChildScrollView(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _content!,
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            )
          else
            Text(
              'No content',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),

          // 跳转按钮
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: widget.onNavigate,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Jump'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
