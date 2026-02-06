# EasyDict

一款简洁的英汉词典 Flutter 应用。

## 功能特性

### 查词功能

- 支持模糊搜索和精确匹配
- 显示单词发音（支持点击播放）
- 展示词性、定义、例句等信息
- 词形变化和词源信息

### 深色模式

- 三种模式：浅色、深色、跟随系统
- 设置自动保存，切换页面保持状态

### 生词本

- 收藏喜欢的单词
- 支持搜索和管理收藏
- 单词数据持久化存储

### 文本修饰语法

支持在词条内容中使用特殊语法标记文本修饰效果：

```
[text](type1,type2)
```

**支持的修饰类型：**

| 效果       | 英文关键字       | 中文关键字 |
| ---------- | ---------------- | ---------- |
| ~~删除线~~ | strike           | 中划线     |
| 下划线     | underline        | 下划线     |
| 下双划线   | double_underline | 下双划线   |
| ~~波浪线~~ | wavy             | 下波浪线   |
| **加粗**   | bold             | 加粗       |
| _斜体_     | italic           | 斜体       |
| 上标       | sup              | 上标       |
| 下标       | sub              | 下标       |

### 链接与颜色规则

| 语法                      | 说明     | 示例                             |
| ------------------------- | -------- | -------------------------------- |
| `[text](color)`           | 文本颜色 | `[红色文本](red)`                |
| `[text](->word)`          | 查词链接 | `[查询apple](->apple)`           |
| `[text](==entry_id.path)` | 精确跳转 | `[跳转到释义](==25153.senses.0)` |

**精确跳转规则说明：**

- `==` 右侧为跳转路径
- 路径以 `.` 分隔
- 第一部分为 `entry_id`，用于在当前词典中查找条目
- 后续部分为 JSON 路径，用于定位条目内的具体元素
- 例如：`25153.senses.0` 表示跳转到 ID 为 25153 的条目的 `senses` 数组的第 0 个元素

**使用示例：**

```
基本修饰：[delete](strike) [underline](underline)
字体样式：[bold](bold) [italic](italic) [bold,italic](bold,italic)
上下标：E = mc[2](sup)，H[2](sub)O
组合：[重要](bold,underline)
```

支持多个类型组合使用，用逗号分隔。

## JSON 数据规范

### 词条结构 (DictionaryEntry)

```json
{
  "entry_id": "fog_001",
  "headword": "fog",
  "entry_type": "word",
  "page": "medical",
  "section": "基本释义",
  "tags": ["IELTS", "TOEFL"],
  "frequency": {"level": "B1", "stars": 4},
  "etymology": [...],
  "inflections": [
    {"type": "past", "value": "fogged"},
    {"type": "present_participle", "value": "fogging"}
  ],
  "pronunciations": [
    {"region": "US", "notation": "/fɔːɡ/", "audio_url": "..."}
  ],
  "certifications": ["IELTS", "TOEFL"],
  "topics": ["赛车", "时尚"],
  "collocations": {...},
  "phrases": {...},
  "theasaruses": [...],
  "boards": [...],
  "senses": [...]
}
```

### 数据库表结构

SQLite 表 `entries` 结构：

```sql
CREATE TABLE entries (
  entry_id TEXT PRIMARY KEY,  -- 主键，唯一标识
  headword TEXT,              -- 词目（用于搜索）
  entry_type TEXT,            -- 词条类型（word/phrase）
  page TEXT,                  -- 页面分类
  section TEXT,               -- 区域分类
  json_data TEXT              -- 完整JSON数据
);
```

**搜索方式：** 按 `headword` 字段进行模糊搜索和精确匹配。

### 释义渲染规则

**英文与中文释义：**

- 英文释义（`definition.en`）和中文释义（`definition.zh`）分开渲染
- 英文释义使用主字体颜色（`colorScheme.onSurface`）
- 中文释义使用次级字体颜色（`colorScheme.outline`），与英文间距 4px
- 两者都支持长按复制

**例句渲染：**

- 例句文本（`text`）和翻译（`translation`）都支持 `[text](type1,type2)` 格式
- 支持的修饰类型：strike（中划线）、underline（下划线）、bold（加粗）、italic（斜体）等
- 例句和翻译都支持长按复制

**示例：**

```json
{
  "definition": {
    "en": "A sudden loud, sharp noise",
    "zh": "（突发的）巨响，砰"
  },
  "examples": [
    {
      "text": "The door [banged](bold) [shut](bold)",
      "translation": "门砰地关上了"
    }
  ]
}
```

渲染效果：

- 英文：A sudden loud, sharp noise
- 中文：（突发的）巨响，砰（与英文间距 4px）
- 例句：The door **banged** **shut**（banged 和 shut 显示为粗体）
- 所有文本支持长按复制

### Pages 与 Section（页面与区域）

用于组织同一词条下的多个释义，支持区域跳转。

**Pages（页面）：**

- 用于分类不同来源的释义（如：英式发音、美式发音、药学词典、儿童词典、大学词典等）
- 同一词条只能属于一个页面（字符串类型）
- 在词条标题下方显示页面标签

**Section（区域）：**

- 用于区分同一页面下的不同词源或词性
- 多个词条按 word 的 `id` 排序 sections
- 区域导航栏显示所有区域，点击可滚动跳转

```json
{
  "page": "medical",
  "section": "基本释义"
}
```

**UI 交互效果：**

- 当 `page` 存在时，显示页面标签（在词条标题下方）
- 当存在多个 section 时，显示区域导航栏（横向滚动 pill 样式）
- 点击区域导航项，自动滚动到对应释义位置

### Board 结构

用于展示额外信息区块：

```json
{
  "display": "210",
  "title": "标题文字",
  "content": ["内容1", "内容2", ...]
}
```

### Sense 结构

用于展示词义信息：

```json
{
  "index": 1,
  "pos": "n | v | adj | adv",
  "grammar": {
    "tags": ["U", "S", "C", "vi", "vt", "T", "often passive", ...],
    "patterns": ["in a ~", "a ~ of N", "~ N", "be ~ged", ...]
  },
  "label": {
    "unclassified": "value",
    "region": "global | us | uk | au | ... (缺省为 global)",
    "topic": ["psychology", "meteorology", "medicine", ...],
    "register": "formal | informal | slang | literary | ... ",
    "usage": ["figurative", "ironic", "archaic", ...],
    "tone": "positive | negative | neutral"
  },
  "definition": {
    "zh": "中文释义",
    "en": "English definition"
  },
  "note": "使用说明",
  "examples": [
    {"text": "例句", "translation": "翻译"}
  ],
  "sub_senses": [
    {
      "index": "a | b | c | ...",
      "pos": "n",
      "grammar": {...},
      "label": {...},
      "definition": {"zh": "子义项", "en": "Sub-sense definition"},
      "note": "子义项说明",
      "examples": [...]
    }
  ]
}
```

**index 格式：** 主义项用数字 (1, 2, 3...)，子义项用字母 (a, b, c...)

## 技术栈

- Flutter
- SQLite (sqflite)
- Provider (状态管理)
- SharedPreferences (设置持久化)

## 运行方式

```bash
flutter pub get
flutter run
```
