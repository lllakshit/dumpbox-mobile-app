// Runs the real sync engine against a running DumpBox API and Supabase.
// Skipped unless DUMPBOX_API, SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY and SUPABASE_SECRET_KEY are set, e.g.:
//   DUMPBOX_API=http://host:3000 SUPABASE_URL=http://host:54321 ... flutter test test/integration
import 'dart:convert';
import 'dart:io';

import 'package:dumpbox/src/api.dart';
import 'package:dumpbox/src/local_store.dart';
import 'package:dumpbox/src/models.dart';
import 'package:dumpbox/src/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final env = Platform.environment;
final apiBase = env['DUMPBOX_API'];
final sbUrl = env['SUPABASE_URL'];
final pub = env['SUPABASE_PUBLISHABLE_KEY'];
final secret = env['SUPABASE_SECRET_KEY'];

Future<String> _token() async {
  final email = 'flutter-${DateTime.now().microsecondsSinceEpoch}@test.dev';
  const password = 'flutter-test-password-123';
  final created = await http.post(
    Uri.parse('$sbUrl/auth/v1/admin/users'),
    headers: {'apikey': secret!, 'authorization': 'Bearer $secret', 'content-type': 'application/json'},
    body: jsonEncode({'email': email, 'password': password, 'email_confirm': true}),
  );
  expect(created.statusCode, lessThan(300), reason: created.body);
  final res = await http.post(
    Uri.parse('$sbUrl/auth/v1/token?grant_type=password'),
    headers: {'apikey': pub!, 'content-type': 'application/json'},
    body: jsonEncode({'email': email, 'password': password}),
  );
  return (jsonDecode(res.body) as Map<String, dynamic>)['access_token'] as String;
}

void main() {
  final skip = (apiBase == null || sbUrl == null || pub == null || secret == null) ? 'live API env not set' : null;
  sqfliteFfiInit();

  test('two devices: capture, file upload, edit and delete reach each other through the real API', () async {
    final token = await _token();
    final tmp = await Directory.systemTemp.createTemp('dumpbox-live');
    Future<SyncEngine> device(String name) async {
      final store = await LocalStore.open(path: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);
      final e = SyncEngine(
        store: store,
        api: ApiClient(tokenProvider: () async => token, baseUrl: apiBase),
        filesDir: Directory('${tmp.path}/$name'),
        source: 'android',
      );
      await e.init();
      return e;
    }

    final phone = await device('phone');
    final tablet = await device('tablet');

    final note = await phone.captureText('Hostel invoice October 4200', tags: ['bills']);
    final src = File('${tmp.path}/invoice.pdf')..writeAsStringSync('%PDF-1.4 hostel invoice');
    final file = await phone.captureFile(src, fileName: 'invoice.pdf', mimeType: 'application/pdf', caption: 'October');
    await phone.sync();
    expect(phone.isPending(note.id), isFalse);
    expect(phone.isPending(file.id), isFalse, reason: 'sync error: ${phone.lastSyncError}, item error: ${phone.failureFor(file.id)}, ops: ${(await phone.store.pendingOps()).map((o) => '${o.kind}:${o.lastError}').toList()}');
    expect(phone.byId(file.id)!.files.single.localPath, isNull, reason: 'uploaded');

    await tablet.sync();
    expect(tablet.byId(note.id)!.tags.single.name, 'bills');
    expect(tablet.byId(file.id)!.files.single.fileName, 'invoice.pdf');

    await tablet.setStarred(tablet.byId(note.id)!, true);
    await tablet.sync();
    await phone.sync();
    expect(phone.byId(note.id)!.starred, isTrue);

    await phone.deleteForever(phone.byId(file.id)!);
    await phone.sync();
    await tablet.sync();
    expect(tablet.byId(file.id), isNull);

    final hits = await phone.api.search({'q': 'invoce'});
    expect(hits.map((h) => h.item.id), contains(note.id));

    for (final e in [phone, tablet]) {
      e.dispose();
      await e.store.close();
    }
    await tmp.delete(recursive: true);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('model parses every field the live API returns', () async {
    final token = await _token();
    final api = ApiClient(tokenProvider: () async => token, baseUrl: apiBase);
    final item = await api.createItem({'type': 'location', 'latitude': 26.9, 'longitude': 75.8, 'location_label': 'Jaipur', 'source': 'android'});
    expect(item.type, ItemType.location);
    expect(item.location!.label, 'Jaipur');
    expect(item.version, 1);
  }, skip: skip);
}
