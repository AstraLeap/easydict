/// 词条 JSON 中不应在内容渲染或导航目录中显示的字段列表
///
/// 这些字段包括：
/// - 系统字段：id, entry_id, dict_id, version
/// - 已单独渲染的内容字段：headword, headline, sense, sense_group 等
/// - 索引字段：links, groups（用于索引，不需要渲染）
/// - 内部字段：hiddenLanguages, hidden_languages
library;

/// 在内容渲染和导航目录中都应该排除的字段
/// component_renderer 和 dictionary_navigation_panel 共享
const List<String> kExcludedEntryKeys = [
  // 系统字段
  'id',
  'entry_id',
  'dict_id',
  'version',

  // 已单独渲染的内容字段
  'headword',
  'headword_syllable', // 音节形式，在 headword 点击时切换显示
  'headline', // headline 在 _buildWord 中作为标题渲染
  'entry_type',
  'page',
  'section',
  'tags',
  'certifications',
  'frequency',
  'pronunciation',
  'phonetic', // 根节点 phonetic 不单独渲染
  'pos', // 根节点 pos 在 _buildWord 中渲染
  'sense',
  'sense_group',
  'phrase', // toJson() 输出 'phrase'
  'phrases', // 原始 JSON 中的 'phrases' 字段
  'data',
  'note', // note 单独渲染，在普通 board 之前
  'clob', // clob 单独渲染
  'text', // text 单独渲染

  // 索引字段（用于索引，不需要渲染）
  'links',
  'groups',

  // 内部字段
  'hiddenLanguages',
  'hidden_languages',
];
