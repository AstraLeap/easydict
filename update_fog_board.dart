import 'dart:io';
import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final currentDir = Directory.current.path;
  final jsonPath = join(currentDir, 'example.json');
  final databasePath = join(currentDir, 'assets', 'easydict', 'dictionary.db');

  final jsonFile = File(jsonPath);
  if (!await jsonFile.exists()) {
    print('Error: $jsonPath not found');
    return;
  }

  final jsonContent = await jsonFile.readAsString();
  final jsonData = jsonDecode(jsonContent) as Map<String, dynamic>;
  final newJsonString = jsonEncode(jsonData);

  final database = await openDatabase(databasePath);

  await database.execute('''
    CREATE TABLE IF NOT EXISTS entries (
      entry_id TEXT PRIMARY KEY,
      headword TEXT,
      entry_type TEXT,
      page TEXT,
      section TEXT,
      json_data TEXT
    )
  ''');

  try {
    await database.execute(
      "INSERT OR REPLACE INTO entries (entry_id, headword, entry_type, page, section, json_data) VALUES (?, ?, ?, ?, ?, ?)",
      [
        jsonData['entry_id'] as String?,
        jsonData['headword'] as String?,
        jsonData['entry_type'] as String?,
        jsonData['page'] as String?,
        jsonData['section'] as String?,
        newJsonString,
      ],
    );

    print('Successfully wrote example.json data to database');
  } catch (e) {
    print('Error: $e');
    rethrow;
  } finally {
    await database.close();
  }
}
