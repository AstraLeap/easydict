import sqlite3
import os
import argparse

def create_db_and_tables(conn):
    """初始化数据库表结构"""
    cursor = conn.cursor()
    
    # 创建 audios 表
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS audios (
            name TEXT PRIMARY KEY,
            blob BLOB NOT NULL
        )
    ''')
    
    # 创建 images 表
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS images (
            name TEXT PRIMARY KEY,
            blob BLOB NOT NULL
        )
    ''')
    conn.commit()

def process_directory(conn, table_name, dir_path):
    """遍历文件夹并将文件写入指定的表"""
    if not dir_path or not os.path.isdir(dir_path):
        return

    cursor = conn.cursor()
    print(f"正在处理文件夹: {dir_path} -> 表: {table_name}")

    for root, dirs, files in os.walk(dir_path):
        for filename in files:
            file_path = os.path.join(root, filename)
            try:
                with open(file_path, 'rb') as f:
                    blob_data = f.read()
                
                # 使用 INSERT OR REPLACE 以防文件名冲突
                cursor.execute(
                    f"INSERT OR REPLACE INTO {table_name} (name, blob) VALUES (?, ?)",
                    (filename, blob_data)
                )
            except Exception as e:
                print(f"处理文件 {file_path} 时出错: {e}")

    conn.commit()
    print(f"完成 {table_name} 表的数据写入。")

def create_indexes(conn):
    """为 name 字段创建索引"""
    cursor = conn.cursor()
    print("正在创建索引...")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_audios_name ON audios(name)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_images_name ON images(name)")
    conn.commit()
    print("索引创建完毕。")

def main():
    parser = argparse.ArgumentParser(description="将文件夹中的文件转化为 BLOB 存储到 SQLite 数据库中。")
    parser.add_argument("audio_dir", help="包含音频文件的文件夹路径")
    parser.add_argument("image_dir", nargs="?", default=None, help="包含图片文件的文件夹路径 (可选)")
    
    args = parser.parse_args()

    db_name = "media.db"
    
    # 连接数据库（如果不存在则自动创建）
    conn = sqlite3.connect(db_name)

    try:
        # 1. 创建表
        create_db_and_tables(conn)

        # 2. 处理音频文件夹
        process_directory(conn, "audios", args.audio_dir)

        # 3. 处理图片文件夹（如果提供）
        if args.image_dir:
            process_directory(conn, "images", args.image_dir)
        else:
            print("未提供图片文件夹参数，跳过 images 表处理。")

        # 4. 创建索引
        create_indexes(conn)

    finally:
        conn.close()
        print(f"数据库 {db_name} 已生成。")

if __name__ == "__main__":
    main()