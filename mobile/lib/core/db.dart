import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

const _schema = [
  'CREATE TABLE kv(k TEXT PRIMARY KEY, v TEXT)',
  'CREATE TABLE zone(id TEXT PRIMARY KEY, json TEXT)',
  'CREATE TABLE asset_type(id TEXT PRIMARY KEY, json TEXT)',
  'CREATE TABLE asset(id TEXT PRIMARY KEY, json TEXT)',
  'CREATE TABLE tag(code TEXT PRIMARY KEY, json TEXT)',
  'CREATE TABLE template(id TEXT PRIMARY KEY, json TEXT)',
  'CREATE TABLE issue(id TEXT PRIMARY KEY, json TEXT)',
  'CREATE TABLE inspection(id TEXT PRIMARY KEY, scanned_at TEXT, json TEXT)',
  'CREATE TABLE photo(id TEXT PRIMARY KEY, path TEXT, json TEXT, uploaded INTEGER DEFAULT 0, tries INTEGER DEFAULT 0, next_try INTEGER DEFAULT 0)',
  // every create/change is written here in the SAME transaction as the record itself
  'CREATE TABLE outbox(seq INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT, id TEXT, payload TEXT)',
];
const _allTables = ['kv', 'zone', 'asset_type', 'asset', 'tag', 'template', 'issue', 'inspection', 'photo', 'outbox'];

class LocalDb {
  LocalDb._(this.db);
  final Database db;
  static LocalDb? _instance;

  static Future<LocalDb> open() async {
    if (_instance != null) return _instance!;
    const ss = FlutterSecureStorage();
    var key = await ss.read(key: 'db_key'); // key lives in Keystore/Keychain, never on disk
    if (key == null) {
      key = const Uuid().v4() + const Uuid().v4();
      await ss.write(key: 'db_key', value: key);
    }
    final path = p.join(await getDatabasesPath(), 'kanha.db');
    final db = await openDatabase(path, password: key, version: 1, onCreate: (d, v) async {
      for (final s in _schema) {
        await d.execute(s);
      }
    });
    return _instance = LocalDb._(db);
  }

  Future<String?> kvGet(String k) async {
    final r = await db.query('kv', where: 'k=?', whereArgs: [k]);
    return r.isEmpty ? null : r.first['v'] as String;
  }

  Future<void> kvSet(String k, String v) =>
      db.insert('kv', {'k': k, 'v': v}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<Map<String, dynamic>>> all(String table, {String? where, List<Object?>? args}) async {
    final rows = await db.query(table, where: where, whereArgs: args);
    return rows.map((r) => jsonDecode(r['json'] as String) as Map<String, dynamic>).toList();
  }

  Future<void> upsert(DatabaseExecutor ex, String table, String keyCol, String key, Map<String, dynamic> obj,
      [Map<String, Object?> extra = const {}]) {
    return ex.insert(table, {keyCol: key, 'json': jsonEncode(obj), ...extra}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Called on logout: encrypted DB is emptied and photo files are removed.
  Future<void> wipe() async {
    for (final r in await db.query('photo')) {
      final f = File(r['path'] as String);
      if (await f.exists()) await f.delete();
    }
    for (final t in _allTables) {
      await db.delete(t);
    }
  }
}
