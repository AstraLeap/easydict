import json
import random
import sqlite3
import unicodedata
from pathlib import Path

import zstandard as zstd

# --- 全局配置与工具函数 ---


def normalize_text(text, lang_code=None, remove_spaces=False):
    """
    基础文本规范化：转小写、去除重音、去除空格
    """
    if not text:
        return ""

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

    if remove_spaces:
        text = text.replace(" ", "")

    # 繁体转简体
    if lang_code in {"zh-tw", "zh-hk", "zh-mo", "zh-hant"}:
        import opencc

        converter = opencc.OpenCC("t2s.json")
        text = converter.convert(text)

    return text


def validate_entry(data, line_num, seen_entry_ids):
    """
    验证 JSON 条目是否包含必填属性
    """
    required_fields = [
        "dict_id",
        "entry_id",
        "headword",
        "entry_type",
        "page",
        "section",
    ]

    # 检查必填字段是否存在
    for field in required_fields:
        if field not in data:
            raise ValueError(f"Line {line_num}: Missing required field '{field}'")

    # 验证并转换 entry_id 为整型
    if isinstance(data["entry_id"], str):
        try:
            data["entry_id"] = int(data["entry_id"])
        except ValueError:
            raise ValueError(
                f"Line {line_num}: 'entry_id' must be convertible to integer, got '{data['entry_id']}'"
            )
    elif not isinstance(data["entry_id"], int):
        raise ValueError(
            f"Line {line_num}: 'entry_id' must be an integer, got {type(data['entry_id']).__name__}"
        )

    # 验证 entry_id 不重复
    entry_id = data["entry_id"]
    if entry_id in seen_entry_ids:
        raise ValueError(f"Line {line_num}: Duplicate 'entry_id' {entry_id}")
    seen_entry_ids.add(entry_id)


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

    dict_size = dict_size_kb * 1024
    is_biaoyi = (
        lang_code.split("-")[0] in {"zh", "ja", "jp", "cn"} if lang_code else False
    )
    # 用于检测 entry_id 重复
    seen_entry_ids = set()

    # 1. 采样与字典训练
    samples = reservoir_sampling(jsonl_path, 10000)
    if not samples:
        print("Error: No data found in JSONL.")
        return

    print("Training Zstd dictionary...")
    dict_data = zstd.train_dictionary(dict_size, samples)
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
            page TEXT,
            section TEXT,
            entry_id INTEGER NOT NULL,
            anchor TEXT,
            FOREIGN KEY (entry_id) REFERENCES entries(entry_id) ON DELETE CASCADE
        )
    """
    )

    # 存储字典
    cursor.execute(
        "INSERT INTO config (key, value) VALUES (?, ?)", ("zstd_dict", dict_bytes)
    )

    # 3. 压缩并批量写入数据
    print("Compressing and inserting data...")
    cctx = zstd.ZstdCompressor(dict_data=dict_data, level=compress_level)

    # 批量插入语句
    entries_sql = "INSERT INTO entries (entry_id, json_data) VALUES (?, ?)"
    indices_sql = "INSERT INTO indices (headword, headword_normalized, phonetic, entry_type, page, section, entry_id, anchor) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"

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

            # 验证必填字段
            validate_entry(data, line_num, seen_entry_ids)

            # 序列化并压缩
            json_bytes = json.dumps(
                data, ensure_ascii=False, separators=(",", ":")
            ).encode("utf-8")
            compressed_data = cctx.compress(json_bytes)

            # 准备 entries 表数据
            eid = data["entry_id"]
            entries_batch.append((eid, compressed_data))

            # 准备 indices 表数据
            hw = data["headword"]
            hw_norm = normalize_text(hw, lang_code=lang_code)
            etype = data["entry_type"]
            pg = data["page"]
            sec = data["section"]
            anchor = data.get("anchor", "")  # 可选字段

            if is_biaoyi:
                # 表意文字词典：处理 phonetic 字段
                phonetic_raw = data.get("phonetic", "")
                phonetic_norm = normalize_text(phonetic_raw, remove_spaces=True)
            else:
                phonetic_norm = None

            indices_batch.append(
                (hw, hw_norm, phonetic_norm, etype, pg, sec, eid, anchor)
            )

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
    import argparse

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
