import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// One queued change, sent to the API in order when the device is online.
class Op {
  Op({this.seq, required this.itemId, required this.kind, required this.method, required this.path, this.body, this.filePath, this.attempts = 0, this.lastError});

  final int? seq;
  final String itemId;

  /// create | update | upload
  final String kind;
  final String method;
  final String path;
  final Map<String, dynamic>? body;
  final String? filePath;
  final int attempts;
  final String? lastError;

  Map<String, Object?> toRow() => {
        'item_id': itemId,
        'kind': kind,
        'method': method,
        'path': path,
        'body': body == null ? null : jsonEncode(body),
        'file_path': filePath,
        'attempts': attempts,
        'last_error': lastError,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

  factory Op.fromRow(Map<String, Object?> r) => Op(
        seq: r['seq'] as int,
        itemId: r['item_id'] as String,
        kind: r['kind'] as String,
        method: r['method'] as String,
        path: r['path'] as String,
        body: r['body'] == null ? null : jsonDecode(r['body'] as String) as Map<String, dynamic>,
        filePath: r['file_path'] as String?,
        attempts: r['attempts'] as int? ?? 0,
        lastError: r['last_error'] as String?,
      );
}

/// On-device copy of the user's items, the queue of unsent changes, and the sync position.
class LocalStore {
  LocalStore(this._db);
  final Database _db;

  static Future<LocalStore> open({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'dumpbox.db');
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE items (id TEXT PRIMARY KEY, data TEXT NOT NULL, created_at TEXT NOT NULL, version INTEGER NOT NULL)');
          await db.execute('CREATE INDEX items_created ON items (created_at DESC)');
          await db.execute(
            'CREATE TABLE outbox (seq INTEGER PRIMARY KEY AUTOINCREMENT, item_id TEXT NOT NULL, kind TEXT NOT NULL, method TEXT NOT NULL, '
            'path TEXT NOT NULL, body TEXT, file_path TEXT, attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT, created_at TEXT NOT NULL)',
          );
          await db.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)');
        },
      ),
    );
    return LocalStore(db);
  }

  Future<List<Item>> allItems() async {
    final rows = await _db.query('items', orderBy: 'created_at DESC');
    return rows.map((r) => Item.fromJson(jsonDecode(r['data'] as String) as Map<String, dynamic>)).toList();
  }

  Future<void> putItems(Iterable<Item> items) async {
    final batch = _db.batch();
    for (final i in items) {
      batch.insert(
        'items',
        {'id': i.id, 'data': jsonEncode(i.toJson()), 'created_at': i.createdAt.toUtc().toIso8601String(), 'version': i.version},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteItems(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await _db.delete('items', where: 'id IN (${List.filled(list.length, '?').join(',')})', whereArgs: list);
  }

  Future<int> enqueue(Op op) => _db.insert('outbox', op.toRow());

  Future<List<Op>> pendingOps() async => (await _db.query('outbox', orderBy: 'seq ASC')).map(Op.fromRow).toList();

  Future<void> removeOp(int seq) => _db.delete('outbox', where: 'seq = ?', whereArgs: [seq]);

  Future<void> removeOpsFor(String itemId) => _db.delete('outbox', where: 'item_id = ?', whereArgs: [itemId]);

  Future<void> markOpFailed(int seq, String error) =>
      _db.rawUpdate('UPDATE outbox SET attempts = attempts + 1, last_error = ? WHERE seq = ?', [error, seq]);

  Future<String?> getMeta(String key) async {
    final r = await _db.query('meta', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> setMeta(String key, String? value) =>
      _db.insert('meta', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  /// Signing out removes everything stored on the device.
  Future<void> clearAll() async {
    await _db.delete('items');
    await _db.delete('outbox');
    await _db.delete('meta');
  }

  Future<void> close() => _db.close();
}
