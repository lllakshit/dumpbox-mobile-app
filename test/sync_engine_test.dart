import 'dart:convert';
import 'dart:io';

import 'package:dumpbox/src/api.dart';
import 'package:dumpbox/src/local_store.dart';
import 'package:dumpbox/src/models.dart';
import 'package:dumpbox/src/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A tiny in-memory stand-in for the /v1 API.
class FakeServer {
  final items = <String, Map<String, dynamic>>{};
  final deleted = <String>[];
  bool offline = false;
  int creates = 0;
  int version = 0;

  Map<String, dynamic> _stamp(Map<String, dynamic> i) {
    i['version'] = (i['version'] as int? ?? 0) + 1;
    i['updated_at'] = DateTime.now().toUtc().add(Duration(microseconds: ++version)).toIso8601String();
    return i;
  }

  late final client = MockClient((req) async {
    if (offline) throw const SocketException('offline');
    final path = req.url.path;
    final body = req.body.isEmpty ? <String, dynamic>{} : jsonDecode(req.body) as Map<String, dynamic>;
    if (req.method == 'POST' && path == '/v1/items') {
      final id = body['id'] as String;
      if (items.containsKey(id)) return http.Response(jsonEncode({'item': items[id], 'created': false}), 200);
      if (body['type'] == 'note' && (body['body'] as String? ?? '').trim().isEmpty) {
        return http.Response(jsonEncode({'error': {'code': 'validation_failed', 'message': 'A note needs text'}}), 400);
      }
      creates++;
      items[id] = _stamp({
        ...body,
        'version': 0,
        'created_at': body['captured_at'],
        'tags': [],
        'collection_ids': [],
        'files': [],
        'pinned': false,
        'starred': false,
      });
      return http.Response(jsonEncode({'item': items[id], 'created': true}), 201);
    }
    final m = RegExp(r'^/v1/items/([^/]+)$').firstMatch(path);
    if (m != null && req.method == 'PATCH') {
      final it = items[m.group(1)]!;
      for (final k in ['starred', 'pinned', 'title', 'body']) {
        if (body.containsKey(k)) it[k] = body[k];
      }
      return http.Response(jsonEncode({'item': _stamp(it)}), 200);
    }
    if (m != null && req.method == 'DELETE') {
      items.remove(m.group(1));
      deleted.add(m.group(1)!);
      return http.Response('', 204);
    }
    if (path == '/v1/changes') {
      final list = items.values.toList()..sort((a, b) => (a['updated_at'] as String).compareTo(b['updated_at'] as String));
      return http.Response(jsonEncode({'items': list, 'deleted_ids': deleted, 'next_since': 'tok', 'has_more': false, 'reset': false}), 200);
    }
    return http.Response(jsonEncode({'error': {'code': 'not_found', 'message': 'no route $path'}}), 404);
  });
}

void main() {
  sqfliteFfiInit();
  late FakeServer server;
  late SyncEngine engine;
  late Directory tmp;

  setUp(() async {
    server = FakeServer();
    tmp = await Directory.systemTemp.createTemp('dumpbox-test');
    final store = await LocalStore.open(path: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);
    final api = ApiClient(tokenProvider: () async => 'token', client: server.client, baseUrl: 'https://api.test');
    engine = SyncEngine(store: store, api: api, filesDir: Directory('${tmp.path}/files'), source: 'android');
    await engine.init();
  });

  tearDown(() async {
    engine.dispose();
    await engine.store.close();
    await tmp.delete(recursive: true);
  });

  test('captures offline, keeps it on the device, and sends it exactly once when back online', () async {
    server.offline = true;
    final item = await engine.captureText('buy train tickets');
    await engine.sync();
    expect(engine.online, isFalse);
    expect(engine.allItems.single.id, item.id);
    expect(engine.isPending(item.id), isTrue);
    expect(server.creates, 0);

    server.offline = false;
    await engine.sync();
    await engine.sync(); // a second run must not resend
    expect(server.creates, 1);
    expect(engine.isPending(item.id), isFalse);
    expect(engine.byId(item.id)!.version, greaterThan(0));
    expect(engine.online, isTrue);
  });

  test('a bare URL is captured as a link', () async {
    final item = await engine.captureText('https://example.com/page');
    expect(item.type, ItemType.link);
    expect(item.url, 'https://example.com/page');
  });

  test('a change the server refuses is dropped and shown on the item, not retried forever', () async {
    final item = await engine.captureText('   ');
    await engine.sync();
    expect(engine.failureFor(item.id), 'A note needs text');
    expect(engine.isPending(item.id), isFalse);
    await engine.sync();
    expect(server.creates, 0);
  });

  test('queued edits apply in order and survive until sent', () async {
    final item = await engine.captureText('note');
    await engine.sync();
    final saved = engine.byId(item.id)!;
    server.offline = true;
    await engine.setStarred(saved, true);
    expect(engine.byId(item.id)!.starred, isTrue, reason: 'shown at once');
    await engine.sync();
    expect(server.items[item.id]!['starred'], isFalse);
    server.offline = false;
    await engine.sync();
    expect(server.items[item.id]!['starred'], isTrue);
    expect(engine.byId(item.id)!.starred, isTrue);
  });

  test('items deleted on another device disappear here', () async {
    final item = await engine.captureText('to remove elsewhere');
    await engine.sync();
    server.items.remove(item.id);
    server.deleted.add(item.id);
    await engine.sync();
    expect(engine.byId(item.id), isNull);
  });

  test('deleting an item that never reached the server makes no server call', () async {
    server.offline = true;
    final item = await engine.captureText('draft');
    await engine.deleteForever(engine.byId(item.id)!);
    server.offline = false;
    await engine.sync();
    expect(server.creates, 0);
    expect(server.deleted, isEmpty);
    expect(engine.byId(item.id), isNull);
  });

  test('local search matches text and tags, offline', () async {
    await engine.captureText('October electricity bill', tags: ['bills']);
    await engine.captureText('Goa trip ideas');
    expect(engine.searchLocal('electricity').length, 1);
    expect(engine.searchLocal('bills').length, 1);
    expect(engine.searchLocal('goa ideas').length, 1);
    expect(engine.searchLocal('nothing'), isEmpty);
  });
}
