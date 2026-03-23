# 给普通用户

使用说明及反馈渠道：https://forum.freemdict.com/t/topic/43251

# 词典文件结构

## 词典文件组织结构

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
    "id": "example_dict", //必填
    "source_language": "en", //必填
    "target_language": ["en", "zh"], //必填
    "name": "Example Dictionary",
    "description": "An example dictionary for demonstration purposes",
    "publisher": "Example Publisher",
    "maintainer": "example_user",
    "encode": "utf-8",
    "contact_maintainer": "example@example.com",
    "version": 13, //一定要是整型！！！
    "updatedAt": "2026-02-23T01:54:36.679419+00:00" //唯一指定的标准时间格式
}
```

## dictionary.db

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

CREATE TABLE groups (
    group_id INTEGER PRIMARY KEY,
    parent_id INTEGER,                   -- 父级组ID
    name TEXT NOT NULL,                  -- 组名
    description TEXT,                    -- 组的描述，JSON文本
    item_list TEXT DEFAULT '[]',         -- 组内项目列表 [{"e": 212, "a": "sense_group.0.sense.1"}]
    sub_group_count INTEGER DEFAULT 0,   -- 直接子组数量
    item_count INTEGER DEFAULT 0,        -- item_list 长度
    FOREIGN KEY (parent_id) REFERENCES groups(group_id) ON DELETE CASCADE
);--分组表，组织词条结构

CREATE INDEX idx_groups_parent ON groups(parent_id);
CREATE INDEX idx_headword_norm ON indices(headword_normalized);
CREATE INDEX idx_phonetic ON indices(phonetic);
CREATE INDEX idx_indices_entry_id ON indices(entry_id);
```

## media.db

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

# 生成词典需要准备的文件

## 词典生成方法

词典作者需要准备以下文件，然后调用 `auxi_tools/build_dictionary.py` 脚本生成词典数据库。

### 准备文件

| 文件            | 必需 | 说明                                                        |
| --------------- | ---- | ----------------------------------------------------------- |
| `entries.jsonl` | 是   | 词条数据文件，每行一个 JSON 对象，[详见](#entriesjsonl结构) |
| `groups.jsonl`  | 否   | 分组数据文件，每行一个 JSON 对象，[详见](#groupsjsonl结构)  |
| `audio/` 文件夹 | 否   | 音频文件目录，文件名需与词条中的 `audio_file` 字段对应      |
| `image/` 文件夹 | 否   | 图片文件目录，文件名需与词条中的 `image_file` 字段对应      |

### 调用方法

```bash
python build_dictionary.py <jsonl_path> <lang> [options]
```

#### 位置参数

| 参数         | 说明                      | 默认值 |
| ------------ | ------------------------- | ------ |
| `jsonl_path` | JSONL 文件路径            | -      |
| `lang`       | 语言代码（如 zh, ja, en） | -      |

#### 可选参数

| 参数                   | 说明                                      | 默认值 |
| ---------------------- | ----------------------------------------- | ------ |
| `--dict-size <KB>`     | Zstd 字典大小 (KB)                        | 112    |
| `--compress-level <N>` | Zstd 压缩级别                             | 7      |
| `--page-size <BYTES>`  | SQLite 页大小 (字节)                      | 4096   |
| `--audio-dir <path>`   | 音频文件夹路径                            | -      |
| `--image-dir <path>`   | 图片文件夹路径                            | -      |
| `--groups <path>`      | groups.jsonl 文件路径                     | -      |
| `-o, --output <path>`  | 输出目录路径（默认为 JSONL 文件所在目录） | -      |

### 使用示例

```bash
# 基础用法：仅生成词典数据库
python auxi_tools/build_dictionary.py data/entries.jsonl ja

# 自定义压缩参数
python auxi_tools/build_dictionary.py data/entries.jsonl zh \
    --dict-size 128 \
    --compress-level 9

# 完整用法：包含媒体资源和分组
python auxi_tools/build_dictionary.py data/entries.jsonl ja \
    --audio-dir data/audio \
    --image-dir data/image \
    --groups data/groups.jsonl \
    -o output/my_dict
```

### 输出文件

执行成功后会在输出目录生成以下文件：

- `dictionary.db` - 词典主数据库
- `media.db` - 媒体资源数据库（如有音频或图片）

## entries.jsonl结构

- jsonl格式，每行一个json格式的`entry`数据，`entry`是词典组织内容的基础单位。
- 同一个词头可下涵多个`entry`，`entry`有两个重要属性，page和section。
- 同一个词头的诸多`entry`按照page属性分类，同一个page的多个`entry`组成一个独立单元，比如“药学词典”page、”儿童词典“page、“美语词典”page、”英语词典“page等。
- 同一个page的各个`entry`之间通过section属性区分，section可以表示不同起源，或是不同词性等等。

```jsonc
{
    "dict_id": "my_dict", // 必填，词典id
    "entry_id": 212, // 必填，**不重复**的entry标识符，**整型**
    "headword": "fog", // 与headline二选一。可重复的词头
    "headline": "つける【付ける・附ける】", // 与headword二选一。如果选择headline，则必须使用links字段，用来表明查什么词可以查到本词头
    "links": "from_word", //可以是string或者是list of string，查询"from_word"时也能查到本词条
    "phonetic": "pinyin", // 可选，辅助搜索词，主要用于表意文字
    "entry_type": "word", // 可选，word或phrase等等
    "groups": [122, 254], // 可选，对应groups表中的group_id，可以是数字，也可以是数字列表
    "page": "medical", // 可选，比如“药学词典”、“美语词典”，查词界面会根据不同的page给entry分组，同时只会显示一组page相同的entry
    "section": "noun", // 可选，区分同一个page下不同的entry，section可以是不同起源，也可以是不同词性
    "certifications": ["IELTS", "TOEFL", "CET-4"], // 可选，还没想好怎么实现
    "frequency": {
        "level": "B1",
        "stars": "3/5",
        "source": "Oxford 3000",
    }, // 可选，还没想好怎么实现
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
            "tail": {
                "synonym": "test",
                "antonym": ["test", "test2"],
                "related": ["test", "test2"],
                "others": "",
            }, //里面任意元素可以是string，也可以是list of string，现实在definition后面
            "image": {
                "image_file": "fog.jpg",
            }, //可选
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
    "text": "any text", //在这里显示任意文本
    "clob": "any text", //在这里显示任意文本，并且不会使用格式化文本渲染
}
```

### 重要补充说明

- data和board内部还可以继续嵌套data或board
- 强烈建议data和board里需要显示的文本键名为语言代码，比如`"zh":"这是一句话"`。
- pronunciation、sense、sense_group、example后面可以是符合格式的map，也可以是符合格式的map组成的列表
- 文本中可以使用`[{someword}](anchor)`的格式化文本，若如此做，查词`{someword}`时可以查到本entry，并滚动到此为止

### 文本修饰语法

#### 基本语法

```
[text](type1,type2)
```

#### type支持的类型

| 语法               | 说明                       |
| ------------------ | -------------------------- |
| `strike`           | 删除线                     |
| `underline`        | 下划线                     |
| `double_underline` | 双下划线                   |
| `wavy`             | 波浪线                     |
| `bold`             | 加粗                       |
| `italic`           | 斜体                       |
| `sup`              | 上标                       |
| `sub`              | 下标                       |
| `color`            | 主题色                     |
| `special`          | 主题色、斜体               |
| `label`            | 一个带背景和边框的标签     |
| `ai`               | AI生成的内容               |
| `:かん`            | 日文振假名（Ruby）         |
| `~apple.svg`       | 行内图片，与文本等高       |
| `->headword`       | 查词headword               |
| `=>group_id`       | 指向group_id的界面         |
| `==entry_id::path` | 根据entry_id和path精确跳转 |
| `==entry_id`       | 跳转到entry_id             |
| `::path`           | 跳转到目标json_path        |

#### 示例

```
"Fruit, such as apple, [banana](banana)."
"For more information, please [see here](==18551::sense_group.0.sense.1)."
"Wow, you are so [pretty](color,bold)!"
```

## groups.jsonl结构

储存jsonl格式，每行的json格式要求如下

```jsonc
{
    "group_id": 1, // 分组ID，需唯一，整型
    "parent_id": 15, // 父分组ID，整型，用于构建层级结构，整型，根分组时为 null
    "name": "基础词汇", // 分组名称
    "description": { "text": "some content." }, // 分组描述，json格式
    "item_list": [
        { "e": 212 }, // e: entry_id，整型
        { "e": 213, "a": "sense.0" }, // a: anchor，JSON Path 锚点，指向词条内的具体位置，可选
    ], // group中包含的entry信息
    "sub_group_count": 2, // 子分组数量，整型
    "item_count": 100, // entry词条数量，整型
}
```

# 软件编译

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
