import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../api.dart';
import 'planner_models.dart';
import 'recurrence.dart';

/// On-device copy of events, tasks and lists, the queue of unsent changes, and the sync position.
class PlannerStore {
  PlannerStore(this._db);
  final Database _db;

  static Future<PlannerStore> open(String path, {DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final db = await f.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE entries (id TEXT PRIMARY KEY, data TEXT NOT NULL, version INTEGER NOT NULL)');
          await db.execute(
            'CREATE TABLE outbox (seq INTEGER PRIMARY KEY AUTOINCREMENT, entry_id TEXT NOT NULL, method TEXT NOT NULL, path TEXT NOT NULL, body TEXT, attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT)',
          );
          await db.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)');
        },
      ),
    );
    return PlannerStore(db);
  }

  Future<List<Entry>> entries() async =>
      (await _db.query('entries')).map((r) => Entry.fromJson(jsonDecode(r['data'] as String) as Map<String, dynamic>)).toList();

  Future<void> putEntries(Iterable<Entry> list) async {
    final b = _db.batch();
    for (final e in list) {
      b.insert('entries', {'id': e.id, 'data': jsonEncode(e.toJson()), 'version': e.version}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await b.commit(noResult: true);
  }

  Future<void> deleteEntry(String id) => _db.delete('entries', where: 'id = ?', whereArgs: [id]);

  Future<void> enqueue(String entryId, String method, String path, Map<String, dynamic>? body) =>
      _db.insert('outbox', {'entry_id': entryId, 'method': method, 'path': path, 'body': body == null ? null : jsonEncode(body)});

  Future<List<Map<String, Object?>>> ops() => _db.query('outbox', orderBy: 'seq ASC');

  Future<void> removeOp(int seq) => _db.delete('outbox', where: 'seq = ?', whereArgs: [seq]);

  Future<void> removeOpsFor(String id) => _db.delete('outbox', where: 'entry_id = ?', whereArgs: [id]);

  Future<void> markFailed(int seq, String err) => _db.rawUpdate('UPDATE outbox SET attempts = attempts + 1, last_error = ? WHERE seq = ?', [err, seq]);

  Future<String?> meta(String key) async {
    final r = await _db.query('meta', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> setMeta(String key, String? value) => _db.insert('meta', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> clear() async {
    await _db.delete('entries');
    await _db.delete('outbox');
    await _db.delete('meta');
  }

  Future<void> close() => _db.close();
}

/// Calendar and tasks for the signed-in user: changes show at once, are queued, and are sent in order; the server's
/// copy comes back through /v1/planner/changes. Works offline; syncs when the connection returns.
class PlannerEngine extends ChangeNotifier {
  PlannerEngine({required this.store, required this.api, this.onChanged});

  final PlannerStore store;
  final ApiClient api;

  /// Called after the local copy changes (used to reschedule notifications).
  final Future<void> Function(PlannerEngine engine)? onChanged;

  final Map<String, Entry> _entries = {};
  List<PlannerList> _lists = [];
  PlannerPrefs prefs = const PlannerPrefs();
  final Map<String, String> _failed = {};
  Future<void>? _running;
  bool _again = false;
  Timer? _debounce;
  bool syncing = false;
  bool online = true;
  String? lastError;

  List<Entry> get entries => _entries.values.where((e) => !e.isDeleted).toList();
  Iterable<Entry> get allEntries => _entries.values;
  List<PlannerList> get lists => _lists;
  List<PlannerList> get calendars => _lists.where((l) => l.isCalendar).toList();
  List<PlannerList> get taskLists => _lists.where((l) => !l.isCalendar).toList();
  Entry? byId(String id) => _entries[id];
  String? failureFor(String id) => _failed[id];

  PlannerList? listById(String? id) {
    if (id == null) return null;
    for (final l in _lists) {
      if (l.id == id) return l;
    }
    return null;
  }

  String? defaultListId(String kind) {
    final want = kind == 'event' ? 'calendar' : 'tasks';
    PlannerList? any;
    for (final l in _lists) {
      if (l.kind != want) continue;
      if (l.isDefault) return l.id;
      any ??= l;
    }
    return any?.id;
  }

  String colorOf(Entry e) => e.color ?? listById(e.listId)?.color ?? '#3a5bd9';

  Future<void> init() async {
    for (final e in await store.entries()) {
      _entries[e.id] = e;
    }
    final l = await store.meta('lists');
    if (l != null) _lists = (jsonDecode(l) as List).map((x) => PlannerList.fromJson(x as Map<String, dynamic>)).toList();
    final p = await store.meta('prefs');
    if (p != null) prefs = PlannerPrefs.fromJson(jsonDecode(p) as Map<String, dynamic>);
    notifyListeners();
  }

  void nudge([Duration delay = const Duration(milliseconds: 300)]) {
    _debounce?.cancel();
    _debounce = Timer(delay, sync);
  }

  // ---------------------------------------------------------------- changes

  /// Creates an event or task from a request body (same fields as POST /v1/planner/entries).
  Future<Entry> create(Map<String, dynamic> body) async {
    final id = body['id'] as String? ?? const Uuid().v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final kind = body['kind'] as String? ?? 'task';
    final payload = {
      ...body,
      'id': id,
      'time_zone': body['time_zone'] ?? localZoneName,
      'list_id': body['list_id'] ?? defaultListId(kind),
    };
    final e = Entry.fromJson({
      ...payload,
      'version': 0,
      'created_at': now,
      'updated_at': now,
      'completed_at': body['completed'] == true ? now : null,
      'position': body['position'] ?? DateTime.now().millisecondsSinceEpoch / 1000,
    });
    _entries[id] = e;
    await store.putEntries([e]);
    await store.enqueue(id, 'POST', '/v1/planner/entries', payload);
    await _changed();
    nudge(Duration.zero);
    return e;
  }

  Future<void> update(Entry e, Map<String, dynamic> patch) async {
    final next = e.applyPatch(patch);
    _entries[e.id] = next;
    await store.putEntries([next]);
    await store.enqueue(e.id, 'PATCH', '/v1/planner/entries/${e.id}', {...patch, if (e.version > 0) 'base_version': e.version});
    await _changed();
    nudge(Duration.zero);
  }

  Future<void> toggleDone(Entry e) => update(e, {'completed': !e.isDone});

  /// Moves to the bin (with subtasks). Entries never sent to the server are simply dropped.
  Future<void> remove(Entry e) async {
    if (e.version == 0 && (await store.ops()).any((o) => o['entry_id'] == e.id && o['method'] == 'POST')) {
      _entries.remove(e.id);
      await store.deleteEntry(e.id);
      await store.removeOpsFor(e.id);
      await _changed();
      return;
    }
    for (final c in _entries.values.where((c) => c.parentId == e.id).toList()) {
      _entries[c.id] = c.applyPatch({'deleted': true});
    }
    await update(e, {'deleted': true});
  }

  Future<void> restore(Entry e) => update(e, {'deleted': false});

  Future<void> savePrefs(PlannerPrefs p) async {
    prefs = p;
    await store.setMeta('prefs', jsonEncode(p.toJson()));
    await _changed();
    try {
      await api.request('PATCH', '/v1/me', body: {'planner': p.toJson()});
    } on ApiException catch (e) {
      lastError = e.message;
      notifyListeners();
    }
  }

  // Lists need the server (names must be unique), so they are not queued.
  Future<PlannerList> createList(String kind, String name) async {
    final d = await api.request('POST', '/v1/planner/lists', body: {'kind': kind, 'name': name});
    final l = PlannerList.fromJson(d['list'] as Map<String, dynamic>);
    await _setLists([..._lists, l]);
    return l;
  }

  Future<void> updateList(PlannerList l, {String? name, String? color, bool? hidden}) async {
    await _setLists(_lists.map((x) => x.id == l.id ? x.copyWith(name: name, color: color, hidden: hidden) : x).toList());
    try {
      await api.request('PATCH', '/v1/planner/lists/${l.id}', body: {'name': ?name, 'color': ?color, 'hidden': ?hidden});
    } on ApiException {
      await _setLists(_lists.map((x) => x.id == l.id ? l : x).toList());
      rethrow;
    }
  }

  Future<void> deleteList(PlannerList l) async {
    await api.request('DELETE', '/v1/planner/lists/${l.id}');
    await _setLists(_lists.where((x) => x.id != l.id).toList());
    await sync();
  }

  Future<void> _setLists(List<PlannerList> l) async {
    _lists = l;
    await store.setMeta('lists', jsonEncode(l.map((x) => x.toJson()).toList()));
    notifyListeners();
  }

  Future<void> _changed() async {
    notifyListeners();
    final cb = onChanged;
    if (cb != null) {
      try {
        await cb(this);
      } catch (e) {
        debugPrint('planner onChanged failed: $e');
      }
    }
  }

  // ---------------------------------------------------------------- sync

  Future<void> sync() {
    final r = _running;
    if (r != null) {
      _again = true;
      return r;
    }
    return _running = _syncOnce().whenComplete(() => _running = null);
  }

  Future<void> _syncOnce() async {
    syncing = true;
    notifyListeners();
    try {
      do {
        _again = false;
        if (!await _flush()) break;
        await _pull();
        lastError = null;
        online = true;
      } while (_again);
    } on ApiException catch (e) {
      if (e.isOffline) {
        online = false;
      } else {
        lastError = e.message;
      }
    } finally {
      syncing = false;
      await _changed();
    }
  }

  Future<bool> _flush() async {
    for (final op in await store.ops()) {
      final seq = op['seq'] as int;
      final id = op['entry_id'] as String;
      final body = op['body'] == null ? null : jsonDecode(op['body'] as String) as Map<String, dynamic>;
      try {
        final d = await api.request(op['method'] as String, op['path'] as String, body: body);
        await store.removeOp(seq);
        _failed.remove(id);
        final pending = (await store.ops()).map((o) => o['entry_id']).toSet();
        for (final key in ['entry', 'next_entry']) {
          final x = d[key];
          if (x is Map<String, dynamic>) {
            final e = Entry.fromJson(x);
            // A newer local change is still queued: keep showing it.
            if (pending.contains(e.id) && key == 'entry') continue;
            _entries[e.id] = e;
            await store.putEntries([e]);
          }
        }
      } on ApiException catch (e) {
        if (e.isOffline) {
          online = false;
          return false;
        }
        if (e.isRetryable) {
          await store.markFailed(seq, e.message);
          return false;
        }
        // Refused for good: drop it and show why. A refused create removes the entry here too.
        await store.removeOp(seq);
        _failed[id] = e.message;
        if (op['method'] == 'POST') {
          await store.removeOpsFor(id);
          _entries.remove(id);
          await store.deleteEntry(id);
        }
        lastError = e.message;
      }
    }
    return true;
  }

  Future<void> _pull() async {
    var since = await store.meta('since');
    final pending = (await store.ops()).map((o) => o['entry_id'] as String).toSet();
    for (var page = 0; page < 100; page++) {
      final q = since == null ? '' : '?since=${Uri.encodeQueryComponent(since)}';
      final d = await api.request('GET', '/v1/planner/changes$q');
      if (d['reset'] == true) {
        since = null;
        await store.setMeta('since', null);
        continue;
      }
      final incoming = ((d['entries'] as List?) ?? const []).map((x) => Entry.fromJson(x as Map<String, dynamic>));
      final save = <Entry>[];
      for (final e in incoming) {
        final have = _entries[e.id];
        if (have != null && have.version > e.version) continue;
        if (pending.contains(e.id)) continue;
        _entries[e.id] = e;
        save.add(e);
      }
      await store.putEntries(save);
      final lists = d['lists'];
      if (lists is List) await _setLists(lists.map((x) => PlannerList.fromJson(x as Map<String, dynamic>)).toList());
      since = d['next_since'] as String?;
      await store.setMeta('since', since);
      if (d['has_more'] != true) break;
    }
    // Preferences live in the profile.
    try {
      final me = await api.request('GET', '/v1/me');
      final p = (me['user'] as Map<String, dynamic>?)?['planner'];
      if (p is Map<String, dynamic>) {
        prefs = PlannerPrefs.fromJson(p);
        await store.setMeta('prefs', jsonEncode(prefs.toJson()));
      }
    } on ApiException {
      // keep the cached ones
    }
  }

  /// Makes sure the background reminder check can read this calendar: a working secret address is kept on the
  /// phone (a new one is made if it was turned off or replaced on the web).
  Future<void> ensureBackgroundFeed(String dbPath, {Future<bool> Function(String url)? check}) async {
    var url = await store.meta('feed_url');
    if (url != null && check != null && !await check(url)) url = null;
    if (url == null) {
      final d = await api.request('POST', '/v1/planner/feed-token');
      url = d['json_url'] as String?;
      if (url == null) return;
      await store.setMeta('feed_url', url);
    }
    feedUrl = url;
    onFeedReady?.call(url, dbPath);
  }

  String? feedUrl;
  void Function(String url, String dbPath)? onFeedReady;

  Future<void> wipe() async {
    _debounce?.cancel();
    await store.clear();
    _entries.clear();
    _lists = [];
    notifyListeners();
  }

  // ---------------------------------------------------------------- helpers for screens

  /// Occurrences in a date range from visible calendars / lists, sorted (all-day first, then by time).
  List<Occurrence> occurrencesIn(String from, String to, {bool includeDone = true}) {
    final hidden = _lists.where((l) => l.hidden).map((l) => l.id).toSet();
    final out = <Occurrence>[];
    for (final e in entries) {
      if (e.listId != null && hidden.contains(e.listId)) continue;
      if (e.isTask && e.parentId != null) continue;
      if (e.isTask && e.isDone && !includeDone) continue;
      out.addAll(occurrences(e, from, to));
    }
    out.sort((a, b) {
      if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : a.entry.title.compareTo(b.entry.title);
    });
    return out;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
