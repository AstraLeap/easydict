/// 浏览列表来源类型
enum BrowseListSource {
  /// 搜索历史记录
  searchHistory,

  /// 生词本列表
  wordBank,
}

/// 浏览列表数据
class BrowseList {
  /// 来源类型
  final BrowseListSource source;

  /// 单词列表
  final List<String> words;

  /// 当前单词索引（初始化时设置）
  final int initialIndex;

  /// 生词本来源时的语言（用于区分不同语言的生词本）
  final String? language;

  /// 生词本来源时的词表名称
  final String? listName;

  const BrowseList({
    required this.source,
    required this.words,
    required this.initialIndex,
    this.language,
    this.listName,
  });

  /// 是否可以前进（有下一个词）
  bool canGoNext(int currentIndex) => currentIndex < words.length - 1;

  /// 是否可以后退（有上一个词）
  bool canGoPrevious(int currentIndex) => currentIndex > 0;

  /// 获取下一个词
  String? getNextWord(int currentIndex) {
    if (!canGoNext(currentIndex)) return null;
    return words[currentIndex + 1];
  }

  /// 获取上一个词
  String? getPreviousWord(int currentIndex) {
    if (!canGoPrevious(currentIndex)) return null;
    return words[currentIndex - 1];
  }

  /// 获取当前位置描述
  String getPositionText(int currentIndex) {
    return '${currentIndex + 1}/${words.length}';
  }
}
