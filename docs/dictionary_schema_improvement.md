# 词典数据结构改进方案

## 一、当前设计的问题分析

### 1.1 表结构不统一

当前设计中，表意文字（中文/日文/韩文）和表音文字（英语等）使用不同的表结构：

**表意文字词典（zh/ja/ko）：**

```sql
CREATE TABLE entries (
    entry_id INTEGER PRIMARY KEY,
    headword TEXT,
    headword_normalized TEXT,
    phonetic TEXT,  -- 有此字段
    entry_type TEXT,
    page TEXT,
    section TEXT,
    json_data BLOB
);
```

**表音文字词典（en等）：**

```sql
CREATE TABLE entries (
    entry_id INTEGER PRIMARY KEY,
    headword TEXT,
    headword_normalized TEXT,  -- 无 phonetic 字段
    entry_type TEXT,
    page TEXT,
    section TEXT,
    json_data BLOB
);
```

这种设计导致：

- 代码中需要大量 `if (isBiaoyi) {...} else {...}` 分支判断
- 维护困难，增加新功能时需要同时考虑两种情况
- 表音文字词典如果有音标需求，无法复用 phonetic 字段

### 1.2 一对多关键词映射问题

当前设计中，一个词条只能有一个 `headword` 和一个 `phonetic`：

```json
{
    "entry_id": 123,
    "headword": "付ける",
    "phonetic": "つける"
}
```

但实际词典中存在以下需求：

#### 日语词典案例

- 同一个词条「つける」可能有多种汉字写法：「付ける」「着ける」「就ける」等
- 广辞苑等词典会将这些合并为一个词条，在不同释义中标注适用的汉字写法
- 用户输入任何一种写法都应该能查到该词条

#### 类语词典（Thesaurus）案例

- 一个条目比较多个词的用法，如「大きい/大きな」的区别
- 输入「大きい」或「大きな」都应该能查到这一条目

#### 中文词典案例

- 同一个词可能有多个拼音（多音字）
- 同一个词可能有繁简多种写法

### 1.3 缺少链接表机制

MDX 词典广泛使用链接功能，例如：

- 参见词条链接
- 同义词跳转
- 词形变化跳转

当前设计无法有效支持这种多对多的链接关系。

---

## 二、改进方案

### 2.1 统一表结构

**新的 entries 表（统一结构）：**

```sql
CREATE TABLE entries (
    entry_id INTEGER PRIMARY KEY,
    entry_type TEXT,
    page TEXT,
    section TEXT,
    json_data BLOB
);
```

将 `headword`、`headword_normalized`、`phonetic` 字段移出 entries 表，统一到链接表中。

### 2.2 引入关键词链接表

**新增 entry_keywords 表：**

```sql
CREATE TABLE entry_keywords (
    keyword_id INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id INTEGER NOT NULL,
    keyword TEXT NOT NULL,           -- 原始关键词（用于显示）
    keyword_normalized TEXT NOT NULL, -- 规范化关键词（用于搜索）
    keyword_type TEXT NOT NULL,       -- 关键词类型
    language TEXT,                    -- 语言代码（可选）
    priority INTEGER DEFAULT 0,       -- 优先级（用于排序）
    FOREIGN KEY (entry_id) REFERENCES entries(entry_id) ON DELETE CASCADE
);

-- 索引设计
CREATE INDEX idx_keyword_normalized ON entry_keywords(keyword_normalized, keyword_type);
CREATE INDEX idx_entry_id ON entry_keywords(entry_id);
```

**keyword_type 取值：**
| 类型 | 说明 | 示例 |
|------|------|------|
| `headword` | 主词头（汉字/原文） | 付ける、和 |
| `variant` | 异体字/变体写法 | 着ける、咊 |
| `hiragana` | 平假名读音 | つける |
| `katakana` | 片假名读音 | ツケル |
| `romaji` | 罗马音（日语） | tsukeru |
| `pinyin` | 拼音（中文） | hé, hè |
| `bopomofo` | 注音符号（中文） | ㄏㄜˊ |
| `ipa` | 国际音标 | /tsɯkeɾɯ/ |
| `alias` | 别名/同义词 | - |
| `reference` | 参见链接 | - |
| `inflection` | 词形变化 | - |

**注意：** 不同类型的读音需要分别存储，因为：

1. 用户可能用任意一种方式检索
2. 每种读音可能有不同的规范化规则
3. 支持按检索方式过滤（如只用拼音搜索）

### 2.3 多种读音检索方式支持

#### 2.3.1 日语检索方式

日语词条需要支持以下检索方式：

| 检索方式 | 示例             | 说明            |
| -------- | ---------------- | --------------- |
| 汉字     | 付ける、着ける   | 多种汉字写法    |
| 平假名   | つける           | 基础读音        |
| 片假名   | ツケル           | 平假名自动转换  |
| 罗马音   | tsukeru, tsukeru | 赫本式/训令式等 |

**自动生成变体关键词：**

```python
import jaconv
import wanakana

def generate_japanese_keywords(
    headword: str,
    hiragana: str = None,
    romaji: str = None
) -> list[dict]:
    """生成日语词条的所有检索关键词"""
    keywords = []

    # 1. 主词头（汉字）
    keywords.append({
        "keyword": headword,
        "keyword_normalized": normalize_text(headword),
        "keyword_type": "headword"
    })

    # 2. 平假名（基础读音）
    if hiragana:
        keywords.append({
            "keyword": hiragana,
            "keyword_normalized": normalize_text(hiragana),
            "keyword_type": "hiragana"
        })

        # 3. 片假名（自动转换）
        katakana = jaconv.hira2kata(hiragana)
        keywords.append({
            "keyword": katakana,
            "keyword_normalized": normalize_text(katakana),
            "keyword_type": "katakana"
        })

    # 4. 罗马音
    if hiragana:
        # 赫本式罗马音
        hepburn = wanakana.to_romaji(hiragana)
        keywords.append({
            "keyword": hepburn,
            "keyword_normalized": normalize_text(hepburn),
            "keyword_type": "romaji"
        })

    if romaji:
        keywords.append({
            "keyword": romaji,
            "keyword_normalized": normalize_text(romaji),
            "keyword_type": "romaji"
        })

    return keywords
```

#### 2.3.2 中文检索方式

中文词条需要支持以下检索方式：

| 检索方式       | 示例   | 说明                 |
| -------------- | ------ | -------------------- |
| 简体           | 和     | 简体汉字             |
| 繁体           | 龢     | 繁体汉字（自动转换） |
| 拼音（带声调） | hé, hè | 带声调拼音           |
| 拼音（无声调） | he     | 不带声调拼音         |
| 注音符号       | ㄏㄜˊ  | 台湾注音             |

**自动生成变体关键词：**

```python
import opencc
from pypinyin import pinyin, Style

def generate_chinese_keywords(
    headword: str,
    pinyin_list: list[str] = None
) -> list[dict]:
    """生成中文词条的所有检索关键词"""
    keywords = []

    # 1. 主词头
    keywords.append({
        "keyword": headword,
        "keyword_normalized": normalize_text(headword),
        "keyword_type": "headword"
    })

    # 2. 繁体变体（自动转换）
    s2t = opencc.OpenCC('s2t.json')
    t2s = opencc.OpenCC('t2s.json')

    traditional = s2t.convert(headword)
    if traditional != headword:
        keywords.append({
            "keyword": traditional,
            "keyword_normalized": normalize_text(traditional),
            "keyword_type": "variant"
        })

    # 3. 拼音
    if pinyin_list:
        for py in pinyin_list:
            # 带声调拼音
            keywords.append({
                "keyword": py,
                "keyword_normalized": normalize_pinyin(py, remove_tone=False),
                "keyword_type": "pinyin"
            })
            # 无声调拼音
            keywords.append({
                "keyword": py,
                "keyword_normalized": normalize_pinyin(py, remove_tone=True),
                "keyword_type": "pinyin"
            })
    else:
        # 自动生成拼音
        for char_pinyin in pinyin(headword, style=Style.TONE):
            py = char_pinyin[0]
            keywords.append({
                "keyword": py,
                "keyword_normalized": normalize_pinyin(py, remove_tone=False),
                "keyword_type": "pinyin"
            })

    # 4. 注音符号（从拼音转换）
    if pinyin_list:
        for py in pinyin_list:
            bopomofo = pinyin_to_bopomofo(py)
            if bopomofo:
                keywords.append({
                    "keyword": bopomofo,
                    "keyword_normalized": bopomofo,
                    "keyword_type": "bopomofo"
                })

    return keywords

def normalize_pinyin(pinyin: str, remove_tone: bool = False) -> str:
    """规范化拼音：转小写、可选去除声调"""
    normalized = pinyin.lower().strip()
    if remove_tone:
        # 声调数字转无声调
        tone_marks = 'āáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜ'
        tone_base = 'aeiouü'
        # ... 声调转换逻辑
    return normalized
```

#### 2.3.3 韩语检索方式

韩语词条需要支持以下检索方式：

| 检索方式 | 示例 | 说明         |
| -------- | ---- | ------------ |
| 谚文     | 하다 | 韩文原文     |
| 罗马音   | hada | RR/MR 罗马音 |

```python
from hangul_utils import hangul_to_romaja

def generate_korean_keywords(headword: str) -> list[dict]:
    """生成韩语词条的所有检索关键词"""
    keywords = []

    # 1. 主词头（谚文）
    keywords.append({
        "keyword": headword,
        "keyword_normalized": normalize_text(headword),
        "keyword_type": "headword"
    })

    # 2. 罗马音
    romaja = hangul_to_romaja(headword)
    keywords.append({
        "keyword": romaja,
        "keyword_normalized": normalize_text(romaja),
        "keyword_type": "romaji"
    })

    return keywords
```

### 2.4 完整的数据库结构

```sql
-- 配置表
CREATE TABLE config (
    key TEXT PRIMARY KEY,
    value BLOB
);

-- 词条数据表
CREATE TABLE entries (
    entry_id INTEGER PRIMARY KEY,
    entry_type TEXT,
    page TEXT,
    section TEXT,
    json_data BLOB
);

-- 关键词链接表
CREATE TABLE entry_keywords (
    keyword_id INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id INTEGER NOT NULL,
    keyword TEXT NOT NULL,
    keyword_normalized TEXT NOT NULL,
    keyword_type TEXT NOT NULL,
    language TEXT,
    priority INTEGER DEFAULT 0,
    FOREIGN KEY (entry_id) REFERENCES entries(entry_id) ON DELETE CASCADE
);

-- 索引
CREATE INDEX idx_entry_id ON entries(entry_id);
CREATE INDEX idx_keyword_normalized ON entry_keywords(keyword_normalized, keyword_type);
CREATE INDEX idx_entry_keywords_entry ON entry_keywords(entry_id);
```

---

## 三、JSON 数据格式调整

### 3.1 日语词典示例

```jsonc
{
    "dict_id": "ja_dict",
    "entry_id": 212,
    "entry_type": "word",
    "page": "main",
    "section": "",

    // 关键词列表（用于构建链接表）
    // 构建时会自动生成平假名→片假名、假名→罗马音等变体
    "keywords": [
        {
            "keyword": "付ける",
            "type": "headword"
        },
        {
            "keyword": "着ける",
            "type": "variant"
        },
        {
            "keyword": "つける",
            "type": "hiragana"
        }
        // 片假名 "ツケル" 和罗马音 "tsukeru" 由构建脚本自动生成
    ],

    // 简化格式（构建时展开为 keywords）
    "headword": "付ける",
    "variants": ["着ける", "就ける"],
    "reading": "つける",  // 平假名读音

    // 其余字段保持不变
    "sense": [
        {
            "label": {"pos": "v"},
            "definition": {"ja": "つける。着ける。"}
        }
    ],
    "pronunciation": [...]
}
```

**构建脚本自动生成的关键词：**

| 原始输入          | 自动生成 | 类型     |
| ----------------- | -------- | -------- |
| つける (hiragana) | ツケル   | katakana |
| つける (hiragana) | tsukeru  | romaji   |

### 3.2 类语词典示例

```jsonc
{
    "dict_id": "ja_thesaurus",
    "entry_id": 100,
    "entry_type": "comparison",
    "page": "main",
    "section": "",

    "keywords": [
        { "keyword": "大きい", "type": "headword" },
        { "keyword": "大きな", "type": "headword" },
        { "keyword": "おおきい", "type": "hiragana" },
        // オオキイ、オオキナ、ookii 等自动生成
    ],

    "sense": [
        {
            "definition": {
                "ja": "「大きい」与「大きな」的用法区别...",
            },
        },
    ],
}
```

### 3.3 中文词典示例

```jsonc
{
    "dict_id": "zh_dict",
    "entry_id": 500,
    "entry_type": "word",
    "page": "main",
    "section": "",

    "keywords": [
        { "keyword": "和", "type": "headword" },
        { "keyword": "咊", "type": "variant" },
        { "keyword": "hé", "type": "pinyin" },
        { "keyword": "hè", "type": "pinyin" },
        { "keyword": "huó", "type": "pinyin" },
        // 繁体 "龢"、注音 "ㄏㄜˊ"、无声调拼音 "he" 等自动生成
    ],

    // 简化格式
    "headword": "和",
    "variants": ["咊"],
    "pinyin": ["hé", "hè", "huó"], // 多音字

    "sense": [
        {
            "label": { "pos": "n", "pinyin": "hé" },
            "definition": { "zh": "和平；和缓" },
        },
        {
            "label": { "pos": "v", "pinyin": "hè" },
            "definition": { "zh": "响应" },
        },
    ],
}
```

**构建脚本自动生成的关键词：**

| 原始输入  | 自动生成 | 类型            |
| --------- | -------- | --------------- |
| 和 (简体) | 龢       | variant (繁体)  |
| hé (拼音) | he       | pinyin (无声调) |
| hé (拼音) | ㄏㄜˊ    | bopomofo        |

### 3.4 韩语词典示例

```jsonc
{
    "dict_id": "ko_dict",
    "entry_id": 300,
    "entry_type": "word",
    "page": "main",
    "section": "",

    "keywords": [
        {"keyword": "하다", "type": "headword"}
        // hada (罗马音) 自动生成
    ],

    "headword": "하다",
    "sense": [...]
}
```

---

## 四、搜索逻辑调整

### 4.1 统一的搜索流程

```dart
Future<List<DictionaryEntry>> searchEntries(String word) async {
    final normalizedWord = normalizeSearchWord(word);

    // 1. 在关键词表中查找匹配的 entry_id
    final entryIds = await db.query(
        'entry_keywords',
        columns: ['entry_id'],
        where: 'keyword_normalized = ?',
        whereArgs: [normalizedWord],
    );

    // 2. 根据 entry_id 批量获取词条数据
    final entries = await db.query(
        'entries',
        where: 'entry_id IN (${entryIds.map((e) => e['entry_id']).join(',')})',
    );

    // 3. 解压并返回
    return parseEntries(entries);
}
```

### 4.2 支持精确匹配和模糊匹配

```sql
-- 精确匹配
SELECT DISTINCT e.* FROM entries e
JOIN entry_keywords k ON e.entry_id = k.entry_id
WHERE k.keyword_normalized = 'つける';

-- 前缀匹配
SELECT DISTINCT e.* FROM entries e
JOIN entry_keywords k ON e.entry_id = k.entry_id
WHERE k.keyword_normalized LIKE 'つけ%';

-- GLOB 匹配
SELECT DISTINCT e.* FROM entries e
JOIN entry_keywords k ON e.entry_id = k.entry_id
WHERE k.keyword_normalized GLOB 'つ*';
```

---

## 五、迁移方案

### 5.1 数据迁移脚本

```python
def migrate_database(old_db_path: str, new_db_path: str, lang_code: str):
    """将旧格式数据库迁移到新格式"""

    old_conn = sqlite3.connect(old_db_path)
    new_conn = sqlite3.connect(new_db_path)

    # 创建新表结构
    create_new_schema(new_conn)

    # 检测旧表结构（表意文字有 phonetic 列）
    old_cursor = old_conn.cursor()
    old_cursor.execute("PRAGMA table_info(entries)")
    columns = [col[1] for col in old_cursor.fetchall()]
    has_phonetic = 'phonetic' in columns

    # 迁移数据
    old_cursor.execute("SELECT * FROM entries")

    for row in old_cursor:
        if has_phonetic:
            # 表意文字旧格式
            entry_id, headword, headword_norm, phonetic, entry_type, page, section, json_data = row
        else:
            # 表音文字旧格式
            entry_id, headword, headword_norm, entry_type, page, section, json_data = row
            phonetic = None

        # 插入 entries 表
        new_conn.execute(
            "INSERT INTO entries VALUES (?, ?, ?, ?)",
            (entry_id, entry_type, page, section, json_data)
        )

        # 插入 headword 关键词
        new_conn.execute(
            "INSERT INTO entry_keywords (entry_id, keyword, keyword_normalized, keyword_type) VALUES (?, ?, ?, ?)",
            (entry_id, headword, headword_norm, 'headword')
        )

        # 根据语言生成读音关键词
        if phonetic:
            if lang_code == 'ja':
                # 日语：生成平假名、片假名、罗马音
                keywords = generate_japanese_keywords(headword, hiragana=phonetic)
                for kw in keywords:
                    if kw['keyword_type'] != 'headword':  # headword 已插入
                        new_conn.execute(
                            "INSERT INTO entry_keywords (entry_id, keyword, keyword_normalized, keyword_type) VALUES (?, ?, ?, ?)",
                            (entry_id, kw['keyword'], kw['keyword_normalized'], kw['keyword_type'])
                        )
            elif lang_code.startswith('zh'):
                # 中文：生成拼音、注音
                keywords = generate_chinese_keywords(headword)
                for kw in keywords:
                    if kw['keyword_type'] != 'headword':
                        new_conn.execute(
                            "INSERT INTO entry_keywords (entry_id, keyword, keyword_normalized, keyword_type) VALUES (?, ?, ?, ?)",
                            (entry_id, kw['keyword'], kw['keyword_normalized'], kw['keyword_type'])
                        )
            elif lang_code == 'ko':
                # 韩语：生成罗马音
                keywords = generate_korean_keywords(headword)
                for kw in keywords:
                    if kw['keyword_type'] != 'headword':
                        new_conn.execute(
                            "INSERT INTO entry_keywords (entry_id, keyword, keyword_normalized, keyword_type) VALUES (?, ?, ?, ?)",
                            (entry_id, kw['keyword'], kw['keyword_normalized'], kw['keyword_type'])
                        )
            else:
                # 其他语言：作为普通 phonetic 处理
                new_conn.execute(
                    "INSERT INTO entry_keywords (entry_id, keyword, keyword_normalized, keyword_type) VALUES (?, ?, ?, ?)",
                    (entry_id, phonetic, phonetic, 'phonetic')
                )

    new_conn.commit()
```

### 5.2 兼容性处理

在 Dart 代码中添加兼容层，支持读取旧格式数据库：

```dart
Future<bool> isNewSchema(Database db) async {
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='entry_keywords'"
    );
    return tables.isNotEmpty;
}

Future<List<DictionaryEntry>> searchEntriesCompat(String word, Database db) async {
    if (await isNewSchema(db)) {
        return searchEntriesNewSchema(db, word);
    } else {
        return searchEntriesOldSchema(db, word);
    }
}
```

---

## 六、优势总结

| 方面       | 当前设计           | 改进方案                          |
| ---------- | ------------------ | --------------------------------- |
| 表结构     | 表意/表音两种结构  | 统一结构                          |
| 关键词映射 | 一对一             | 多对多                            |
| 日语检索   | 仅支持假名         | 汉字/平假名/片假名/罗马音         |
| 中文检索   | 仅支持汉字+拼音    | 汉字(繁简)/拼音(带调/无声调)/注音 |
| 韩语检索   | 仅支持谚文         | 谚文/罗马音                       |
| 类语词典   | 不支持             | 完全支持                          |
| MDX链接    | 不支持             | 通过链接表支持                    |
| 多音字     | 需要特殊处理       | 原生支持                          |
| 代码复杂度 | 高（大量分支判断） | 低（统一逻辑）                    |

### 检索方式对照表

| 语言 | 检索方式     | 示例    | 自动生成             |
| ---- | ------------ | ------- | -------------------- |
| 日语 | 汉字         | 付ける  | -                    |
| 日语 | 平假名       | つける  | -                    |
| 日语 | 片假名       | ツケル  | ✓ 从平假名自动转换   |
| 日语 | 罗马音       | tsukeru | ✓ 从假名自动转换     |
| 中文 | 简体         | 和      | -                    |
| 中文 | 繁体         | 龢      | ✓ 从简体自动转换     |
| 中文 | 拼音(带调)   | hé      | -                    |
| 中文 | 拼音(无声调) | he      | ✓ 从带调拼音自动转换 |
| 中文 | 注音符号     | ㄏㄜˊ   | ✓ 从拼音自动转换     |
| 韩语 | 谚文         | 하다    | -                    |
| 韩语 | 罗马音       | hada    | ✓ 从谚文自动转换     |

---

## 七、实施建议

1. **第一阶段**：实现新表结构，保持向后兼容
2. **第二阶段**：更新构建脚本，支持新的 JSON 格式
3. **第三阶段**：迁移现有词典数据
4. **第四阶段**：移除旧格式兼容代码

建议在下一个大版本（如 v2.0）中完成此改进。
