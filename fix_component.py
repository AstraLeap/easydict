f = r'f:\Codes\easydict\lib\components\component_renderer.dart'
with open(f, 'r', encoding='utf-8') as fp:
    c = fp.read()

# Fix 2: Replace simple pos in _buildLabelInlineSpans with proper styled version
old2 = """    // pos field
    final posValue = label['pos'];
    if (posValue != null) {
      final posText = _capitalizeFirst(
        posValue is String ? posValue : '$posValue',
      );
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _buildLabelWidget(context, posText, 'pos', false),
        ),
      );
    }"""

new2 = """    // pos 字段 - 使用专用 DictElementType.pos 样式
    final posValue = label['pos'];
    if (posValue != null) {
      final posText = (posValue is String ? posValue : '$posValue').toUpperCase();
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: PathScope.append(
            context,
            key: 'label.pos',
            child: Builder(
              builder: (context) {
                final posCs = Theme.of(context).colorScheme;
                return _buildTappableWidget(
                  context: context,
                  pathData: _PathData(PathScope.of(context), 'Part of Speech'),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    child: Text(
                      posText,
                      style: DictTypography.getScaledStyle(
                        DictElementType.pos,
                        language: _sourceLanguage,
                        fontScales: _fontScales,
                        color: posCs.primary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }"""

if old2 in c:
    c = c.replace(old2, new2)
    print('Fix 2 applied')
else:
    idx = c.find("// pos field")
    if idx >= 0:
        print('Fix 2 NOT found (mismatch), actual:')
        print(repr(c[idx:idx+300]))
    else:
        print('Fix 2: "// pos field" comment not found at all')
        # Search for alternate text
        idx2 = c.find("_buildLabelWidget(context, posText,")
        if idx2 >= 0:
            print('Found _buildLabelWidget call:')
            print(repr(c[max(0,idx2-200):idx2+100]))

# Fix 3: Make pos param not required
old3 = '    required String pos,'
new3 = "    String pos = '',"
if old3 in c:
    c = c.replace(old3, new3)
    print('Fix 3 applied')
else:
    print('Fix 3 NOT found')

with open(f, 'w', encoding='utf-8') as fp:
    fp.write(c)
print('Done writing file')
