///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

part of 'strings.g.dart';

// Path: <root>
typedef TranslationsZh = Translations; // ignore: unused_element
class Translations with BaseTranslations<AppLocale, Translations> {
	/// Returns the current translations of the given [context].
	///
	/// Usage:
	/// final t = Translations.of(context);
	static Translations of(BuildContext context) => InheritedLocaleData.of<AppLocale, Translations>(context).translations;

	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	Translations({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.zh,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <zh>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	dynamic operator[](String key) => $meta.getTranslation(key);

	late final Translations _root = this; // ignore: unused_field

	Translations $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => Translations(meta: meta ?? this.$meta);

	// Translations
	late final TranslationsNavZh nav = TranslationsNavZh.internal(_root);
	late final TranslationsLanguageZh language = TranslationsLanguageZh.internal(_root);
	late final TranslationsCommonZh common = TranslationsCommonZh.internal(_root);
	late final TranslationsSettingsZh settings = TranslationsSettingsZh.internal(_root);
	late final TranslationsSearchZh search = TranslationsSearchZh.internal(_root);
	late final TranslationsWordBankZh wordBank = TranslationsWordBankZh.internal(_root);
	late final TranslationsThemeZh theme = TranslationsThemeZh.internal(_root);
	late final TranslationsHelpZh help = TranslationsHelpZh.internal(_root);
	late final TranslationsLangNamesZh langNames = TranslationsLangNamesZh.internal(_root);
	late final TranslationsFontZh font = TranslationsFontZh.internal(_root);
	late final TranslationsAiZh ai = TranslationsAiZh.internal(_root);
	late final TranslationsCloudZh cloud = TranslationsCloudZh.internal(_root);
	late final TranslationsDictZh dict = TranslationsDictZh.internal(_root);
	late final TranslationsEntryZh entry = TranslationsEntryZh.internal(_root);
}

// Path: nav
class TranslationsNavZh {
	TranslationsNavZh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '查词'
	String get search => '查词';

	/// zh: '单词本'
	String get wordBank => '单词本';

	/// zh: '设置'
	String get settings => '设置';
}

// Path: language
class TranslationsLanguageZh {
	TranslationsLanguageZh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '跟随系统'
	String get auto => '跟随系统';

	/// zh: '中文'
	String get zh => '中文';

	/// zh: 'English'
	String get en => 'English';

	/// zh: '应用语言'
	String get dialogTitle => '应用语言';

	/// zh: '选择界面显示语言'
	String get dialogSubtitle => '选择界面显示语言';
}

// Path: common
class TranslationsCommonZh {
	TranslationsCommonZh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '确定'
	String get ok => '确定';

	/// zh: '取消'
	String get cancel => '取消';

	/// zh: '保存'
	String get save => '保存';

	/// zh: '确认'
	String get confirm => '确认';

	/// zh: '撤销'
	String get undo => '撤销';

	/// zh: '删除'
	String get delete => '删除';

	/// zh: '清除'
	String get clear => '清除';

	/// zh: '重置'
	String get reset => '重置';

	/// zh: '关闭'
	String get close => '关闭';

	/// zh: '返回'
	String get back => '返回';

	/// zh: '加载中...'
	String get loading => '加载中...';

	/// zh: '暂无数据'
	String get noData => '暂无数据';

	/// zh: '完成'
	String get done => '完成';

	/// zh: '重命名'
	String get rename => '重命名';

	/// zh: '导入'
	String get import => '导入';

	/// zh: '全部'
	String get all => '全部';

	/// zh: '警告'
	String get warning => '警告';

	/// zh: '此操作不可恢复'
	String get irreversible => '此操作不可恢复';

	/// zh: '重试'
	String get retry => '重试';

	/// zh: '退出'
	String get logout => '退出';

	/// zh: '登录'
	String get login => '登录';

	/// zh: '注册'
	String get register => '注册';

	/// zh: '复制'
	String get copy => '复制';

	/// zh: '继续'
	String get continue_ => '继续';

	/// zh: '设置'
	String get set_ => '设置';

	/// zh: '修改'
	String get change => '修改';

	/// zh: '更新'
	String get update => '更新';

	/// zh: '下载'
	String get download => '下载';

	/// zh: '上传'
	String get upload => '上传';

	/// zh: '暂无内容'
	String get noContent => '暂无内容';

	/// zh: '错误'
	String get error => '错误';

	/// zh: '成功'
	String get success => '成功';

	/// zh: '测试中...'
	String get testing => '测试中...';

	/// zh: '测试连接'
	String get testConnection => '测试连接';

	/// zh: '保存配置'
	String get saveConfig => '保存配置';

	/// zh: '未知'
	String get unknown => '未知';

	/// zh: '全屏'
	String get fullscreen => '全屏';

	/// zh: '退出全屏'
	String get exitFullscreen => '退出全屏';

	/// zh: '请稍后重试'
	String get retryLater => '请稍后重试';

	/// zh: '暂不'
	String get notNow => '暂不';

	/// zh: '不再提示'
	String get neverAskAgain => '不再提示';

	/// zh: '重做'
	String get redo => '重做';

	/// zh: '选择语言'
	String get selectLanguage => '选择语言';
}

// Path: settings
class TranslationsSettingsZh {
	TranslationsSettingsZh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '设置'
	String get title => '设置';

	/// zh: '云服务'
	String get cloudService => '云服务';

	/// zh: '词典管理'
	String get dictionaryManager => '词典管理';

	/// zh: 'AI 配置'
	String get aiConfig => 'AI 配置';

	/// zh: '字体配置'
	String get fontConfig => '字体配置';

	/// zh: '主题设置'
	String get themeSettings => '主题设置';

	/// zh: '软件布局缩放'
	String get layoutScale => '软件布局缩放';

	/// zh: '点击动作设置'
	String get clickAction => '点击动作设置';

	/// zh: '底部工具栏设置'
	String get toolbar => '底部工具栏设置';

	/// zh: '其他设置'
	String get misc => '其他设置';

	/// zh: '关于软件'
	String get about => '关于软件';

	/// zh: '应用语言'
	String get appLanguage => '应用语言';

	late final TranslationsSettingsScaleDialogZh scaleDialog = TranslationsSettingsScaleDialogZh.internal(_root);
	late final TranslationsSettingsClickActionDialogZh clickActionDialog = TranslationsSettingsClickActionDialogZh.internal(_root);
	late final TranslationsSettingsToolbarDialogZh toolbarDialog = TranslationsSettingsToolbarDialogZh.internal(_root);
	late final TranslationsSettingsMiscPageZh misc_page = TranslationsSettingsMiscPageZh.internal(_root);
	late final TranslationsSettingsActionLabelZh actionLabel = TranslationsSettingsActionLabelZh.internal(_root);
}

// Path: search
class TranslationsSearchZh {
	TranslationsSearchZh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '输入单词'
	String get hint => '输入单词';

	/// zh: '搜索单词本'
	String get hintWordBank => '搜索单词本';

	/// zh: '未找到单词: {word}'
	String noResult({required Object word}) => '未找到单词: ${word}';

	/// zh: '输入单词开始查询'
	String get startHint => '输入单词开始查询';

	/// zh: '历史记录'
	String get historyTitle => '历史记录';

	/// zh: '清除'
	String get historyClear => '清除';

	/// zh: '历史记录已清除'
	String get historyCleared => '历史记录已清除';

	/// zh: '已删除 "{word}"'
	String historyDeleted({required Object word}) => '已删除 "${word}"';

	/// zh: '通配符模式下请从候选词列表中选择词条'
	String get wildcardNoEntry => '通配符模式下请从候选词列表中选择词条';

	/// zh: '高级选项'
	String get advancedOptions => '高级选项';

	/// zh: '查询'
	String get searchBtn => '查询';

	/// zh: '搜索选项'
	String get searchOptionsTitle => '搜索选项';

	/// zh: '精确搜索'
	String get exactMatch => '精确搜索';

	/// zh: '简繁区分'
	String get toneExact => '简繁区分';

	/// zh: '读音候选词'
	String get phoneticCandidates => '读音候选词';

	/// zh: '搜索结果'
	String get searchResults => '搜索结果';

	/// zh: '当前没有已启用的词典'
	String get noEnabledDicts => '当前没有已启用的词典';

	/// zh: 'LIKE 模式（输入含 % 或 _）： % 匹配任意个字符，_ 匹配恰好一个字符 例：hel% → hello、help；%字 → 汉字、生字；h_llo → hello、hallo GLOB 模式（输入含 * ? [ ] ^），区分大小写： * 匹配任意个字符，? 匹配单个字符 [abc] 匹配括号内任一字符，[^abc] 排除括号内字符 例：h?llo → hello、hallo；[aeiou]* → 所有元音字母开头的词'
	String get wildcardHint => 'LIKE 模式（输入含 % 或 _）：\n  % 匹配任意个字符，_ 匹配恰好一个字符\n  例：hel% → hello、help；%字 → 汉字、生字；h_llo → hello、hallo\n\nGLOB 模式（输入含 * ? [ ] ^），区分大小写：\n  * 匹配任意个字符，? 匹配单个字符\n  [abc] 匹配括号内任一字符，[^abc] 排除括号内字符\n  例：h?llo → hello、hallo；[aeiou]* → 所有元音字母开头的词';

	/// zh: '下载完成，搜索 "{word}" 以测试功能'
	String dbDownloaded({required Object word}) => '下载完成，搜索 "${word}" 以测试功能';
}

// Path: wordBank
class TranslationsWordBankZh {
	TranslationsWordBankZh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '单词本'
	String get title => '单词本';

	/// zh: '单词本还是空的'
	String get empty => '单词本还是空的';

	/// zh: '在查词时点击收藏按钮添加单词'
	String get emptyHint => '在查词时点击收藏按钮添加单词';

	/// zh: '没有找到单词'
	String get noWordsFound => '没有找到单词';

	/// zh: '未找到单词: {word}'
	String wordNotFound({required Object word}) => '未找到单词: ${word}';

	/// zh: '已移除单词'
	String get wordRemoved => '已移除单词';

	/// zh: '已更新词表归属'
	String get wordListUpdated => '已更新词表归属';

	/// zh: '管理词表'
	String get manageLists => '管理词表';

	/// zh: '排序方式'
	String get sortTooltip => '排序方式';

	/// zh: '添加顺序'
	String get sortAddTimeDesc => '添加顺序';

	/// zh: '字母顺序'
	String get sortAlphabetical => '字母顺序';

	/// zh: '随机排序'
	String get sortRandom => '随机排序';

	/// zh: '导入到 {language}'
	String importToLanguage({required Object language}) => '导入到 ${language}';

	/// zh: '词表名称：'
	String get listNameLabel => '词表名称：';

	/// zh: '例如：托福、雅思、GRE'
	String get listNameHint => '例如：托福、雅思、GRE';

	/// zh: '选择文件'
	String get pickFile => '选择文件';

	/// zh: '预览10个单词：'
	String get previewWords => '预览10个单词：';

	/// zh: '共识别到 {count} 个单词预览'
	String previewCount({required Object count}) => '共识别到 ${count} 个单词预览';

	/// zh: '成功导入 {count} 个单词到 "{list}"'
	String importSuccess({required Object count, required Object list}) => '成功导入 ${count} 个单词到 "${list}"';

	/// zh: '导入失败'
	String get importFailed => '导入失败';

	/// zh: '词表 "{list}" 已存在，请使用其他名称'
	String importListExists({required Object list}) => '词表 "${list}" 已存在，请使用其他名称';

	/// zh: '文件读取失败'
	String get importFileError => '文件读取失败';

	/// zh: '编辑 {language} 词表'
	String editListsTitle({required Object language}) => '编辑 ${language} 词表';

	/// zh: '重命名词表'
	String get renameList => '重命名词表';

	/// zh: '词表名称'
	String get listNameFieldLabel => '词表名称';

	/// zh: '输入新名称'
	String get listNameFieldHint => '输入新名称';

	/// zh: '删除词表'
	String get deleteList => '删除词表';

	/// zh: '确定要删除词表 "{name}" 吗？ 这将删除该词表及其所有数据。如果一个单词不属于任何其他词表，也会被删除。'
	String deleteListConfirm({required Object name}) => '确定要删除词表 "${name}" 吗？\n\n这将删除该词表及其所有数据。如果一个单词不属于任何其他词表，也会被删除。';

	/// zh: '导入词表'
	String get importListBtn => '导入词表';

	/// zh: '词表已更新'
	String get listSaved => '词表已更新';

	/// zh: '操作失败'
	String get listOpFailed => '操作失败';

	/// zh: '词表名称已存在，请使用其他名称'
	String get listNameExists => '词表名称已存在，请使用其他名称';

	/// zh: '选择词表'
	String get selectLists => '选择词表';

	/// zh: '调整"{word}"的词表'
	String adjustLists({required Object word}) => '调整"${word}"的词表';

	/// zh: '新建词表...'
	String get newListHint => '新建词表...';

	/// zh: '从单词本移除'
	String get removeWord => '从单词本移除';
}

// Path: theme
class TranslationsThemeZh {
	TranslationsThemeZh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '主题设置'
	String get title => '主题设置';

	/// zh: '浅色'
	String get light => '浅色';

	/// zh: '深色'
	String get dark => '深色';

	/// zh: '跟随系统'
	String get system => '跟随系统';

	/// zh: '主题色'
	String get seedColor => '主题色';

	/// zh: '系统主题色'
	String get systemAccent => '系统主题色';

	/// zh: '自定义'
	String get custom => '自定义';

	/// zh: '外观模式'
	String get appearanceMode => '外观模式';

	/// zh: '主题颜色'
	String get themeColor => '主题颜色';

	/// zh: '预览效果'
	String get preview => '预览效果';

	/// zh: '跟随系统'
	String get followSystem => '跟随系统';

	/// zh: '浅色模式'
	String get lightMode => '浅色模式';

	/// zh: '深色模式'
	String get darkMode => '深色模式';

	/// zh: '这是一段示例文字，展示应用的主题效果预览。'
	String get previewText => '这是一段示例文字，展示应用的主题效果预览。';

	/// zh: '主色'
	String get primaryColor => '主色';

	/// zh: '主容器'
	String get primaryContainer => '主容器';

	/// zh: '辅色'
	String get secondary => '辅色';

	/// zh: '强调'
	String get tertiary => '强调';

	/// zh: '背景'
	String get surface => '背景';

	/// zh: '卡片'
	String get card => '卡片';

	/// zh: '错误'
	String get error => '错误';

	/// zh: '边框'
	String get outline => '边框';

	late final TranslationsThemeColorNamesZh colorNames = TranslationsThemeColorNamesZh.internal(_root);
}

// Path: help
class TranslationsHelpZh {
	TranslationsHelpZh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '关于软件'
	String get title => '关于软件';

	/// zh: '查词，不折腾'
	String get tagline => '查词，不折腾';

	/// zh: '词典反馈'
	String get forumTitle => '词典反馈';

	/// zh: '欢迎提出改进建议'
	String get forumSubtitle => '欢迎提出改进建议';

	/// zh: '查看源码、提交 Issue'
	String get githubSubtitle => '查看源码、提交 Issue';

	/// zh: '爱发电'
	String get afdianTitle => '爱发电';

	/// zh: '支持开发者'
	String get afdianSubtitle => '支持开发者';

	/// zh: '检查更新'
	String get checkUpdate => '检查更新';

	/// zh: '正在检查…'
	String get checking => '正在检查…';

	/// zh: '发现新版本 {version} · 点击前往 GitHub 下载'
	String updateAvailable({required Object version}) => '发现新版本 ${version} · 点击前往 GitHub 下载';

	/// zh: '已是最新版本 {version}'
	String upToDate({required Object version}) => '已是最新版本 ${version}';

	/// zh: '当前版本 {version}'
	String currentVersion({required Object version}) => '当前版本 ${version}';

	/// zh: '检查失败，点击重试'
	String get updateError => '检查失败，点击重试';

	/// zh: 'GitHub API 错误 (状态码 {code})'
	String githubApiError({required Object code}) => 'GitHub API 错误 (状态码 ${code})';

	/// zh: '检查更新失败: {error}'
	String checkUpdateError({required Object error}) => '检查更新失败: ${error}';
}

// Path: langNames
class TranslationsLangNamesZh {
	TranslationsLangNamesZh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '中文'
	String get zh => '中文';

	/// zh: '日语'
	String get ja => '日语';

	/// zh: '韩语'
	String get ko => '韩语';

	/// zh: '英语'
	String get en => '英语';

	/// zh: '法语'
	String get fr => '法语';

	/// zh: '德语'
	String get de => '德语';

	/// zh: '西班牙语'
	String get es => '西班牙语';

	/// zh: '意大利语'
	String get it => '意大利语';

	/// zh: '俄语'
	String get ru => '俄语';

	/// zh: '葡萄牙语'
	String get pt => '葡萄牙语';

	/// zh: '阿拉伯语'
	String get ar => '阿拉伯语';

	/// zh: '文本'
	String get text => '文本';

	/// zh: '自动'
	String get auto => '自动';

	/// zh: '中文（简体）'
	String get zhHans => '中文（简体）';

	/// zh: '中文（繁体）'
	String get zhHant => '中文（繁体）';
}

// Path: font
class TranslationsFontZh {
	TranslationsFontZh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '字体配置'
	String get title => '字体配置';

	/// zh: '字体文件夹'
	String get folderLabel => '字体文件夹';

	/// zh: '未设置'
	String get folderNotSet => '未设置';

	/// zh: '设置'
	String get folderSet => '设置';

	/// zh: '修改'
	String get folderChange => '修改';

	/// zh: '刷新字体'
	String get refreshTooltip => '刷新字体';

	/// zh: '字体已刷新'
	String get refreshSuccess => '字体已刷新';

	/// zh: '未找到包含语言信息的词典'
	String get noDicts => '未找到包含语言信息的词典';

	/// zh: '无衬线字体'
	String get sansSerif => '无衬线字体';

	/// zh: '衬线字体'
	String get serif => '衬线字体';

	/// zh: '常规'
	String get regular => '常规';

	/// zh: '粗体'
	String get bold => '粗体';

	/// zh: '斜体'
	String get italic => '斜体';

	/// zh: '粗斜体'
	String get boldItalic => '粗斜体';

	/// zh: '未配置'
	String get notConfigured => '未配置';

	/// zh: '选择 {language} 字体'
	String selectFont({required Object language}) => '选择 ${language} 字体';

	/// zh: '清除自定义字体'
	String get clearFont => '清除自定义字体';

	/// zh: '字体配置已保存'
	String get fontSaved => '字体配置已保存';

	/// zh: '请先设置字体文件夹'
	String get setFolderFirst => '请先设置字体文件夹';

	/// zh: '语言文件夹不存在: {lang}'
	String folderNotExist({required Object lang}) => '语言文件夹不存在: ${lang}';

	/// zh: '语言文件夹 {lang} 中没有字体文件'
	String noFontFiles({required Object lang}) => '语言文件夹 ${lang} 中没有字体文件';

	/// zh: '文件夹不存在'
	String get folderDoesNotExist => '文件夹不存在';

	/// zh: '字体文件夹已设置，已自动创建语言子文件夹'
	String get folderSetSuccess => '字体文件夹已设置，已自动创建语言子文件夹';

	/// zh: '{type}缩放倍率'
	String scaleDialogTitle({required Object type}) => '${type}缩放倍率';

	/// zh: '仅用于调整不同字体的尺寸一致性'
	String get scaleDialogSubtitle => '仅用于调整不同字体的尺寸一致性';

	/// zh: '100'
	String get resetValue => '100';
}

// Path: ai
class TranslationsAiZh {
	TranslationsAiZh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: 'AI配置'
	String get title => 'AI配置';

	/// zh: '快速模型'
	String get tabFast => '快速模型';

	/// zh: '标准模型'
	String get tabStandard => '标准模型';

	/// zh: '音频模型'
	String get tabAudio => '音频模型';

	/// zh: '快速模型'
	String get fastModel => '快速模型';

	/// zh: '适用于日常查询，速度优先'
	String get fastModelSubtitle => '适用于日常查询，速度优先';

	/// zh: '标准模型'
	String get standardModel => '标准模型';

	/// zh: '适用于高质量翻译和解释'
	String get standardModelSubtitle => '适用于高质量翻译和解释';

	/// zh: '选择服务商'
	String get providerLabel => '选择服务商';

	/// zh: '模型'
	String get modelLabel => '模型';

	/// zh: '请输入模型名称'
	String get modelRequired => '请输入模型名称';

	/// zh: 'Base URL (可选)'
	String get baseUrlLabel => 'Base URL (可选)';

	/// zh: '留空使用默认地址'
	String get baseUrlHint => '留空使用默认地址';

	/// zh: '仅在使用自定义端点或代理时需要修改url'
	String get baseUrlNote => '仅在使用自定义端点或代理时需要修改url';

	/// zh: '请输入API Key'
	String get apiKeyRequired => '请输入API Key';

	/// zh: '默认模型: {model}'
	String defaultModel({required Object model}) => '默认模型: ${model}';

	/// zh: '深度思考'
	String get deepThinkingTitle => '深度思考';

	/// zh: '在支持的模型上开启思考链（CoT）输出，可显示思考过程'
	String get deepThinkingSubtitle => '在支持的模型上开启思考链（CoT）输出，可显示思考过程';

	/// zh: '配置已保存'
	String get configSaved => '配置已保存';

	/// zh: 'API 连接成功！响应正常'
	String get testSuccess => 'API 连接成功！响应正常';

	/// zh: 'API 错误: {message}'
	String testError({required Object message}) => 'API 错误: ${message}';

	/// zh: '连接超时，请检查网络或 Base URL'
	String get testTimeout => '连接超时，请检查网络或 Base URL';

	/// zh: '连接失败: {message}'
	String testFailed({required Object message}) => '连接失败: ${message}';

	/// zh: '请先输入 API Key'
	String get testApiKeyRequired => '请先输入 API Key';

	/// zh: '测试失败: {error}'
	String testFailedWithError({required Object error}) => '测试失败: ${error}';

	/// zh: 'TTS 配置已保存，请在发音时测试'
	String get ttsSaved => 'TTS 配置已保存，请在发音时测试';

	/// zh: '配置文本转语音服务，用于词典发音功能'
	String get ttsTitle => '配置文本转语音服务，用于词典发音功能';

	/// zh: '留空使用: https://texttospeech.googleapis.com/v1'
	String get ttsBaseUrlHintGoogle => '留空使用: https://texttospeech.googleapis.com/v1';

	/// zh: 'Edge TTS 是微软 Edge 浏览器的语音合成服务，无需配置即可使用'
	String get ttsEdgeNote => 'Edge TTS 是微软 Edge 浏览器的语音合成服务，无需配置即可使用';

	/// zh: '语言音色设置'
	String get ttsVoiceSettings => '语言音色设置';

	/// zh: '为每种语言设置发音音色，词典发音时将根据语言自动选择对应音色'
	String get ttsVoiceSettingsSubtitle => '为每种语言设置发音音色，词典发音时将根据语言自动选择对应音色';

	/// zh: '无可用音色'
	String get ttsNoVoice => '无可用音色';

	/// zh: '使用 Azure Speech Service 获取 API Key'
	String get ttsAzureNote => '使用 Azure Speech Service 获取 API Key';

	/// zh: '使用 Google Cloud Service Account JSON Key 访问 https://console.cloud.google.com/apis/credentials 创建'
	String get ttsGoogleNote => '使用 Google Cloud Service Account JSON Key\n访问 https://console.cloud.google.com/apis/credentials 创建';

	/// zh: 'Moonshot（月之暗面）'
	String get providerMoonshot => 'Moonshot（月之暗面）';

	/// zh: '智谱AI'
	String get providerZhipu => '智谱AI';

	/// zh: '阿里云（DashScope）'
	String get providerAli => '阿里云（DashScope）';

	/// zh: '自定义'
	String get providerCustom => '自定义';
}

// Path: cloud
class TranslationsCloudZh {
	TranslationsCloudZh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '云服务'
	String get title => '云服务';

	/// zh: '在线订阅地址'
	String get subscriptionLabel => '在线订阅地址';

	/// zh: '请输入词典订阅网址'
	String get subscriptionHint => '请输入词典订阅网址';

	/// zh: '保存'
	String get subscriptionSaveTooltip => '保存';

	/// zh: '在线订阅地址已保存'
	String get subscriptionSaved => '在线订阅地址已保存';

	/// zh: '订阅地址已变更，已退出当前账号'
	String get subscriptionChanged => '订阅地址已变更，已退出当前账号';

	/// zh: '设置订阅地址后可查看和下载在线词典'
	String get subscriptionHint2 => '设置订阅地址后可查看和下载在线词典';

	/// zh: '账户管理'
	String get accountTitle => '账户管理';

	/// zh: '登录'
	String get loginBtn => '登录';

	/// zh: '注册'
	String get registerBtn => '注册';

	/// zh: '退出'
	String get logoutBtn => '退出';

	/// zh: '登录'
	String get loginDialogTitle => '登录';

	/// zh: '用户名或邮箱'
	String get usernameOrEmail => '用户名或邮箱';

	/// zh: '密码'
	String get passwordLabel => '密码';

	/// zh: '注册'
	String get registerDialogTitle => '注册';

	/// zh: '用户名'
	String get usernameLabel => '用户名';

	/// zh: '邮箱'
	String get emailLabel => '邮箱';

	/// zh: '确认密码'
	String get confirmPasswordLabel => '确认密码';

	/// zh: '登录成功'
	String get loginSuccess => '登录成功';

	/// zh: '登录失败'
	String get loginFailed => '登录失败';

	/// zh: '请输入用户名/邮箱和密码'
	String get loginRequired => '请输入用户名/邮箱和密码';

	/// zh: '注册成功'
	String get registerSuccess => '注册成功';

	/// zh: '注册失败'
	String get registerFailed => '注册失败';

	/// zh: '请输入邮箱、用户名和密码'
	String get registerRequired => '请输入邮箱、用户名和密码';

	/// zh: '请输入用户名'
	String get registerUsernameRequired => '请输入用户名';

	/// zh: '两次输入的密码不一致'
	String get registerPasswordMismatch => '两次输入的密码不一致';

	/// zh: '已退出登录'
	String get loggedOut => '已退出登录';

	/// zh: '请求超时，请检查网络连接'
	String get requestTimeout => '请求超时，请检查网络连接';

	/// zh: '注册失败: {error}'
	String registerFailedError({required Object error}) => '注册失败: ${error}';

	/// zh: '登录失败: {error}'
	String loginFailedError({required Object error}) => '登录失败: ${error}';

	/// zh: '同步到云端'
	String get syncToCloud => '同步到云端';

	/// zh: '将本地设置上传到云端'
	String get syncToCloudSubtitle => '将本地设置上传到云端';

	/// zh: '从云端同步'
	String get syncFromCloud => '从云端同步';

	/// zh: '从云端下载设置到本地'
	String get syncFromCloudSubtitle => '从云端下载设置到本地';

	/// zh: '上传设置'
	String get uploadTitle => '上传设置';

	/// zh: '确定要将本地设置上传到云端吗？这将覆盖云端的设置数据。'
	String get uploadConfirm => '确定要将本地设置上传到云端吗？这将覆盖云端的设置数据。';

	/// zh: '设置已上传到云端'
	String get uploadSuccess => '设置已上传到云端';

	/// zh: '上传失败'
	String get uploadFailed => '上传失败';

	/// zh: '创建设置包失败'
	String get createPackageFailed => '创建设置包失败';

	/// zh: '上传失败: {error}'
	String uploadFailedError({required Object error}) => '上传失败: ${error}';

	/// zh: '请至少选择一个要更新的文件'
	String get selectAtLeastOneFileToUpdate => '请至少选择一个要更新的文件';

	/// zh: '下载设置'
	String get downloadTitle => '下载设置';

	/// zh: '确定要从云端下载设置吗？这将覆盖本地的设置数据。'
	String get downloadConfirm => '确定要从云端下载设置吗？这将覆盖本地的设置数据。';

	/// zh: '设置已从云端同步'
	String get downloadSuccess => '设置已从云端同步';

	/// zh: '下载失败'
	String get downloadFailed => '下载失败';

	/// zh: '云端暂无设置数据'
	String get downloadEmpty => '云端暂无设置数据';

	/// zh: '解压失败'
	String get extractFailed => '解压失败';

	/// zh: '在线词典 ({count})'
	String onlineDicts({required Object count}) => '在线词典 (${count})';

	/// zh: '已连接到订阅源，可在"词典管理"中查看和下载词典'
	String get onlineDictsConnected => '已连接到订阅源，可在"词典管理"中查看和下载词典';

	/// zh: '推送更新'
	String get pushUpdatesTitle => '推送更新';

	/// zh: '发现 {count} 条更新记录：'
	String pushUpdateCount({required Object count}) => '发现 ${count} 条更新记录：';

	/// zh: '没有需要推送的更新记录'
	String get noPushUpdates => '没有需要推送的更新记录';

	/// zh: '没有有效的条目需要推送'
	String get noValidEntries => '没有有效的条目需要推送';

	/// zh: '更新消息'
	String get pushMessageLabel => '更新消息';

	/// zh: '请输入更新说明'
	String get pushMessageHint => '请输入更新说明';

	/// zh: '更新条目'
	String get updateEntry => '更新条目';

	/// zh: '推送成功'
	String get pushSuccess => '推送成功';

	/// zh: '推送失败: {error}'
	String pushFailed({required Object error}) => '推送失败: ${error}';

	/// zh: '推送失败'
	String get pushFailedGeneral => '推送失败';

	/// zh: '加载更新记录失败: {error}'
	String loadUpdatesFailed({required Object error}) => '加载更新记录失败: ${error}';

	/// zh: '[新增] '
	String get opInsert => '[新增] ';

	/// zh: '[删除] '
	String get opDelete => '[删除] ';

	/// zh: '请先登录'
	String get loginFirst => '请先登录';

	/// zh: '请先配置云服务订阅地址'
	String get serverNotSet => '请先配置云服务订阅地址';

	/// zh: '请先配置上传服务器地址'
	String get uploadServerNotSet => '请先配置上传服务器地址';

	/// zh: '登录已过期，请重新登录'
	String get sessionExpired => '登录已过期，请重新登录';

	/// zh: '需要文件访问权限'
	String get permissionTitle => '需要文件访问权限';

	/// zh: '访问外部目录需要「所有文件访问」权限。 点击「去授权」后，系统将跳转到设置页面，请在「管理所有文件」中找到本应用并开启权限，然后返回应用即可生效。'
	String get permissionBody => '访问外部目录需要「所有文件访问」权限。\n\n点击「去授权」后，系统将跳转到设置页面，请在「管理所有文件」中找到本应用并开启权限，然后返回应用即可生效。';

	/// zh: '去授权'
	String get goAuthorize => '去授权';

	/// zh: '未获得文件访问权限，操作已取消'
	String get permissionDenied => '未获得文件访问权限，操作已取消';

	/// zh: '未登录，请先登录'
	String get notLoggedIn => '未登录，请先登录';

	/// zh: '获取用户信息失败'
	String get getUserFailed => '获取用户信息失败';

	/// zh: '获取用户信息失败: {error}'
	String getUserFailedError({required Object error}) => '获取用户信息失败: ${error}';

	/// zh: '请求失败'
	String get requestFailed => '请求失败';

	/// zh: '下载失败: {error}'
	String downloadFailedError({required Object error}) => '下载失败: ${error}';

	/// zh: '设置文件不存在'
	String get settingsFileNotFound => '设置文件不存在';

	/// zh: '没有需要推送的更新'
	String get noNeedToPushUpdates => '没有需要推送的更新';

	/// zh: '请选择所有必填文件'
	String get selectAllRequiredFiles => '请选择所有必填文件';

	/// zh: '（必填）'
	String get requiredField => '（必填）';

	/// zh: '（可选）'
	String get optionalField => '（可选）';

	/// zh: '上传新词典'
	String get uploadNewDict => '上传新词典';

	/// zh: '版本说明'
	String get versionNoteLabel => '版本说明';

	/// zh: '输入版本说明...'
	String get replaceFileHint => '输入版本说明...';

	/// zh: '未选择的文件不会被更新'
	String get replaceFileTip => '未选择的文件不会被更新';

	/// zh: '请输入JSON内容'
	String get enterJsonContent => '请输入JSON内容';

	/// zh: '第{line}行解析失败："{preview}"'
	String importLineError({required Object line, required Object preview}) => '第${line}行解析失败："${preview}"';

	/// zh: 'JSON解析失败'
	String get jsonParseError => 'JSON解析失败';

	/// zh: '第{item}条不是JSON对象'
	String importItemNotObject({required Object item}) => '第${item}条不是JSON对象';

	/// zh: '第{item}条没有ID'
	String importItemMissingId({required Object item}) => '第${item}条没有ID';

	/// zh: '第{item}条（id={id}, {word}）写入失败'
	String importItemWriteFailed({required Object item, required Object id, required Object word}) => '第${item}条（id=${id}, ${word}）写入失败';

	/// zh: '第{item}条处理失败: {error}'
	String importItemFailed({required Object item, required Object error}) => '第${item}条处理失败: ${error}';

	/// zh: '成功导入{count}条'
	String importSuccessCount({required Object count}) => '成功导入${count}条';

	/// zh: '，失败{count}条'
	String importFailedCount({required Object count}) => '，失败${count}条';

	/// zh: '...还有{count}个错误'
	String importMoreErrors({required Object count}) => '...还有${count}个错误';

	/// zh: '导入失败: {error}'
	String importFailedError({required Object error}) => '导入失败: ${error}';

	/// zh: '请输入词条ID'
	String get enterEntryId => '请输入词条ID';

	/// zh: '请输入词头'
	String get enterHeadword => '请输入词头';

	/// zh: '未找到ID为{id}的词条'
	String entryIdNotFound({required Object id}) => '未找到ID为${id}的词条';

	/// zh: '未找到词条："{word}"'
	String headwordNotFound({required Object word}) => '未找到词条："${word}"';

	/// zh: '搜索失败: {error}'
	String searchFailed({required Object error}) => '搜索失败: ${error}';

	/// zh: '确定删除词条"{headword}"（ID: {id}）？此操作不可撤销。'
	String deleteEntryConfirmContent({required Object headword, required Object id}) => '确定删除词条"${headword}"（ID: ${id}）？此操作不可撤销。';

	/// zh: '词条已删除'
	String get entryDeleted => '词条已删除';

	/// zh: '词条删除失败'
	String get entryDeleteFailed => '词条删除失败';

	/// zh: '删除失败: {error}'
	String deleteFailedError({required Object error}) => '删除失败: ${error}';

	/// zh: '更新词条数据'
	String get updateJsonTitle => '更新词条数据';

	/// zh: '导入'
	String get importTab => '导入';

	/// zh: '删除/搜索'
	String get deleteSearchTab => '删除/搜索';

	/// zh: '输入JSONL内容，每行一个词条...'
	String get importJsonPlaceholder => '输入JSONL内容，每行一个词条...';

	/// zh: '清空'
	String get clearLabel => '清空';

	/// zh: '导入中...'
	String get importing => '导入中...';

	/// zh: '写入数据库'
	String get writingToDb => '写入数据库';

	/// zh: '按ID搜索'
	String get idSearch => '按ID搜索';

	/// zh: '按词头搜索'
	String get prefixSearch => '按词头搜索';

	/// zh: '词头'
	String get searchHeadwordLabel => '词头';

	/// zh: '输入entry_id'
	String get searchIdHint => '输入entry_id';

	/// zh: '输入词头'
	String get searchHeadwordHint => '输入词头';

	/// zh: '找到{count}条词条'
	String matchedEntries({required Object count}) => '找到${count}条词条';

	/// zh: '删除中...'
	String get deleting => '删除中...';

	/// zh: '删除词条'
	String get deleteEntry => '删除词条';

	/// zh: '没有找到可同步的文件'
	String get noSyncableFiles => '没有找到可同步的文件';

	/// zh: '创建压缩包失败: {error}'
	String createPackageFailedError({required Object error}) => '创建压缩包失败: ${error}';

	/// zh: '压缩包文件不存在'
	String get archiveNotFound => '压缩包文件不存在';

	/// zh: '压缩包中没有有效的文件'
	String get archiveNoValidFiles => '压缩包中没有有效的文件';

	/// zh: '解压失败: {error}'
	String extractFailedError({required Object error}) => '解压失败: ${error}';
}

// Path: dict
class TranslationsDictZh {
	TranslationsDictZh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '词典管理'
	String get title => '词典管理';

	/// zh: '词典排序'
	String get tabSort => '词典排序';

	/// zh: '词典来源'
	String get tabSource => '词典来源';

	/// zh: '创作者中心'
	String get tabCreator => '创作者中心';

	/// zh: '本地词典目录'
	String get localDir => '本地词典目录';

	/// zh: '更改目录'
	String get changeDirTooltip => '更改目录';

	/// zh: '词典目录已设置: {dir}'
	String dirSet({required Object dir}) => '词典目录已设置: ${dir}';

	/// zh: '还没有词典'
	String get noDict => '还没有词典';

	/// zh: '切换到"在线订阅"Tab设置订阅地址 或点击右下角的商店按钮浏览在线词典'
	String get noDictHint => '切换到"在线订阅"Tab设置订阅地址\n或点击右下角的商店按钮浏览在线词典';

	/// zh: '已启用（长按拖动排序）'
	String get enabled => '已启用（长按拖动排序）';

	/// zh: '已禁用'
	String get disabled => '已禁用';

	/// zh: '{count} 个'
	String enabledCount({required Object count}) => '${count} 个';

	/// zh: '{count} 个'
	String disabledCount({required Object count}) => '${count} 个';

	/// zh: '长按语言标签可拖动排序'
	String get dragHint => '长按语言标签可拖动排序';

	/// zh: '在线词典列表'
	String get onlineDicts => '在线词典列表';

	/// zh: '{count} 个'
	String onlineCount({required Object count}) => '${count} 个';

	/// zh: '加载失败'
	String get loadFailed => '加载失败';

	/// zh: '加载在线词典失败'
	String get loadOnlineFailed => '加载在线词典失败';

	/// zh: '暂无在线词典'
	String get noOnlineDicts => '暂无在线词典';

	/// zh: '请先在"设置 - 云服务"中配置订阅地址'
	String get noOnlineDictsHint => '请先在"设置 - 云服务"中配置订阅地址';

	/// zh: '暂无上传的词典'
	String get noCreatorDicts => '暂无上传的词典';

	/// zh: '请先在"词典来源"页面配置云服务并登录'
	String get noCreatorDictsHint => '请先在"词典来源"页面配置云服务并登录';

	/// zh: '更新 ({count})'
	String updateCount({required Object count}) => '更新 (${count})';

	/// zh: '发现 {count} 个词典有更新'
	String hasUpdates({required Object count}) => '发现 ${count} 个词典有更新';

	/// zh: '所有词典已是最新版本'
	String get allUpToDate => '所有词典已是最新版本';

	/// zh: '检查更新'
	String get checkUpdates => '检查更新';

	/// zh: '检查中...'
	String get checking => '检查中...';

	/// zh: '下载: {name}'
	String downloadDict({required Object name}) => '下载: ${name}';

	/// zh: '选择要下载的内容:'
	String get selectContent => '选择要下载的内容:';

	/// zh: '[必选]词典元数据'
	String get dictMeta => '[必选]词典元数据';

	/// zh: '[必选]词典图标'
	String get dictIcon => '[必选]词典图标';

	/// zh: '[必选]词典数据库'
	String get dictDb => '[必选]词典数据库';

	/// zh: '[必选]词典数据库（{size}）'
	String dictDbWithSize({required Object size}) => '[必选]词典数据库（${size}）';

	/// zh: '媒体数据库'
	String get mediaDb => '媒体数据库';

	/// zh: '媒体数据库（{size}）'
	String mediaDbWithSize({required Object size}) => '媒体数据库（${size}）';

	/// zh: '找不到词典 {id} 的媒体数据库'
	String mediaDbNotFound({required Object id}) => '找不到词典 ${id} 的媒体数据库';

	/// zh: '找不到词典 {id} 的数据库'
	String dictDbNotFound({required Object id}) => '找不到词典 ${id} 的数据库';

	/// zh: '获取词典列表失败'
	String get getDictListFailed => '获取词典列表失败';

	/// zh: '服务器返回格式无效'
	String get invalidResponseFormat => '服务器返回格式无效';

	/// zh: '获取词典列表失败: {error}'
	String getDictListFailedError({required Object error}) => '获取词典列表失败: ${error}';

	/// zh: '开始下载'
	String get startDownload => '开始下载';

	/// zh: '[{step}/{total}] 下载 {name}'
	String downloading({required Object step, required Object total, required Object name}) => '[${step}/${total}] 下载 ${name}';

	/// zh: '[{step}/{total}] 下载条目更新'
	String downloadingEntries({required Object step, required Object total}) => '[${step}/${total}] 下载条目更新';

	/// zh: '更新成功'
	String get updateSuccess => '更新成功';

	/// zh: '更新失败: {error}'
	String updateFailed({required Object error}) => '更新失败: ${error}';

	/// zh: '确认删除'
	String get deleteConfirmTitle => '确认删除';

	/// zh: '确定要删除词典 "{name}" 吗？'
	String deleteConfirmBody({required Object name}) => '确定要删除词典 "${name}" 吗？';

	/// zh: '词典已删除'
	String get deleteSuccess => '词典已删除';

	/// zh: '删除失败: {error}'
	String deleteFailed({required Object error}) => '删除失败: ${error}';

	/// zh: '未找到指定词典'
	String get dictNotFound => '未找到指定词典';

	/// zh: '词典删除失败'
	String get dictDeleteFailed => '词典删除失败';

	/// zh: '状态更新失败'
	String get statusUpdateFailed => '状态更新失败';

	/// zh: '准备中'
	String get statusPreparing => '准备中';

	/// zh: '准备更新'
	String get statusPreparingUpdate => '准备更新';

	/// zh: '下载中'
	String get statusDownloading => '下载中';

	/// zh: '已完成'
	String get statusCompleted => '已完成';

	/// zh: '未配置词典存储目录'
	String get storeNotConfigured => '未配置词典存储目录';

	/// zh: '下载失败'
	String get downloadFailed => '下载失败';

	/// zh: '更新JSON'
	String get tooltipUpdateJson => '更新JSON';

	/// zh: '替换文件'
	String get tooltipReplaceFile => '替换文件';

	/// zh: '推送更新'
	String get tooltipPushUpdate => '推送更新';

	/// zh: '删除'
	String get tooltipDelete => '删除';

	/// zh: '更新词典'
	String get tooltipUpdate => '更新词典';

	/// zh: '下载词典'
	String get tooltipDownload => '下载词典';

	/// zh: '{n}天前'
	String daysAgo({required Object n}) => '${n}天前';

	/// zh: '{n}个月前'
	String monthsAgo({required Object n}) => '${n}个月前';

	/// zh: '{n}年前'
	String yearsAgo({required Object n}) => '${n}年前';

	/// zh: '{n}小时前'
	String hoursAgo({required Object n}) => '${n}小时前';

	/// zh: '{n}分钟前'
	String minutesAgo({required Object n}) => '${n}分钟前';

	/// zh: '刚刚'
	String get justNow => '刚刚';

	/// zh: '未知'
	String get dateUnknown => '未知';

	/// zh: '没有选择要更新的文件'
	String get noFileSelected => '没有选择要更新的文件';

	/// zh: '请先配置云服务地址'
	String get configCloudFirst => '请先配置云服务地址';

	/// zh: '无法获取词典信息'
	String get getDictInfoFailed => '无法获取词典信息';

	/// zh: '版本已更新至 {version}，无需下载文件'
	String versionUpdated({required Object version}) => '版本已更新至 ${version}，无需下载文件';

	/// zh: '词典存储位置'
	String get androidChoiceTitle => '词典存储位置';

	/// zh: '应用专属目录'
	String get androidAppDir => '应用专属目录';

	/// zh: '卸载应用后词典数据将被删除'
	String get androidAppDirWarning => '卸载应用后词典数据将被删除';

	/// zh: '外部公共目录'
	String get androidExtDir => '外部公共目录';

	/// zh: '卸载或更新应用后词典仍可保留'
	String get androidExtDirNote => '卸载或更新应用后词典仍可保留';

	/// zh: '推荐'
	String get androidRecommended => '推荐';

	/// zh: '自定义路径'
	String get androidCustomDir => '自定义路径';

	/// zh: '手动选择任意外部目录'
	String get androidCustomDirNote => '手动选择任意外部目录';

	/// zh: '权限已授予'
	String get permissionGranted => '权限已授予';

	/// zh: '需申请「所有文件访问」权限'
	String get permissionNeeded => '需申请「所有文件访问」权限';

	/// zh: '无法写入 {dir}，请检查权限'
	String cantWrite({required Object dir}) => '无法写入 ${dir}，请检查权限';

	/// zh: '无法写入所选目录，请重新选择'
	String get cantWritePicked => '无法写入所选目录，请重新选择';

	/// zh: '点击「确定」后系统将跳转到设置页面，请开启「管理所有文件」权限后返回应用。'
	String get permissionDialogBody => '点击「确定」后系统将跳转到设置页面，请开启「管理所有文件」权限后返回应用。';

	/// zh: '统计信息'
	String get statsTitle => '统计信息';

	/// zh: '词条数'
	String get entryCount => '词条数';

	/// zh: '音频文件'
	String get audioFiles => '音频文件';

	/// zh: '图片文件'
	String get imageFiles => '图片文件';

	/// zh: '词典信息'
	String get dictInfoTitle => '词典信息';

	/// zh: '文件信息'
	String get filesTitle => '文件信息';

	/// zh: '存在'
	String get fileExists => '存在';

	/// zh: '缺失'
	String get fileMissing => '缺失';

	/// zh: '删除词典'
	String get deleteDictTitle => '删除词典';

	/// zh: '确定删除「{name}」？ 这将删除该词典的所有文件（包括数据库、媒体、元数据等），且无法恢复。'
	String deleteDictBody({required Object name}) => '确定删除「${name}」？\n\n这将删除该词典的所有文件（包括数据库、媒体、元数据等），且无法恢复。';

	/// zh: '词典「{name}」已删除'
	String deleteDictSuccess({required Object name}) => '词典「${name}」已删除';

	/// zh: '删除失败: {error}'
	String deleteDictFailed({required Object error}) => '删除失败: ${error}';

	/// zh: '无法获取文件信息'
	String get cannotGetFileInfo => '无法获取文件信息';

	/// zh: '更新词典 - {name}'
	String updateDictTitle({required Object name}) => '更新词典 - ${name}';

	/// zh: '智能更新'
	String get smartUpdate => '智能更新';

	/// zh: '手动选择'
	String get manualSelect => '手动选择';

	/// zh: '已是最新版本'
	String get upToDate => '已是最新版本';

	/// zh: '当前词典没有可用的更新'
	String get noUpdates => '当前词典没有可用的更新';

	/// zh: '当前版本: v{version}'
	String currentVersion({required Object version}) => '当前版本: v${version}';

	/// zh: '更新历史:'
	String get updateHistory => '更新历史:';

	/// zh: '需要下载:'
	String get filesToDownload => '需要下载:';

	/// zh: '文件: {files}'
	String fileLabel({required Object files}) => '文件: ${files}';

	/// zh: '条目: {count} 个'
	String entryLabel({required Object count}) => '条目: ${count} 个';

	/// zh: '没有可用的智能更新'
	String get noSmartUpdate => '没有可用的智能更新';

	/// zh: '请至少选择一项要更新的内容'
	String get selectAtLeastOneItem => '请至少选择一项要更新的内容';

	/// zh: '批量更新词典'
	String get batchUpdateTitle => '批量更新词典';

	/// zh: '重新检查更新'
	String get recheck => '重新检查更新';

	/// zh: '更新 ({count})'
	String batchUpdateCount({required Object count}) => '更新 (${count})';

	/// zh: '发现 {count} 个词典有更新'
	String batchHasUpdates({required Object count}) => '发现 ${count} 个词典有更新';

	/// zh: '全选'
	String get selectAll => '全选';

	/// zh: '取消全选'
	String get deselectAll => '取消全选';

	/// zh: 'v{from} → v{to} | {files} 个文件'
	String versionRange({required Object from, required Object to, required Object files}) => 'v${from} → v${to} | ${files} 个文件';

	/// zh: '{count} 条更新'
	String updateRecordCount({required Object count}) => '${count} 条更新';

	/// zh: '发布者'
	String get publisher => '发布者';

	/// zh: '维护者'
	String get maintainer => '维护者';

	/// zh: '联系方式'
	String get contact => '联系方式';

	/// zh: '版本'
	String get versionLabel => '版本';

	/// zh: '更新'
	String get updatedLabel => '更新';

	/// zh: '词典详情'
	String get detailTitle => '词典详情';

	/// zh: '准备上传'
	String get statusPreparingUpload => '准备上传';

	/// zh: '[{step}/{total}] 上传 {name}'
	String uploadingFile({required Object step, required Object total, required Object name}) => '[${step}/${total}] 上传 ${name}';

	/// zh: '上传完成'
	String get statusUploadCompleted => '上传完成';

	/// zh: '上传失败'
	String get statusUploadFailed => '上传失败';

	/// zh: '已取消'
	String get cancelled => '已取消';

	/// zh: '失败'
	String get statusFailed => '失败';

	/// zh: '更新完成'
	String get statusUpdateCompleted => '更新完成';

	/// zh: '下载 {name}'
	String downloadingFile({required Object name}) => '下载 ${name}';

	/// zh: '获取词典列表失败: HTTP {code}'
	String fetchListFailedHttp({required Object code}) => '获取词典列表失败: HTTP ${code}';

	/// zh: '获取词典列表超时'
	String get fetchListTimeout => '获取词典列表超时';

	/// zh: '获取词典详情失败: HTTP {code}'
	String fetchDetailFailedHttp({required Object code}) => '获取词典详情失败: HTTP ${code}';

	/// zh: '未选择任何内容'
	String get noContentSelected => '未选择任何内容';

	/// zh: '[{step}/{total}] 下载词典数据库'
	String downloadingDatabase({required Object step, required Object total}) => '[${step}/${total}] 下载词典数据库';

	/// zh: '下载数据库失败: HTTP {code}'
	String downloadDbFailedHttp({required Object code}) => '下载数据库失败: HTTP ${code}';

	/// zh: '[{step}/{total}] 下载词典数据库 {progress}%'
	String downloadingDatabaseProgress({required Object step, required Object total, required Object progress}) => '[${step}/${total}] 下载词典数据库 ${progress}%';

	/// zh: '[{step}/{total}] 下载媒体数据库'
	String downloadingMedia({required Object step, required Object total}) => '[${step}/${total}] 下载媒体数据库';

	/// zh: '下载媒体数据库失败: HTTP {code}'
	String downloadMediaFailedHttp({required Object code}) => '下载媒体数据库失败: HTTP ${code}';

	/// zh: '[{step}/{total}] 下载媒体数据库 {progress}%'
	String downloadingMediaProgress({required Object step, required Object total, required Object progress}) => '[${step}/${total}] 下载媒体数据库 ${progress}%';

	/// zh: '[{step}/{total}] 下载元数据'
	String downloadingMeta({required Object step, required Object total}) => '[${step}/${total}] 下载元数据';

	/// zh: '下载元数据失败: {url}, HTTP {code}'
	String downloadMetaFailed({required Object url, required Object code}) => '下载元数据失败: ${url}, HTTP ${code}';

	/// zh: '[{step}/{total}] 下载图标'
	String downloadingIcon({required Object step, required Object total}) => '[${step}/${total}] 下载图标';

	/// zh: '响应内容为空'
	String get responseEmpty => '响应内容为空';

	/// zh: '英语搜索增强（出错）'
	String get dbDialogTitleError => '英语搜索增强（出错）';

	/// zh: '英语搜索增强'
	String get dbDialogTitle => '英语搜索增强';

	/// zh: '拼写变体（colour → color）'
	String get dbFeatureVariant => '拼写变体（colour → color）';

	/// zh: '缩写（abbr. → abbreviation）'
	String get dbFeatureAbbr => '缩写（abbr. → abbreviation）';

	/// zh: '名词化（happy → happiness）'
	String get dbFeatureNominal => '名词化（happy → happiness）';

	/// zh: '屈折词形（runs, ran, running → run）'
	String get dbFeatureInflection => '屈折词形（runs, ran, running → run）';

	/// zh: '例：搜索"colour"可找到"color"的词条'
	String get dbExample => '例：搜索"colour"可找到"color"的词条';

	/// zh: '下载出错: {error}'
	String downloadError({required Object error}) => '下载出错: ${error}';

	/// zh: '上传出错: {error}'
	String uploadError({required Object error}) => '上传出错: ${error}';

	/// zh: '上传成功'
	String get uploadSuccess => '上传成功';

	/// zh: '下载{name}失败: {error}'
	String downloadFileFailedError({required Object name, required Object error}) => '下载${name}失败: ${error}';

	/// zh: '下载{name}失败'
	String downloadFileFailed({required Object name}) => '下载${name}失败';

	/// zh: '下载条目更新失败'
	String get downloadEntriesFailed => '下载条目更新失败';

	/// zh: '搜索词条...'
	String get searchEntries => '搜索词条...';

	/// zh: '暂无词条'
	String get noEntries => '暂无词条';

	/// zh: '英语词典数据库不存在，请先下载'
	String get dbNotExists => '英语词典数据库不存在，请先下载';
}

// Path: entry
class TranslationsEntryZh {
	TranslationsEntryZh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '已将 "{word}" 从单词本移除'
	String wordRemoved({required Object word}) => '已将 "${word}" 从单词本移除';

	/// zh: '已更新 "{word}" 的词表归属'
	String wordListUpdated({required Object word}) => '已更新 "${word}" 的词表归属';

	/// zh: '请至少选择一个词表'
	String get selectAtLeastOne => '请至少选择一个词表';

	/// zh: '已将 "{word}" 加入单词本'
	String wordAdded({required Object word}) => '已将 "${word}" 加入单词本';

	/// zh: '添加失败'
	String get addFailed => '添加失败';

	/// zh: '无法获取当前词条'
	String get noEntry => '无法获取当前词条';

	/// zh: '词条信息不完整'
	String get entryIncomplete => '词条信息不完整';

	/// zh: '正在重置词条...'
	String get resetting => '正在重置词条...';

	/// zh: '服务器上未找到该词条'
	String get notFoundOnServer => '服务器上未找到该词条';

	/// zh: '词条已重置'
	String get resetSuccess => '词条已重置';

	/// zh: '重置失败'
	String get resetFailed => '重置失败';

	/// zh: '保存失败: {error}'
	String saveFailed({required Object error}) => '保存失败: ${error}';

	/// zh: '保存成功'
	String get saveSuccess => '保存成功';

	/// zh: '处理失败: {error}'
	String processFailed({required Object error}) => '处理失败: ${error}';

	/// zh: '正在翻译...'
	String get translating => '正在翻译...';

	/// zh: '翻译失败: {error}'
	String translateFailed({required Object error}) => '翻译失败: ${error}';

	/// zh: '切换失败: {error}'
	String toggleFailed({required Object error}) => '切换失败: ${error}';

	/// zh: '未找到单词: {word}'
	String wordNotFound({required Object word}) => '未找到单词: ${word}';

	/// zh: '当前页没有内容'
	String get noPageContent => '当前页没有内容';

	/// zh: '已复制到剪贴板'
	String get copiedToClipboard => '已复制到剪贴板';

	/// zh: 'AI请求失败: {error}'
	String aiRequestFailed({required Object error}) => 'AI请求失败: ${error}';

	/// zh: '请求失败:'
	String get aiRequestFailedShort => '请求失败:';

	/// zh: 'AI请求失败: {error}'
	String aiChatFailed({required Object error}) => 'AI请求失败: ${error}';

	/// zh: 'AI总结失败: {error}'
	String aiSumFailed({required Object error}) => 'AI总结失败: ${error}';

	/// zh: '总结当前页'
	String get summarizePage => '总结当前页';

	/// zh: '删除记录'
	String get deleteRecord => '删除记录';

	/// zh: '确定删除这条AI聊天记录吗？'
	String get deleteRecordConfirm => '确定删除这条AI聊天记录吗？';

	/// zh: 'AI正在思考中...'
	String get aiThinking => 'AI正在思考中...';

	/// zh: '正在输出...'
	String get outputting => '正在输出...';

	/// zh: '思考过程'
	String get thinkingProcess => '思考过程';

	/// zh: '暂无聊天记录'
	String get noChatHistory => '暂无聊天记录';

	/// zh: '继续对话'
	String get continueChatTitle => '继续对话';

	/// zh: '原始问题'
	String get originalQuestion => '原始问题';

	/// zh: 'AI回答'
	String get aiAnswer => 'AI回答';

	/// zh: '继续提问'
	String get continueAsk => '继续提问';

	/// zh: '基于以上对话继续提问...'
	String get continueAskHint => '基于以上对话继续提问...';

	/// zh: '重新生成'
	String get regenerate => '重新生成';

	/// zh: '简洁点'
	String get moreConc => '简洁点';

	/// zh: '详细点'
	String get moreDetailed => '详细点';

	/// zh: '输入任意问题...'
	String get chatInputHint => '输入任意问题...';

	/// zh: '刚刚'
	String get justNow => '刚刚';

	/// zh: '{n}分钟前'
	String minutesAgo({required Object n}) => '${n}分钟前';

	/// zh: '{n}小时前'
	String hoursAgo({required Object n}) => '${n}小时前';

	/// zh: '{n}天前'
	String daysAgo({required Object n}) => '${n}天前';

	/// zh: '原形'
	String get morphBase => '原形';

	/// zh: '名词形'
	String get morphNominal => '名词形';

	/// zh: '复数'
	String get morphPlural => '复数';

	/// zh: '过去式'
	String get morphPast => '过去式';

	/// zh: '过去分词'
	String get morphPastPart => '过去分词';

	/// zh: '现在分词'
	String get morphPresPart => '现在分词';

	/// zh: '三单'
	String get morphThirdSing => '三单';

	/// zh: '比较级'
	String get morphComp => '比较级';

	/// zh: '最高级'
	String get morphSuperl => '最高级';

	/// zh: '变体'
	String get morphSpellingVariant => '变体';

	/// zh: '名词化'
	String get morphNominalization => '名词化';

	/// zh: '屈折词'
	String get morphInflection => '屈折词';

	/// zh: '不可数'
	String get uncountable => '不可数';

	/// zh: '请总结当前页的所有词典内容'
	String get summaryQuestion => '请总结当前页的所有词典内容';

	/// zh: '当前页内容总结'
	String get summaryTitle => '当前页内容总结';

	/// zh: '点我AI总结'
	String get aiSummaryButton => '点我AI总结';

	/// zh: '{first}等{count}个词条'
	String summaryEntriesLabel({required Object first, required Object count}) => '${first}等${count}个词条';

	/// zh: '{dict} [{page}] AI总结'
	String chatStartSummary({required Object dict, required Object page}) => '${dict} [${page}] AI总结';

	/// zh: '{dict} [{path}] AI询问'
	String chatStartElement({required Object dict, required Object path}) => '${dict} [${path}] AI询问';

	/// zh: '「{word}」AI自由聊天'
	String chatStartFreeChat({required Object word}) => '「${word}」AI自由聊天';

	/// zh: 'AI自由聊天'
	String get chatOverviewFreeChat => 'AI自由聊天';

	/// zh: '{dict} [{page}] AI总结'
	String chatOverviewSummary({required Object dict, required Object page}) => '${dict} [${page}] AI总结';

	/// zh: '{dict} AI总结'
	String chatOverviewSummaryNoPage({required Object dict}) => '${dict} AI总结';

	/// zh: '{dict} AI询问'
	String chatOverviewAsk({required Object dict}) => '${dict} AI询问';

	/// zh: '返回初始路径'
	String get returnToStart => '返回初始路径';

	/// zh: '路径'
	String get path => '路径';

	/// zh: '这是词典中单词"{word}"的一部分，请解释这部分内容。'
	String explainPrompt({required Object word}) => '这是词典中单词"${word}"的一部分，请解释这部分内容。';

	/// zh: '当前查询单词: {word}'
	String currentWord({required Object word}) => '当前查询单词: ${word}';

	/// zh: '当前词典: {dictId}'
	String currentDict({required Object dictId}) => '当前词典: ${dictId}';

	/// zh: '未找到词条: {entryId}'
	String entryNotFound({required Object entryId}) => '未找到词条: ${entryId}';

	/// zh: '提取文本失败'
	String get extractFailed => '提取文本失败';

	/// zh: '生成音频中...'
	String get generatingAudio => '生成音频中...';

	/// zh: '语音合成失败: {error}'
	String speakFailed({required Object error}) => '语音合成失败: ${error}';

	/// zh: '未找到短语："{phrase}"'
	String phraseNotFound({required Object phrase}) => '未找到短语："${phrase}"';

	/// zh: '图片加载失败'
	String get imageLoadFailed => '图片加载失败';

	/// zh: '根节点必须是JSON对象'
	String get rootMustBeObject => '根节点必须是JSON对象';

	/// zh: '保存到数据库失败'
	String get dbUpdateFailed => '保存到数据库失败';

	/// zh: '格式化失败: {error}'
	String jsonFormatFailed({required Object error}) => '格式化失败: ${error}';

	/// zh: 'JSON语法错误: {error}'
	String jsonSyntaxError({required Object error}) => 'JSON语法错误: ${error}';

	/// zh: '格式化JSON'
	String get formatJson => '格式化JSON';

	/// zh: '语法错误'
	String get syntaxError => '语法错误';

	/// zh: '语法检查通过'
	String get syntaxCheck => '语法检查通过';

	/// zh: '语法错误: {error}'
	String jsonErrorLabel({required Object error}) => '语法错误: ${error}';

	/// zh: '拼写变体'
	String get spellingVariantLabel => '拼写变体';

	/// zh: '缩写'
	String get abbreviationLabel => '缩写';

	/// zh: '首字母缩略词'
	String get acronymLabel => '首字母缩略词';

	/// zh: '复数形式'
	String get morphPluralForm => '复数形式';

	/// zh: '第三人称单数'
	String get morphThirdSingFull => '第三人称单数';
}

// Path: settings.scaleDialog
class TranslationsSettingsScaleDialogZh {
	TranslationsSettingsScaleDialogZh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '软件布局缩放'
	String get title => '软件布局缩放';

	/// zh: '调整词典内容显示的整体缩放比例'
	String get subtitle => '调整词典内容显示的整体缩放比例';

	/// zh: '保持缩放更改？'
	String get confirmTitle => '保持缩放更改？';

	/// zh: '新的缩放比例为 {percent}%。 将在 {seconds} 秒后自动恢复原比例。'
	String confirmBody({required Object percent, required Object seconds}) => '新的缩放比例为 ${percent}%。\n将在 ${seconds} 秒后自动恢复原比例。';
}

// Path: settings.clickActionDialog
class TranslationsSettingsClickActionDialogZh {
	TranslationsSettingsClickActionDialogZh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '点击动作设置'
	String get title => '点击动作设置';

	/// zh: '列表第一项将作为点击时的功能，其它通过右键/长按触发'
	String get hint => '列表第一项将作为点击时的功能，其它通过右键/长按触发';

	/// zh: '点击功能'
	String get primaryLabel => '点击功能';
}

// Path: settings.toolbarDialog
class TranslationsSettingsToolbarDialogZh {
	TranslationsSettingsToolbarDialogZh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '底部工具栏设置'
	String get title => '底部工具栏设置';

	/// zh: '拖动调整，分割线以下合并到菜单中，工具栏至多{max}个图标'
	String hint({required Object max}) => '拖动调整，分割线以下合并到菜单中，工具栏至多${max}个图标';

	/// zh: '分割线 (拖动调整)'
	String get dividerLabel => '分割线 (拖动调整)';

	/// zh: '工具栏'
	String get toolbar => '工具栏';

	/// zh: '更多菜单'
	String get overflow => '更多菜单';

	/// zh: '工具栏最多只能有 {max} 个功能'
	String maxItemsError({required Object max}) => '工具栏最多只能有 ${max} 个功能';
}

// Path: settings.misc_page
class TranslationsSettingsMiscPageZh {
	TranslationsSettingsMiscPageZh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '其它设置'
	String get title => '其它设置';

	/// zh: 'AI 聊天记录管理'
	String get aiChatTitle => 'AI 聊天记录管理';

	/// zh: '聊天记录总数'
	String get recordCount => '聊天记录总数';

	/// zh: '{count} 条记录'
	String records({required Object count}) => '${count} 条记录';

	/// zh: '自动清理设置'
	String get autoCleanup => '自动清理设置';

	/// zh: '不自动清理'
	String get noAutoCleanup => '不自动清理';

	/// zh: '保留最近 {days} 天的记录'
	String keepRecentDays({required Object days}) => '保留最近 ${days} 天的记录';

	/// zh: '清除所有聊天记录'
	String get clearAll => '清除所有聊天记录';

	/// zh: '确认清除'
	String get clearAllConfirmTitle => '确认清除';

	/// zh: '确定要清除所有 AI 聊天记录吗？此操作不可恢复。'
	String get clearAllConfirmBody => '确定要清除所有 AI 聊天记录吗？此操作不可恢复。';

	/// zh: '已清除所有聊天记录'
	String get clearAllSuccess => '已清除所有聊天记录';

	/// zh: '辅助查词数据库设置'
	String get auxDbTitle => '辅助查词数据库设置';

	/// zh: '不询问查词重定向数据库'
	String get skipAskRedirect => '不询问查词重定向数据库';

	/// zh: '已选择不再询问'
	String get skipAskEnabled => '已选择不再询问';

	/// zh: '已恢复询问'
	String get skipAskDisabled => '已恢复询问';

	/// zh: '删除辅助查词数据库'
	String get deleteAuxDb => '删除辅助查词数据库';

	/// zh: '英语数据库已安装，点击删除'
	String get auxDbInstalled => '英语数据库已安装，点击删除';

	/// zh: '暂未安装任何辅助查词数据库'
	String get auxDbNotInstalled => '暂未安装任何辅助查词数据库';

	/// zh: '删除数据库'
	String get deleteAuxDbConfirmTitle => '删除数据库';

	/// zh: '确定要删除辅助查词数据库吗？删除后可重新下载。'
	String get deleteAuxDbConfirmBody => '确定要删除辅助查词数据库吗？删除后可重新下载。';

	/// zh: '辅助查词数据库已删除'
	String get deleteAuxDbSuccess => '辅助查词数据库已删除';

	/// zh: '数据库文件不存在'
	String get deleteAuxDbNotExist => '数据库文件不存在';

	/// zh: '词典更新设置'
	String get dictUpdateTitle => '词典更新设置';

	/// zh: '自动检查词典更新'
	String get autoCheckDictUpdate => '自动检查词典更新';

	/// zh: '每天检查本地词典是否有更新'
	String get autoCheckDictUpdateSubtitle => '每天检查本地词典是否有更新';

	/// zh: '自动清理设置'
	String get autoCleanupDialogTitle => '自动清理设置';

	/// zh: '保留最近 7 天'
	String get keep7Days => '保留最近 7 天';

	/// zh: '保留最近 30 天'
	String get keep30Days => '保留最近 30 天';

	/// zh: '保留最近 90 天'
	String get keep90Days => '保留最近 90 天';
}

// Path: settings.actionLabel
class TranslationsSettingsActionLabelZh {
	TranslationsSettingsActionLabelZh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '切换翻译'
	String get aiTranslate => '切换翻译';

	/// zh: '复制文本'
	String get copy => '复制文本';

	/// zh: '询问 AI'
	String get askAi => '询问 AI';

	/// zh: '编辑'
	String get edit => '编辑';

	/// zh: '朗读'
	String get speak => '朗读';

	/// zh: '返回'
	String get back => '返回';

	/// zh: '收藏'
	String get favorite => '收藏';

	/// zh: '显示/隐藏翻译'
	String get toggleTranslate => '显示/隐藏翻译';

	/// zh: 'AI 历史记录'
	String get aiHistory => 'AI 历史记录';

	/// zh: '重置词条'
	String get resetEntry => '重置词条';
}

// Path: theme.colorNames
class TranslationsThemeColorNamesZh {
	TranslationsThemeColorNamesZh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '蓝色'
	String get blue => '蓝色';

	/// zh: '靛蓝色'
	String get indigo => '靛蓝色';

	/// zh: '紫色'
	String get purple => '紫色';

	/// zh: '深紫色'
	String get deepPurple => '深紫色';

	/// zh: '粉色'
	String get pink => '粉色';

	/// zh: '红色'
	String get red => '红色';

	/// zh: '深橙色'
	String get deepOrange => '深橙色';

	/// zh: '橙色'
	String get orange => '橙色';

	/// zh: '琥珀色'
	String get amber => '琥珀色';

	/// zh: '黄色'
	String get yellow => '黄色';

	/// zh: '青柠色'
	String get lime => '青柠色';

	/// zh: '浅绿色'
	String get lightGreen => '浅绿色';

	/// zh: '绿色'
	String get green => '绿色';

	/// zh: '青色'
	String get teal => '青色';

	/// zh: '天蓝色'
	String get cyan => '天蓝色';
}

/// The flat map containing all translations for locale <zh>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on Translations {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'nav.search' => '查词',
			'nav.wordBank' => '单词本',
			'nav.settings' => '设置',
			'language.auto' => '跟随系统',
			'language.zh' => '中文',
			'language.en' => 'English',
			'language.dialogTitle' => '应用语言',
			'language.dialogSubtitle' => '选择界面显示语言',
			'common.ok' => '确定',
			'common.cancel' => '取消',
			'common.save' => '保存',
			'common.confirm' => '确认',
			'common.undo' => '撤销',
			'common.delete' => '删除',
			'common.clear' => '清除',
			'common.reset' => '重置',
			'common.close' => '关闭',
			'common.back' => '返回',
			'common.loading' => '加载中...',
			'common.noData' => '暂无数据',
			'common.done' => '完成',
			'common.rename' => '重命名',
			'common.import' => '导入',
			'common.all' => '全部',
			'common.warning' => '警告',
			'common.irreversible' => '此操作不可恢复',
			'common.retry' => '重试',
			'common.logout' => '退出',
			'common.login' => '登录',
			'common.register' => '注册',
			'common.copy' => '复制',
			'common.continue_' => '继续',
			'common.set_' => '设置',
			'common.change' => '修改',
			'common.update' => '更新',
			'common.download' => '下载',
			'common.upload' => '上传',
			'common.noContent' => '暂无内容',
			'common.error' => '错误',
			'common.success' => '成功',
			'common.testing' => '测试中...',
			'common.testConnection' => '测试连接',
			'common.saveConfig' => '保存配置',
			'common.unknown' => '未知',
			'common.fullscreen' => '全屏',
			'common.exitFullscreen' => '退出全屏',
			'common.retryLater' => '请稍后重试',
			'common.notNow' => '暂不',
			'common.neverAskAgain' => '不再提示',
			'common.redo' => '重做',
			'common.selectLanguage' => '选择语言',
			'settings.title' => '设置',
			'settings.cloudService' => '云服务',
			'settings.dictionaryManager' => '词典管理',
			'settings.aiConfig' => 'AI 配置',
			'settings.fontConfig' => '字体配置',
			'settings.themeSettings' => '主题设置',
			'settings.layoutScale' => '软件布局缩放',
			'settings.clickAction' => '点击动作设置',
			'settings.toolbar' => '底部工具栏设置',
			'settings.misc' => '其他设置',
			'settings.about' => '关于软件',
			'settings.appLanguage' => '应用语言',
			'settings.scaleDialog.title' => '软件布局缩放',
			'settings.scaleDialog.subtitle' => '调整词典内容显示的整体缩放比例',
			'settings.scaleDialog.confirmTitle' => '保持缩放更改？',
			'settings.scaleDialog.confirmBody' => ({required Object percent, required Object seconds}) => '新的缩放比例为 ${percent}%。\n将在 ${seconds} 秒后自动恢复原比例。',
			'settings.clickActionDialog.title' => '点击动作设置',
			'settings.clickActionDialog.hint' => '列表第一项将作为点击时的功能，其它通过右键/长按触发',
			'settings.clickActionDialog.primaryLabel' => '点击功能',
			'settings.toolbarDialog.title' => '底部工具栏设置',
			'settings.toolbarDialog.hint' => ({required Object max}) => '拖动调整，分割线以下合并到菜单中，工具栏至多${max}个图标',
			'settings.toolbarDialog.dividerLabel' => '分割线 (拖动调整)',
			'settings.toolbarDialog.toolbar' => '工具栏',
			'settings.toolbarDialog.overflow' => '更多菜单',
			'settings.toolbarDialog.maxItemsError' => ({required Object max}) => '工具栏最多只能有 ${max} 个功能',
			'settings.misc_page.title' => '其它设置',
			'settings.misc_page.aiChatTitle' => 'AI 聊天记录管理',
			'settings.misc_page.recordCount' => '聊天记录总数',
			'settings.misc_page.records' => ({required Object count}) => '${count} 条记录',
			'settings.misc_page.autoCleanup' => '自动清理设置',
			'settings.misc_page.noAutoCleanup' => '不自动清理',
			'settings.misc_page.keepRecentDays' => ({required Object days}) => '保留最近 ${days} 天的记录',
			'settings.misc_page.clearAll' => '清除所有聊天记录',
			'settings.misc_page.clearAllConfirmTitle' => '确认清除',
			'settings.misc_page.clearAllConfirmBody' => '确定要清除所有 AI 聊天记录吗？此操作不可恢复。',
			'settings.misc_page.clearAllSuccess' => '已清除所有聊天记录',
			'settings.misc_page.auxDbTitle' => '辅助查词数据库设置',
			'settings.misc_page.skipAskRedirect' => '不询问查词重定向数据库',
			'settings.misc_page.skipAskEnabled' => '已选择不再询问',
			'settings.misc_page.skipAskDisabled' => '已恢复询问',
			'settings.misc_page.deleteAuxDb' => '删除辅助查词数据库',
			'settings.misc_page.auxDbInstalled' => '英语数据库已安装，点击删除',
			'settings.misc_page.auxDbNotInstalled' => '暂未安装任何辅助查词数据库',
			'settings.misc_page.deleteAuxDbConfirmTitle' => '删除数据库',
			'settings.misc_page.deleteAuxDbConfirmBody' => '确定要删除辅助查词数据库吗？删除后可重新下载。',
			'settings.misc_page.deleteAuxDbSuccess' => '辅助查词数据库已删除',
			'settings.misc_page.deleteAuxDbNotExist' => '数据库文件不存在',
			'settings.misc_page.dictUpdateTitle' => '词典更新设置',
			'settings.misc_page.autoCheckDictUpdate' => '自动检查词典更新',
			'settings.misc_page.autoCheckDictUpdateSubtitle' => '每天检查本地词典是否有更新',
			'settings.misc_page.autoCleanupDialogTitle' => '自动清理设置',
			'settings.misc_page.keep7Days' => '保留最近 7 天',
			'settings.misc_page.keep30Days' => '保留最近 30 天',
			'settings.misc_page.keep90Days' => '保留最近 90 天',
			'settings.actionLabel.aiTranslate' => '切换翻译',
			'settings.actionLabel.copy' => '复制文本',
			'settings.actionLabel.askAi' => '询问 AI',
			'settings.actionLabel.edit' => '编辑',
			'settings.actionLabel.speak' => '朗读',
			'settings.actionLabel.back' => '返回',
			'settings.actionLabel.favorite' => '收藏',
			'settings.actionLabel.toggleTranslate' => '显示/隐藏翻译',
			'settings.actionLabel.aiHistory' => 'AI 历史记录',
			'settings.actionLabel.resetEntry' => '重置词条',
			'search.hint' => '输入单词',
			'search.hintWordBank' => '搜索单词本',
			'search.noResult' => ({required Object word}) => '未找到单词: ${word}',
			'search.startHint' => '输入单词开始查询',
			'search.historyTitle' => '历史记录',
			'search.historyClear' => '清除',
			'search.historyCleared' => '历史记录已清除',
			'search.historyDeleted' => ({required Object word}) => '已删除 "${word}"',
			'search.wildcardNoEntry' => '通配符模式下请从候选词列表中选择词条',
			'search.advancedOptions' => '高级选项',
			'search.searchBtn' => '查询',
			'search.searchOptionsTitle' => '搜索选项',
			'search.exactMatch' => '精确搜索',
			'search.toneExact' => '简繁区分',
			'search.phoneticCandidates' => '读音候选词',
			'search.searchResults' => '搜索结果',
			'search.noEnabledDicts' => '当前没有已启用的词典',
			'search.wildcardHint' => 'LIKE 模式（输入含 % 或 _）：\n  % 匹配任意个字符，_ 匹配恰好一个字符\n  例：hel% → hello、help；%字 → 汉字、生字；h_llo → hello、hallo\n\nGLOB 模式（输入含 * ? [ ] ^），区分大小写：\n  * 匹配任意个字符，? 匹配单个字符\n  [abc] 匹配括号内任一字符，[^abc] 排除括号内字符\n  例：h?llo → hello、hallo；[aeiou]* → 所有元音字母开头的词',
			'search.dbDownloaded' => ({required Object word}) => '下载完成，搜索 "${word}" 以测试功能',
			'wordBank.title' => '单词本',
			'wordBank.empty' => '单词本还是空的',
			'wordBank.emptyHint' => '在查词时点击收藏按钮添加单词',
			'wordBank.noWordsFound' => '没有找到单词',
			'wordBank.wordNotFound' => ({required Object word}) => '未找到单词: ${word}',
			'wordBank.wordRemoved' => '已移除单词',
			'wordBank.wordListUpdated' => '已更新词表归属',
			'wordBank.manageLists' => '管理词表',
			'wordBank.sortTooltip' => '排序方式',
			'wordBank.sortAddTimeDesc' => '添加顺序',
			'wordBank.sortAlphabetical' => '字母顺序',
			'wordBank.sortRandom' => '随机排序',
			'wordBank.importToLanguage' => ({required Object language}) => '导入到 ${language}',
			'wordBank.listNameLabel' => '词表名称：',
			'wordBank.listNameHint' => '例如：托福、雅思、GRE',
			'wordBank.pickFile' => '选择文件',
			'wordBank.previewWords' => '预览10个单词：',
			'wordBank.previewCount' => ({required Object count}) => '共识别到 ${count} 个单词预览',
			'wordBank.importSuccess' => ({required Object count, required Object list}) => '成功导入 ${count} 个单词到 "${list}"',
			'wordBank.importFailed' => '导入失败',
			'wordBank.importListExists' => ({required Object list}) => '词表 "${list}" 已存在，请使用其他名称',
			'wordBank.importFileError' => '文件读取失败',
			'wordBank.editListsTitle' => ({required Object language}) => '编辑 ${language} 词表',
			'wordBank.renameList' => '重命名词表',
			'wordBank.listNameFieldLabel' => '词表名称',
			'wordBank.listNameFieldHint' => '输入新名称',
			'wordBank.deleteList' => '删除词表',
			'wordBank.deleteListConfirm' => ({required Object name}) => '确定要删除词表 "${name}" 吗？\n\n这将删除该词表及其所有数据。如果一个单词不属于任何其他词表，也会被删除。',
			'wordBank.importListBtn' => '导入词表',
			'wordBank.listSaved' => '词表已更新',
			'wordBank.listOpFailed' => '操作失败',
			'wordBank.listNameExists' => '词表名称已存在，请使用其他名称',
			'wordBank.selectLists' => '选择词表',
			'wordBank.adjustLists' => ({required Object word}) => '调整"${word}"的词表',
			'wordBank.newListHint' => '新建词表...',
			'wordBank.removeWord' => '从单词本移除',
			'theme.title' => '主题设置',
			'theme.light' => '浅色',
			'theme.dark' => '深色',
			'theme.system' => '跟随系统',
			'theme.seedColor' => '主题色',
			'theme.systemAccent' => '系统主题色',
			'theme.custom' => '自定义',
			'theme.appearanceMode' => '外观模式',
			'theme.themeColor' => '主题颜色',
			'theme.preview' => '预览效果',
			'theme.followSystem' => '跟随系统',
			'theme.lightMode' => '浅色模式',
			'theme.darkMode' => '深色模式',
			'theme.previewText' => '这是一段示例文字，展示应用的主题效果预览。',
			'theme.primaryColor' => '主色',
			'theme.primaryContainer' => '主容器',
			'theme.secondary' => '辅色',
			'theme.tertiary' => '强调',
			'theme.surface' => '背景',
			'theme.card' => '卡片',
			'theme.error' => '错误',
			'theme.outline' => '边框',
			'theme.colorNames.blue' => '蓝色',
			'theme.colorNames.indigo' => '靛蓝色',
			'theme.colorNames.purple' => '紫色',
			'theme.colorNames.deepPurple' => '深紫色',
			'theme.colorNames.pink' => '粉色',
			'theme.colorNames.red' => '红色',
			'theme.colorNames.deepOrange' => '深橙色',
			'theme.colorNames.orange' => '橙色',
			'theme.colorNames.amber' => '琥珀色',
			'theme.colorNames.yellow' => '黄色',
			'theme.colorNames.lime' => '青柠色',
			'theme.colorNames.lightGreen' => '浅绿色',
			'theme.colorNames.green' => '绿色',
			'theme.colorNames.teal' => '青色',
			'theme.colorNames.cyan' => '天蓝色',
			'help.title' => '关于软件',
			'help.tagline' => '查词，不折腾',
			'help.forumTitle' => '词典反馈',
			'help.forumSubtitle' => '欢迎提出改进建议',
			'help.githubSubtitle' => '查看源码、提交 Issue',
			'help.afdianTitle' => '爱发电',
			'help.afdianSubtitle' => '支持开发者',
			'help.checkUpdate' => '检查更新',
			'help.checking' => '正在检查…',
			'help.updateAvailable' => ({required Object version}) => '发现新版本 ${version} · 点击前往 GitHub 下载',
			'help.upToDate' => ({required Object version}) => '已是最新版本 ${version}',
			'help.currentVersion' => ({required Object version}) => '当前版本 ${version}',
			'help.updateError' => '检查失败，点击重试',
			'help.githubApiError' => ({required Object code}) => 'GitHub API 错误 (状态码 ${code})',
			'help.checkUpdateError' => ({required Object error}) => '检查更新失败: ${error}',
			'langNames.zh' => '中文',
			'langNames.ja' => '日语',
			'langNames.ko' => '韩语',
			'langNames.en' => '英语',
			'langNames.fr' => '法语',
			'langNames.de' => '德语',
			'langNames.es' => '西班牙语',
			'langNames.it' => '意大利语',
			'langNames.ru' => '俄语',
			'langNames.pt' => '葡萄牙语',
			'langNames.ar' => '阿拉伯语',
			'langNames.text' => '文本',
			'langNames.auto' => '自动',
			'langNames.zhHans' => '中文（简体）',
			'langNames.zhHant' => '中文（繁体）',
			'font.title' => '字体配置',
			'font.folderLabel' => '字体文件夹',
			'font.folderNotSet' => '未设置',
			'font.folderSet' => '设置',
			'font.folderChange' => '修改',
			'font.refreshTooltip' => '刷新字体',
			'font.refreshSuccess' => '字体已刷新',
			'font.noDicts' => '未找到包含语言信息的词典',
			'font.sansSerif' => '无衬线字体',
			'font.serif' => '衬线字体',
			'font.regular' => '常规',
			'font.bold' => '粗体',
			'font.italic' => '斜体',
			'font.boldItalic' => '粗斜体',
			'font.notConfigured' => '未配置',
			'font.selectFont' => ({required Object language}) => '选择 ${language} 字体',
			'font.clearFont' => '清除自定义字体',
			'font.fontSaved' => '字体配置已保存',
			'font.setFolderFirst' => '请先设置字体文件夹',
			'font.folderNotExist' => ({required Object lang}) => '语言文件夹不存在: ${lang}',
			'font.noFontFiles' => ({required Object lang}) => '语言文件夹 ${lang} 中没有字体文件',
			'font.folderDoesNotExist' => '文件夹不存在',
			'font.folderSetSuccess' => '字体文件夹已设置，已自动创建语言子文件夹',
			'font.scaleDialogTitle' => ({required Object type}) => '${type}缩放倍率',
			'font.scaleDialogSubtitle' => '仅用于调整不同字体的尺寸一致性',
			'font.resetValue' => '100',
			'ai.title' => 'AI配置',
			'ai.tabFast' => '快速模型',
			'ai.tabStandard' => '标准模型',
			'ai.tabAudio' => '音频模型',
			'ai.fastModel' => '快速模型',
			'ai.fastModelSubtitle' => '适用于日常查询，速度优先',
			'ai.standardModel' => '标准模型',
			'ai.standardModelSubtitle' => '适用于高质量翻译和解释',
			'ai.providerLabel' => '选择服务商',
			'ai.modelLabel' => '模型',
			'ai.modelRequired' => '请输入模型名称',
			'ai.baseUrlLabel' => 'Base URL (可选)',
			'ai.baseUrlHint' => '留空使用默认地址',
			'ai.baseUrlNote' => '仅在使用自定义端点或代理时需要修改url',
			'ai.apiKeyRequired' => '请输入API Key',
			'ai.defaultModel' => ({required Object model}) => '默认模型: ${model}',
			'ai.deepThinkingTitle' => '深度思考',
			'ai.deepThinkingSubtitle' => '在支持的模型上开启思考链（CoT）输出，可显示思考过程',
			'ai.configSaved' => '配置已保存',
			'ai.testSuccess' => 'API 连接成功！响应正常',
			'ai.testError' => ({required Object message}) => 'API 错误: ${message}',
			'ai.testTimeout' => '连接超时，请检查网络或 Base URL',
			'ai.testFailed' => ({required Object message}) => '连接失败: ${message}',
			'ai.testApiKeyRequired' => '请先输入 API Key',
			'ai.testFailedWithError' => ({required Object error}) => '测试失败: ${error}',
			'ai.ttsSaved' => 'TTS 配置已保存，请在发音时测试',
			'ai.ttsTitle' => '配置文本转语音服务，用于词典发音功能',
			'ai.ttsBaseUrlHintGoogle' => '留空使用: https://texttospeech.googleapis.com/v1',
			'ai.ttsEdgeNote' => 'Edge TTS 是微软 Edge 浏览器的语音合成服务，无需配置即可使用',
			'ai.ttsVoiceSettings' => '语言音色设置',
			'ai.ttsVoiceSettingsSubtitle' => '为每种语言设置发音音色，词典发音时将根据语言自动选择对应音色',
			'ai.ttsNoVoice' => '无可用音色',
			'ai.ttsAzureNote' => '使用 Azure Speech Service 获取 API Key',
			'ai.ttsGoogleNote' => '使用 Google Cloud Service Account JSON Key\n访问 https://console.cloud.google.com/apis/credentials 创建',
			'ai.providerMoonshot' => 'Moonshot（月之暗面）',
			'ai.providerZhipu' => '智谱AI',
			'ai.providerAli' => '阿里云（DashScope）',
			'ai.providerCustom' => '自定义',
			'cloud.title' => '云服务',
			'cloud.subscriptionLabel' => '在线订阅地址',
			'cloud.subscriptionHint' => '请输入词典订阅网址',
			'cloud.subscriptionSaveTooltip' => '保存',
			'cloud.subscriptionSaved' => '在线订阅地址已保存',
			'cloud.subscriptionChanged' => '订阅地址已变更，已退出当前账号',
			'cloud.subscriptionHint2' => '设置订阅地址后可查看和下载在线词典',
			'cloud.accountTitle' => '账户管理',
			'cloud.loginBtn' => '登录',
			'cloud.registerBtn' => '注册',
			'cloud.logoutBtn' => '退出',
			'cloud.loginDialogTitle' => '登录',
			'cloud.usernameOrEmail' => '用户名或邮箱',
			'cloud.passwordLabel' => '密码',
			'cloud.registerDialogTitle' => '注册',
			'cloud.usernameLabel' => '用户名',
			'cloud.emailLabel' => '邮箱',
			'cloud.confirmPasswordLabel' => '确认密码',
			'cloud.loginSuccess' => '登录成功',
			'cloud.loginFailed' => '登录失败',
			'cloud.loginRequired' => '请输入用户名/邮箱和密码',
			'cloud.registerSuccess' => '注册成功',
			'cloud.registerFailed' => '注册失败',
			'cloud.registerRequired' => '请输入邮箱、用户名和密码',
			'cloud.registerUsernameRequired' => '请输入用户名',
			'cloud.registerPasswordMismatch' => '两次输入的密码不一致',
			'cloud.loggedOut' => '已退出登录',
			'cloud.requestTimeout' => '请求超时，请检查网络连接',
			'cloud.registerFailedError' => ({required Object error}) => '注册失败: ${error}',
			'cloud.loginFailedError' => ({required Object error}) => '登录失败: ${error}',
			'cloud.syncToCloud' => '同步到云端',
			'cloud.syncToCloudSubtitle' => '将本地设置上传到云端',
			'cloud.syncFromCloud' => '从云端同步',
			'cloud.syncFromCloudSubtitle' => '从云端下载设置到本地',
			'cloud.uploadTitle' => '上传设置',
			'cloud.uploadConfirm' => '确定要将本地设置上传到云端吗？这将覆盖云端的设置数据。',
			'cloud.uploadSuccess' => '设置已上传到云端',
			'cloud.uploadFailed' => '上传失败',
			'cloud.createPackageFailed' => '创建设置包失败',
			'cloud.uploadFailedError' => ({required Object error}) => '上传失败: ${error}',
			'cloud.selectAtLeastOneFileToUpdate' => '请至少选择一个要更新的文件',
			'cloud.downloadTitle' => '下载设置',
			'cloud.downloadConfirm' => '确定要从云端下载设置吗？这将覆盖本地的设置数据。',
			'cloud.downloadSuccess' => '设置已从云端同步',
			'cloud.downloadFailed' => '下载失败',
			'cloud.downloadEmpty' => '云端暂无设置数据',
			'cloud.extractFailed' => '解压失败',
			'cloud.onlineDicts' => ({required Object count}) => '在线词典 (${count})',
			'cloud.onlineDictsConnected' => '已连接到订阅源，可在"词典管理"中查看和下载词典',
			'cloud.pushUpdatesTitle' => '推送更新',
			'cloud.pushUpdateCount' => ({required Object count}) => '发现 ${count} 条更新记录：',
			'cloud.noPushUpdates' => '没有需要推送的更新记录',
			'cloud.noValidEntries' => '没有有效的条目需要推送',
			'cloud.pushMessageLabel' => '更新消息',
			'cloud.pushMessageHint' => '请输入更新说明',
			'cloud.updateEntry' => '更新条目',
			'cloud.pushSuccess' => '推送成功',
			'cloud.pushFailed' => ({required Object error}) => '推送失败: ${error}',
			'cloud.pushFailedGeneral' => '推送失败',
			'cloud.loadUpdatesFailed' => ({required Object error}) => '加载更新记录失败: ${error}',
			'cloud.opInsert' => '[新增] ',
			'cloud.opDelete' => '[删除] ',
			'cloud.loginFirst' => '请先登录',
			'cloud.serverNotSet' => '请先配置云服务订阅地址',
			'cloud.uploadServerNotSet' => '请先配置上传服务器地址',
			'cloud.sessionExpired' => '登录已过期，请重新登录',
			'cloud.permissionTitle' => '需要文件访问权限',
			'cloud.permissionBody' => '访问外部目录需要「所有文件访问」权限。\n\n点击「去授权」后，系统将跳转到设置页面，请在「管理所有文件」中找到本应用并开启权限，然后返回应用即可生效。',
			'cloud.goAuthorize' => '去授权',
			'cloud.permissionDenied' => '未获得文件访问权限，操作已取消',
			'cloud.notLoggedIn' => '未登录，请先登录',
			'cloud.getUserFailed' => '获取用户信息失败',
			'cloud.getUserFailedError' => ({required Object error}) => '获取用户信息失败: ${error}',
			'cloud.requestFailed' => '请求失败',
			'cloud.downloadFailedError' => ({required Object error}) => '下载失败: ${error}',
			'cloud.settingsFileNotFound' => '设置文件不存在',
			'cloud.noNeedToPushUpdates' => '没有需要推送的更新',
			'cloud.selectAllRequiredFiles' => '请选择所有必填文件',
			'cloud.requiredField' => '（必填）',
			'cloud.optionalField' => '（可选）',
			'cloud.uploadNewDict' => '上传新词典',
			'cloud.versionNoteLabel' => '版本说明',
			'cloud.replaceFileHint' => '输入版本说明...',
			'cloud.replaceFileTip' => '未选择的文件不会被更新',
			'cloud.enterJsonContent' => '请输入JSON内容',
			'cloud.importLineError' => ({required Object line, required Object preview}) => '第${line}行解析失败："${preview}"',
			'cloud.jsonParseError' => 'JSON解析失败',
			'cloud.importItemNotObject' => ({required Object item}) => '第${item}条不是JSON对象',
			'cloud.importItemMissingId' => ({required Object item}) => '第${item}条没有ID',
			'cloud.importItemWriteFailed' => ({required Object item, required Object id, required Object word}) => '第${item}条（id=${id}, ${word}）写入失败',
			'cloud.importItemFailed' => ({required Object item, required Object error}) => '第${item}条处理失败: ${error}',
			'cloud.importSuccessCount' => ({required Object count}) => '成功导入${count}条',
			'cloud.importFailedCount' => ({required Object count}) => '，失败${count}条',
			'cloud.importMoreErrors' => ({required Object count}) => '...还有${count}个错误',
			'cloud.importFailedError' => ({required Object error}) => '导入失败: ${error}',
			'cloud.enterEntryId' => '请输入词条ID',
			'cloud.enterHeadword' => '请输入词头',
			'cloud.entryIdNotFound' => ({required Object id}) => '未找到ID为${id}的词条',
			'cloud.headwordNotFound' => ({required Object word}) => '未找到词条："${word}"',
			'cloud.searchFailed' => ({required Object error}) => '搜索失败: ${error}',
			'cloud.deleteEntryConfirmContent' => ({required Object headword, required Object id}) => '确定删除词条"${headword}"（ID: ${id}）？此操作不可撤销。',
			'cloud.entryDeleted' => '词条已删除',
			'cloud.entryDeleteFailed' => '词条删除失败',
			'cloud.deleteFailedError' => ({required Object error}) => '删除失败: ${error}',
			'cloud.updateJsonTitle' => '更新词条数据',
			'cloud.importTab' => '导入',
			'cloud.deleteSearchTab' => '删除/搜索',
			'cloud.importJsonPlaceholder' => '输入JSONL内容，每行一个词条...',
			'cloud.clearLabel' => '清空',
			'cloud.importing' => '导入中...',
			'cloud.writingToDb' => '写入数据库',
			'cloud.idSearch' => '按ID搜索',
			'cloud.prefixSearch' => '按词头搜索',
			'cloud.searchHeadwordLabel' => '词头',
			'cloud.searchIdHint' => '输入entry_id',
			'cloud.searchHeadwordHint' => '输入词头',
			'cloud.matchedEntries' => ({required Object count}) => '找到${count}条词条',
			'cloud.deleting' => '删除中...',
			'cloud.deleteEntry' => '删除词条',
			'cloud.noSyncableFiles' => '没有找到可同步的文件',
			'cloud.createPackageFailedError' => ({required Object error}) => '创建压缩包失败: ${error}',
			'cloud.archiveNotFound' => '压缩包文件不存在',
			'cloud.archiveNoValidFiles' => '压缩包中没有有效的文件',
			'cloud.extractFailedError' => ({required Object error}) => '解压失败: ${error}',
			'dict.title' => '词典管理',
			'dict.tabSort' => '词典排序',
			'dict.tabSource' => '词典来源',
			'dict.tabCreator' => '创作者中心',
			'dict.localDir' => '本地词典目录',
			'dict.changeDirTooltip' => '更改目录',
			'dict.dirSet' => ({required Object dir}) => '词典目录已设置: ${dir}',
			'dict.noDict' => '还没有词典',
			'dict.noDictHint' => '切换到"在线订阅"Tab设置订阅地址\n或点击右下角的商店按钮浏览在线词典',
			'dict.enabled' => '已启用（长按拖动排序）',
			'dict.disabled' => '已禁用',
			'dict.enabledCount' => ({required Object count}) => '${count} 个',
			'dict.disabledCount' => ({required Object count}) => '${count} 个',
			'dict.dragHint' => '长按语言标签可拖动排序',
			'dict.onlineDicts' => '在线词典列表',
			'dict.onlineCount' => ({required Object count}) => '${count} 个',
			'dict.loadFailed' => '加载失败',
			'dict.loadOnlineFailed' => '加载在线词典失败',
			'dict.noOnlineDicts' => '暂无在线词典',
			'dict.noOnlineDictsHint' => '请先在"设置 - 云服务"中配置订阅地址',
			'dict.noCreatorDicts' => '暂无上传的词典',
			'dict.noCreatorDictsHint' => '请先在"词典来源"页面配置云服务并登录',
			'dict.updateCount' => ({required Object count}) => '更新 (${count})',
			'dict.hasUpdates' => ({required Object count}) => '发现 ${count} 个词典有更新',
			'dict.allUpToDate' => '所有词典已是最新版本',
			'dict.checkUpdates' => '检查更新',
			'dict.checking' => '检查中...',
			'dict.downloadDict' => ({required Object name}) => '下载: ${name}',
			'dict.selectContent' => '选择要下载的内容:',
			'dict.dictMeta' => '[必选]词典元数据',
			'dict.dictIcon' => '[必选]词典图标',
			'dict.dictDb' => '[必选]词典数据库',
			'dict.dictDbWithSize' => ({required Object size}) => '[必选]词典数据库（${size}）',
			'dict.mediaDb' => '媒体数据库',
			'dict.mediaDbWithSize' => ({required Object size}) => '媒体数据库（${size}）',
			'dict.mediaDbNotFound' => ({required Object id}) => '找不到词典 ${id} 的媒体数据库',
			'dict.dictDbNotFound' => ({required Object id}) => '找不到词典 ${id} 的数据库',
			'dict.getDictListFailed' => '获取词典列表失败',
			'dict.invalidResponseFormat' => '服务器返回格式无效',
			'dict.getDictListFailedError' => ({required Object error}) => '获取词典列表失败: ${error}',
			'dict.startDownload' => '开始下载',
			'dict.downloading' => ({required Object step, required Object total, required Object name}) => '[${step}/${total}] 下载 ${name}',
			'dict.downloadingEntries' => ({required Object step, required Object total}) => '[${step}/${total}] 下载条目更新',
			'dict.updateSuccess' => '更新成功',
			'dict.updateFailed' => ({required Object error}) => '更新失败: ${error}',
			'dict.deleteConfirmTitle' => '确认删除',
			'dict.deleteConfirmBody' => ({required Object name}) => '确定要删除词典 "${name}" 吗？',
			'dict.deleteSuccess' => '词典已删除',
			'dict.deleteFailed' => ({required Object error}) => '删除失败: ${error}',
			'dict.dictNotFound' => '未找到指定词典',
			'dict.dictDeleteFailed' => '词典删除失败',
			'dict.statusUpdateFailed' => '状态更新失败',
			'dict.statusPreparing' => '准备中',
			'dict.statusPreparingUpdate' => '准备更新',
			'dict.statusDownloading' => '下载中',
			'dict.statusCompleted' => '已完成',
			'dict.storeNotConfigured' => '未配置词典存储目录',
			'dict.downloadFailed' => '下载失败',
			'dict.tooltipUpdateJson' => '更新JSON',
			'dict.tooltipReplaceFile' => '替换文件',
			'dict.tooltipPushUpdate' => '推送更新',
			'dict.tooltipDelete' => '删除',
			'dict.tooltipUpdate' => '更新词典',
			'dict.tooltipDownload' => '下载词典',
			'dict.daysAgo' => ({required Object n}) => '${n}天前',
			'dict.monthsAgo' => ({required Object n}) => '${n}个月前',
			'dict.yearsAgo' => ({required Object n}) => '${n}年前',
			'dict.hoursAgo' => ({required Object n}) => '${n}小时前',
			'dict.minutesAgo' => ({required Object n}) => '${n}分钟前',
			'dict.justNow' => '刚刚',
			'dict.dateUnknown' => '未知',
			'dict.noFileSelected' => '没有选择要更新的文件',
			'dict.configCloudFirst' => '请先配置云服务地址',
			'dict.getDictInfoFailed' => '无法获取词典信息',
			'dict.versionUpdated' => ({required Object version}) => '版本已更新至 ${version}，无需下载文件',
			'dict.androidChoiceTitle' => '词典存储位置',
			'dict.androidAppDir' => '应用专属目录',
			'dict.androidAppDirWarning' => '卸载应用后词典数据将被删除',
			'dict.androidExtDir' => '外部公共目录',
			'dict.androidExtDirNote' => '卸载或更新应用后词典仍可保留',
			'dict.androidRecommended' => '推荐',
			'dict.androidCustomDir' => '自定义路径',
			'dict.androidCustomDirNote' => '手动选择任意外部目录',
			'dict.permissionGranted' => '权限已授予',
			'dict.permissionNeeded' => '需申请「所有文件访问」权限',
			'dict.cantWrite' => ({required Object dir}) => '无法写入 ${dir}，请检查权限',
			'dict.cantWritePicked' => '无法写入所选目录，请重新选择',
			_ => null,
		} ?? switch (path) {
			'dict.permissionDialogBody' => '点击「确定」后系统将跳转到设置页面，请开启「管理所有文件」权限后返回应用。',
			'dict.statsTitle' => '统计信息',
			'dict.entryCount' => '词条数',
			'dict.audioFiles' => '音频文件',
			'dict.imageFiles' => '图片文件',
			'dict.dictInfoTitle' => '词典信息',
			'dict.filesTitle' => '文件信息',
			'dict.fileExists' => '存在',
			'dict.fileMissing' => '缺失',
			'dict.deleteDictTitle' => '删除词典',
			'dict.deleteDictBody' => ({required Object name}) => '确定删除「${name}」？\n\n这将删除该词典的所有文件（包括数据库、媒体、元数据等），且无法恢复。',
			'dict.deleteDictSuccess' => ({required Object name}) => '词典「${name}」已删除',
			'dict.deleteDictFailed' => ({required Object error}) => '删除失败: ${error}',
			'dict.cannotGetFileInfo' => '无法获取文件信息',
			'dict.updateDictTitle' => ({required Object name}) => '更新词典 - ${name}',
			'dict.smartUpdate' => '智能更新',
			'dict.manualSelect' => '手动选择',
			'dict.upToDate' => '已是最新版本',
			'dict.noUpdates' => '当前词典没有可用的更新',
			'dict.currentVersion' => ({required Object version}) => '当前版本: v${version}',
			'dict.updateHistory' => '更新历史:',
			'dict.filesToDownload' => '需要下载:',
			'dict.fileLabel' => ({required Object files}) => '文件: ${files}',
			'dict.entryLabel' => ({required Object count}) => '条目: ${count} 个',
			'dict.noSmartUpdate' => '没有可用的智能更新',
			'dict.selectAtLeastOneItem' => '请至少选择一项要更新的内容',
			'dict.batchUpdateTitle' => '批量更新词典',
			'dict.recheck' => '重新检查更新',
			'dict.batchUpdateCount' => ({required Object count}) => '更新 (${count})',
			'dict.batchHasUpdates' => ({required Object count}) => '发现 ${count} 个词典有更新',
			'dict.selectAll' => '全选',
			'dict.deselectAll' => '取消全选',
			'dict.versionRange' => ({required Object from, required Object to, required Object files}) => 'v${from} → v${to} | ${files} 个文件',
			'dict.updateRecordCount' => ({required Object count}) => '${count} 条更新',
			'dict.publisher' => '发布者',
			'dict.maintainer' => '维护者',
			'dict.contact' => '联系方式',
			'dict.versionLabel' => '版本',
			'dict.updatedLabel' => '更新',
			'dict.detailTitle' => '词典详情',
			'dict.statusPreparingUpload' => '准备上传',
			'dict.uploadingFile' => ({required Object step, required Object total, required Object name}) => '[${step}/${total}] 上传 ${name}',
			'dict.statusUploadCompleted' => '上传完成',
			'dict.statusUploadFailed' => '上传失败',
			'dict.cancelled' => '已取消',
			'dict.statusFailed' => '失败',
			'dict.statusUpdateCompleted' => '更新完成',
			'dict.downloadingFile' => ({required Object name}) => '下载 ${name}',
			'dict.fetchListFailedHttp' => ({required Object code}) => '获取词典列表失败: HTTP ${code}',
			'dict.fetchListTimeout' => '获取词典列表超时',
			'dict.fetchDetailFailedHttp' => ({required Object code}) => '获取词典详情失败: HTTP ${code}',
			'dict.noContentSelected' => '未选择任何内容',
			'dict.downloadingDatabase' => ({required Object step, required Object total}) => '[${step}/${total}] 下载词典数据库',
			'dict.downloadDbFailedHttp' => ({required Object code}) => '下载数据库失败: HTTP ${code}',
			'dict.downloadingDatabaseProgress' => ({required Object step, required Object total, required Object progress}) => '[${step}/${total}] 下载词典数据库 ${progress}%',
			'dict.downloadingMedia' => ({required Object step, required Object total}) => '[${step}/${total}] 下载媒体数据库',
			'dict.downloadMediaFailedHttp' => ({required Object code}) => '下载媒体数据库失败: HTTP ${code}',
			'dict.downloadingMediaProgress' => ({required Object step, required Object total, required Object progress}) => '[${step}/${total}] 下载媒体数据库 ${progress}%',
			'dict.downloadingMeta' => ({required Object step, required Object total}) => '[${step}/${total}] 下载元数据',
			'dict.downloadMetaFailed' => ({required Object url, required Object code}) => '下载元数据失败: ${url}, HTTP ${code}',
			'dict.downloadingIcon' => ({required Object step, required Object total}) => '[${step}/${total}] 下载图标',
			'dict.responseEmpty' => '响应内容为空',
			'dict.dbDialogTitleError' => '英语搜索增强（出错）',
			'dict.dbDialogTitle' => '英语搜索增强',
			'dict.dbFeatureVariant' => '拼写变体（colour → color）',
			'dict.dbFeatureAbbr' => '缩写（abbr. → abbreviation）',
			'dict.dbFeatureNominal' => '名词化（happy → happiness）',
			'dict.dbFeatureInflection' => '屈折词形（runs, ran, running → run）',
			'dict.dbExample' => '例：搜索"colour"可找到"color"的词条',
			'dict.downloadError' => ({required Object error}) => '下载出错: ${error}',
			'dict.uploadError' => ({required Object error}) => '上传出错: ${error}',
			'dict.uploadSuccess' => '上传成功',
			'dict.downloadFileFailedError' => ({required Object name, required Object error}) => '下载${name}失败: ${error}',
			'dict.downloadFileFailed' => ({required Object name}) => '下载${name}失败',
			'dict.downloadEntriesFailed' => '下载条目更新失败',
			'dict.searchEntries' => '搜索词条...',
			'dict.noEntries' => '暂无词条',
			'dict.dbNotExists' => '英语词典数据库不存在，请先下载',
			'entry.wordRemoved' => ({required Object word}) => '已将 "${word}" 从单词本移除',
			'entry.wordListUpdated' => ({required Object word}) => '已更新 "${word}" 的词表归属',
			'entry.selectAtLeastOne' => '请至少选择一个词表',
			'entry.wordAdded' => ({required Object word}) => '已将 "${word}" 加入单词本',
			'entry.addFailed' => '添加失败',
			'entry.noEntry' => '无法获取当前词条',
			'entry.entryIncomplete' => '词条信息不完整',
			'entry.resetting' => '正在重置词条...',
			'entry.notFoundOnServer' => '服务器上未找到该词条',
			'entry.resetSuccess' => '词条已重置',
			'entry.resetFailed' => '重置失败',
			'entry.saveFailed' => ({required Object error}) => '保存失败: ${error}',
			'entry.saveSuccess' => '保存成功',
			'entry.processFailed' => ({required Object error}) => '处理失败: ${error}',
			'entry.translating' => '正在翻译...',
			'entry.translateFailed' => ({required Object error}) => '翻译失败: ${error}',
			'entry.toggleFailed' => ({required Object error}) => '切换失败: ${error}',
			'entry.wordNotFound' => ({required Object word}) => '未找到单词: ${word}',
			'entry.noPageContent' => '当前页没有内容',
			'entry.copiedToClipboard' => '已复制到剪贴板',
			'entry.aiRequestFailed' => ({required Object error}) => 'AI请求失败: ${error}',
			'entry.aiRequestFailedShort' => '请求失败:',
			'entry.aiChatFailed' => ({required Object error}) => 'AI请求失败: ${error}',
			'entry.aiSumFailed' => ({required Object error}) => 'AI总结失败: ${error}',
			'entry.summarizePage' => '总结当前页',
			'entry.deleteRecord' => '删除记录',
			'entry.deleteRecordConfirm' => '确定删除这条AI聊天记录吗？',
			'entry.aiThinking' => 'AI正在思考中...',
			'entry.outputting' => '正在输出...',
			'entry.thinkingProcess' => '思考过程',
			'entry.noChatHistory' => '暂无聊天记录',
			'entry.continueChatTitle' => '继续对话',
			'entry.originalQuestion' => '原始问题',
			'entry.aiAnswer' => 'AI回答',
			'entry.continueAsk' => '继续提问',
			'entry.continueAskHint' => '基于以上对话继续提问...',
			'entry.regenerate' => '重新生成',
			'entry.moreConc' => '简洁点',
			'entry.moreDetailed' => '详细点',
			'entry.chatInputHint' => '输入任意问题...',
			'entry.justNow' => '刚刚',
			'entry.minutesAgo' => ({required Object n}) => '${n}分钟前',
			'entry.hoursAgo' => ({required Object n}) => '${n}小时前',
			'entry.daysAgo' => ({required Object n}) => '${n}天前',
			'entry.morphBase' => '原形',
			'entry.morphNominal' => '名词形',
			'entry.morphPlural' => '复数',
			'entry.morphPast' => '过去式',
			'entry.morphPastPart' => '过去分词',
			'entry.morphPresPart' => '现在分词',
			'entry.morphThirdSing' => '三单',
			'entry.morphComp' => '比较级',
			'entry.morphSuperl' => '最高级',
			'entry.morphSpellingVariant' => '变体',
			'entry.morphNominalization' => '名词化',
			'entry.morphInflection' => '屈折词',
			'entry.uncountable' => '不可数',
			'entry.summaryQuestion' => '请总结当前页的所有词典内容',
			'entry.summaryTitle' => '当前页内容总结',
			'entry.aiSummaryButton' => '点我AI总结',
			'entry.summaryEntriesLabel' => ({required Object first, required Object count}) => '${first}等${count}个词条',
			'entry.chatStartSummary' => ({required Object dict, required Object page}) => '${dict} [${page}] AI总结',
			'entry.chatStartElement' => ({required Object dict, required Object path}) => '${dict} [${path}] AI询问',
			'entry.chatStartFreeChat' => ({required Object word}) => '「${word}」AI自由聊天',
			'entry.chatOverviewFreeChat' => 'AI自由聊天',
			'entry.chatOverviewSummary' => ({required Object dict, required Object page}) => '${dict} [${page}] AI总结',
			'entry.chatOverviewSummaryNoPage' => ({required Object dict}) => '${dict} AI总结',
			'entry.chatOverviewAsk' => ({required Object dict}) => '${dict} AI询问',
			'entry.returnToStart' => '返回初始路径',
			'entry.path' => '路径',
			'entry.explainPrompt' => ({required Object word}) => '这是词典中单词"${word}"的一部分，请解释这部分内容。',
			'entry.currentWord' => ({required Object word}) => '当前查询单词: ${word}',
			'entry.currentDict' => ({required Object dictId}) => '当前词典: ${dictId}',
			'entry.entryNotFound' => ({required Object entryId}) => '未找到词条: ${entryId}',
			'entry.extractFailed' => '提取文本失败',
			'entry.generatingAudio' => '生成音频中...',
			'entry.speakFailed' => ({required Object error}) => '语音合成失败: ${error}',
			'entry.phraseNotFound' => ({required Object phrase}) => '未找到短语："${phrase}"',
			'entry.imageLoadFailed' => '图片加载失败',
			'entry.rootMustBeObject' => '根节点必须是JSON对象',
			'entry.dbUpdateFailed' => '保存到数据库失败',
			'entry.jsonFormatFailed' => ({required Object error}) => '格式化失败: ${error}',
			'entry.jsonSyntaxError' => ({required Object error}) => 'JSON语法错误: ${error}',
			'entry.formatJson' => '格式化JSON',
			'entry.syntaxError' => '语法错误',
			'entry.syntaxCheck' => '语法检查通过',
			'entry.jsonErrorLabel' => ({required Object error}) => '语法错误: ${error}',
			'entry.spellingVariantLabel' => '拼写变体',
			'entry.abbreviationLabel' => '缩写',
			'entry.acronymLabel' => '首字母缩略词',
			'entry.morphPluralForm' => '复数形式',
			'entry.morphThirdSingFull' => '第三人称单数',
			_ => null,
		};
	}
}
