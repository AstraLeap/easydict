import json
import sqlite3
import zstandard as zstd
import random
from pathlib import Path


def normalize_text(text, remove_accents=True):
    import unicodedata
    if remove_accents:
        text = text.lower()
        text = unicodedata.normalize('NFD', text)
        text = ''.join(c for c in text if unicodedata.category(c) != 'Mn')
    return text


def train_dictionary_from_jsonl(jsonl_path, db_path, dict_size=112*1024, page_size=4096, is_biaoyi=False):
    word_lines = []
    phrase_lines = []

    has_phonetic = False

    with open(jsonl_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            data = json.loads(line)
            entry_type = data.get('entry_type', 'word')
            if entry_type == 'phrase':
                phrase_lines.append(line)
            else:
                word_lines.append(line)

            if not has_phonetic and 'phonetic' in data:
                has_phonetic = True

    word_count = len(word_lines)
    phrase_count = len(phrase_lines)
    total_count = word_count + phrase_count

    if total_count == 0:
        raise ValueError("No entries found in JSONL file")

    if is_biaoyi and has_phonetic:
        print("Phonetic mode enabled: will create phonetic index, no headword_normalized")
    elif is_biaoyi:
        print("Phonetic mode enabled but no phonetic field found in data")

    sample_count = min(total_count, 10000, max(2000, total_count // 50))
    word_sample_count = int(sample_count * word_count / total_count)
    phrase_sample_count = sample_count - word_sample_count

    print(f"Total entries: {total_count} (words: {word_count}, phrases: {phrase_count})")
    print(f"Dynamic sample count: {sample_count} (2% of total, min 2000, max total)")
    print(f"Sampling {word_sample_count} words and {phrase_sample_count} phrases")

    random.seed(42)

    if len(word_lines) > word_sample_count:
        word_samples = random.sample(word_lines, word_sample_count)
    else:
        word_samples = word_lines

    if len(phrase_lines) > phrase_sample_count:
        phrase_samples = random.sample(phrase_lines, phrase_sample_count)
    else:
        phrase_samples = phrase_lines

    all_samples = word_samples + phrase_samples
    random.shuffle(all_samples)

    print(f"Total samples for training: {len(all_samples)}")

    sample_bytes = [s.encode('utf-8') for s in all_samples]

    print("Training dictionary...")
    dict_data = zstd.train_dictionary(dict_size, sample_bytes)

    print(f"Dictionary trained, size: {len(dict_data)} bytes")

    Path(db_path).parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute(f"PRAGMA page_size = {page_size}")

    cursor.execute('''
        CREATE TABLE IF NOT EXISTS config (
            key TEXT PRIMARY KEY,
            value BLOB
        )
    ''')

    if is_biaoyi:
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS entries (
                entry_id INTEGER PRIMARY KEY,
                headword TEXT,
                phonetic TEXT,
                entry_type TEXT,
                page TEXT,
                section TEXT,
                json_data BLOB
            )
        ''')
    else:
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS entries (
                entry_id INTEGER PRIMARY KEY,
                headword TEXT,
                headword_normalized TEXT,
                entry_type TEXT,
                page TEXT,
                section TEXT,
                json_data BLOB
            )
        ''')

    conn.commit()
    conn.close()

    print(f"Database structure saved: {db_path}")

    return dict_data, is_biaoyi


def compress_and_write_to_db(jsonl_path, db_path, dict_data, batch_size=500, is_biaoyi=False):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    dict_compressed = dict_data
    dict_bytes = dict_compressed.as_bytes()

    cctx = zstd.ZstdCompressor(dict_data=dict_compressed, level=7)

    print(f"Using dictionary for compression, size: {len(dict_bytes)} bytes")

    cursor.execute('''
        INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)
    ''', ('zstd_dict', dict_bytes))

    conn.commit()

    total_count = 0

    with open(jsonl_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            data = json.loads(line)

            json_str = json.dumps(data, ensure_ascii=False, separators=(',', ':'))
            compressed_data = cctx.compress(json_str.encode('utf-8'))

            entry_id_int = int(data['entry_id'])
            headword = data.get('headword', '')

            if is_biaoyi:
                phonetic_raw = data.get('phonetic', '')
                phonetic_normalized = normalize_text(phonetic_raw, remove_accents=True)

                cursor.execute('''
                    INSERT OR REPLACE INTO entries (entry_id, headword, phonetic, entry_type, page, section, json_data)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                ''', (entry_id_int, headword, phonetic_normalized, data.get('entry_type', 'word'),
                      data['page'], data.get('section', ''), compressed_data))
            else:
                headword_normalized = normalize_text(headword)

                cursor.execute('''
                    INSERT OR REPLACE INTO entries (entry_id, headword, headword_normalized, entry_type, page, section, json_data)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                ''', (entry_id_int, headword, headword_normalized, data.get('entry_type', 'word'),
                      data['page'], data.get('section', ''), compressed_data))

            total_count += 1

            if total_count % batch_size == 0:
                conn.commit()
                print(f"Processed {total_count} entries...")

    conn.commit()

    cursor.execute("CREATE INDEX IF NOT EXISTS idx_entry_id ON entries(entry_id)")

    if is_biaoyi:
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_headword ON entries(headword)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_phonetic ON entries(phonetic)")
    else:
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_headword_normalized ON entries(headword_normalized)")

    conn.commit()

    conn.close()

    print(f"Total entries written to database: {total_count}")

    return total_count


def vacuum_database(db_path):
    import os
    size_before = os.path.getsize(db_path)

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("VACUUM")
    conn.commit()
    conn.close()

    size_after = os.path.getsize(db_path)
    print(f"Database vacuumed: {size_before/1024/1024:.2f}MB -> {size_after/1024/1024:.2f}MB (saved {(size_before-size_after)/1024/1024:.2f}MB)")


def build_database_from_jsonl(jsonl_path, db_path, dict_size=112*1024, page_size=4096, is_biaoyi=False):
    import os
    if os.path.exists(db_path):
        os.remove(db_path)
        print(f"Removed existing database: {db_path}")

    print("=" * 50)
    print("Phase 1: Training dictionary and creating database...")
    print("=" * 50)
    dict_data, phonetic_flag = train_dictionary_from_jsonl(jsonl_path, db_path, dict_size, page_size, is_biaoyi)

    print("\n" + "=" * 50)
    print("Phase 2: Compressing and writing to database...")
    print("=" * 50)
    compress_and_write_to_db(jsonl_path, db_path, dict_data, is_biaoyi=phonetic_flag)

    print("\n" + "=" * 50)
    print("Phase 3: Vacuuming database...")
    print("=" * 50)
    vacuum_database(db_path)

    print("\n" + "=" * 50)
    print("Database build complete!")
    print("=" * 50)


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 3:
        print("Usage: python build_db_from_jsonl.py <jsonl_path> <db_path> [dict_size_kb] [page_size] [--biaoyi]")
        print("  jsonl_path: 输入JSONL文件路径")
        print("  db_path: 输出数据库路径")
        print("  dict_size_kb: 字典大小 KB (默认 112)")
        print("  page_size: SQLite 页面大小 (默认 4096)")
        print("  --biaoyi: 启用表音文字模式 (如汉字等，需要phonetic字段)")
        sys.exit(1)

    jsonl_path = sys.argv[1]
    db_path = sys.argv[2]

    is_biaoyi = '--biaoyi' in sys.argv

    argv_without_flags = [arg for arg in sys.argv[1:] if not arg.startswith('--')]
    dict_size = int(argv_without_flags[2]) * 1024 if len(argv_without_flags) > 2 else 112 * 1024
    page_size = int(argv_without_flags[3]) if len(argv_without_flags) > 3 else 4096

    build_database_from_jsonl(jsonl_path, db_path, dict_size, page_size, is_biaoyi)
