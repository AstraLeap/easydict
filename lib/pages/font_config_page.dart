import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../logger.dart';
import '../services/dictionary_manager.dart';
import '../services/font_loader_service.dart';
import '../services/preferences_service.dart';
import '../utils/language_utils.dart';
import '../utils/toast_utils.dart';

class FontConfigPage extends StatefulWidget {
  const FontConfigPage({super.key});

  @override
  State<FontConfigPage> createState() => _FontConfigPageState();
}

class _FontConfigPageState extends State<FontConfigPage>
    with TickerProviderStateMixin {
  TabController? _tabController;
  String? _fontFolderPath;
  Map<String, DetectedFonts> _detectedFonts = {};
  Map<String, UserFontConfigs> _userFontConfigs = {};
  Map<String, Map<String, double>> _fontScales = {};
  List<String> _languages = [];
  bool _isLoading = true;
  double _dictionaryContentScale = 1.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _initTabController() {
    _tabController?.addListener(() {
      if (mounted && !_tabController!.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController?.removeListener(() {});
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadData({
    bool forceRescan = false,
    bool skipAutoSave = false,
  }) async {
    final prefs = PreferencesService();
    final fontPath = await prefs.getFontFolderPath();
    final languages = await _getAvailableLanguages();
    final userConfigs = await prefs.getFontConfigs();
    final fontScales = await prefs.getAllFontScales();
    final dictionaryContentScale = await prefs.getDictionaryContentScale();

    Map<String, DetectedFonts> detectedFonts = {};
    if (fontPath != null && fontPath.isNotEmpty) {
      detectedFonts = await _scanAllLanguageFonts(fontPath, languages);

      // 自动将扫描到的字体保存为配置（强制重新扫描时会覆盖现有配置）
      if (!skipAutoSave) {
        await _autoSaveDetectedFonts(
          detectedFonts,
          userConfigs,
          prefs,
          forceRescan: forceRescan,
        );
      }

      // 重新获取用户配置
      userConfigs.clear();
      final newUserConfigs = await prefs.getFontConfigs();
      userConfigs.addAll(newUserConfigs);
    }

    if (mounted) {
      setState(() {
        _fontFolderPath = fontPath;
        _detectedFonts = detectedFonts;
        _userFontConfigs = _convertToUserFontConfigs(userConfigs);
        _fontScales = fontScales;
        _languages = languages;
        _dictionaryContentScale = dictionaryContentScale;
        if (_languages.isNotEmpty) {
          _tabController = TabController(
            length: _languages.length,
            vsync: this,
          );
          _initTabController();
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _autoSaveDetectedFonts(
    Map<String, DetectedFonts> detectedFonts,
    Map<String, Map<String, String>> existingConfigs,
    PreferencesService prefs, {
    bool forceRescan = false,
  }) async {
    for (final langEntry in detectedFonts.entries) {
      final language = langEntry.key;
      final detected = langEntry.value;

      // 如果用户已有配置且不是强制重新扫描，跳过该语言的检测
      if (!forceRescan && existingConfigs.containsKey(language)) {
        continue;
      }

      // 保存扫描到的字体
      if (detected.serif.regular != null) {
        await prefs.setFontConfig(
          language: language,
          fontType: 'serif_regular',
          fontPath: detected.serif.regular!.path,
        );
      }
      if (detected.serif.bold != null) {
        await prefs.setFontConfig(
          language: language,
          fontType: 'serif_bold',
          fontPath: detected.serif.bold!.path,
        );
      }
      if (detected.serif.italic != null) {
        await prefs.setFontConfig(
          language: language,
          fontType: 'serif_italic',
          fontPath: detected.serif.italic!.path,
        );
      }
      if (detected.serif.boldItalic != null) {
        await prefs.setFontConfig(
          language: language,
          fontType: 'serif_bold_italic',
          fontPath: detected.serif.boldItalic!.path,
        );
      }
      if (detected.sans.regular != null) {
        await prefs.setFontConfig(
          language: language,
          fontType: 'sans_regular',
          fontPath: detected.sans.regular!.path,
        );
      }
      if (detected.sans.bold != null) {
        await prefs.setFontConfig(
          language: language,
          fontType: 'sans_bold',
          fontPath: detected.sans.bold!.path,
        );
      }
      if (detected.sans.italic != null) {
        await prefs.setFontConfig(
          language: language,
          fontType: 'sans_italic',
          fontPath: detected.sans.italic!.path,
        );
      }
      if (detected.sans.boldItalic != null) {
        await prefs.setFontConfig(
          language: language,
          fontType: 'sans_bold_italic',
          fontPath: detected.sans.boldItalic!.path,
        );
      }
    }

    Logger.i('自动保存字体配置完成', tag: 'FontLoader');
  }

  Map<String, UserFontConfigs> _convertToUserFontConfigs(
    Map<String, Map<String, String>> configs,
  ) {
    final result = <String, UserFontConfigs>{};
    for (final entry in configs.entries) {
      final lang = entry.key;
      final langConfigs = entry.value;
      final userFonts = UserFontConfigs();

      for (final fontTypeEntry in langConfigs.entries) {
        final fontType = fontTypeEntry.key;
        final fontPath = fontTypeEntry.value;
        final fileName = fontPath.split(Platform.pathSeparator).last;

        switch (fontType) {
          case 'serif_regular':
            userFonts.serifRegular = FontFile(fontPath, fileName);
            break;
          case 'serif_bold':
            userFonts.serifBold = FontFile(fontPath, fileName);
            break;
          case 'serif_italic':
            userFonts.serifItalic = FontFile(fontPath, fileName);
            break;
          case 'serif_bold_italic':
            userFonts.serifBoldItalic = FontFile(fontPath, fileName);
            break;
          case 'sans_regular':
            userFonts.sansRegular = FontFile(fontPath, fileName);
            break;
          case 'sans_bold':
            userFonts.sansBold = FontFile(fontPath, fileName);
            break;
          case 'sans_italic':
            userFonts.sansItalic = FontFile(fontPath, fileName);
            break;
          case 'sans_bold_italic':
            userFonts.sansBoldItalic = FontFile(fontPath, fileName);
            break;
        }
      }
      result[lang] = userFonts;
    }
    return result;
  }

  Future<Map<String, DetectedFonts>> _scanAllLanguageFonts(
    String basePath,
    List<String> languages,
  ) async {
    final result = <String, DetectedFonts>{};

    for (final lang in languages) {
      final fontDir = Directory('$basePath\\$lang');
      if (await fontDir.exists()) {
        result[lang] = await _scanFontDirectory(fontDir);
      } else {
        result[lang] = DetectedFonts();
      }
    }

    return result;
  }

  Future<DetectedFonts> _scanFontDirectory(Directory dir) async {
    final detected = DetectedFonts();

    try {
      final entities = await dir.list().toList();
      final files = entities.whereType<File>().where((f) {
        final ext = f.path.toLowerCase();
        return ext.endsWith('.ttf') ||
            ext.endsWith('.otf') ||
            ext.endsWith('.woff2');
      });

      for (final file in files) {
        final fileName = file.path.split(Platform.pathSeparator).last;
        final lowerName = fileName.toLowerCase();

        final type = _detectFontType(lowerName);
        if (type != null) {
          if (_categorizeAsSerif(lowerName)) {
            detected.setSerifFont(type, file.path, fileName);
          } else {
            detected.setSansFont(type, file.path, fileName);
          }
        }
      }
    } catch (e) {
      debugPrint('扫描字体目录失败: $e');
    }

    return detected;
  }

  String? _detectFontType(String fileName) {
    final hasBold = fileName.contains('bold');
    final hasItalic = fileName.contains('italic');

    String weight;
    if (hasBold && hasItalic) {
      weight = 'bold_italic';
    } else if (hasBold) {
      weight = 'bold';
    } else if (hasItalic) {
      weight = 'italic';
    } else if (fileName.contains('regular')) {
      weight = 'regular';
    } else {
      weight = 'regular';
    }

    return weight;
  }

  bool _categorizeAsSerif(String fileName) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.contains('sans')) return false;
    return true;
  }

  Future<List<String>> _getAvailableLanguages() async {
    final dictManager = DictionaryManager();
    final allMetadata = await dictManager.getAllDictionariesMetadata();
    final languageSet = <String>{};

    for (final metadata in allMetadata) {
      if (metadata.sourceLanguage.isNotEmpty) {
        final lang = metadata.sourceLanguage.toLowerCase();
        if (_isValidLanguage(lang)) {
          languageSet.add(lang);
        }
      }
      for (final targetLang in metadata.targetLanguages) {
        if (targetLang.isNotEmpty) {
          final lang = targetLang.toLowerCase();
          if (_isValidLanguage(lang)) {
            languageSet.add(lang);
          }
        }
      }
    }

    final languageList = languageSet.toList();
    languageList.sort((a, b) {
      final order = [
        'en',
        'zh',
        'ja',
        'ko',
        'fr',
        'de',
        'es',
        'it',
        'ru',
        'pt',
        'ar',
      ];
      final indexA = order.indexOf(a);
      final indexB = order.indexOf(b);
      if (indexA == -1 && indexB == -1) return a.compareTo(b);
      if (indexA == -1) return 1;
      if (indexB == -1) return -1;
      return indexA.compareTo(indexB);
    });

    return languageList;
  }

  bool _isValidLanguage(String langCode) {
    final validLanguages = [
      'en',
      'zh',
      'ja',
      'ko',
      'fr',
      'de',
      'es',
      'it',
      'ru',
      'pt',
      'ar',
      'text',
    ];
    return validLanguages.contains(langCode.toLowerCase());
  }

  Future<void> _selectFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();

    if (result != null) {
      final dir = Directory(result);
      if (!await dir.exists()) {
        if (mounted) {
          showToast(context, '文件夹不存在');
        }
        return;
      }

      // 获取词典使用的语言集合并创建子文件夹
      final languages = await _getAvailableLanguages();
      await _createLanguageSubfolders(result, languages);

      final prefs = PreferencesService();
      await prefs.setFontFolderPath(result);
      await PreferencesService().clearAllFontConfigs();
      await _loadData(forceRescan: true);

      if (mounted) {
        showToast(context, '字体文件夹已设置，已自动创建语言子文件夹');
      }
    }
  }

  Future<void> _createLanguageSubfolders(
    String basePath,
    List<String> languages,
  ) async {
    try {
      for (final lang in languages) {
        final langDir = Directory('$basePath\\$lang');
        if (!await langDir.exists()) {
          await langDir.create(recursive: true);
          Logger.i('创建语言子文件夹: ${langDir.path}', tag: 'FontLoader');
        }
      }
    } catch (e) {
      // 创建失败时静默处理，不提醒用户
    }
  }

  Future<void> _selectFontFile(
    String language,
    String type,
    bool isSerif,
  ) async {
    if (_fontFolderPath == null || _fontFolderPath!.isEmpty) {
      showToast(context, '请先设置字体文件夹');
      return;
    }

    final fontDir = Directory('$_fontFolderPath\\$language');
    if (!await fontDir.exists()) {
      showToast(context, '语言文件夹不存在: $language');
      return;
    }

    final files = await fontDir.list().where((entity) {
      if (entity is File) {
        final ext = entity.path.toLowerCase();
        return ext.endsWith('.ttf') ||
            ext.endsWith('.otf') ||
            ext.endsWith('.woff2');
      }
      return false;
    }).toList();

    if (files.isEmpty) {
      showToast(context, '语言文件夹 $language 中没有字体文件');
      return;
    }

    final fontFiles = files.map((f) {
      final name = f.path.split(Platform.pathSeparator).last;
      return {'path': f.path, 'name': name};
    }).toList();

    final fullType = '${isSerif ? 'serif' : 'sans'}_$type';

    final selectedFont = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('选择 ${LanguageUtils.getLanguageDisplayName(language)} 字体'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop<Map<String, String>>(context, {}),
            child: const Text('清除自定义字体'),
          ),
          ...fontFiles.map(
            (font) => SimpleDialogOption(
              onPressed: () =>
                  Navigator.pop<Map<String, String>>(context, font),
              child: Text(font['name']!),
            ),
          ),
        ],
      ),
    );

    if (selectedFont != null) {
      final prefs = PreferencesService();
      if (selectedFont.isEmpty) {
        Logger.i(
          '清除字体配置: language=$language, fontType=$fullType',
          tag: 'FontLoader',
        );
        await prefs.clearFontConfig(language: language, fontType: fullType);
      } else {
        await prefs.setFontConfig(
          language: language,
          fontType: fullType,
          fontPath: selectedFont['path']!,
        );
        Logger.i(
          '保存字体配置: language=$language, fontType=$fullType, path=${selectedFont['path']}',
          tag: 'FontLoader',
        );
      }

      // 重新加载字体
      await FontLoaderService().reloadFonts();

      await _loadData(skipAutoSave: true);

      if (mounted) {
        showToast(context, '字体配置已保存');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverAppBar(
                  title: const Text('显示与字体'),
                  pinned: true,
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  surfaceTintColor: Colors.transparent,
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: '刷新字体',
                        onPressed: () async {
                          setState(() => _isLoading = true);
                          await PreferencesService().clearAllFontConfigs();
                          await _loadData(forceRescan: true);
                          await FontLoaderService().reloadFonts();
                          if (mounted) {
                            showToast(context, '字体已刷新');
                          }
                        },
                      ),
                    ),
                  ],
                ),
                SliverToBoxAdapter(
                  child: Card(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: ListTile(
                      leading: const Icon(Icons.zoom_in),
                      title: const Text('词典内容缩放'),
                      subtitle: Text(
                        '${(_dictionaryContentScale * 100).toInt()}%',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _showDictionaryContentScaleDialog,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Card(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: const Text('字体文件夹'),
                      subtitle: Text(
                        _fontFolderPath ?? '未设置',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _fontFolderPath == null
                              ? Theme.of(context).colorScheme.outline
                              : null,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: _selectFolder,
                        tooltip: _fontFolderPath == null ? '设置' : '修改',
                      ),
                    ),
                  ),
                ),
                if (_languages.isNotEmpty && _tabController != null) ...[
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _SliverTabBarDelegate(
                      TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        tabs: _languages
                            .map(
                              (lang) => Tab(
                                text: LanguageUtils.getLanguageDisplayName(
                                  lang,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      Theme.of(context).scaffoldBackgroundColor,
                    ),
                  ),
                  // 使用 SliverList 来显示当前选中的 tab 内容
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 800),
                          child: _buildLanguageTabContent(
                            _languages[_tabController!.index],
                          ),
                        ),
                      );
                    }, childCount: 1),
                  ),
                ] else if (!_isLoading)
                  const SliverFillRemaining(
                    child: Center(child: Text('未找到包含语言信息的词典')),
                  ),
              ],
            ),
    );
  }

  Widget _buildLanguageTabContent(String language) {
    final detected = _detectedFonts[language] ?? DetectedFonts();
    final userConfigs = _userFontConfigs[language] ?? UserFontConfigs();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildFontCategorySection(
            '无衬线字体',
            Icons.text_format,
            detected.sans,
            userConfigs,
            language,
            isSerif: false,
          ),
          const SizedBox(height: 16),
          _buildFontCategorySection(
            '衬线字体',
            Icons.format_textdirection_l_to_r,
            detected.serif,
            userConfigs,
            language,
            isSerif: true,
          ),
        ],
      ),
    );
  }

  Widget _buildFontCategorySection(
    String title,
    IconData icon,
    FontTypeFonts fonts,
    UserFontConfigs userFonts,
    String language, {
    required bool isSerif,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final fontScale = _fontScales[language]?[isSerif ? 'serif' : 'sans'] ?? 1.0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                _buildFontScaleControl(language, isSerif, fontScale),
              ],
            ),
            const SizedBox(height: 16),
            if (isSerif) ...[
              _buildFontStatusRow(
                'regular',
                '常规',
                userFonts.serifRegular,
                language: language,
                isSerif: isSerif,
              ),
              const SizedBox(height: 8),
              _buildFontStatusRow(
                'bold',
                '粗体',
                userFonts.serifBold,
                language: language,
                isSerif: isSerif,
              ),
              const SizedBox(height: 8),
              _buildFontStatusRow(
                'italic',
                '斜体',
                userFonts.serifItalic,
                language: language,
                isSerif: isSerif,
              ),
              const SizedBox(height: 8),
              _buildFontStatusRow(
                'bold_italic',
                '粗斜体',
                userFonts.serifBoldItalic,
                language: language,
                isSerif: isSerif,
              ),
            ] else ...[
              _buildFontStatusRow(
                'regular',
                '常规',
                userFonts.sansRegular,
                language: language,
                isSerif: isSerif,
              ),
              const SizedBox(height: 8),
              _buildFontStatusRow(
                'bold',
                '粗体',
                userFonts.sansBold,
                language: language,
                isSerif: isSerif,
              ),
              const SizedBox(height: 8),
              _buildFontStatusRow(
                'italic',
                '斜体',
                userFonts.sansItalic,
                language: language,
                isSerif: isSerif,
              ),
              const SizedBox(height: 8),
              _buildFontStatusRow(
                'bold_italic',
                '粗斜体',
                userFonts.sansBoldItalic,
                language: language,
                isSerif: isSerif,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFontScaleControl(
    String language,
    bool isSerif,
    double currentScale,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.text_fields, size: 16, color: colorScheme.outline),
        const SizedBox(width: 4),
        InkWell(
          onTap: () => _showFontScaleDialog(language, isSerif, currentScale),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${(currentScale * 100).round()}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showFontScaleDialog(
    String language,
    bool isSerif,
    double currentScale,
  ) async {
    await showDialog(
      context: context,
      builder: (context) {
        return ScaleDialogWidget(
          title: '${isSerif ? '衬线字体' : '无衬线字体'}缩放倍率',
          subtitle: '仅用于调整不同字体的尺寸一致性',
          currentValue: (currentScale * 100).round().toDouble(),
          min: 75,
          max: 150,
          divisions: 5,
          unit: '%',
          onSave: (value) async {
            final prefs = PreferencesService();
            await prefs.setFontScale(language, isSerif, value / 100);
            // 刷新 FontLoaderService 中的字体缩放缓存
            await FontLoaderService().reloadFontScales();
            if (mounted) {
              setState(() {
                _fontScales[language] ??= {};
                _fontScales[language]![isSerif ? 'serif' : 'sans'] =
                    value / 100;
              });
            }
          },
        );
      },
    );
  }

  Future<void> _showDictionaryContentScaleDialog() async {
    await showDialog(
      context: context,
      builder: (context) {
        return ScaleDialogWidget(
          title: '词典内容缩放',
          subtitle: '这是调整词典内容缩放的主要入口',
          currentValue: (_dictionaryContentScale * 100).round().toDouble(),
          min: 50,
          max: 200,
          divisions: 5,
          unit: '%',
          onSave: (value) async {
            final prefs = PreferencesService();
            await prefs.setDictionaryContentScale(value / 100);
            // 刷新 FontLoaderService 中的词典内容缩放缓存
            await FontLoaderService().reloadDictionaryContentScale();
            if (mounted) {
              setState(() {
                _dictionaryContentScale = value / 100;
              });
            }
          },
        );
      },
    );
  }

  Widget _buildFontStatusRow(
    String type,
    String label,
    FontFile? fontFile, {
    required String language,
    required bool isSerif,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final exists = fontFile != null;

    return InkWell(
      onTap: () => _selectFontFile(language, type, isSerif),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: exists
              ? colorScheme.primaryContainer.withValues(alpha: 0.3)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: exists
                ? colorScheme.primary.withValues(alpha: 0.3)
                : colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              exists ? Icons.check_circle : Icons.cancel_outlined,
              size: 18,
              color: exists ? colorScheme.primary : colorScheme.outline,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: exists ? colorScheme.onSurface : colorScheme.outline,
              ),
            ),
            const Spacer(),
            if (exists) ...[
              Expanded(
                child: Text(
                  fontFile.fileName,
                  style: TextStyle(fontSize: 12, color: colorScheme.primary),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ] else
              Text(
                '未配置',
                style: TextStyle(fontSize: 12, color: colorScheme.outline),
              ),
          ],
        ),
      ),
    );
  }
}

class ScaleDialogWidget extends StatefulWidget {
  final String title;
  final String? subtitle;
  final double currentValue;
  final double min;
  final double max;
  final int divisions;
  final String unit;
  final Future<void> Function(double) onSave;

  const ScaleDialogWidget({
    super.key,
    required this.title,
    this.subtitle,
    required this.currentValue,
    required this.min,
    required this.max,
    required this.divisions,
    required this.unit,
    required this.onSave,
  });

  @override
  State<ScaleDialogWidget> createState() => _ScaleDialogWidgetState();
}

class _ScaleDialogWidgetState extends State<ScaleDialogWidget> {
  late double _value;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _value = widget.currentValue;
    _controller = TextEditingController(text: _formatValue(_value));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatValue(double value) {
    if (widget.unit == '%') {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(1);
  }

  double _parseValue(String text) {
    // 移除可能的 % 符号和空白字符
    final cleanText = text.replaceAll('%', '').trim();
    final parsed = double.tryParse(cleanText);
    if (parsed != null) {
      if (widget.unit == '%') {
        if (parsed >= widget.min && parsed <= widget.max) {
          return parsed;
        }
      } else {
        if (parsed >= widget.min && parsed <= widget.max) {
          return parsed;
        }
      }
    }
    return _value;
  }

  @override
  Widget build(BuildContext context) {
    final isPercentage = widget.unit == '%';

    return AlertDialog(
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.subtitle!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                isPercentage
                    ? '${widget.min.toInt()}%'
                    : widget.min.toStringAsFixed(1),
              ),
              Expanded(
                child: Slider(
                  value: _value.clamp(widget.min, widget.max),
                  min: widget.min,
                  max: widget.max,
                  divisions: ((widget.max - widget.min) / widget.divisions)
                      .round(),
                  label: _formatValue(_value),
                  onChanged: (value) {
                    setState(() {
                      _value = value;
                      _controller.text = _formatValue(value);
                    });
                  },
                ),
              ),
              Text(
                isPercentage
                    ? '${widget.max.toInt()}%'
                    : widget.max.toStringAsFixed(1),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('当前数值: '),
              SizedBox(
                width: 80,
                child: TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    suffixText: widget.unit,
                  ),
                  keyboardType: TextInputType.number,
                  controller: _controller,
                  onChanged: (value) {
                    // 实时更新 _value，确保保存时能获取最新值
                    final parsed = _parseValue(value);
                    if (parsed != _value) {
                      setState(() {
                        _value = parsed;
                      });
                    }
                  },
                  onSubmitted: (value) {
                    setState(() {
                      _value = _parseValue(value);
                      _controller.text = _formatValue(_value);
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () async {
            // 保存前先从控制器同步最新值（用户可能输入后未按回车）
            final latestValue = _parseValue(_controller.text);
            await widget.onSave(latestValue);
            if (context.mounted) {
              Navigator.pop(context);
            }
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color backgroundColor;

  _SliverTabBarDelegate(this.tabBar, this.backgroundColor);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: backgroundColor, child: tabBar);
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar ||
        backgroundColor != oldDelegate.backgroundColor;
  }
}

class DetectedFonts {
  FontTypeFonts serif = FontTypeFonts();
  FontTypeFonts sans = FontTypeFonts();

  void setSerifFont(String type, String path, String fileName) {
    _setFont(serif, type, path, fileName);
  }

  void setSansFont(String type, String path, String fileName) {
    _setFont(sans, type, path, fileName);
  }

  void _setFont(
    FontTypeFonts fonts,
    String type,
    String path,
    String fileName,
  ) {
    switch (type) {
      case 'regular':
        fonts.regular = FontFile(path, fileName);
        break;
      case 'bold':
        fonts.bold = FontFile(path, fileName);
        break;
      case 'italic':
        fonts.italic = FontFile(path, fileName);
        break;
      case 'bold_italic':
        fonts.boldItalic = FontFile(path, fileName);
        break;
    }
  }
}

class FontTypeFonts {
  FontFile? regular;
  FontFile? bold;
  FontFile? italic;
  FontFile? boldItalic;
}

class FontFile {
  final String path;
  final String fileName;

  FontFile(this.path, this.fileName);
}

class UserFontConfigs {
  FontFile? serifRegular;
  FontFile? serifBold;
  FontFile? serifItalic;
  FontFile? serifBoldItalic;
  FontFile? sansRegular;
  FontFile? sansBold;
  FontFile? sansItalic;
  FontFile? sansBoldItalic;
}
