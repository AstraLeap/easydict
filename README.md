# EasyDict

一款多平台电子词典。

## 快速开始

```bash
# 安装依赖
flutter pub get

# 运行应用
flutter run

# 构建 Windows 版本
flutter build windows

# 构建 Android 版本
flutter build apk
```

## json数据格式

### json结构

```jsonc
{
  "dict_id": "my_dict", // 必填，词典id
  "version": "1.0.0", // 必填，entry版本
  "entry_id": 212, // 必填，不重复的entry标识符，整型
  "headword": "fog", // 必填，词头，可重复
  "headword_normalized": "fog", // 必填，小写且去音调符号的词头
  "entry_type": "word", // 必填，word或phrase
  "auxi_search": "fog", // 可选，辅助搜索词，主要用于中文、日文
  "page": "medical", // 可选，比如“药学词典”、“美语词典”，查词界面会根据不同的page给entry分组，同时只会显示一批page相同的entry
  "section": "noun", // 可选，区分同一个page下不同的entry，section可以是不同起源，也可以是不同词性
  "certifications": ["IELTS", "TOEFL", "CET-4"], // 可选，还没想好怎么实现
  "frequency": {
    "level": "B1",
    "stars": "3/5",
    "source": "Oxford 3000",
  }, // 可选，还没想好怎么实现
  "topic": ["赛车", "时尚", "经济"], // 可选，还没想好怎么实现
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
  "datas": {
    "key1": {},
    "key2": {},
  }, //可选，本部分为自定义数据部分，会渲染为tab组件，key1，key2会显示为tab名。datas可以放在词典的任何地方
  "phrases": ["fog in", "fog of"], // 可选，短语部分

  "sense": [
    {
      "index": 1, //必选
      "label": {
        "pos": "n",
        "pattern": ["in a ~", "mental ~"],
        "grammar": ["U", "S"],
        "region": "global",
        "register": "informal",
        "usage": ["figurative"],
        "tone": "neutral",
        "topic": ["psychology"],
        "unclassified": "test",
      }, //里面统统是可选
      "definition": {
        "zh": "困惑，迷惘；（理智、感情等）混浊不清的状态",
        "en": "A state of mental confusion or uncertainty.",
      }, //必填，map里可以有多个键值对，但键值一定要是metadata.json中target_language列表里有的值
      "images": {
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
        {},
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
      "group_name": "noun", //释义组的组名
      "sense": [{}, {}],
    },
    {},
  ], //释义组
}
```

**1. 除了上面给定的键值外，还可以添加自定义键值对 `customKey:customValue`，这会被渲染为一个可折叠的board，board标题为customKey**

**2. pronunciation、sense、sense_group、example后面可以是符合格式的map，也可以是符合格式的map组成的列表**

### 文本修饰语法

#### 基本语法

```
[text](type1,type2)
```

#### type支持的类型

| 语法               | 说明         |
| ------------------ | ------------ |
| `strike`           | 删除线       |
| `underline`        | 下划线       |
| `double_underline` | 双下划线     |
| `wavy`             | 波浪线       |
| `bold`             | 加粗         |
| `italic`           | 斜体         |
| `sup`              | 上标         |
| `sub`              | 下标         |
| `color`            | 主题色       |
| `color`            | 主题色、斜体 |
| `->dog`            | 查词dog链接  |
| `==entry_id.path`  | 精确跳转     |

## 词典包结构

```
dictionary_name/
├── metadata.json      # 词典元数据
├── dictionary.db      # 词条数据库
├── media.db           # 媒体资源数据库（可选）
└── logo.png           # 词典 Logo
```

### metadata.json

```json
{
  "id": "example_dict",
  "name": "Example Dictionary",
  "version": "1.0.0",
  "description": "An example dictionary for demonstration purposes",
  "source_language": "en",
  "target_language": ["en", "zh"],
  "publisher": "Example Publisher",
  "maintainer": "example_user",
  "contact_maintainer": "example@example.com",
  "repository": "https://github.com/example/dictionary",
  "createdAt": "2024-01-01T00:00:00.000Z",
  "updatedAt": "2024-01-01T00:00:00.000Z"
}
```

### dictionary.db

```sql
CREATE TABLE config (
    key TEXT PRIMARY KEY,--唯一键值为'zstd_dict'
    value BLOB --这里储存zstd的字典，用于压缩和解压
);

CREATE TABLE entries (
    entry_id INTEGER PRIMARY KEY,
    headword TEXT,
    headword_normalized TEXT,--只用给这个字段建立索引
    entry_type TEXT,
    page TEXT,
    section TEXT,
    version TEXT,
    json_data BLOB--储存使用zstd压缩后的json数据
);

CREATE INDEX idx_headword_normalized ON entries(headword_normalized);
```

### media.db

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

### logo.png

必须是png格式，方形
