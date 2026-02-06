import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

void main() async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;
  var db = await databaseFactory.openDatabase('assets/search/en.db');
  
  var tables = await db.query('sqlite_master', where: 'type = ?', whereArgs: ['table']);
  for (var table in tables) {
    print('Table: ${table['name']}');
    var columns = await db.rawQuery('PRAGMA table_info(${table['name']})');
    for (var col in columns) {
      print('  ${col['name']} (${col['type']})');
    }
  }
  await db.close();
}
