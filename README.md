# 给普通用户

使用说明及反馈渠道：https://forum.freemdict.com/t/topic/43251

# 快速开始

```bash
# 安装依赖
flutter pub get

# 运行应用
flutter run
```

## 构建发布版本

| 平台    | 命令                    |
| ------- | ----------------------- |
| Windows | `flutter build windows` |
| Android | `flutter build apk`     |
| macOS   | `flutter build macos`   |
| iOS     | `flutter build ios`     |
| Linux   | `flutter build linux`   |

## 可选编译参数（--dart-define）

| 参数               | 说明                                      |
| ------------------ | ----------------------------------------- |
| `ENABLE_LOG=true`  | 启用日志输出（默认关闭），调试时使用      |
| `LOG_TO_FILE=true` | 将日志同时写入文件，适合 Release 模式调试 |

两个参数可以同时使用：

```bash
flutter run --dart-define=ENABLE_LOG=true --dart-define=LOG_TO_FILE=true
flutter build windows --dart-define=LOG_TO_FILE=true
```

# 词典文件结构

词典格式组织如下：

```
{dict_root_folder}/
├── {dict_id_1}/                 # 文件夹名必须与 metadata.json 中的 id 一致
│   ├── metadata.json            # 词典元数据
│   ├── logo.png                 # 词典 Logo
│   ├── dictionary.db            # 词条数据库
│   └── media.db                 # 媒体资源数据库（可选）
├── {dict_id_2}/
│   └── ...
└── {dict_id_3}/
    └── ...
```

## metadata.json

```json
{
  "id": "example_dict",//必填
  "source_language": "en",//必填
  "target_language": ["en", "zh"],//必填
  "name": "Example Dictionary",
  "description": "An example dictionary for demonstration purposes",
  "publisher": "Example Publisher",
  "maintainer": "example_user",
  "encode": "utf-8",
  "contact_maintainer": "example@example.com",
  "version": 13, //一定要是整型！！！
  "updatedAt": ""2026-02-23T01:54:36.679419+00:00""//唯一指定的标准时间格式
}
```

## dictionary.db

制作词典时可使用本项目的`auxi_tools/build_db_from_jsonl.py`脚本，将jsonl文件转换为sqlite数据库。

```sql
CREATE TABLE config (
    key TEXT PRIMARY KEY,--唯一键值为'zstd_dict'
    value BLOB --这里储存zstd的字典，用于压缩和解压
);--只有一行

CREATE TABLE entries (
    entry_id INTEGER PRIMARY KEY,
    json_data BLOB--储存使用zstd压缩后的json数据
);--数据表

CREATE TABLE indices (
    id INTEGER PRIMARY KEY,
    headword TEXT NOT NULL,--原始headword
    headword_normalized TEXT NOT NULL,--标准化后的headword。建立索引
    phonetic TEXT,--标准化后的phonetic。建立索引
    entry_type TEXT,--entry类型
    entry_id INTEGER NOT NULL,--关联entries表
    anchor TEXT,--JSON路径，用于定位词条内的具体位置
    FOREIGN KEY (entry_id) REFERENCES entries(entry_id) ON DELETE CASCADE
);--索引表，每个entry可能有多条索引记录

CREATE INDEX idx_headword_norm ON indices(headword_normalized);
CREATE INDEX idx_phonetic ON indices(phonetic);
CREATE INDEX idx_indices_entry_id ON indices(entry_id);
```

### indices 表说明

indices 表用于存储词条的索引信息，支持一个词条对应多个索引记录：

- **headword 来源**（按优先级）：
    1. JSON 中的 `headword` 字段
    2. `links` 字段（可以是 string 或 list of string）
    3. 递归搜索 JSON 中所有 `[text](anchor)` 格式标签

- **anchor 字段**：
    - 当 headword 来自 `headword` 或 `links` 时，anchor 为空字符串
    - 当 headword 来自 `[text](anchor)` 时，anchor 为 JSON 路径，格式如 `sense_group.0.sense.0.label.pattern.0`

## media.db

制作词典时可使用本项目的`auxi_tools/build_media_db.py`脚本，将多媒体文件转换为sqlite数据库，该脚本可递归处理子文件夹。

```sql
CREATE TABLE audios (
    name TEXT PRIMARY KEY,--音频名，带文件后缀
    blob BLOB NOT NULL--无压缩，二进制数据
);

CREATE TABLE images (
    name TEXT PRIMARY KEY,--图片名，带文件后缀
    blob BLOB NOT NULL--无压缩，二进制数据
);

CREATE INDEX idx_audios_name ON audios(name);
CREATE INDEX idx_images_name ON images(name);
```

# json数据格式

- 词典数据以json格式的`entry`为基础单位，数据库中存储着一堆`entry`。
- 同一个单词可以下涵多个`entry`，`entry`有两个重要属性，page和section。
- 同一个单词的诸多`entry`按照page属性分类，同一个page的多个`entry`组成一个独立单元，比如“药学词典”page、”儿童词典“page、“美语词典”page、”英语词典“page等。
- 同一个page的各个`entry`之间通过section属性区分，section可以表示不同起源，或是不同词性等等。

## entry的json结构

```jsonc
{
    "dict_id": "my_dict", // 必填，词典id
    "entry_id": 212, // 必填，**不重复**的entry标识符，**整型**
    "headword": "fog", // 与headline二选一，单词头，可重复
    "headline": "つける【付ける・附ける】", // 与headword二选一，复杂词头
    "links": "from_word", //可以是string或者是list of string，查询"from_word"时也能查到本词条
    "entry_type": "word", // 必填，word或phrase
    "phonetic": "pinyin", // 可选，辅助搜索词，主要用于表意文字
    "page": "medical", // 必填，比如“药学词典”、“美语词典”，查词界面会根据不同的page给entry分组，同时只会显示一组page相同的entry，如果没有则留空:""
    "section": "noun", // 必填，区分同一个page下不同的entry，section可以是不同起源，也可以是不同词性，如果没有则留空:""
    "certifications": ["IELTS", "TOEFL", "CET-4"], // 可选，还没想好怎么实现
    "frequency": {
        "level": "B1",
        "stars": "3/5",
        "source": "Oxford 3000",
    }, // 可选，还没想好怎么实现
    "topic": ["赛车", "时尚", "经济"], // 可选，还没想好怎么实现，感觉这个可以单独在dictionary.db中生成一个表，记录每个类中有哪些子类和哪些单词。
    "stroke": "3", // 可选，笔画数
    "pos": "n", // 可选，词性
    "pronunciation": [
        {
            "region": "US",
            "notation": "/fɔːɡ/",
            "audio_file": "fog_us.mp3",
        },
        {
            "region": "UK",
            "notation": "/fɒɡ/",
            "audio_file": "fog_uk.opus",
        },
    ], //可选，发音部分
    "phrases": ["fog in", "fog of"], // 可选，短语部分
    "data": {
        "key1": {},
        "key2": {},
    }, //可选，本部分为自定义数据部分，会渲染为tab组件，key1，key2会显示为tab名。data可以放在词典的任何地方
    "customKey": {}, //除了规范里给定的键值外，还可以添加自定义键值，这会被渲染为board元素。board标题为customKey，customKey对应的值需要是一个map，map里的键值对会被渲染为board的内容。

    "sense": [
        {
            "index": 1, //必选
            "label": {
                "signpost": "same opinion",
                "word": "someword",
                "pos": "n",
                "grammar": ["U", "S"],
                "pronunciation": "/dɔːɡ/",
                "variant": "foggy",
                "region": "global",
                "pattern": ["in a ~", "mental ~"],
                "register": "informal",
                "usage": ["figurative"],
                "tone": "neutral",
                "complex": "雜",
                "topic": ["psychology"],
                "others": "other label", //可以使用自定义的键名
            }, //里面全部是可选，里面所有的值都既可以是string，也可以是string list。label的值既可以是一个map，也可以是map list。
            "definition": {
                "zh": "困惑，迷惘；（理智、感情等）混浊不清的状态",
                "en": "A state of mental confusion or uncertainty.",
            }, //释义字段，map里可以有多个键值对，但键值一定要是metadata.json中target_language列表里有的值
            "image": {
                "image_file": "fog.jpg",
            }, //可选
            "synonym": "test", //可以是string，也可以是list of string
            "antonym": ["test", "test2"], //可以是string，也可以是list of string
            "related": ["test", "test2"], //可以是string，也可以是list of string
            "note": "常用于 'in a fog' 结构，描述因疲倦或震惊而无法正常思考。", //可选，批准部分
            "example": [
                {
                    "en": "He was walking around in a mental fog after the accident.",
                    "zh": "事故发生后，他整个人都陷入了意识模糊的状态中。",
                    "source": {
                        "author": "Robert Louis",
                        "title": "Mental States and Trauma",
                        "date": "2025-01",
                        "publisher": "Health Press",
                    }, //可选，例句来源
                    "audios": [
                        {
                            "region": "UK", // 可选，例句音频地区
                            "audio_file": "fog_ex1_uk.mp3",
                        },
                    ], //可选，例句音频
                }, //必填，map里可以有多个键值对，但键值一定要是metadata.json中target_language列表里有的值
                {
                    "usage": "take courage/guts", //例句的用法
                    "en": "[It takes](bold) courage to admit you are wrong.",
                },
                {
                    "usage_group": "take (sb) sth (to do sth)", //一个例句用法中有多组例句
                    "example ": [
                        { "en": "Repairs take time to carry out." },
                        {
                            "en": "[It took](bold) a few minutes for his eyes to adjust to the dark.",
                        },
                    ],
                },
            ], //可选
            "subsense": [
                {
                    "index": "a",
                    "definition": {},
                },
                {
                    "index": "b",
                    "definition": {},
                },
            ], //释义的子释义，格式与释义的格式相同
        },
    ],
    "sense_group": [
        {
            "group_name": "noun", //释义组的组名（可选，无则不渲染组名行）
            "group_sub_name": "obsoleted sense", //释义组的副组名（可选，无则不渲染副组名行）
            "sense": [{}, {}],
        },
        {
            "sense": [{}, {}], // 无 group_name 和 group_sub_name 时，仅渲染 sense 列表
        },
    ], //释义组
    "clob": "any text", //在这里显示任意无法结构化的文本，不推荐使用
}
```

### 注意

- data和board内部还可以继续嵌套data或board
- 强烈建议data和board里需要显示的文本键名为语言代码，比如`"zh":"这是一句话"`。
- pronunciation、sense、sense_group、example后面可以是符合格式的map，也可以是符合格式的map组成的列表

## 文本修饰语法

### 基本语法

```
[text](type1,type2)
```

### type支持的类型

| 语法               | 说明                   |
| ------------------ | ---------------------- |
| `strike`           | 删除线                 |
| `underline`        | 下划线                 |
| `double_underline` | 双下划线               |
| `wavy`             | 波浪线                 |
| `bold`             | 加粗                   |
| `italic`           | 斜体                   |
| `sup`              | 上标                   |
| `sub`              | 下标                   |
| `color`            | 主题色                 |
| `special`          | 主题色、斜体           |
| `label`            | 一个带背景和边框的标签 |
| `ai`               | AI生成的内容           |
| `->dog`            | 查词dog链接            |
| `==entry_id.path`  | 精确跳转               |
| `:かん`            | 日文振假名（Ruby）     |

### 示例

```
For more information, please [see here](->wood).
"Wow, you are so [pretty](color,bold)!"
```
