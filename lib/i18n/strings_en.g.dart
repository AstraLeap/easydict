///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'strings.g.dart';

// Path: <root>
class TranslationsEn extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsEn({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.en,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		super.$meta.setFlatMapFunction($meta.getTranslation); // copy base translations to super.$meta
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <en>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	@override dynamic operator[](String key) => $meta.getTranslation(key) ?? super.$meta.getTranslation(key);

	late final TranslationsEn _root = this; // ignore: unused_field

	@override 
	TranslationsEn $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsEn(meta: meta ?? this.$meta);

	// Translations
	@override late final _TranslationsNavEn nav = _TranslationsNavEn._(_root);
	@override late final _TranslationsLanguageEn language = _TranslationsLanguageEn._(_root);
	@override late final _TranslationsCommonEn common = _TranslationsCommonEn._(_root);
	@override late final _TranslationsSettingsEn settings = _TranslationsSettingsEn._(_root);
	@override late final _TranslationsSearchEn search = _TranslationsSearchEn._(_root);
	@override late final _TranslationsWordBankEn wordBank = _TranslationsWordBankEn._(_root);
	@override late final _TranslationsThemeEn theme = _TranslationsThemeEn._(_root);
	@override late final _TranslationsHelpEn help = _TranslationsHelpEn._(_root);
	@override late final _TranslationsLangNamesEn langNames = _TranslationsLangNamesEn._(_root);
	@override late final _TranslationsFontEn font = _TranslationsFontEn._(_root);
	@override late final _TranslationsAiEn ai = _TranslationsAiEn._(_root);
	@override late final _TranslationsCloudEn cloud = _TranslationsCloudEn._(_root);
	@override late final _TranslationsDictEn dict = _TranslationsDictEn._(_root);
	@override late final _TranslationsEntryEn entry = _TranslationsEntryEn._(_root);
	@override late final _TranslationsGroupsEn groups = _TranslationsGroupsEn._(_root);
}

// Path: nav
class _TranslationsNavEn extends TranslationsNavZh {
	_TranslationsNavEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get search => 'Search';
	@override String get wordBank => 'Word Bank';
	@override String get settings => 'Settings';
}

// Path: language
class _TranslationsLanguageEn extends TranslationsLanguageZh {
	_TranslationsLanguageEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get auto => 'Follow System';
	@override String get zh => '中文';
	@override String get en => 'English';
	@override String get dialogTitle => 'App Language';
	@override String get dialogSubtitle => 'Select the display language';
}

// Path: common
class _TranslationsCommonEn extends TranslationsCommonZh {
	_TranslationsCommonEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get ok => 'OK';
	@override String get cancel => 'Cancel';
	@override String get save => 'Save';
	@override String get confirm => 'Confirm';
	@override String get undo => 'Undo';
	@override String get delete => 'Delete';
	@override String get clear => 'Clear';
	@override String get reset => 'Reset';
	@override String get close => 'Close';
	@override String get back => 'Back';
	@override String get loading => 'Loading...';
	@override String get noData => 'No data';
	@override String get done => 'Done';
	@override String get rename => 'Rename';
	@override String get import => 'Import';
	@override String get all => 'All';
	@override String get warning => 'Warning';
	@override String get irreversible => 'This action cannot be undone';
	@override String get retry => 'Retry';
	@override String get logout => 'Logout';
	@override String get login => 'Login';
	@override String get register => 'Register';
	@override String get copy => 'Copy';
	@override String get continue_ => 'Continue';
	@override String get set_ => 'Set';
	@override String get change => 'Change';
	@override String get update => 'Update';
	@override String get download => 'Download';
	@override String get upload => 'Upload';
	@override String get noContent => 'No content';
	@override String get error => 'Error';
	@override String get success => 'Success';
	@override String get testing => 'Testing...';
	@override String get testConnection => 'Test Config';
	@override String get saveConfig => 'Save Config';
	@override String get unknown => 'Unknown';
	@override String get fullscreen => 'Fullscreen';
	@override String get exitFullscreen => 'Exit Fullscreen';
	@override String get retryLater => 'Please try again later';
	@override String get notNow => 'Not Now';
	@override String get neverAskAgain => 'Never Ask Again';
	@override String get redo => 'Redo';
	@override String get selectLanguage => 'Select Language';
}

// Path: settings
class _TranslationsSettingsEn extends TranslationsSettingsZh {
	_TranslationsSettingsEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Settings';
	@override String get cloudService => 'Cloud Service';
	@override String get dictionaryManager => 'Dictionary Manager';
	@override String get aiConfig => 'AI Config';
	@override String get fontConfig => 'Font Config';
	@override String get themeSettings => 'Theme Settings';
	@override String get layoutScale => 'Layout Scale';
	@override String get clickAction => 'Click Action';
	@override String get toolbar => 'Bottom Toolbar';
	@override String get misc => 'Other Settings';
	@override String get about => 'About';
	@override String get appLanguage => 'App Language';
	@override String get audioBackend => 'Audio Playback Engine';
	@override late final _TranslationsSettingsAudioBackendDialogEn audioBackendDialog = _TranslationsSettingsAudioBackendDialogEn._(_root);
	@override late final _TranslationsSettingsScaleDialogEn scaleDialog = _TranslationsSettingsScaleDialogEn._(_root);
	@override late final _TranslationsSettingsClickActionDialogEn clickActionDialog = _TranslationsSettingsClickActionDialogEn._(_root);
	@override late final _TranslationsSettingsToolbarDialogEn toolbarDialog = _TranslationsSettingsToolbarDialogEn._(_root);
	@override late final _TranslationsSettingsMiscPageEn misc_page = _TranslationsSettingsMiscPageEn._(_root);
	@override late final _TranslationsSettingsActionLabelEn actionLabel = _TranslationsSettingsActionLabelEn._(_root);
	@override String get clipboardWatch => 'Clipboard Watch';
	@override String get clipboardWatchEnabled => 'Enabled, auto-search when copying text';
	@override String get clipboardWatchDisabled => 'Disabled';
	@override String get minimizeToTray => 'Minimize to Tray';
	@override String get minimizeToTrayDesc => 'Minimize to system tray when closing window';
}

// Path: search
class _TranslationsSearchEn extends TranslationsSearchZh {
	_TranslationsSearchEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get hint => 'Enter a word';
	@override String get hintWordBank => 'Search word bank';
	@override String noResult({required Object word}) => 'Word not found: ${word}';
	@override String get startHint => 'Enter a word to start lookup';
	@override String get historyTitle => 'History';
	@override String get historyClear => 'Clear';
	@override String get historyCleared => 'History cleared';
	@override String historyDeleted({required Object word}) => 'Deleted "${word}"';
	@override String get wildcardNoEntry => 'In wildcard mode, please select a word from the candidate list';
	@override String get advancedOptions => 'Advanced Options';
	@override String get searchBtn => 'Search';
	@override String get searchOptionsTitle => 'Search Options';
	@override String get exactMatch => 'Exact Match';
	@override String get toneExact => 'Distinguish Trad/Simp';
	@override String get phoneticCandidates => 'Phonetic Candidates';
	@override String get searchResults => 'Search Results';
	@override String get noEnabledDicts => 'No dictionaries are enabled';
	@override String get wildcardHint => 'LIKE pattern (enter % or _):\n  % matches any number of chars, _ matches exactly one\n  e.g. hel% → hello, help; h_llo → hello, hallo\n\nGLOB pattern (enter * ? [ ] ^), case-sensitive:\n  * matches any chars, ? matches one char\n  [abc] matches any char in brackets, [^abc] excludes them\n  e.g. h?llo → hello, hallo; [aeiou]* → words starting with a vowel';
	@override String dbDownloaded({required Object word}) => 'Download complete, search "${word}" to test';
	@override String get dailyWords => 'Daily Vocabulary';
	@override String get dailyWordsRefresh => 'Refresh';
	@override String get dailyWordsSettings => 'Settings';
	@override String get dailyWordsCount => 'Word Count';
	@override String get dailyWordsLanguage => 'List Language';
	@override String get dailyWordsList => 'List Scope';
	@override String get dailyWordsAllLists => 'All Lists';
	@override String get dailyWordsNoWords => 'No words in the list';
	@override String get dailyWordsNoList => 'No list available';
}

// Path: wordBank
class _TranslationsWordBankEn extends TranslationsWordBankZh {
	_TranslationsWordBankEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Word Bank';
	@override String get empty => 'Your word bank is empty';
	@override String get emptyHint => 'Tap the favorite button while looking up words to add them';
	@override String get noWordsFound => 'No words found';
	@override String wordNotFound({required Object word}) => 'Word not found: ${word}';
	@override String get wordRemoved => 'Word removed';
	@override String get wordListUpdated => 'Word list updated';
	@override String get manageLists => 'Manage Lists';
	@override String get sortTooltip => 'Sort by';
	@override String get sortAddTimeDesc => 'Add Order';
	@override String get sortAlphabetical => 'Alphabetical';
	@override String get sortRandom => 'Random';
	@override String importToLanguage({required Object language}) => 'Import to ${language}';
	@override String get listNameLabel => 'List name:';
	@override String get listNameHint => 'e.g. TOEFL, IELTS, GRE';
	@override String get pickFile => 'Pick File';
	@override String get previewWords => 'Preview 10 words:';
	@override String previewCount({required Object count}) => '${count} words recognized (preview)';
	@override String importSuccess({required Object count, required Object list}) => 'Successfully imported ${count} words to "${list}"';
	@override String get importFailed => 'Import failed';
	@override String importListExists({required Object list}) => 'List "${list}" already exists, please use a different name';
	@override String get importFileError => 'Failed to read file';
	@override String editListsTitle({required Object language}) => 'Edit ${language} Lists';
	@override String get renameList => 'Rename List';
	@override String get listNameFieldLabel => 'List name';
	@override String get listNameFieldHint => 'Enter new name';
	@override String get deleteList => 'Delete List';
	@override String deleteListConfirm({required Object name}) => 'Delete list "${name}"?\n\nThis will delete the list and all its data. Words not in any other list will also be deleted.';
	@override String get importListBtn => 'Import List';
	@override String get listSaved => 'List updated';
	@override String get listOpFailed => 'Operation failed';
	@override String get listNameExists => 'List name already exists, please use a different name';
	@override String get selectLists => 'Select lists';
	@override String adjustLists({required Object word}) => 'Adjust lists for "${word}"';
	@override String get newListHint => 'Add new list...';
	@override String get removeWord => 'Remove word';
}

// Path: theme
class _TranslationsThemeEn extends TranslationsThemeZh {
	_TranslationsThemeEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Theme Settings';
	@override String get light => 'Light';
	@override String get dark => 'Dark';
	@override String get system => 'Follow System';
	@override String get seedColor => 'Seed Color';
	@override String get systemAccent => 'System Accent';
	@override String get custom => 'Custom';
	@override String get appearanceMode => 'Appearance Mode';
	@override String get themeColor => 'Theme Color';
	@override String get preview => 'Preview';
	@override String get followSystem => 'Follow System';
	@override String get lightMode => 'Light Mode';
	@override String get darkMode => 'Dark Mode';
	@override String get previewText => 'This is sample text showing the app\'s theme preview.';
	@override String get primaryColor => 'Primary';
	@override String get primaryContainer => 'Primary Container';
	@override String get secondary => 'Secondary';
	@override String get tertiary => 'Tertiary';
	@override String get surface => 'Background';
	@override String get card => 'Card';
	@override String get error => 'Error';
	@override String get outline => 'Border';
	@override late final _TranslationsThemeColorNamesEn colorNames = _TranslationsThemeColorNamesEn._(_root);
}

// Path: help
class _TranslationsHelpEn extends TranslationsHelpZh {
	_TranslationsHelpEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'About';
	@override String get tagline => 'Look up words, hassle-free';
	@override String get forumTitle => 'Feedback';
	@override String get forumSubtitle => 'Suggestions and feedback welcome';
	@override String get githubSubtitle => 'View source code, file issues';
	@override String get afdianTitle => 'Afdian';
	@override String get afdianSubtitle => 'Support the developer';
	@override String get checkUpdate => 'Check for Updates';
	@override String get checking => 'Checking…';
	@override String updateAvailable({required Object version}) => 'New version ${version} found · Click to download from GitHub';
	@override String upToDate({required Object version}) => 'Up to date (${version})';
	@override String currentVersion({required Object version}) => 'Current version ${version}';
	@override String get updateError => 'Check failed, tap to retry';
	@override String githubApiError({required Object code}) => 'GitHub API error (status ${code})';
	@override String checkUpdateError({required Object error}) => 'Update check failed: ${error}';
}

// Path: langNames
class _TranslationsLangNamesEn extends TranslationsLangNamesZh {
	_TranslationsLangNamesEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get zh => 'Chinese';
	@override String get jp => 'Japanese';
	@override String get ko => 'Korean';
	@override String get en => 'English';
	@override String get fr => 'French';
	@override String get de => 'German';
	@override String get es => 'Spanish';
	@override String get it => 'Italian';
	@override String get ru => 'Russian';
	@override String get pt => 'Portuguese';
	@override String get ar => 'Arabic';
	@override String get text => 'Text';
	@override String get auto => 'Auto';
	@override String get zhHans => 'Simplified Chinese';
	@override String get zhHant => 'Traditional Chinese';
}

// Path: font
class _TranslationsFontEn extends TranslationsFontZh {
	_TranslationsFontEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Font Config';
	@override String get folderLabel => 'Font Folder';
	@override String get folderNotSet => 'Not set';
	@override String get folderSet => 'Set';
	@override String get folderChange => 'Change';
	@override String get refreshTooltip => 'Refresh Fonts';
	@override String get refreshSuccess => 'Fonts refreshed';
	@override String get noDicts => 'No dictionaries with language info found';
	@override String get sansSerif => 'Sans-serif';
	@override String get serif => 'Serif';
	@override String get regular => 'Regular';
	@override String get bold => 'Bold';
	@override String get italic => 'Italic';
	@override String get boldItalic => 'Bold Italic';
	@override String get notConfigured => 'Not configured';
	@override String selectFont({required Object language}) => 'Select ${language} font';
	@override String get clearFont => 'Clear custom font';
	@override String get fontSaved => 'Font config saved';
	@override String get setFolderFirst => 'Please set a font folder first';
	@override String folderNotExist({required Object lang}) => 'Language folder not found: ${lang}';
	@override String noFontFiles({required Object lang}) => 'No font files in folder ${lang}';
	@override String get folderDoesNotExist => 'Folder does not exist';
	@override String get folderSetSuccess => 'Font folder set, language subfolders created';
	@override String scaleDialogTitle({required Object type}) => '${type} Scale';
	@override String get scaleDialogSubtitle => 'Adjust scale for font size consistency';
	@override String get resetValue => '100';
}

// Path: ai
class _TranslationsAiEn extends TranslationsAiZh {
	_TranslationsAiEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'AI Config';
	@override String get tabFast => 'Fast Model';
	@override String get tabStandard => 'Standard Model';
	@override String get tabAudio => 'Audio Model';
	@override String get fastModel => 'Fast Model';
	@override String get fastModelSubtitle => 'Optimized for quick lookups';
	@override String get standardModel => 'Standard Model';
	@override String get standardModelSubtitle => 'For high-quality translation and explanations';
	@override String get providerLabel => 'Select Provider';
	@override String get modelLabel => 'Model';
	@override String get modelRequired => 'Please enter a model name';
	@override String get baseUrlLabel => 'Base URL (optional)';
	@override String get baseUrlHint => 'Leave blank to use default';
	@override String get baseUrlNote => 'Only modify if using a custom endpoint or proxy';
	@override String get apiKeyRequired => 'Please enter an API Key';
	@override String defaultModel({required Object model}) => 'Default model: ${model}';
	@override String get deepThinkingTitle => 'Deep Thinking';
	@override String get deepThinkingSubtitle => 'Enable chain-of-thought on supported models';
	@override String get configSaved => 'Config saved';
	@override String get testSuccess => 'API connected successfully!';
	@override String testError({required Object message}) => 'API error: ${message}';
	@override String get testTimeout => 'Connection timed out, check network or Base URL';
	@override String testFailed({required Object message}) => 'Connection failed: ${message}';
	@override String get testApiKeyRequired => 'Please enter an API Key first';
	@override String testFailedWithError({required Object error}) => 'Test failed: ${error}';
	@override String get ttsSaved => 'TTS config saved, test it via pronunciation';
	@override String get ttsTitle => 'Configure text-to-speech for dictionary pronunciation';
	@override String get ttsBaseUrlHintGoogle => 'Leave blank to use: https://texttospeech.googleapis.com/v1';
	@override String get ttsEdgeNote => 'Edge TTS is Microsoft Edge\'s TTS service, no configuration needed';
	@override String get ttsVoiceSettings => 'Voice Settings';
	@override String get ttsVoiceSettingsSubtitle => 'Set a voice per language; used automatically during pronunciation';
	@override String get ttsNoVoice => 'No voice available';
	@override String get ttsAzureNote => 'Get API Key from Azure Speech Service';
	@override String get ttsGoogleNote => 'Use a Google Cloud Service Account JSON Key\nCreate at https://console.cloud.google.com/apis/credentials';
	@override String get providerMoonshot => 'Moonshot';
	@override String get providerZhipu => 'Zhipu AI';
	@override String get providerAli => 'Alibaba Cloud (DashScope)';
	@override String get providerCustom => 'Custom (OpenAI Compatible)';
}

// Path: cloud
class _TranslationsCloudEn extends TranslationsCloudZh {
	_TranslationsCloudEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Cloud Service';
	@override String get subscriptionLabel => 'Online Subscription URL';
	@override String get subscriptionHint => 'Enter dictionary subscription URL';
	@override String get subscriptionSaveTooltip => 'Save';
	@override String get subscriptionSaved => 'Subscription URL saved';
	@override String get subscriptionChanged => 'URL changed, logged out of current account';
	@override String get subscriptionHint2 => 'Set a subscription URL to view and download online dictionaries';
	@override String get accountTitle => 'Account';
	@override String get loginBtn => 'Login';
	@override String get registerBtn => 'Register';
	@override String get logoutBtn => 'Logout';
	@override String get loginDialogTitle => 'Login';
	@override String get usernameOrEmail => 'Username or email';
	@override String get passwordLabel => 'Password';
	@override String get registerDialogTitle => 'Register';
	@override String get usernameLabel => 'Username';
	@override String get emailLabel => 'Email';
	@override String get confirmPasswordLabel => 'Confirm Password';
	@override String get loginSuccess => 'Logged in';
	@override String get loginFailed => 'Login failed';
	@override String get loginRequired => 'Please enter username/email and password';
	@override String get registerSuccess => 'Registered';
	@override String get registerFailed => 'Registration failed';
	@override String get registerRequired => 'Please enter email, username and password';
	@override String get registerUsernameRequired => 'Please enter a username';
	@override String get registerPasswordMismatch => 'Passwords do not match';
	@override String get loggedOut => 'Logged out';
	@override String get requestTimeout => 'Request timed out, please check your network connection';
	@override String registerFailedError({required Object error}) => 'Registration failed: ${error}';
	@override String loginFailedError({required Object error}) => 'Login failed: ${error}';
	@override String get syncToCloud => 'Sync to Cloud';
	@override String get syncToCloudSubtitle => 'Upload local settings to cloud';
	@override String get syncFromCloud => 'Sync from Cloud';
	@override String get syncFromCloudSubtitle => 'Download settings from cloud';
	@override String get uploadTitle => 'Upload Settings';
	@override String get uploadConfirm => 'Upload local settings to cloud? This will overwrite cloud data.';
	@override String get uploadSuccess => 'Settings uploaded';
	@override String get uploadFailed => 'Upload failed';
	@override String get createPackageFailed => 'Failed to create settings package';
	@override String uploadFailedError({required Object error}) => 'Upload failed: ${error}';
	@override String get selectAtLeastOneFileToUpdate => 'Please select at least one file to update';
	@override String fileNameMismatch({required Object expected, required Object actual}) => 'File name mismatch. Expected "${expected}", got "${actual}"';
	@override String get downloadTitle => 'Download Settings';
	@override String get downloadConfirm => 'Download settings from cloud? This will overwrite local data.';
	@override String get downloadSuccess => 'Settings synced from cloud';
	@override String get downloadFailed => 'Download failed';
	@override String get downloadEmpty => 'No settings in cloud';
	@override String get extractFailed => 'Extraction failed';
	@override String onlineDicts({required Object count}) => 'Online Dicts (${count})';
	@override String get onlineDictsConnected => 'Connected to subscription, view and download dicts in "Dictionary Manager"';
	@override String get pushUpdatesTitle => 'Push Updates';
	@override String pushUpdateCount({required Object count}) => '${count} update records found:';
	@override String get noPushUpdates => 'No updates to push';
	@override String get noValidEntries => 'No valid entries to push';
	@override String get pushMessageLabel => 'Update message';
	@override String get pushMessageHint => 'Enter update description';
	@override String get updateEntry => 'Update entries';
	@override String get pushSuccess => 'Pushed successfully';
	@override String pushFailed({required Object error}) => 'Push failed: ${error}';
	@override String get pushFailedGeneral => 'Push failed';
	@override String loadUpdatesFailed({required Object error}) => 'Failed to load update records: ${error}';
	@override String get opInsert => '[New] ';
	@override String get opDelete => '[Deleted] ';
	@override String get loginFirst => 'Please log in first';
	@override String get serverNotSet => 'Please configure the cloud service subscription URL first';
	@override String get uploadServerNotSet => 'Please configure the upload server URL first';
	@override String get sessionExpired => 'Session expired, please log in again';
	@override String get permissionTitle => 'File Access Required';
	@override String get permissionBody => 'External directory access requires the "All Files Access" permission.\n\nTap "Authorize" to open Settings, find this app under "Manage All Files" and enable the permission.';
	@override String get goAuthorize => 'Authorize';
	@override String get permissionDenied => 'File access denied, operation cancelled';
	@override String get notLoggedIn => 'Not logged in, please log in first';
	@override String get getUserFailed => 'Failed to get user info';
	@override String getUserFailedError({required Object error}) => 'Failed to get user info: ${error}';
	@override String get requestFailed => 'Request failed';
	@override String downloadFailedError({required Object error}) => 'Download failed: ${error}';
	@override String get settingsFileNotFound => 'Settings file not found';
	@override String get noNeedToPushUpdates => 'No updates to push';
	@override String get selectAllRequiredFiles => 'Please select all required files';
	@override String get requiredField => ' (required)';
	@override String get optionalField => ' (optional)';
	@override String get uploadNewDict => 'Upload New Dictionary';
	@override String get versionNoteLabel => 'Version note';
	@override String get replaceFileHint => 'Enter version description...';
	@override String get replaceFileTip => 'Files not selected will not be updated';
	@override String get enterJsonContent => 'Please enter JSON content';
	@override String importLineError({required Object line, required Object preview}) => 'Line ${line}: parse error: "${preview}"';
	@override String get jsonParseError => 'JSON parse error';
	@override String importItemNotObject({required Object item}) => 'Item ${item} is not a JSON object';
	@override String importItemMissingId({required Object item}) => 'Item ${item} has no ID';
	@override String importItemWriteFailed({required Object item, required Object id, required Object word}) => 'Item ${item} (id=${id}, ${word}) write failed';
	@override String importItemFailed({required Object item, required Object error}) => 'Item ${item} failed: ${error}';
	@override String importSuccessCount({required Object count}) => 'Imported ${count} entries';
	@override String importFailedCount({required Object count}) => ', ${count} failed';
	@override String importMoreErrors({required Object count}) => '... and ${count} more';
	@override String importFailedError({required Object error}) => 'Import failed: ${error}';
	@override String get enterEntryId => 'Please enter entry ID';
	@override String get enterHeadword => 'Please enter headword';
	@override String entryIdNotFound({required Object id}) => 'Entry not found for ID: ${id}';
	@override String headwordNotFound({required Object word}) => 'Entry not found: "${word}"';
	@override String searchFailed({required Object error}) => 'Search failed: ${error}';
	@override String deleteEntryConfirmContent({required Object headword, required Object id}) => 'Delete "${headword}" (ID: ${id})? This cannot be undone.';
	@override String get entryDeleted => 'Entry deleted';
	@override String get entryDeleteFailed => 'Failed to delete entry';
	@override String deleteFailedError({required Object error}) => 'Delete failed: ${error}';
	@override String get updateJsonTitle => 'Update Entry Data';
	@override String get importTab => 'Import';
	@override String get deleteSearchTab => 'Delete';
	@override String get importJsonPlaceholder => 'Paste JSON or JSONL format data...';
	@override String get clearLabel => 'Clear';
	@override String get importing => 'Importing...';
	@override String get writingToDb => 'Write to DB';
	@override String get idSearch => 'Search by ID';
	@override String get prefixSearch => 'Search by headword';
	@override String get searchHeadwordLabel => 'Headword';
	@override String get searchIdHint => 'Enter entry_id';
	@override String get searchHeadwordHint => 'Enter headword';
	@override String matchedEntries({required Object count}) => '${count} entries found';
	@override String get deleting => 'Deleting...';
	@override String get deleteEntry => 'Delete Entry';
	@override String get noSyncableFiles => 'No syncable files found';
	@override String createPackageFailedError({required Object error}) => 'Failed to create package: ${error}';
	@override String get archiveNotFound => 'Archive file not found';
	@override String get archiveNoValidFiles => 'No valid files in archive';
	@override String extractFailedError({required Object error}) => 'Extraction failed: ${error}';
}

// Path: dict
class _TranslationsDictEn extends TranslationsDictZh {
	_TranslationsDictEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Dictionary Manager';
	@override String get tabSort => 'Dict Order';
	@override String get tabSource => 'Dict Source';
	@override String get tabCreator => 'Creator Center';
	@override String get localDir => 'Local Dict Directory';
	@override String get changeDirTooltip => 'Change Directory';
	@override String dirSet({required Object dir}) => 'Dict directory set: ${dir}';
	@override String get noDict => 'No dictionaries yet';
	@override String get noDictHint => 'Go to "Online Subscription" tab to set a URL\nor tap the store button to browse online dicts';
	@override String get enabled => 'Enabled (long-press to reorder)';
	@override String get disabled => 'Disabled';
	@override String enabledCount({required Object count}) => '${count}';
	@override String disabledCount({required Object count}) => '${count}';
	@override String get dragHint => 'Long-press language tab to drag and reorder';
	@override String get onlineDicts => 'Online Dictionaries';
	@override String onlineCount({required Object count}) => '${count}';
	@override String get loadFailed => 'Load failed';
	@override String get loadOnlineFailed => 'Failed to load online dictionaries';
	@override String get noOnlineDicts => 'No online dictionaries';
	@override String get noOnlineDictsHint => 'Configure subscription URL in Settings → Cloud Service first';
	@override String get noCreatorDicts => 'No uploaded dictionaries';
	@override String get noCreatorDictsHint => 'Configure cloud service and log in on the Dict Source tab first';
	@override String updateCount({required Object count}) => 'Updates (${count})';
	@override String hasUpdates({required Object count}) => '${count} dictionaries have updates';
	@override String get allUpToDate => 'All dictionaries are up to date';
	@override String get checkUpdates => 'Check Updates';
	@override String get checking => 'Checking...';
	@override String downloadDict({required Object name}) => 'Download: ${name}';
	@override String get selectContent => 'Select content to download:';
	@override String get dictMeta => '[Required] Dict metadata';
	@override String get dictIcon => '[Required] Dict icon';
	@override String get dictDb => '[Required] Dictionary database';
	@override String dictDbWithSize({required Object size}) => '[Required] Dict database (${size})';
	@override String get mediaDb => 'Media database';
	@override String mediaDbWithSize({required Object size}) => 'Media database (${size})';
	@override String mediaDbNotFound({required Object id}) => 'Media database not found for dictionary: ${id}';
	@override String get mediaDbNotExists => 'Local file not exists, skip update';
	@override String get mediaDbNotExistsCanDownload => 'Local file not exists, can download';
	@override String dictDbNotFound({required Object id}) => 'Dictionary database not found for: ${id}';
	@override String get getDictListFailed => 'Failed to get dictionary list';
	@override String get invalidResponseFormat => 'Invalid response format from server';
	@override String getDictListFailedError({required Object error}) => 'Failed to get dictionary list: ${error}';
	@override String get startDownload => 'Start Download';
	@override String get statusResuming => 'Resuming download...';
	@override String downloading({required Object step, required Object total, required Object name}) => '[${step}/${total}] Downloading ${name}';
	@override String downloadingEntries({required Object step, required Object total}) => '[${step}/${total}] Downloading entry updates';
	@override String get updateSuccess => 'Updated successfully';
	@override String updateFailed({required Object error}) => 'Update failed: ${error}';
	@override String get deleteConfirmTitle => 'Confirm Delete';
	@override String deleteConfirmBody({required Object name}) => 'Delete dictionary "${name}"?';
	@override String get deleteSuccess => 'Dictionary deleted';
	@override String deleteFailed({required Object error}) => 'Delete failed: ${error}';
	@override String get dictNotFound => 'Dictionary not found';
	@override String get dictDeleteFailed => 'Dictionary delete failed';
	@override String get statusUpdateFailed => 'Status update failed';
	@override String get statusPreparing => 'Preparing';
	@override String get statusPreparingUpdate => 'Preparing update';
	@override String get statusDownloading => 'Downloading';
	@override String get statusCompleted => 'Completed';
	@override String get storeNotConfigured => 'Dictionary storage directory not configured';
	@override String get downloadFailed => 'Download failed';
	@override String get tooltipUpdateJson => 'Update JSON';
	@override String get tooltipReplaceFile => 'Replace File';
	@override String get tooltipPushUpdate => 'Push Update';
	@override String get tooltipDelete => 'Delete';
	@override String get tooltipUpdate => 'Update dictionary';
	@override String get tooltipDownload => 'Download dictionary';
	@override String daysAgo({required Object n}) => '${n} days ago';
	@override String monthsAgo({required Object n}) => '${n} months ago';
	@override String yearsAgo({required Object n}) => '${n} years ago';
	@override String hoursAgo({required Object n}) => '${n}h ago';
	@override String minutesAgo({required Object n}) => '${n}m ago';
	@override String get justNow => 'Just now';
	@override String get dateUnknown => 'Unknown';
	@override String get noFileSelected => 'No file selected to update';
	@override String get configCloudFirst => 'Please configure cloud service first';
	@override String get getDictInfoFailed => 'Cannot get dictionary info';
	@override String versionUpdated({required Object version}) => 'Version updated to ${version}, no download needed';
	@override String get androidChoiceTitle => 'Dictionary Storage';
	@override String get androidAppDir => 'App-specific directory';
	@override String get androidAppDirWarning => 'Data will be deleted if app is uninstalled';
	@override String get androidExtDir => 'External public directory';
	@override String get androidExtDirNote => 'Data persists after app updates/uninstall';
	@override String get androidRecommended => 'Recommended';
	@override String get androidCustomDir => 'Custom path';
	@override String get androidCustomDirNote => 'Select any external directory';
	@override String get permissionGranted => 'Permission granted';
	@override String get permissionNeeded => 'Requires All Files Access permission';
	@override String cantWrite({required Object dir}) => 'Cannot write to ${dir}, check permissions';
	@override String get cantWritePicked => 'Cannot write to selected directory, please choose another';
	@override String get permissionDialogBody => 'Tap OK to open Settings, enable "Manage All Files" permission, then return to the app.';
	@override String get statsTitle => 'Statistics';
	@override String get entryCount => 'Entries';
	@override String get audioFiles => 'Audio Files';
	@override String get imageFiles => 'Image Files';
	@override String get dictInfoTitle => 'Dictionary Info';
	@override String get filesTitle => 'File Info';
	@override String get fileExists => 'Present';
	@override String get fileMissing => 'Missing';
	@override String get deleteDictTitle => 'Delete Dictionary';
	@override String deleteDictBody({required Object name}) => 'Delete "${name}"?\n\nThis will permanently delete all dictionary files (database, media, metadata, etc.).';
	@override String deleteDictSuccess({required Object name}) => '"${name}" deleted';
	@override String deleteDictFailed({required Object error}) => 'Delete failed: ${error}';
	@override String get cannotGetFileInfo => 'Cannot get file info';
	@override String updateDictTitle({required Object name}) => 'Update Dict - ${name}';
	@override String get smartUpdate => 'Smart Update';
	@override String get manualSelect => 'Manual Select';
	@override String get upToDate => 'Up to date';
	@override String get noUpdates => 'No updates available for this dictionary';
	@override String currentVersion({required Object version}) => 'Current version: v${version}';
	@override String get updateHistory => 'Update history:';
	@override String get filesToDownload => 'Files to download:';
	@override String fileLabel({required Object files}) => 'Files: ${files}';
	@override String entryLabel({required Object count}) => '${count} entries';
	@override String get noSmartUpdate => 'No smart updates available';
	@override String get selectAtLeastOneItem => 'Please select at least one item';
	@override String get batchUpdateTitle => 'Batch Update';
	@override String get recheck => 'Re-check Updates';
	@override String batchUpdateCount({required Object count}) => 'Update (${count})';
	@override String batchHasUpdates({required Object count}) => '${count} dictionaries can be updated';
	@override String get selectAll => 'Select All';
	@override String get deselectAll => 'Deselect All';
	@override String versionRange({required Object from, required Object to, required Object files}) => 'v${from} → v${to} | ${files} files';
	@override String updateRecordCount({required Object count}) => '${count} records';
	@override String get publisher => 'Publisher';
	@override String get maintainer => 'Maintainer';
	@override String get contact => 'Contact';
	@override String get versionLabel => 'Version';
	@override String get updatedLabel => 'Updated';
	@override String get detailTitle => 'Dictionary Details';
	@override String get statusPreparingUpload => 'Preparing upload';
	@override String uploadingFile({required Object step, required Object total, required Object name}) => '[${step}/${total}] Uploading ${name}';
	@override String get statusUploadCompleted => 'Upload completed';
	@override String get statusUploadFailed => 'Upload failed';
	@override String get cancelled => 'Cancelled';
	@override String get paused => 'Paused';
	@override String get pause => 'Pause';
	@override String get resume => 'Resume';
	@override String get terminate => 'Terminate';
	@override String get statusFailed => 'Failed';
	@override String get statusUpdateCompleted => 'Update completed';
	@override String downloadingFile({required Object name}) => 'Downloading ${name}';
	@override String fetchListFailedHttp({required Object code}) => 'Failed to fetch dictionary list: HTTP ${code}';
	@override String get fetchListTimeout => 'Dictionary list fetch timed out';
	@override String fetchDetailFailedHttp({required Object code}) => 'Failed to fetch dictionary detail: HTTP ${code}';
	@override String get noContentSelected => 'No content selected';
	@override String downloadingDatabase({required Object step, required Object total}) => '[${step}/${total}] Downloading dictionary database';
	@override String downloadDbFailedHttp({required Object code}) => 'Failed to download database: HTTP ${code}';
	@override String downloadingDatabaseProgress({required Object step, required Object total, required Object progress}) => '[${step}/${total}] Downloading dictionary database ${progress}%';
	@override String downloadingMedia({required Object step, required Object total}) => '[${step}/${total}] Downloading media database';
	@override String downloadMediaFailedHttp({required Object code}) => 'Failed to download media database: HTTP ${code}';
	@override String downloadingMediaProgress({required Object step, required Object total, required Object progress}) => '[${step}/${total}] Downloading media database ${progress}%';
	@override String downloadingMeta({required Object step, required Object total}) => '[${step}/${total}] Downloading metadata';
	@override String downloadMetaFailed({required Object url, required Object code}) => 'Failed to download metadata: ${url}, HTTP ${code}';
	@override String downloadingIcon({required Object step, required Object total}) => '[${step}/${total}] Downloading icon';
	@override String get responseEmpty => 'Response body is empty';
	@override String get dbDialogTitleError => 'Enhance English Search (Error)';
	@override String get dbDialogTitle => 'Enhance English Search';
	@override String get dbFeatureVariant => 'Spelling variants (colour → color)';
	@override String get dbFeatureAbbr => 'Abbreviations (abbr. → abbreviation)';
	@override String get dbFeatureNominal => 'Nominalizations (happy → happiness)';
	@override String get dbFeatureInflection => 'Inflections (runs, ran, running → run)';
	@override String get dbExample => 'e.g. Searching "colour" returns entries for "color"';
	@override String downloadError({required Object error}) => 'Download error: ${error}';
	@override String uploadError({required Object error}) => 'Upload error: ${error}';
	@override String get uploadSuccess => 'Upload successful';
	@override String downloadFileFailedError({required Object name, required Object error}) => 'Failed to download ${name}: ${error}';
	@override String downloadFileFailed({required Object name}) => 'Failed to download ${name}';
	@override String get downloadEntriesFailed => 'Failed to download entry updates';
	@override String get searchEntries => 'Search entries...';
	@override String get noEntries => 'No entries';
	@override String get dbNotExists => 'English dictionary database not found, please download first';
	@override String crc32Mismatch({required Object file, required Object expected, required Object actual}) => 'CRC32 verification failed for ${file}: expected ${expected}, got ${actual}';
	@override String crc32VerifyFailed({required Object error}) => 'CRC32 verification error: ${error}';
}

// Path: entry
class _TranslationsEntryEn extends TranslationsEntryZh {
	_TranslationsEntryEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String wordRemoved({required Object word}) => 'Removed "${word}" from word bank';
	@override String wordListUpdated({required Object word}) => 'Updated word list for "${word}"';
	@override String get selectAtLeastOne => 'Please select at least one list';
	@override String wordAdded({required Object word}) => 'Added "${word}" to word bank';
	@override String get addFailed => 'Add failed';
	@override String get noEntry => 'Cannot get current entry';
	@override String get entryIncomplete => 'Entry information is incomplete';
	@override String get resetting => 'Resetting entry...';
	@override String get notFoundOnServer => 'Entry not found on server';
	@override String get resetSuccess => 'Entry reset';
	@override String get resetFailed => 'Reset failed';
	@override String saveFailed({required Object error}) => 'Save failed: ${error}';
	@override String get saveSuccess => 'Saved';
	@override String processFailed({required Object error}) => 'Process failed: ${error}';
	@override String get translating => 'Translating...';
	@override String translateFailed({required Object error}) => 'Translation failed: ${error}';
	@override String toggleFailed({required Object error}) => 'Toggle failed: ${error}';
	@override String wordNotFound({required Object word}) => 'Word not found: ${word}';
	@override String get noPageContent => 'No content on this page';
	@override String get copiedToClipboard => 'Copied to clipboard';
	@override String get pathCopiedToClipboard => 'Path copied to clipboard';
	@override String get pathNotFound => 'Path not found';
	@override String aiRequestFailed({required Object error}) => 'AI request failed: ${error}';
	@override String get aiRequestFailedShort => 'Request failed:';
	@override String aiChatFailed({required Object error}) => 'AI request failed: ${error}';
	@override String aiSumFailed({required Object error}) => 'AI summary failed: ${error}';
	@override String get summarizePage => 'Summarize current page';
	@override String get deleteRecord => 'Delete record';
	@override String get deleteRecordConfirm => 'Delete this AI chat record?';
	@override String get aiThinking => 'AI is thinking...';
	@override String get outputting => 'Generating...';
	@override String get thinkingProcess => 'Thinking';
	@override String get noChatHistory => 'No chat history';
	@override String get continueChatTitle => 'Continue Chat';
	@override String get originalQuestion => 'Original Question';
	@override String get aiAnswer => 'AI Answer';
	@override String get continueAsk => 'Continue asking';
	@override String get continueAskHint => 'Ask a follow-up question...';
	@override String get regenerate => 'Regenerate';
	@override String get moreConc => 'More Concise';
	@override String get moreDetailed => 'More Detailed';
	@override String get chatInputHint => 'Ask anything...';
	@override String get justNow => 'Just now';
	@override String minutesAgo({required Object n}) => '${n}m ago';
	@override String hoursAgo({required Object n}) => '${n}h ago';
	@override String daysAgo({required Object n}) => '${n}d ago';
	@override String get morphBase => 'Base';
	@override String get morphNominal => 'Nominal';
	@override String get morphPlural => 'Plural';
	@override String get morphPast => 'Past';
	@override String get morphPastPart => 'Past Participle';
	@override String get morphPresPart => 'Present Participle';
	@override String get morphThirdSing => '3rd Sing.';
	@override String get morphComp => 'Comparative';
	@override String get morphSuperl => 'Superlative';
	@override String get morphSpellingVariant => 'Variant';
	@override String get morphNominalization => 'Nominalization';
	@override String get morphInflection => 'Inflection';
	@override String get uncountable => 'uncountable';
	@override String get summaryQuestion => 'Please summarize all dictionary content on this page';
	@override String get summaryTitle => 'Current page summary';
	@override String get aiSummaryButton => 'Tap to AI Summarize';
	@override String summaryEntriesLabel({required Object first, required Object count}) => '${first} and ${count} entries';
	@override String chatStartSummary({required Object dict, required Object page}) => '${dict} [${page}] AI Summary';
	@override String chatStartElement({required Object dict, required Object path}) => '${dict} [${path}] AI Inquiry';
	@override String chatStartFreeChat({required Object word}) => '"${word}" Free Chat';
	@override String get chatOverviewFreeChat => 'Free Chat';
	@override String chatOverviewSummary({required Object dict, required Object page}) => '${dict} [${page}] AI Summary';
	@override String chatOverviewSummaryNoPage({required Object dict}) => '${dict} AI Summary';
	@override String chatOverviewAsk({required Object dict}) => '${dict} AI Inquiry';
	@override String get returnToStart => 'Return to initial path';
	@override String get path => 'Path';
	@override String explainPrompt({required Object word}) => 'This is part of the dictionary entry for "${word}", please explain this section.';
	@override String currentWord({required Object word}) => 'Current word: ${word}';
	@override String currentDict({required Object dictId}) => 'Current dictionary: ${dictId}';
	@override String entryNotFound({required Object entryId}) => 'Entry not found: ${entryId}';
	@override String get returnToOriginal => 'Return';
	@override String get extractFailed => 'Failed to extract text';
	@override String get generatingAudio => 'Generating audio...';
	@override String speakFailed({required Object error}) => 'TTS failed: ${error}';
	@override String phraseNotFound({required Object phrase}) => 'Phrase not found: "${phrase}"';
	@override String get imageLoadFailed => 'Failed to load image';
	@override String get rootMustBeObject => 'Root must be a JSON object';
	@override String get dbUpdateFailed => 'Failed to save to database';
	@override String jsonFormatFailed({required Object error}) => 'Format failed: ${error}';
	@override String jsonSyntaxError({required Object error}) => 'JSON syntax error: ${error}';
	@override String get formatJson => 'Format JSON';
	@override String get syntaxError => 'Syntax error';
	@override String get syntaxCheck => 'Syntax OK';
	@override String jsonErrorLabel({required Object error}) => 'Syntax error: ${error}';
	@override String get spellingVariantLabel => 'Spelling variant';
	@override String get abbreviationLabel => 'Abbreviation';
	@override String get acronymLabel => 'Acronym';
	@override String get morphPluralForm => 'Plural form';
	@override String get morphThirdSingFull => 'Third person singular';
}

// Path: groups
class _TranslationsGroupsEn extends TranslationsGroupsZh {
	_TranslationsGroupsEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Group Management';
	@override String get manageGroups => 'Manage Groups';
	@override String get createGroup => 'Create Group';
	@override String get editGroup => 'Edit Group';
	@override String get deleteGroup => 'Delete Group';
	@override String deleteGroupConfirm({required Object name}) => 'Are you sure you want to delete group "${name}"? Its subgroups will also be deleted.';
	@override String get groupName => 'Group Name';
	@override String get groupNameHint => 'Enter group name';
	@override String get description => 'Description';
	@override String get descriptionHint => 'Optional, supports JSON format component list';
	@override String get subGroups => 'Subgroups';
	@override String get entries => 'Entries';
	@override String get noGroups => 'No groups';
	@override String get noSubGroups => 'No subgroups';
	@override String get noEntries => 'No entries';
	@override String get belongsTo => 'Belongs to';
	@override String get breadcrumb => 'Location';
	@override String get rootGroup => 'Root';
	@override String get addEntry => 'Add Entry';
	@override String get addEntryHint => 'Search by headword';
	@override String get removeEntry => 'Remove Entry';
	@override String get entryAdded => 'Entry added to group';
	@override String get entryRemoved => 'Entry removed from group';
	@override String get groupCreated => 'Group created';
	@override String get groupUpdated => 'Group updated';
	@override String get groupDeleted => 'Group deleted';
	@override String get createFailed => 'Failed to create group';
	@override String get updateFailed => 'Failed to update group';
	@override String get deleteFailed => 'Failed to delete group';
	@override String get loadFailed => 'Failed to load groups';
	@override String statsInfo({required Object groups, required Object items}) => '${groups} groups, ${items} entries';
	@override String get navigateToEntry => 'Navigate to entry';
	@override String get navigateToAnchor => 'Navigate to anchor';
	@override String groupLink({required Object name}) => 'Group: ${name}';
	@override String get parentGroup => 'Parent Group';
	@override String get selectParent => 'Select Parent';
	@override String get none => 'None (Root)';
	@override String anchorInfo({required Object anchor}) => 'Anchor: ${anchor}';
	@override String get wholeEntry => 'Whole Entry';
}

// Path: settings.audioBackendDialog
class _TranslationsSettingsAudioBackendDialogEn extends TranslationsSettingsAudioBackendDialogZh {
	_TranslationsSettingsAudioBackendDialogEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Audio Playback Engine';
	@override String get subtitle => 'Select audio backend (switch if Android playback stutters)';
	@override String get mediaKit => 'MediaKit (Default)';
	@override String get audioplayers => 'AudioPlayers';
}

// Path: settings.scaleDialog
class _TranslationsSettingsScaleDialogEn extends TranslationsSettingsScaleDialogZh {
	_TranslationsSettingsScaleDialogEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Layout Scale';
	@override String get subtitle => 'Adjust the overall scale of dictionary content display';
	@override String get confirmTitle => 'Keep scale change?';
	@override String confirmBody({required Object percent, required Object seconds}) => 'New scale is ${percent}%.\nWill auto-revert in ${seconds} seconds.';
}

// Path: settings.clickActionDialog
class _TranslationsSettingsClickActionDialogEn extends TranslationsSettingsClickActionDialogZh {
	_TranslationsSettingsClickActionDialogEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Click Action Settings';
	@override String get hint => 'The first item is the tap action; others are triggered via right-click/long-press';
	@override String get primaryLabel => 'Tap Action';
}

// Path: settings.toolbarDialog
class _TranslationsSettingsToolbarDialogEn extends TranslationsSettingsToolbarDialogZh {
	_TranslationsSettingsToolbarDialogEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Bottom Toolbar Settings';
	@override String hint({required Object max}) => 'Drag to reorder; items below the divider go to the overflow menu; max ${max} toolbar icons';
	@override String get dividerLabel => 'Divider (drag to adjust)';
	@override String get toolbar => 'Toolbar';
	@override String get overflow => 'More Menu';
	@override String maxItemsError({required Object max}) => 'The toolbar can have at most ${max} items';
}

// Path: settings.misc_page
class _TranslationsSettingsMiscPageEn extends TranslationsSettingsMiscPageZh {
	_TranslationsSettingsMiscPageEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Other Settings';
	@override String get aiChatTitle => 'AI Chat History';
	@override String get recordCount => 'Total Records';
	@override String records({required Object count}) => '${count} records';
	@override String get autoCleanup => 'Auto Cleanup';
	@override String get noAutoCleanup => 'No Auto Cleanup';
	@override String keepRecentDays({required Object days}) => 'Keep last ${days} days';
	@override String get clearAll => 'Clear All Chat History';
	@override String get clearAllConfirmTitle => 'Confirm Clear';
	@override String get clearAllConfirmBody => 'Delete all AI chat history? This cannot be undone.';
	@override String get clearAllSuccess => 'All chat history cleared';
	@override String get auxDbTitle => 'Auxiliary Dictionary Database';
	@override String get skipAskRedirect => 'Don\'t ask when redirecting to aux database';
	@override String get skipAskEnabled => 'No longer asking';
	@override String get skipAskDisabled => 'Restored asking';
	@override String get deleteAuxDb => 'Delete Aux Dictionary Database';
	@override String get auxDbInstalled => 'English database installed, tap to delete';
	@override String get auxDbNotInstalled => 'No auxiliary database installed';
	@override String get deleteAuxDbConfirmTitle => 'Delete Database';
	@override String get deleteAuxDbConfirmBody => 'Delete auxiliary dictionary database? You can re-download it later.';
	@override String get deleteAuxDbSuccess => 'Aux database deleted';
	@override String get deleteAuxDbNotExist => 'Database file not found';
	@override String get dictUpdateTitle => 'Dictionary Update Settings';
	@override String get autoCheckDictUpdate => 'Auto Check Dict Updates';
	@override String get autoCheckDictUpdateSubtitle => 'Check daily if local dictionaries have updates';
	@override String get autoCleanupDialogTitle => 'Auto Cleanup Settings';
	@override String get keep7Days => 'Keep last 7 days';
	@override String get keep30Days => 'Keep last 30 days';
	@override String get keep90Days => 'Keep last 90 days';
	@override String get desktopFeaturesTitle => 'Desktop Features';
}

// Path: settings.actionLabel
class _TranslationsSettingsActionLabelEn extends TranslationsSettingsActionLabelZh {
	_TranslationsSettingsActionLabelEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get aiTranslate => 'Translate';
	@override String get copy => 'Copy Text';
	@override String get askAi => 'Ask AI';
	@override String get edit => 'Edit';
	@override String get speak => 'Speak';
	@override String get back => 'Back';
	@override String get search => 'Search';
	@override String get favorite => 'Favorite';
	@override String get toggleTranslate => 'Show/Hide Translation';
	@override String get aiHistory => 'AI History';
	@override String get resetEntry => 'Reset Entry';
}

// Path: theme.colorNames
class _TranslationsThemeColorNamesEn extends TranslationsThemeColorNamesZh {
	_TranslationsThemeColorNamesEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get blue => 'Blue';
	@override String get indigo => 'Indigo';
	@override String get purple => 'Purple';
	@override String get deepPurple => 'Deep Purple';
	@override String get pink => 'Pink';
	@override String get red => 'Red';
	@override String get deepOrange => 'Deep Orange';
	@override String get orange => 'Orange';
	@override String get amber => 'Amber';
	@override String get yellow => 'Yellow';
	@override String get lime => 'Lime';
	@override String get lightGreen => 'Light Green';
	@override String get green => 'Green';
	@override String get teal => 'Teal';
	@override String get cyan => 'Cyan';
}

/// The flat map containing all translations for locale <en>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsEn {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'nav.search' => 'Search',
			'nav.wordBank' => 'Word Bank',
			'nav.settings' => 'Settings',
			'language.auto' => 'Follow System',
			'language.zh' => '中文',
			'language.en' => 'English',
			'language.dialogTitle' => 'App Language',
			'language.dialogSubtitle' => 'Select the display language',
			'common.ok' => 'OK',
			'common.cancel' => 'Cancel',
			'common.save' => 'Save',
			'common.confirm' => 'Confirm',
			'common.undo' => 'Undo',
			'common.delete' => 'Delete',
			'common.clear' => 'Clear',
			'common.reset' => 'Reset',
			'common.close' => 'Close',
			'common.back' => 'Back',
			'common.loading' => 'Loading...',
			'common.noData' => 'No data',
			'common.done' => 'Done',
			'common.rename' => 'Rename',
			'common.import' => 'Import',
			'common.all' => 'All',
			'common.warning' => 'Warning',
			'common.irreversible' => 'This action cannot be undone',
			'common.retry' => 'Retry',
			'common.logout' => 'Logout',
			'common.login' => 'Login',
			'common.register' => 'Register',
			'common.copy' => 'Copy',
			'common.continue_' => 'Continue',
			'common.set_' => 'Set',
			'common.change' => 'Change',
			'common.update' => 'Update',
			'common.download' => 'Download',
			'common.upload' => 'Upload',
			'common.noContent' => 'No content',
			'common.error' => 'Error',
			'common.success' => 'Success',
			'common.testing' => 'Testing...',
			'common.testConnection' => 'Test Config',
			'common.saveConfig' => 'Save Config',
			'common.unknown' => 'Unknown',
			'common.fullscreen' => 'Fullscreen',
			'common.exitFullscreen' => 'Exit Fullscreen',
			'common.retryLater' => 'Please try again later',
			'common.notNow' => 'Not Now',
			'common.neverAskAgain' => 'Never Ask Again',
			'common.redo' => 'Redo',
			'common.selectLanguage' => 'Select Language',
			'settings.title' => 'Settings',
			'settings.cloudService' => 'Cloud Service',
			'settings.dictionaryManager' => 'Dictionary Manager',
			'settings.aiConfig' => 'AI Config',
			'settings.fontConfig' => 'Font Config',
			'settings.themeSettings' => 'Theme Settings',
			'settings.layoutScale' => 'Layout Scale',
			'settings.clickAction' => 'Click Action',
			'settings.toolbar' => 'Bottom Toolbar',
			'settings.misc' => 'Other Settings',
			'settings.about' => 'About',
			'settings.appLanguage' => 'App Language',
			'settings.audioBackend' => 'Audio Playback Engine',
			'settings.audioBackendDialog.title' => 'Audio Playback Engine',
			'settings.audioBackendDialog.subtitle' => 'Select audio backend (switch if Android playback stutters)',
			'settings.audioBackendDialog.mediaKit' => 'MediaKit (Default)',
			'settings.audioBackendDialog.audioplayers' => 'AudioPlayers',
			'settings.scaleDialog.title' => 'Layout Scale',
			'settings.scaleDialog.subtitle' => 'Adjust the overall scale of dictionary content display',
			'settings.scaleDialog.confirmTitle' => 'Keep scale change?',
			'settings.scaleDialog.confirmBody' => ({required Object percent, required Object seconds}) => 'New scale is ${percent}%.\nWill auto-revert in ${seconds} seconds.',
			'settings.clickActionDialog.title' => 'Click Action Settings',
			'settings.clickActionDialog.hint' => 'The first item is the tap action; others are triggered via right-click/long-press',
			'settings.clickActionDialog.primaryLabel' => 'Tap Action',
			'settings.toolbarDialog.title' => 'Bottom Toolbar Settings',
			'settings.toolbarDialog.hint' => ({required Object max}) => 'Drag to reorder; items below the divider go to the overflow menu; max ${max} toolbar icons',
			'settings.toolbarDialog.dividerLabel' => 'Divider (drag to adjust)',
			'settings.toolbarDialog.toolbar' => 'Toolbar',
			'settings.toolbarDialog.overflow' => 'More Menu',
			'settings.toolbarDialog.maxItemsError' => ({required Object max}) => 'The toolbar can have at most ${max} items',
			'settings.misc_page.title' => 'Other Settings',
			'settings.misc_page.aiChatTitle' => 'AI Chat History',
			'settings.misc_page.recordCount' => 'Total Records',
			'settings.misc_page.records' => ({required Object count}) => '${count} records',
			'settings.misc_page.autoCleanup' => 'Auto Cleanup',
			'settings.misc_page.noAutoCleanup' => 'No Auto Cleanup',
			'settings.misc_page.keepRecentDays' => ({required Object days}) => 'Keep last ${days} days',
			'settings.misc_page.clearAll' => 'Clear All Chat History',
			'settings.misc_page.clearAllConfirmTitle' => 'Confirm Clear',
			'settings.misc_page.clearAllConfirmBody' => 'Delete all AI chat history? This cannot be undone.',
			'settings.misc_page.clearAllSuccess' => 'All chat history cleared',
			'settings.misc_page.auxDbTitle' => 'Auxiliary Dictionary Database',
			'settings.misc_page.skipAskRedirect' => 'Don\'t ask when redirecting to aux database',
			'settings.misc_page.skipAskEnabled' => 'No longer asking',
			'settings.misc_page.skipAskDisabled' => 'Restored asking',
			'settings.misc_page.deleteAuxDb' => 'Delete Aux Dictionary Database',
			'settings.misc_page.auxDbInstalled' => 'English database installed, tap to delete',
			'settings.misc_page.auxDbNotInstalled' => 'No auxiliary database installed',
			'settings.misc_page.deleteAuxDbConfirmTitle' => 'Delete Database',
			'settings.misc_page.deleteAuxDbConfirmBody' => 'Delete auxiliary dictionary database? You can re-download it later.',
			'settings.misc_page.deleteAuxDbSuccess' => 'Aux database deleted',
			'settings.misc_page.deleteAuxDbNotExist' => 'Database file not found',
			'settings.misc_page.dictUpdateTitle' => 'Dictionary Update Settings',
			'settings.misc_page.autoCheckDictUpdate' => 'Auto Check Dict Updates',
			'settings.misc_page.autoCheckDictUpdateSubtitle' => 'Check daily if local dictionaries have updates',
			'settings.misc_page.autoCleanupDialogTitle' => 'Auto Cleanup Settings',
			'settings.misc_page.keep7Days' => 'Keep last 7 days',
			'settings.misc_page.keep30Days' => 'Keep last 30 days',
			'settings.misc_page.keep90Days' => 'Keep last 90 days',
			'settings.misc_page.desktopFeaturesTitle' => 'Desktop Features',
			'settings.actionLabel.aiTranslate' => 'Translate',
			'settings.actionLabel.copy' => 'Copy Text',
			'settings.actionLabel.askAi' => 'Ask AI',
			'settings.actionLabel.edit' => 'Edit',
			'settings.actionLabel.speak' => 'Speak',
			'settings.actionLabel.back' => 'Back',
			'settings.actionLabel.search' => 'Search',
			'settings.actionLabel.favorite' => 'Favorite',
			'settings.actionLabel.toggleTranslate' => 'Show/Hide Translation',
			'settings.actionLabel.aiHistory' => 'AI History',
			'settings.actionLabel.resetEntry' => 'Reset Entry',
			'settings.clipboardWatch' => 'Clipboard Watch',
			'settings.clipboardWatchEnabled' => 'Enabled, auto-search when copying text',
			'settings.clipboardWatchDisabled' => 'Disabled',
			'settings.minimizeToTray' => 'Minimize to Tray',
			'settings.minimizeToTrayDesc' => 'Minimize to system tray when closing window',
			'search.hint' => 'Enter a word',
			'search.hintWordBank' => 'Search word bank',
			'search.noResult' => ({required Object word}) => 'Word not found: ${word}',
			'search.startHint' => 'Enter a word to start lookup',
			'search.historyTitle' => 'History',
			'search.historyClear' => 'Clear',
			'search.historyCleared' => 'History cleared',
			'search.historyDeleted' => ({required Object word}) => 'Deleted "${word}"',
			'search.wildcardNoEntry' => 'In wildcard mode, please select a word from the candidate list',
			'search.advancedOptions' => 'Advanced Options',
			'search.searchBtn' => 'Search',
			'search.searchOptionsTitle' => 'Search Options',
			'search.exactMatch' => 'Exact Match',
			'search.toneExact' => 'Distinguish Trad/Simp',
			'search.phoneticCandidates' => 'Phonetic Candidates',
			'search.searchResults' => 'Search Results',
			'search.noEnabledDicts' => 'No dictionaries are enabled',
			'search.wildcardHint' => 'LIKE pattern (enter % or _):\n  % matches any number of chars, _ matches exactly one\n  e.g. hel% → hello, help; h_llo → hello, hallo\n\nGLOB pattern (enter * ? [ ] ^), case-sensitive:\n  * matches any chars, ? matches one char\n  [abc] matches any char in brackets, [^abc] excludes them\n  e.g. h?llo → hello, hallo; [aeiou]* → words starting with a vowel',
			'search.dbDownloaded' => ({required Object word}) => 'Download complete, search "${word}" to test',
			'search.dailyWords' => 'Daily Vocabulary',
			'search.dailyWordsRefresh' => 'Refresh',
			'search.dailyWordsSettings' => 'Settings',
			'search.dailyWordsCount' => 'Word Count',
			'search.dailyWordsLanguage' => 'List Language',
			'search.dailyWordsList' => 'List Scope',
			'search.dailyWordsAllLists' => 'All Lists',
			'search.dailyWordsNoWords' => 'No words in the list',
			'search.dailyWordsNoList' => 'No list available',
			'wordBank.title' => 'Word Bank',
			'wordBank.empty' => 'Your word bank is empty',
			'wordBank.emptyHint' => 'Tap the favorite button while looking up words to add them',
			'wordBank.noWordsFound' => 'No words found',
			'wordBank.wordNotFound' => ({required Object word}) => 'Word not found: ${word}',
			'wordBank.wordRemoved' => 'Word removed',
			'wordBank.wordListUpdated' => 'Word list updated',
			'wordBank.manageLists' => 'Manage Lists',
			'wordBank.sortTooltip' => 'Sort by',
			'wordBank.sortAddTimeDesc' => 'Add Order',
			'wordBank.sortAlphabetical' => 'Alphabetical',
			'wordBank.sortRandom' => 'Random',
			'wordBank.importToLanguage' => ({required Object language}) => 'Import to ${language}',
			'wordBank.listNameLabel' => 'List name:',
			'wordBank.listNameHint' => 'e.g. TOEFL, IELTS, GRE',
			'wordBank.pickFile' => 'Pick File',
			'wordBank.previewWords' => 'Preview 10 words:',
			'wordBank.previewCount' => ({required Object count}) => '${count} words recognized (preview)',
			'wordBank.importSuccess' => ({required Object count, required Object list}) => 'Successfully imported ${count} words to "${list}"',
			'wordBank.importFailed' => 'Import failed',
			'wordBank.importListExists' => ({required Object list}) => 'List "${list}" already exists, please use a different name',
			'wordBank.importFileError' => 'Failed to read file',
			'wordBank.editListsTitle' => ({required Object language}) => 'Edit ${language} Lists',
			'wordBank.renameList' => 'Rename List',
			'wordBank.listNameFieldLabel' => 'List name',
			'wordBank.listNameFieldHint' => 'Enter new name',
			'wordBank.deleteList' => 'Delete List',
			'wordBank.deleteListConfirm' => ({required Object name}) => 'Delete list "${name}"?\n\nThis will delete the list and all its data. Words not in any other list will also be deleted.',
			'wordBank.importListBtn' => 'Import List',
			'wordBank.listSaved' => 'List updated',
			'wordBank.listOpFailed' => 'Operation failed',
			'wordBank.listNameExists' => 'List name already exists, please use a different name',
			'wordBank.selectLists' => 'Select lists',
			'wordBank.adjustLists' => ({required Object word}) => 'Adjust lists for "${word}"',
			'wordBank.newListHint' => 'Add new list...',
			'wordBank.removeWord' => 'Remove word',
			'theme.title' => 'Theme Settings',
			'theme.light' => 'Light',
			'theme.dark' => 'Dark',
			'theme.system' => 'Follow System',
			'theme.seedColor' => 'Seed Color',
			'theme.systemAccent' => 'System Accent',
			'theme.custom' => 'Custom',
			'theme.appearanceMode' => 'Appearance Mode',
			'theme.themeColor' => 'Theme Color',
			'theme.preview' => 'Preview',
			'theme.followSystem' => 'Follow System',
			'theme.lightMode' => 'Light Mode',
			'theme.darkMode' => 'Dark Mode',
			'theme.previewText' => 'This is sample text showing the app\'s theme preview.',
			'theme.primaryColor' => 'Primary',
			'theme.primaryContainer' => 'Primary Container',
			'theme.secondary' => 'Secondary',
			'theme.tertiary' => 'Tertiary',
			'theme.surface' => 'Background',
			'theme.card' => 'Card',
			'theme.error' => 'Error',
			'theme.outline' => 'Border',
			'theme.colorNames.blue' => 'Blue',
			'theme.colorNames.indigo' => 'Indigo',
			'theme.colorNames.purple' => 'Purple',
			'theme.colorNames.deepPurple' => 'Deep Purple',
			'theme.colorNames.pink' => 'Pink',
			'theme.colorNames.red' => 'Red',
			'theme.colorNames.deepOrange' => 'Deep Orange',
			'theme.colorNames.orange' => 'Orange',
			'theme.colorNames.amber' => 'Amber',
			'theme.colorNames.yellow' => 'Yellow',
			'theme.colorNames.lime' => 'Lime',
			'theme.colorNames.lightGreen' => 'Light Green',
			'theme.colorNames.green' => 'Green',
			'theme.colorNames.teal' => 'Teal',
			'theme.colorNames.cyan' => 'Cyan',
			'help.title' => 'About',
			'help.tagline' => 'Look up words, hassle-free',
			'help.forumTitle' => 'Feedback',
			'help.forumSubtitle' => 'Suggestions and feedback welcome',
			'help.githubSubtitle' => 'View source code, file issues',
			'help.afdianTitle' => 'Afdian',
			'help.afdianSubtitle' => 'Support the developer',
			'help.checkUpdate' => 'Check for Updates',
			'help.checking' => 'Checking…',
			'help.updateAvailable' => ({required Object version}) => 'New version ${version} found · Click to download from GitHub',
			'help.upToDate' => ({required Object version}) => 'Up to date (${version})',
			'help.currentVersion' => ({required Object version}) => 'Current version ${version}',
			'help.updateError' => 'Check failed, tap to retry',
			'help.githubApiError' => ({required Object code}) => 'GitHub API error (status ${code})',
			'help.checkUpdateError' => ({required Object error}) => 'Update check failed: ${error}',
			'langNames.zh' => 'Chinese',
			'langNames.jp' => 'Japanese',
			'langNames.ko' => 'Korean',
			'langNames.en' => 'English',
			'langNames.fr' => 'French',
			'langNames.de' => 'German',
			'langNames.es' => 'Spanish',
			'langNames.it' => 'Italian',
			'langNames.ru' => 'Russian',
			'langNames.pt' => 'Portuguese',
			'langNames.ar' => 'Arabic',
			'langNames.text' => 'Text',
			'langNames.auto' => 'Auto',
			'langNames.zhHans' => 'Simplified Chinese',
			'langNames.zhHant' => 'Traditional Chinese',
			'font.title' => 'Font Config',
			'font.folderLabel' => 'Font Folder',
			'font.folderNotSet' => 'Not set',
			'font.folderSet' => 'Set',
			'font.folderChange' => 'Change',
			'font.refreshTooltip' => 'Refresh Fonts',
			'font.refreshSuccess' => 'Fonts refreshed',
			'font.noDicts' => 'No dictionaries with language info found',
			'font.sansSerif' => 'Sans-serif',
			'font.serif' => 'Serif',
			'font.regular' => 'Regular',
			'font.bold' => 'Bold',
			'font.italic' => 'Italic',
			'font.boldItalic' => 'Bold Italic',
			'font.notConfigured' => 'Not configured',
			'font.selectFont' => ({required Object language}) => 'Select ${language} font',
			'font.clearFont' => 'Clear custom font',
			'font.fontSaved' => 'Font config saved',
			'font.setFolderFirst' => 'Please set a font folder first',
			'font.folderNotExist' => ({required Object lang}) => 'Language folder not found: ${lang}',
			'font.noFontFiles' => ({required Object lang}) => 'No font files in folder ${lang}',
			'font.folderDoesNotExist' => 'Folder does not exist',
			'font.folderSetSuccess' => 'Font folder set, language subfolders created',
			'font.scaleDialogTitle' => ({required Object type}) => '${type} Scale',
			'font.scaleDialogSubtitle' => 'Adjust scale for font size consistency',
			'font.resetValue' => '100',
			'ai.title' => 'AI Config',
			'ai.tabFast' => 'Fast Model',
			'ai.tabStandard' => 'Standard Model',
			'ai.tabAudio' => 'Audio Model',
			'ai.fastModel' => 'Fast Model',
			'ai.fastModelSubtitle' => 'Optimized for quick lookups',
			'ai.standardModel' => 'Standard Model',
			'ai.standardModelSubtitle' => 'For high-quality translation and explanations',
			'ai.providerLabel' => 'Select Provider',
			'ai.modelLabel' => 'Model',
			'ai.modelRequired' => 'Please enter a model name',
			'ai.baseUrlLabel' => 'Base URL (optional)',
			'ai.baseUrlHint' => 'Leave blank to use default',
			'ai.baseUrlNote' => 'Only modify if using a custom endpoint or proxy',
			'ai.apiKeyRequired' => 'Please enter an API Key',
			'ai.defaultModel' => ({required Object model}) => 'Default model: ${model}',
			'ai.deepThinkingTitle' => 'Deep Thinking',
			'ai.deepThinkingSubtitle' => 'Enable chain-of-thought on supported models',
			'ai.configSaved' => 'Config saved',
			'ai.testSuccess' => 'API connected successfully!',
			'ai.testError' => ({required Object message}) => 'API error: ${message}',
			'ai.testTimeout' => 'Connection timed out, check network or Base URL',
			'ai.testFailed' => ({required Object message}) => 'Connection failed: ${message}',
			'ai.testApiKeyRequired' => 'Please enter an API Key first',
			'ai.testFailedWithError' => ({required Object error}) => 'Test failed: ${error}',
			'ai.ttsSaved' => 'TTS config saved, test it via pronunciation',
			'ai.ttsTitle' => 'Configure text-to-speech for dictionary pronunciation',
			'ai.ttsBaseUrlHintGoogle' => 'Leave blank to use: https://texttospeech.googleapis.com/v1',
			'ai.ttsEdgeNote' => 'Edge TTS is Microsoft Edge\'s TTS service, no configuration needed',
			'ai.ttsVoiceSettings' => 'Voice Settings',
			'ai.ttsVoiceSettingsSubtitle' => 'Set a voice per language; used automatically during pronunciation',
			'ai.ttsNoVoice' => 'No voice available',
			'ai.ttsAzureNote' => 'Get API Key from Azure Speech Service',
			'ai.ttsGoogleNote' => 'Use a Google Cloud Service Account JSON Key\nCreate at https://console.cloud.google.com/apis/credentials',
			'ai.providerMoonshot' => 'Moonshot',
			'ai.providerZhipu' => 'Zhipu AI',
			'ai.providerAli' => 'Alibaba Cloud (DashScope)',
			'ai.providerCustom' => 'Custom (OpenAI Compatible)',
			'cloud.title' => 'Cloud Service',
			'cloud.subscriptionLabel' => 'Online Subscription URL',
			'cloud.subscriptionHint' => 'Enter dictionary subscription URL',
			'cloud.subscriptionSaveTooltip' => 'Save',
			'cloud.subscriptionSaved' => 'Subscription URL saved',
			'cloud.subscriptionChanged' => 'URL changed, logged out of current account',
			'cloud.subscriptionHint2' => 'Set a subscription URL to view and download online dictionaries',
			'cloud.accountTitle' => 'Account',
			'cloud.loginBtn' => 'Login',
			'cloud.registerBtn' => 'Register',
			'cloud.logoutBtn' => 'Logout',
			'cloud.loginDialogTitle' => 'Login',
			'cloud.usernameOrEmail' => 'Username or email',
			'cloud.passwordLabel' => 'Password',
			'cloud.registerDialogTitle' => 'Register',
			'cloud.usernameLabel' => 'Username',
			'cloud.emailLabel' => 'Email',
			'cloud.confirmPasswordLabel' => 'Confirm Password',
			'cloud.loginSuccess' => 'Logged in',
			'cloud.loginFailed' => 'Login failed',
			'cloud.loginRequired' => 'Please enter username/email and password',
			'cloud.registerSuccess' => 'Registered',
			'cloud.registerFailed' => 'Registration failed',
			'cloud.registerRequired' => 'Please enter email, username and password',
			'cloud.registerUsernameRequired' => 'Please enter a username',
			'cloud.registerPasswordMismatch' => 'Passwords do not match',
			'cloud.loggedOut' => 'Logged out',
			'cloud.requestTimeout' => 'Request timed out, please check your network connection',
			'cloud.registerFailedError' => ({required Object error}) => 'Registration failed: ${error}',
			'cloud.loginFailedError' => ({required Object error}) => 'Login failed: ${error}',
			'cloud.syncToCloud' => 'Sync to Cloud',
			'cloud.syncToCloudSubtitle' => 'Upload local settings to cloud',
			'cloud.syncFromCloud' => 'Sync from Cloud',
			'cloud.syncFromCloudSubtitle' => 'Download settings from cloud',
			'cloud.uploadTitle' => 'Upload Settings',
			'cloud.uploadConfirm' => 'Upload local settings to cloud? This will overwrite cloud data.',
			'cloud.uploadSuccess' => 'Settings uploaded',
			'cloud.uploadFailed' => 'Upload failed',
			'cloud.createPackageFailed' => 'Failed to create settings package',
			'cloud.uploadFailedError' => ({required Object error}) => 'Upload failed: ${error}',
			'cloud.selectAtLeastOneFileToUpdate' => 'Please select at least one file to update',
			'cloud.fileNameMismatch' => ({required Object expected, required Object actual}) => 'File name mismatch. Expected "${expected}", got "${actual}"',
			'cloud.downloadTitle' => 'Download Settings',
			'cloud.downloadConfirm' => 'Download settings from cloud? This will overwrite local data.',
			'cloud.downloadSuccess' => 'Settings synced from cloud',
			'cloud.downloadFailed' => 'Download failed',
			'cloud.downloadEmpty' => 'No settings in cloud',
			'cloud.extractFailed' => 'Extraction failed',
			'cloud.onlineDicts' => ({required Object count}) => 'Online Dicts (${count})',
			'cloud.onlineDictsConnected' => 'Connected to subscription, view and download dicts in "Dictionary Manager"',
			'cloud.pushUpdatesTitle' => 'Push Updates',
			'cloud.pushUpdateCount' => ({required Object count}) => '${count} update records found:',
			'cloud.noPushUpdates' => 'No updates to push',
			'cloud.noValidEntries' => 'No valid entries to push',
			'cloud.pushMessageLabel' => 'Update message',
			'cloud.pushMessageHint' => 'Enter update description',
			'cloud.updateEntry' => 'Update entries',
			'cloud.pushSuccess' => 'Pushed successfully',
			'cloud.pushFailed' => ({required Object error}) => 'Push failed: ${error}',
			'cloud.pushFailedGeneral' => 'Push failed',
			'cloud.loadUpdatesFailed' => ({required Object error}) => 'Failed to load update records: ${error}',
			'cloud.opInsert' => '[New] ',
			'cloud.opDelete' => '[Deleted] ',
			'cloud.loginFirst' => 'Please log in first',
			'cloud.serverNotSet' => 'Please configure the cloud service subscription URL first',
			'cloud.uploadServerNotSet' => 'Please configure the upload server URL first',
			'cloud.sessionExpired' => 'Session expired, please log in again',
			'cloud.permissionTitle' => 'File Access Required',
			'cloud.permissionBody' => 'External directory access requires the "All Files Access" permission.\n\nTap "Authorize" to open Settings, find this app under "Manage All Files" and enable the permission.',
			'cloud.goAuthorize' => 'Authorize',
			'cloud.permissionDenied' => 'File access denied, operation cancelled',
			'cloud.notLoggedIn' => 'Not logged in, please log in first',
			'cloud.getUserFailed' => 'Failed to get user info',
			'cloud.getUserFailedError' => ({required Object error}) => 'Failed to get user info: ${error}',
			'cloud.requestFailed' => 'Request failed',
			'cloud.downloadFailedError' => ({required Object error}) => 'Download failed: ${error}',
			'cloud.settingsFileNotFound' => 'Settings file not found',
			'cloud.noNeedToPushUpdates' => 'No updates to push',
			'cloud.selectAllRequiredFiles' => 'Please select all required files',
			'cloud.requiredField' => ' (required)',
			'cloud.optionalField' => ' (optional)',
			'cloud.uploadNewDict' => 'Upload New Dictionary',
			'cloud.versionNoteLabel' => 'Version note',
			'cloud.replaceFileHint' => 'Enter version description...',
			'cloud.replaceFileTip' => 'Files not selected will not be updated',
			'cloud.enterJsonContent' => 'Please enter JSON content',
			'cloud.importLineError' => ({required Object line, required Object preview}) => 'Line ${line}: parse error: "${preview}"',
			'cloud.jsonParseError' => 'JSON parse error',
			'cloud.importItemNotObject' => ({required Object item}) => 'Item ${item} is not a JSON object',
			'cloud.importItemMissingId' => ({required Object item}) => 'Item ${item} has no ID',
			'cloud.importItemWriteFailed' => ({required Object item, required Object id, required Object word}) => 'Item ${item} (id=${id}, ${word}) write failed',
			'cloud.importItemFailed' => ({required Object item, required Object error}) => 'Item ${item} failed: ${error}',
			'cloud.importSuccessCount' => ({required Object count}) => 'Imported ${count} entries',
			'cloud.importFailedCount' => ({required Object count}) => ', ${count} failed',
			'cloud.importMoreErrors' => ({required Object count}) => '... and ${count} more',
			'cloud.importFailedError' => ({required Object error}) => 'Import failed: ${error}',
			'cloud.enterEntryId' => 'Please enter entry ID',
			'cloud.enterHeadword' => 'Please enter headword',
			'cloud.entryIdNotFound' => ({required Object id}) => 'Entry not found for ID: ${id}',
			'cloud.headwordNotFound' => ({required Object word}) => 'Entry not found: "${word}"',
			'cloud.searchFailed' => ({required Object error}) => 'Search failed: ${error}',
			'cloud.deleteEntryConfirmContent' => ({required Object headword, required Object id}) => 'Delete "${headword}" (ID: ${id})? This cannot be undone.',
			'cloud.entryDeleted' => 'Entry deleted',
			'cloud.entryDeleteFailed' => 'Failed to delete entry',
			'cloud.deleteFailedError' => ({required Object error}) => 'Delete failed: ${error}',
			'cloud.updateJsonTitle' => 'Update Entry Data',
			'cloud.importTab' => 'Import',
			'cloud.deleteSearchTab' => 'Delete',
			'cloud.importJsonPlaceholder' => 'Paste JSON or JSONL format data...',
			'cloud.clearLabel' => 'Clear',
			'cloud.importing' => 'Importing...',
			'cloud.writingToDb' => 'Write to DB',
			'cloud.idSearch' => 'Search by ID',
			'cloud.prefixSearch' => 'Search by headword',
			'cloud.searchHeadwordLabel' => 'Headword',
			'cloud.searchIdHint' => 'Enter entry_id',
			'cloud.searchHeadwordHint' => 'Enter headword',
			'cloud.matchedEntries' => ({required Object count}) => '${count} entries found',
			'cloud.deleting' => 'Deleting...',
			'cloud.deleteEntry' => 'Delete Entry',
			'cloud.noSyncableFiles' => 'No syncable files found',
			'cloud.createPackageFailedError' => ({required Object error}) => 'Failed to create package: ${error}',
			'cloud.archiveNotFound' => 'Archive file not found',
			'cloud.archiveNoValidFiles' => 'No valid files in archive',
			'cloud.extractFailedError' => ({required Object error}) => 'Extraction failed: ${error}',
			'dict.title' => 'Dictionary Manager',
			'dict.tabSort' => 'Dict Order',
			'dict.tabSource' => 'Dict Source',
			'dict.tabCreator' => 'Creator Center',
			'dict.localDir' => 'Local Dict Directory',
			'dict.changeDirTooltip' => 'Change Directory',
			'dict.dirSet' => ({required Object dir}) => 'Dict directory set: ${dir}',
			'dict.noDict' => 'No dictionaries yet',
			'dict.noDictHint' => 'Go to "Online Subscription" tab to set a URL\nor tap the store button to browse online dicts',
			'dict.enabled' => 'Enabled (long-press to reorder)',
			'dict.disabled' => 'Disabled',
			'dict.enabledCount' => ({required Object count}) => '${count}',
			'dict.disabledCount' => ({required Object count}) => '${count}',
			'dict.dragHint' => 'Long-press language tab to drag and reorder',
			'dict.onlineDicts' => 'Online Dictionaries',
			'dict.onlineCount' => ({required Object count}) => '${count}',
			'dict.loadFailed' => 'Load failed',
			'dict.loadOnlineFailed' => 'Failed to load online dictionaries',
			'dict.noOnlineDicts' => 'No online dictionaries',
			'dict.noOnlineDictsHint' => 'Configure subscription URL in Settings → Cloud Service first',
			'dict.noCreatorDicts' => 'No uploaded dictionaries',
			'dict.noCreatorDictsHint' => 'Configure cloud service and log in on the Dict Source tab first',
			'dict.updateCount' => ({required Object count}) => 'Updates (${count})',
			'dict.hasUpdates' => ({required Object count}) => '${count} dictionaries have updates',
			'dict.allUpToDate' => 'All dictionaries are up to date',
			'dict.checkUpdates' => 'Check Updates',
			'dict.checking' => 'Checking...',
			'dict.downloadDict' => ({required Object name}) => 'Download: ${name}',
			'dict.selectContent' => 'Select content to download:',
			'dict.dictMeta' => '[Required] Dict metadata',
			'dict.dictIcon' => '[Required] Dict icon',
			'dict.dictDb' => '[Required] Dictionary database',
			'dict.dictDbWithSize' => ({required Object size}) => '[Required] Dict database (${size})',
			'dict.mediaDb' => 'Media database',
			'dict.mediaDbWithSize' => ({required Object size}) => 'Media database (${size})',
			'dict.mediaDbNotFound' => ({required Object id}) => 'Media database not found for dictionary: ${id}',
			'dict.mediaDbNotExists' => 'Local file not exists, skip update',
			'dict.mediaDbNotExistsCanDownload' => 'Local file not exists, can download',
			'dict.dictDbNotFound' => ({required Object id}) => 'Dictionary database not found for: ${id}',
			'dict.getDictListFailed' => 'Failed to get dictionary list',
			'dict.invalidResponseFormat' => 'Invalid response format from server',
			'dict.getDictListFailedError' => ({required Object error}) => 'Failed to get dictionary list: ${error}',
			'dict.startDownload' => 'Start Download',
			'dict.statusResuming' => 'Resuming download...',
			'dict.downloading' => ({required Object step, required Object total, required Object name}) => '[${step}/${total}] Downloading ${name}',
			'dict.downloadingEntries' => ({required Object step, required Object total}) => '[${step}/${total}] Downloading entry updates',
			'dict.updateSuccess' => 'Updated successfully',
			'dict.updateFailed' => ({required Object error}) => 'Update failed: ${error}',
			'dict.deleteConfirmTitle' => 'Confirm Delete',
			'dict.deleteConfirmBody' => ({required Object name}) => 'Delete dictionary "${name}"?',
			'dict.deleteSuccess' => 'Dictionary deleted',
			'dict.deleteFailed' => ({required Object error}) => 'Delete failed: ${error}',
			'dict.dictNotFound' => 'Dictionary not found',
			'dict.dictDeleteFailed' => 'Dictionary delete failed',
			'dict.statusUpdateFailed' => 'Status update failed',
			'dict.statusPreparing' => 'Preparing',
			'dict.statusPreparingUpdate' => 'Preparing update',
			'dict.statusDownloading' => 'Downloading',
			'dict.statusCompleted' => 'Completed',
			'dict.storeNotConfigured' => 'Dictionary storage directory not configured',
			'dict.downloadFailed' => 'Download failed',
			'dict.tooltipUpdateJson' => 'Update JSON',
			'dict.tooltipReplaceFile' => 'Replace File',
			'dict.tooltipPushUpdate' => 'Push Update',
			'dict.tooltipDelete' => 'Delete',
			_ => null,
		} ?? switch (path) {
			'dict.tooltipUpdate' => 'Update dictionary',
			'dict.tooltipDownload' => 'Download dictionary',
			'dict.daysAgo' => ({required Object n}) => '${n} days ago',
			'dict.monthsAgo' => ({required Object n}) => '${n} months ago',
			'dict.yearsAgo' => ({required Object n}) => '${n} years ago',
			'dict.hoursAgo' => ({required Object n}) => '${n}h ago',
			'dict.minutesAgo' => ({required Object n}) => '${n}m ago',
			'dict.justNow' => 'Just now',
			'dict.dateUnknown' => 'Unknown',
			'dict.noFileSelected' => 'No file selected to update',
			'dict.configCloudFirst' => 'Please configure cloud service first',
			'dict.getDictInfoFailed' => 'Cannot get dictionary info',
			'dict.versionUpdated' => ({required Object version}) => 'Version updated to ${version}, no download needed',
			'dict.androidChoiceTitle' => 'Dictionary Storage',
			'dict.androidAppDir' => 'App-specific directory',
			'dict.androidAppDirWarning' => 'Data will be deleted if app is uninstalled',
			'dict.androidExtDir' => 'External public directory',
			'dict.androidExtDirNote' => 'Data persists after app updates/uninstall',
			'dict.androidRecommended' => 'Recommended',
			'dict.androidCustomDir' => 'Custom path',
			'dict.androidCustomDirNote' => 'Select any external directory',
			'dict.permissionGranted' => 'Permission granted',
			'dict.permissionNeeded' => 'Requires All Files Access permission',
			'dict.cantWrite' => ({required Object dir}) => 'Cannot write to ${dir}, check permissions',
			'dict.cantWritePicked' => 'Cannot write to selected directory, please choose another',
			'dict.permissionDialogBody' => 'Tap OK to open Settings, enable "Manage All Files" permission, then return to the app.',
			'dict.statsTitle' => 'Statistics',
			'dict.entryCount' => 'Entries',
			'dict.audioFiles' => 'Audio Files',
			'dict.imageFiles' => 'Image Files',
			'dict.dictInfoTitle' => 'Dictionary Info',
			'dict.filesTitle' => 'File Info',
			'dict.fileExists' => 'Present',
			'dict.fileMissing' => 'Missing',
			'dict.deleteDictTitle' => 'Delete Dictionary',
			'dict.deleteDictBody' => ({required Object name}) => 'Delete "${name}"?\n\nThis will permanently delete all dictionary files (database, media, metadata, etc.).',
			'dict.deleteDictSuccess' => ({required Object name}) => '"${name}" deleted',
			'dict.deleteDictFailed' => ({required Object error}) => 'Delete failed: ${error}',
			'dict.cannotGetFileInfo' => 'Cannot get file info',
			'dict.updateDictTitle' => ({required Object name}) => 'Update Dict - ${name}',
			'dict.smartUpdate' => 'Smart Update',
			'dict.manualSelect' => 'Manual Select',
			'dict.upToDate' => 'Up to date',
			'dict.noUpdates' => 'No updates available for this dictionary',
			'dict.currentVersion' => ({required Object version}) => 'Current version: v${version}',
			'dict.updateHistory' => 'Update history:',
			'dict.filesToDownload' => 'Files to download:',
			'dict.fileLabel' => ({required Object files}) => 'Files: ${files}',
			'dict.entryLabel' => ({required Object count}) => '${count} entries',
			'dict.noSmartUpdate' => 'No smart updates available',
			'dict.selectAtLeastOneItem' => 'Please select at least one item',
			'dict.batchUpdateTitle' => 'Batch Update',
			'dict.recheck' => 'Re-check Updates',
			'dict.batchUpdateCount' => ({required Object count}) => 'Update (${count})',
			'dict.batchHasUpdates' => ({required Object count}) => '${count} dictionaries can be updated',
			'dict.selectAll' => 'Select All',
			'dict.deselectAll' => 'Deselect All',
			'dict.versionRange' => ({required Object from, required Object to, required Object files}) => 'v${from} → v${to} | ${files} files',
			'dict.updateRecordCount' => ({required Object count}) => '${count} records',
			'dict.publisher' => 'Publisher',
			'dict.maintainer' => 'Maintainer',
			'dict.contact' => 'Contact',
			'dict.versionLabel' => 'Version',
			'dict.updatedLabel' => 'Updated',
			'dict.detailTitle' => 'Dictionary Details',
			'dict.statusPreparingUpload' => 'Preparing upload',
			'dict.uploadingFile' => ({required Object step, required Object total, required Object name}) => '[${step}/${total}] Uploading ${name}',
			'dict.statusUploadCompleted' => 'Upload completed',
			'dict.statusUploadFailed' => 'Upload failed',
			'dict.cancelled' => 'Cancelled',
			'dict.paused' => 'Paused',
			'dict.pause' => 'Pause',
			'dict.resume' => 'Resume',
			'dict.terminate' => 'Terminate',
			'dict.statusFailed' => 'Failed',
			'dict.statusUpdateCompleted' => 'Update completed',
			'dict.downloadingFile' => ({required Object name}) => 'Downloading ${name}',
			'dict.fetchListFailedHttp' => ({required Object code}) => 'Failed to fetch dictionary list: HTTP ${code}',
			'dict.fetchListTimeout' => 'Dictionary list fetch timed out',
			'dict.fetchDetailFailedHttp' => ({required Object code}) => 'Failed to fetch dictionary detail: HTTP ${code}',
			'dict.noContentSelected' => 'No content selected',
			'dict.downloadingDatabase' => ({required Object step, required Object total}) => '[${step}/${total}] Downloading dictionary database',
			'dict.downloadDbFailedHttp' => ({required Object code}) => 'Failed to download database: HTTP ${code}',
			'dict.downloadingDatabaseProgress' => ({required Object step, required Object total, required Object progress}) => '[${step}/${total}] Downloading dictionary database ${progress}%',
			'dict.downloadingMedia' => ({required Object step, required Object total}) => '[${step}/${total}] Downloading media database',
			'dict.downloadMediaFailedHttp' => ({required Object code}) => 'Failed to download media database: HTTP ${code}',
			'dict.downloadingMediaProgress' => ({required Object step, required Object total, required Object progress}) => '[${step}/${total}] Downloading media database ${progress}%',
			'dict.downloadingMeta' => ({required Object step, required Object total}) => '[${step}/${total}] Downloading metadata',
			'dict.downloadMetaFailed' => ({required Object url, required Object code}) => 'Failed to download metadata: ${url}, HTTP ${code}',
			'dict.downloadingIcon' => ({required Object step, required Object total}) => '[${step}/${total}] Downloading icon',
			'dict.responseEmpty' => 'Response body is empty',
			'dict.dbDialogTitleError' => 'Enhance English Search (Error)',
			'dict.dbDialogTitle' => 'Enhance English Search',
			'dict.dbFeatureVariant' => 'Spelling variants (colour → color)',
			'dict.dbFeatureAbbr' => 'Abbreviations (abbr. → abbreviation)',
			'dict.dbFeatureNominal' => 'Nominalizations (happy → happiness)',
			'dict.dbFeatureInflection' => 'Inflections (runs, ran, running → run)',
			'dict.dbExample' => 'e.g. Searching "colour" returns entries for "color"',
			'dict.downloadError' => ({required Object error}) => 'Download error: ${error}',
			'dict.uploadError' => ({required Object error}) => 'Upload error: ${error}',
			'dict.uploadSuccess' => 'Upload successful',
			'dict.downloadFileFailedError' => ({required Object name, required Object error}) => 'Failed to download ${name}: ${error}',
			'dict.downloadFileFailed' => ({required Object name}) => 'Failed to download ${name}',
			'dict.downloadEntriesFailed' => 'Failed to download entry updates',
			'dict.searchEntries' => 'Search entries...',
			'dict.noEntries' => 'No entries',
			'dict.dbNotExists' => 'English dictionary database not found, please download first',
			'dict.crc32Mismatch' => ({required Object file, required Object expected, required Object actual}) => 'CRC32 verification failed for ${file}: expected ${expected}, got ${actual}',
			'dict.crc32VerifyFailed' => ({required Object error}) => 'CRC32 verification error: ${error}',
			'entry.wordRemoved' => ({required Object word}) => 'Removed "${word}" from word bank',
			'entry.wordListUpdated' => ({required Object word}) => 'Updated word list for "${word}"',
			'entry.selectAtLeastOne' => 'Please select at least one list',
			'entry.wordAdded' => ({required Object word}) => 'Added "${word}" to word bank',
			'entry.addFailed' => 'Add failed',
			'entry.noEntry' => 'Cannot get current entry',
			'entry.entryIncomplete' => 'Entry information is incomplete',
			'entry.resetting' => 'Resetting entry...',
			'entry.notFoundOnServer' => 'Entry not found on server',
			'entry.resetSuccess' => 'Entry reset',
			'entry.resetFailed' => 'Reset failed',
			'entry.saveFailed' => ({required Object error}) => 'Save failed: ${error}',
			'entry.saveSuccess' => 'Saved',
			'entry.processFailed' => ({required Object error}) => 'Process failed: ${error}',
			'entry.translating' => 'Translating...',
			'entry.translateFailed' => ({required Object error}) => 'Translation failed: ${error}',
			'entry.toggleFailed' => ({required Object error}) => 'Toggle failed: ${error}',
			'entry.wordNotFound' => ({required Object word}) => 'Word not found: ${word}',
			'entry.noPageContent' => 'No content on this page',
			'entry.copiedToClipboard' => 'Copied to clipboard',
			'entry.pathCopiedToClipboard' => 'Path copied to clipboard',
			'entry.pathNotFound' => 'Path not found',
			'entry.aiRequestFailed' => ({required Object error}) => 'AI request failed: ${error}',
			'entry.aiRequestFailedShort' => 'Request failed:',
			'entry.aiChatFailed' => ({required Object error}) => 'AI request failed: ${error}',
			'entry.aiSumFailed' => ({required Object error}) => 'AI summary failed: ${error}',
			'entry.summarizePage' => 'Summarize current page',
			'entry.deleteRecord' => 'Delete record',
			'entry.deleteRecordConfirm' => 'Delete this AI chat record?',
			'entry.aiThinking' => 'AI is thinking...',
			'entry.outputting' => 'Generating...',
			'entry.thinkingProcess' => 'Thinking',
			'entry.noChatHistory' => 'No chat history',
			'entry.continueChatTitle' => 'Continue Chat',
			'entry.originalQuestion' => 'Original Question',
			'entry.aiAnswer' => 'AI Answer',
			'entry.continueAsk' => 'Continue asking',
			'entry.continueAskHint' => 'Ask a follow-up question...',
			'entry.regenerate' => 'Regenerate',
			'entry.moreConc' => 'More Concise',
			'entry.moreDetailed' => 'More Detailed',
			'entry.chatInputHint' => 'Ask anything...',
			'entry.justNow' => 'Just now',
			'entry.minutesAgo' => ({required Object n}) => '${n}m ago',
			'entry.hoursAgo' => ({required Object n}) => '${n}h ago',
			'entry.daysAgo' => ({required Object n}) => '${n}d ago',
			'entry.morphBase' => 'Base',
			'entry.morphNominal' => 'Nominal',
			'entry.morphPlural' => 'Plural',
			'entry.morphPast' => 'Past',
			'entry.morphPastPart' => 'Past Participle',
			'entry.morphPresPart' => 'Present Participle',
			'entry.morphThirdSing' => '3rd Sing.',
			'entry.morphComp' => 'Comparative',
			'entry.morphSuperl' => 'Superlative',
			'entry.morphSpellingVariant' => 'Variant',
			'entry.morphNominalization' => 'Nominalization',
			'entry.morphInflection' => 'Inflection',
			'entry.uncountable' => 'uncountable',
			'entry.summaryQuestion' => 'Please summarize all dictionary content on this page',
			'entry.summaryTitle' => 'Current page summary',
			'entry.aiSummaryButton' => 'Tap to AI Summarize',
			'entry.summaryEntriesLabel' => ({required Object first, required Object count}) => '${first} and ${count} entries',
			'entry.chatStartSummary' => ({required Object dict, required Object page}) => '${dict} [${page}] AI Summary',
			'entry.chatStartElement' => ({required Object dict, required Object path}) => '${dict} [${path}] AI Inquiry',
			'entry.chatStartFreeChat' => ({required Object word}) => '"${word}" Free Chat',
			'entry.chatOverviewFreeChat' => 'Free Chat',
			'entry.chatOverviewSummary' => ({required Object dict, required Object page}) => '${dict} [${page}] AI Summary',
			'entry.chatOverviewSummaryNoPage' => ({required Object dict}) => '${dict} AI Summary',
			'entry.chatOverviewAsk' => ({required Object dict}) => '${dict} AI Inquiry',
			'entry.returnToStart' => 'Return to initial path',
			'entry.path' => 'Path',
			'entry.explainPrompt' => ({required Object word}) => 'This is part of the dictionary entry for "${word}", please explain this section.',
			'entry.currentWord' => ({required Object word}) => 'Current word: ${word}',
			'entry.currentDict' => ({required Object dictId}) => 'Current dictionary: ${dictId}',
			'entry.entryNotFound' => ({required Object entryId}) => 'Entry not found: ${entryId}',
			'entry.returnToOriginal' => 'Return',
			'entry.extractFailed' => 'Failed to extract text',
			'entry.generatingAudio' => 'Generating audio...',
			'entry.speakFailed' => ({required Object error}) => 'TTS failed: ${error}',
			'entry.phraseNotFound' => ({required Object phrase}) => 'Phrase not found: "${phrase}"',
			'entry.imageLoadFailed' => 'Failed to load image',
			'entry.rootMustBeObject' => 'Root must be a JSON object',
			'entry.dbUpdateFailed' => 'Failed to save to database',
			'entry.jsonFormatFailed' => ({required Object error}) => 'Format failed: ${error}',
			'entry.jsonSyntaxError' => ({required Object error}) => 'JSON syntax error: ${error}',
			'entry.formatJson' => 'Format JSON',
			'entry.syntaxError' => 'Syntax error',
			'entry.syntaxCheck' => 'Syntax OK',
			'entry.jsonErrorLabel' => ({required Object error}) => 'Syntax error: ${error}',
			'entry.spellingVariantLabel' => 'Spelling variant',
			'entry.abbreviationLabel' => 'Abbreviation',
			'entry.acronymLabel' => 'Acronym',
			'entry.morphPluralForm' => 'Plural form',
			'entry.morphThirdSingFull' => 'Third person singular',
			'groups.title' => 'Group Management',
			'groups.manageGroups' => 'Manage Groups',
			'groups.createGroup' => 'Create Group',
			'groups.editGroup' => 'Edit Group',
			'groups.deleteGroup' => 'Delete Group',
			'groups.deleteGroupConfirm' => ({required Object name}) => 'Are you sure you want to delete group "${name}"? Its subgroups will also be deleted.',
			'groups.groupName' => 'Group Name',
			'groups.groupNameHint' => 'Enter group name',
			'groups.description' => 'Description',
			'groups.descriptionHint' => 'Optional, supports JSON format component list',
			'groups.subGroups' => 'Subgroups',
			'groups.entries' => 'Entries',
			'groups.noGroups' => 'No groups',
			'groups.noSubGroups' => 'No subgroups',
			'groups.noEntries' => 'No entries',
			'groups.belongsTo' => 'Belongs to',
			'groups.breadcrumb' => 'Location',
			'groups.rootGroup' => 'Root',
			'groups.addEntry' => 'Add Entry',
			'groups.addEntryHint' => 'Search by headword',
			'groups.removeEntry' => 'Remove Entry',
			'groups.entryAdded' => 'Entry added to group',
			'groups.entryRemoved' => 'Entry removed from group',
			'groups.groupCreated' => 'Group created',
			'groups.groupUpdated' => 'Group updated',
			'groups.groupDeleted' => 'Group deleted',
			'groups.createFailed' => 'Failed to create group',
			'groups.updateFailed' => 'Failed to update group',
			'groups.deleteFailed' => 'Failed to delete group',
			'groups.loadFailed' => 'Failed to load groups',
			'groups.statsInfo' => ({required Object groups, required Object items}) => '${groups} groups, ${items} entries',
			'groups.navigateToEntry' => 'Navigate to entry',
			'groups.navigateToAnchor' => 'Navigate to anchor',
			'groups.groupLink' => ({required Object name}) => 'Group: ${name}',
			'groups.parentGroup' => 'Parent Group',
			'groups.selectParent' => 'Select Parent',
			'groups.none' => 'None (Root)',
			'groups.anchorInfo' => ({required Object anchor}) => 'Anchor: ${anchor}',
			'groups.wholeEntry' => 'Whole Entry',
			_ => null,
		};
	}
}
