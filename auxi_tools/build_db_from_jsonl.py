import json
import sqlite3
import zstandard as zstd
import random
import unicodedata
from pathlib import Path

# --- 全局配置与工具函数 ---


def is_ideographic_lang(lang_code):
    base_lang = lang_code.split("-")[0].lower()
    return base_lang in {"zh", "ja"} if base_lang else False


def normalize_text(text, lang_code=None, remove_spaces=False):
    """基础文本规范化：转小写、去除重音、去除空格"""
    text = "".join(
        c for c in unicodedata.normalize("NFD", text) if unicodedata.category(c) != "Mn"
    ).strip()
    if remove_spaces:
        text = text.replace(" ", "")
    if lang_code in {"zh-tw", "zh-hk", "zh-mo", "zh-hant"}:
        import opencc

        converter = opencc.OpenCC("t2s.json")
        text = converter.convert(text)
    return text


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
    is_biaoyi = is_ideographic_lang(lang_code)

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

    cursor.execute("CREATE TABLE config (key TEXT PRIMARY KEY, value BLOB)")

    if is_biaoyi:
        cursor.execute(
            """
            CREATE TABLE entries (
                entry_id INTEGER PRIMARY KEY,
                headword TEXT,
                headword_normalized TEXT,
                phonetic TEXT,
                entry_type TEXT,
                page TEXT,
                section TEXT,
                json_data BLOB
            )
        """
        )
    else:
        cursor.execute(
            """
            CREATE TABLE entries (
                entry_id INTEGER PRIMARY KEY,
                headword TEXT,
                headword_normalized TEXT,
                entry_type TEXT,
                page TEXT,
                section TEXT,
                json_data BLOB
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

    if is_biaoyi:
        sql = "INSERT INTO entries VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
    else:
        sql = "INSERT INTO entries VALUES (?, ?, ?, ?, ?, ?, ?)"

    batch = []
    total_count = 0

    with open(jsonl_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            data = json.loads(line)
            # 序列化并压缩
            json_bytes = json.dumps(
                data, ensure_ascii=False, separators=(",", ":")
            ).encode("utf-8")
            compressed_data = cctx.compress(json_bytes)

            # 准备元数据
            eid = int(data["entry_id"])
            hw = data.get("headword", "")
            etype = data.get("entry_type", "word")
            pg = data.get("page", "")
            sec = data.get("section", "")

            hw_norm = normalize_text(hw, lang_code=lang_code)

            if is_biaoyi:
                phonetic_raw = data.get("phonetic", "")
                phonetic_norm = normalize_text(phonetic_raw, remove_spaces=True)
                batch.append(
                    (eid, hw, hw_norm, phonetic_norm, etype, pg, sec, compressed_data)
                )
            else:
                batch.append((eid, hw, hw_norm, etype, pg, sec, compressed_data))

            if len(batch) >= 1000:
                cursor.executemany(sql, batch)
                total_count += len(batch)
                batch = []
                if total_count % 5000 == 0:
                    print(f"Processed {total_count} entries...")

        if batch:
            cursor.executemany(sql, batch)
            total_count += len(batch)

    # 后置创建索引（速度比插入时带索引快得多）
    print("Creating indexes...")
    cursor.execute("CREATE INDEX idx_entry_id ON entries(entry_id)")
    if is_biaoyi:
        cursor.execute(
            "CREATE INDEX idx_phonetic ON entries(phonetic, headword_normalized, headword)"
        )
        cursor.execute(
            "CREATE INDEX idx_headword ON entries(headword_normalized, phonetic, headword)"
        )
    else:
        cursor.execute(
            "CREATE INDEX idx_headword ON entries(headword_normalized, headword)"
        )

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
        help="SQLite page size in KB(default: 4096)",
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
