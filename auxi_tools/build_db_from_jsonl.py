import json, random, sqlite3, unicodedata, argparse, re
from pathlib import Path

import zstandard as zstd


def normalize_japanese(text: str) -> str:
    text = text.lower()

    # -----------------------------------------------------
    # 1. 罗马音转平假名 (修正版)
    # -----------------------------------------------------
    # 修复 tch 逻辑: 让 ch 保留给后续匹配
    text = text.replace("tch", "っch")
    # 修复 Hepburn 传统 m 处理 (如 shimbun -> しんぶん)
    text = re.sub(r"m(?=[bpm])", "ん", text)
    # 修复双辅音促音
    text = re.sub(r"([bcdfghjklmpqrstvwxyz])\1", r"っ\1", text)
    # 修复词尾或辅音前的 n
    text = re.sub(r"n(?=[^aeiouy]|$)", "ん", text)

    romaji_map = {
        "kya": "きゃ",
        "kyu": "きゅ",
        "kyo": "きょ",
        "sha": "しゃ",
        "shi": "し",
        "shu": "しゅ",
        "she": "しぇ",
        "sho": "しょ",
        "cha": "ちゃ",
        "chi": "ち",
        "chu": "ちゅ",
        "che": "ちぇ",
        "cho": "ちょ",
        "nya": "にゃ",
        "nyu": "にゅ",
        "nyo": "にょ",
        "hya": "ひゃ",
        "hyu": "ひゅ",
        "hyo": "ひょ",
        "mya": "みゃ",
        "myu": "みゅ",
        "myo": "みょ",
        "rya": "りゃ",
        "ryu": "りゅ",
        "ryo": "りょ",
        "gya": "ぎゃ",
        "gyu": "ぎゅ",
        "gyo": "ぎょ",
        "ja": "じゃ",
        "ji": "じ",
        "ju": "じゅ",
        "je": "じぇ",
        "jo": "じょ",
        "bya": "びゃ",
        "byu": "びゅ",
        "byo": "びょ",
        "pya": "ぴゃ",
        "pyu": "ぴゅ",
        "pyo": "ぴょ",
        "ka": "か",
        "ki": "き",
        "ku": "く",
        "ke": "け",
        "ko": "こ",
        "sa": "さ",
        "su": "す",
        "se": "せ",
        "so": "そ",
        "ta": "た",
        "te": "て",
        "to": "と",
        "tsu": "つ",
        "na": "な",
        "ni": "に",
        "nu": "ぬ",
        "ne": "ね",
        "no": "の",
        "ha": "は",
        "hi": "ひ",
        "fu": "ふ",
        "hu": "ふ",
        "he": "へ",
        "ho": "ほ",
        "ma": "ま",
        "mi": "み",
        "mu": "む",
        "me": "め",
        "mo": "も",
        "ya": "や",
        "yu": "ゆ",
        "yo": "よ",
        "ra": "ら",
        "ri": "り",
        "ru": "る",
        "re": "れ",
        "ro": "ろ",
        "wa": "わ",
        "wi": "ゐ",
        "we": "ゑ",
        "wo": "を",
        "ga": "が",
        "gi": "ぎ",
        "gu": "ぐ",
        "ge": "げ",
        "go": "ご",
        "za": "ざ",
        "zu": "ず",
        "ze": "ぜ",
        "zo": "ぞ",
        "da": "だ",
        "di": "ぢ",
        "du": "づ",
        "de": "で",
        "do": "ど",
        "ba": "ば",
        "bi": "び",
        "bu": "ぶ",
        "be": "べ",
        "bo": "ぼ",
        "pa": "ぱ",
        "pi": "ぴ",
        "pu": "ぷ",
        "pe": "ぺ",
        "po": "ぽ",
        "a": "あ",
        "i": "い",
        "u": "う",
        "e": "え",
        "o": "お",
        "ā": "ああ",
        "ī": "いい",
        "ū": "うう",
        "ē": "ええ",
        "ō": "おお",
    }
    for romaji in sorted(romaji_map.keys(), key=len, reverse=True):
        text = text.replace(romaji, romaji_map[romaji])

    # -----------------------------------------------------
    # 2 & 3 & 4: 清洗与片转平、去浊音逻辑（保持不变）
    # -----------------------------------------------------
    text = re.sub(r"[\s　]+", "", text)
    text = re.sub(r"[’・－\-]", "", text)

    text = "".join(
        [chr(ord(c) - 0x60) if 0x30A1 <= ord(c) <= 0x30F6 else c for c in text]
    )

    text = unicodedata.normalize("NFD", text)
    text = text.replace("\u3099", "").replace("\u309a", "")
    text = unicodedata.normalize("NFC", text)

    # -----------------------------------------------------
    # 5. 长音 "ー" 转换 (修复连续长音和汉字中断 Bug)
    # -----------------------------------------------------
    vowel_map = {
        "あ": "あ",
        "か": "あ",
        "さ": "あ",
        "た": "あ",
        "な": "あ",
        "は": "あ",
        "ま": "あ",
        "や": "あ",
        "ら": "あ",
        "わ": "あ",
        "ぁ": "あ",
        "ゃ": "あ",
        "ゎ": "あ",
        "い": "い",
        "き": "い",
        "し": "い",
        "ち": "い",
        "に": "い",
        "ひ": "い",
        "み": "い",
        "り": "い",
        "ゐ": "い",
        "ぃ": "い",
        "う": "う",
        "く": "う",
        "す": "う",
        "つ": "う",
        "ぬ": "う",
        "ふ": "う",
        "む": "う",
        "ゆ": "う",
        "る": "う",
        "ぅ": "う",
        "ゅ": "う",
        "え": "え",
        "け": "え",
        "せ": "え",
        "て": "え",
        "ね": "え",
        "へ": "え",
        "め": "え",
        "れ": "え",
        "ゑ": "え",
        "ぇ": "え",
        "お": "お",
        "こ": "お",
        "そ": "お",
        "と": "お",
        "の": "お",
        "ほ": "お",
        "も": "お",
        "よ": "お",
        "ろ": "お",
        "を": "お",
        "ぉ": "お",
        "ょ": "お",
    }

    res_choonpu = []
    current_vowel = None

    for c in text:
        if c == "ー":
            # 如果前面存在有效母音，则转换为该母音，否则保留(比如句首的异常长音)
            if current_vowel:
                res_choonpu.append(current_vowel)
            else:
                res_choonpu.append(c)
        else:
            res_choonpu.append(c)
            # 动态更新当前母音环境（如果遇到汉字或无母音符号，则清除上下文）
            if c in vowel_map:
                current_vowel = vowel_map[c]
            else:
                current_vowel = None

    text = "".join(res_choonpu)

    # -----------------------------------------------------
    # 6. 小文字转大文字
    # -----------------------------------------------------
    small_to_large = str.maketrans("ぁぃぅぇぉゃゅょゎっ", "あいうえおやゆよわつ")
    text = text.translate(small_to_large)

    return text


def normalize_text(text, lang_code, is_phonetic):
    """
    基础文本规范化：转小写、去除重音、去除空格
    """
    if not text:
        return ""

    if is_phonetic:
        text = text.replace(" ", "")

    # 汉语繁体转简体
    if lang_code in {"zh-tw", "zh-hk", "zh-mo", "zh-hant"} and not is_phonetic:
        import opencc

        converter = opencc.OpenCC("t2s.json")
        text = converter.convert(text)

    # 日语发音标准化
    if lang_code in {"ja", "jp"} and is_phonetic:
        text = normalize_japanese(text)

    # Unicode 标准化：NFD 分解后去除变音符号（Mn 类别）
    text = (
        "".join(
            c
            for c in unicodedata.normalize("NFD", text)
            if unicodedata.category(c) != "Mn"
        )
        .strip()
        .lower()
    )

    return text


def extract_headwords_from_headline(headline):
    """
    从headline中提取headword标签。
    格式示例: つける【[付ける](headword)・[附ける](headword)】
    提取 [text](headword) 格式中的text作为headword。

    返回: dict，key为headword，value为anchor（此处anchor为空字符串）
    """
    import re

    # 匹配 [text](headword) 格式
    pattern = r"\[([^\]]+)\]\(headword\)"
    matches = re.findall(pattern, headline)
    # 返回字典，anchor默认为空字符串
    return {hw: "" for hw in matches}


def extract_anchors_from_json(data, current_path=""):
    """
    递归搜索JSON对象，提取所有 [text](anchor) 格式的标签。

    参数:
        data: JSON数据（dict、list、str或其他类型）
        current_path: 当前JSON路径

    返回: dict，key为headword（提取的text），value为anchor（JSON路径）
    """
    import re

    result = {}

    if isinstance(data, dict):
        for key, value in data.items():
            new_path = f"{current_path}.{key}" if current_path else key
            result.update(extract_anchors_from_json(value, new_path))
    elif isinstance(data, list):
        for i, item in enumerate(data):
            new_path = f"{current_path}.{i}" if current_path else str(i)
            result.update(extract_anchors_from_json(item, new_path))
    elif isinstance(data, str):
        # 匹配 [text](anchor) 格式
        pattern = r"\[([^\]]+)\]\(anchor\)"
        matches = re.findall(pattern, data)
        for text in matches:
            result[text] = current_path

    return result


def reservoir_sampling(jsonl_path, sample_size=10000):
    """
    水库采样算法：在不加载整个文件到内存的情况下，随机抽取样本。
    适合处理 GB 级别的 JSONL 文件。
    """
    samples = []
    print(f"Sampling {sample_size} entries for dictionary training...")
    with open(jsonl_path, "r", encoding="utf-8") as f:
        for i, line in enumerate(f):
            line = line.strip()
            if not line:
                continue
            if i < sample_size:
                samples.append(line.encode("utf-8"))
            else:
                r = random.randint(0, i)
                if r < sample_size:
                    samples[r] = line.encode("utf-8")
    return samples


def build_database_from_jsonl(
    jsonl_path, db_path, lang_code, dict_size_kb=112, compress_level=7, page_size=4096
):
    lang_code = lang_code.lower()

    # 1. 采样与字典训练
    samples = reservoir_sampling(jsonl_path, 10000)
    if not samples:
        print("Error: No data found in JSONL.")
        return

    print("Training Zstd dictionary...")
    dict_data = zstd.train_dictionary(dict_size_kb * 1024, samples)
    dict_bytes = dict_data.as_bytes()
    del samples  # 释放内存

    # 2. 初始化数据库
    if Path(db_path).exists():
        Path(db_path).unlink()

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # 极致性能 PRAGMA
    cursor.execute(f"PRAGMA page_size = {page_size}")
    cursor.execute("PRAGMA synchronous = OFF")
    cursor.execute("PRAGMA journal_mode = WAL")
    cursor.execute("PRAGMA cache_size = -64000")  # 64MB 缓存
    cursor.execute("PRAGMA foreign_keys = ON")  # 启用外键约束

    cursor.execute("CREATE TABLE config (key TEXT PRIMARY KEY, value BLOB)")

    # 存储zstd字典
    cursor.execute(
        "INSERT INTO config (key, value) VALUES (?, ?)", ("zstd_dict", dict_bytes)
    )

    # 创建 entries 表（只包含 entry_id 和 json_data）
    cursor.execute(
        """
        CREATE TABLE entries (
            entry_id INTEGER PRIMARY KEY,
            json_data BLOB
        )
    """
    )

    # 创建 indices 表（索引字段）
    cursor.execute(
        """
        CREATE TABLE indices (
            id INTEGER PRIMARY KEY,
            headword TEXT NOT NULL,
            headword_normalized TEXT NOT NULL,
            phonetic TEXT,
            entry_type TEXT,
            entry_id INTEGER NOT NULL,
            anchor TEXT,
            FOREIGN KEY (entry_id) REFERENCES entries(entry_id) ON DELETE CASCADE
        )
    """
    )

    # 3. 压缩并批量写入数据
    print("Compressing and inserting data...")
    cctx = zstd.ZstdCompressor(dict_data=dict_data, level=compress_level)

    # 批量插入语句
    entries_sql = "INSERT INTO entries (entry_id, json_data) VALUES (?, ?)"
    indices_sql = "INSERT INTO indices (headword, headword_normalized, phonetic, entry_type, entry_id, anchor) VALUES (?, ?, ?, ?, ?, ?)"

    entries_batch = []
    indices_batch = []
    total_count = 0
    line_num = 0

    with open(jsonl_path, "r", encoding="utf-8") as f:
        for line in f:
            line_num += 1
            line = line.strip()
            if not line:
                continue

            data = json.loads(line)

            # 序列化并压缩
            json_bytes = json.dumps(
                data, ensure_ascii=False, separators=(",", ":")
            ).encode("utf-8")
            compressed_data = cctx.compress(json_bytes)

            # 准备 entries 表数据
            eid = data["entry_id"]
            entries_batch.append((eid, compressed_data))

            # 处理 phonetic 字段
            phonetic_raw = data.get("phonetic", "")
            phonetic_norm = normalize_text(phonetic_raw, lang_code, True)

            # 准备 indices 表数据
            # 使用字典维护 headword -> anchor 的映射
            headword_anchor_map = {}

            # 1. 优先从 headword 字段提取
            if "headword" in data:
                headword_anchor_map[data["headword"]] = ""

            # 2. 从 headline 字段提取 [text](headword) 格式
            headline = data.get("headline", "")
            if headline:
                headword_anchor_map.update(extract_headwords_from_headline(headline))

            # 3. 递归搜索整个JSON，提取 [text](anchor) 格式
            headword_anchor_map.update(extract_anchors_from_json(data))

            # 如果没有任何headword，打印警告
            if not headword_anchor_map:
                print(
                    f"Warning: No headword found for entry_id {eid} at line {line_num}"
                )

            etype = data["entry_type"]

            # 为每个headword分别创建索引行
            for hw, anchor in headword_anchor_map.items():
                hw_norm = normalize_text(hw, lang_code, False)
                indices_batch.append((hw, hw_norm, phonetic_norm, etype, eid, anchor))

            if len(entries_batch) >= 1000:
                cursor.executemany(entries_sql, entries_batch)
                cursor.executemany(indices_sql, indices_batch)
                total_count += len(entries_batch)
                entries_batch = []
                indices_batch = []
                if total_count % 5000 == 0:
                    print(f"Processed {total_count} entries...")

        if entries_batch:
            cursor.executemany(entries_sql, entries_batch)
            cursor.executemany(indices_sql, indices_batch)
            total_count += len(entries_batch)

    # 后置创建索引（速度比插入时带索引快得多）
    print("Creating indexes...")
    cursor.execute("CREATE INDEX idx_headword_norm ON indices(headword_normalized)")
    cursor.execute("CREATE INDEX idx_phonetic ON indices(phonetic)")
    cursor.execute("CREATE INDEX idx_indices_entry_id ON indices(entry_id)")

    conn.commit()

    # 5. 收尾：Vacuum
    print("Vacuuming database...")
    size_before = Path(db_path).stat().st_size
    cursor.execute("VACUUM")
    conn.close()
    size_after = Path(db_path).stat().st_size

    print(f"\nBuild Complete!")
    print(f"DB Path: {db_path}")
    print(f"Total Entries: {total_count}")
    print(f"Size before VACUUM: {size_before / 1024 / 1024:.2f} MB")
    print(f"Size after VACUUM: {size_after / 1024 / 1024:.2f} MB")


# --- 命令行入口 ---

if __name__ == "__main__":
    ## for test
    # print(
    #     extract_headwords_from_headline(
    #         "つける【[付ける](headword)・[附ける](headword)】"
    #     )
    # )
    # test_cases = [
    #     "コンピューター",  # 片假名+长音+半浊音 -> こんひゆうたあ
    #     "ローマ字",  # 罗马音(片假名)+汉字 -> ろおま字 (保留非匹配字符)
    #     "chotto matteta",  # 罗马音+促音 -> ちよつとまつてた
    #     "ぎゅうにゅう",  # 浊音+拗音 -> きゆうにゆう
    #     "パーティー",  # 半浊音+小文字+长音 -> はあていい
    #     "A・B－C’",  # 特殊符号 -> abc (全角减号等被移除)
    # ]
    # for case in test_cases:
    #     print(f"{case}  =>  {normalize_japanese(case)}")

    parser = argparse.ArgumentParser(
        description="JSONL to Optimized SQLite Dictionary Builder"
    )
    parser.add_argument("jsonl_path", help="Input JSONL file path")
    parser.add_argument("lang", help="Language code (e.g., zh, ja, en)")
    parser.add_argument(
        "dict_size",
        nargs="?",
        type=int,
        default=112,
        help="Zstd dict size in KB (default: 112)",
    )
    parser.add_argument(
        "compress_level",
        nargs="?",
        type=int,
        default=7,
        help="Zstd compression level (default: 7)",
    )
    parser.add_argument(
        "page_size",
        nargs="?",
        type=int,
        default=4096,
        help="SQLite page size in bytes (default: 4096)",
    )

    args = parser.parse_args()

    jsonl_path = Path(args.jsonl_path)
    db_path = jsonl_path.with_suffix(".db")

    build_database_from_jsonl(
        jsonl_path=str(jsonl_path),
        db_path=str(db_path),
        lang_code=args.lang,
        dict_size_kb=args.dict_size,
        compress_level=args.compress_level,
        page_size=args.page_size,
    )
