import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'capture.dart';
import 'local_store.dart';
import 'models.dart';

/// Keeps the on-device copy in step with the server.
///
/// Every change is applied on the device first and queued; [sync] sends the queue in order, then pulls
/// `/v1/changes`. Items carry client-made ids, so a retried send never creates a duplicate.
class SyncEngine extends ChangeNotifier {
  SyncEngine({required this.store, required this.api, required this.filesDir, String? source})
      : source = source ?? (Platform.isIOS ? 'ios' : 'android');

  final LocalStore store;
  final ApiClient api;

  /// Where picked files are copied while they wait to upload.
  final Directory filesDir;
  final String source;

  final Map<String, Item> _items = {};
  final Map<String, String> _failed = {};
  final Set<String> _pendingIds = {};
  bool _online = true;
  bool _syncing = false;
  bool _again = false;
  Future<void>? _running;
  Timer? _debounce;
  String? lastSyncError;

  bool get online => _online;
  bool get syncing => _syncing;
  String? failureFor(String id) => _failed[id];
  bool isPending(String id) => _pendingIds.contains(id);

  Future<void> init() async {
    for (final i in await store.allItems()) {
      _items[i.id] = i;
    }
    await _refreshPending();
    notifyListeners();
  }

  /// Items for a view, newest first.
  List<Item> itemsFor(FeedView view) {
    final list = _items.values.where(view.includes).toList()
      ..sort((a, b) {
        final c = b.createdAt.compareTo(a.createdAt);
        return c != 0 ? c : b.id.compareTo(a.id);
      });
    return list;
  }

  List<Item> get allItems => itemsFor(const AllView());

  Item? byId(String id) => _items[id];

  List<Item> searchLocal(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return _items.values.where((i) => !i.isTrashed && words.every(i.searchText.contains)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  void setOnline(bool value) {
    if (_online == value) return;
    _online = value;
    notifyListeners();
    if (value) nudge();
  }

  /// Ask for a sync soon (realtime events, app resume, connectivity back). Bursts collapse into one.
  void nudge([Duration delay = const Duration(milliseconds: 300)]) {
    _debounce?.cancel();
    _debounce = Timer(delay, sync);
  }

  // ---------------------------------------------------------------- capture

  Future<Item> captureText(String text, {List<String> tags = const [], List<String> collectionIds = const []}) {
    final kind = classifyText(text);
    return _capture(
      kind.isLink ? {'type': 'link', 'url': kind.url} : {'type': 'note', 'body': text},
      tags: tags,
      collectionIds: collectionIds,
    );
  }

  Future<Item> capturePlace(double latitude, double longitude, String? label, {List<String> tags = const [], List<String> collectionIds = const []}) =>
      _capture(
        {'type': 'location', 'latitude': latitude, 'longitude': longitude, 'location_label': (label?.trim().isEmpty ?? true) ? null : label!.trim()},
        tags: tags,
        collectionIds: collectionIds,
      );

  /// Copies the file into app storage first, so it survives until it is uploaded even if the app closes.
  Future<Item> captureFile(File source, {required String fileName, required String mimeType, String? caption, List<String> tags = const [], List<String> collectionIds = const []}) async {
    final id = const Uuid().v4();
    final fileId = const Uuid().v4();
    await filesDir.create(recursive: true);
    final local = await source.copy(p.join(filesDir.path, '$fileId-${p.basename(fileName)}'));
    final size = await local.length();
    final type = mimeType.startsWith('image/') ? 'image' : (mimeType.startsWith('audio/') ? 'voice' : 'file');
    final placeholder = FileMeta(id: fileId, fileName: fileName, mimeType: mimeType, sizeBytes: size, localPath: local.path);
    final item = await _capture(
      {'type': type, if (caption != null && caption.trim().isNotEmpty) 'body': caption.trim()},
      id: id,
      files: [placeholder],
      tags: tags,
      collectionIds: collectionIds,
      syncNow: false,
    );
    await store.enqueue(Op(itemId: id, kind: 'upload', method: 'POST', path: '/v1/uploads', body: {'file_name': fileName, 'mime_type': mimeType}, filePath: local.path));
    await _refreshPending();
    nudge(Duration.zero);
    return item;
  }

  Future<Item> _capture(
    Map<String, dynamic> fields, {
    String? id,
    List<FileMeta> files = const [],
    List<String> tags = const [],
    List<String> collectionIds = const [],
    bool syncNow = true,
  }) async {
    final itemId = id ?? const Uuid().v4();
    final now = DateTime.now().toUtc();
    final payload = <String, dynamic>{
      'id': itemId,
      ...fields,
      'source': source,
      'captured_at': now.toIso8601String(),
      if (tags.isNotEmpty) 'tags': tags,
      if (collectionIds.isNotEmpty) 'collection_ids': collectionIds,
    };
    final item = Item.fromJson({
      ...payload,
      'version': 0,
      'created_at': payload['captured_at'],
      'updated_at': payload['captured_at'],
      if (fields['url'] != null) 'link': {'title': null},
      if (fields['latitude'] != null) 'location': {'latitude': fields['latitude'], 'longitude': fields['longitude'], 'label': fields['location_label']},
      'tags': tags.map((t) => {'id': 'local-$t', 'name': t}).toList(),
      'collection_ids': collectionIds,
      'files': files.map((f) => f.toJson()).toList(),
    });
    _items[itemId] = item;
    await store.putItems([item]);
    await store.enqueue(Op(itemId: itemId, kind: 'create', method: 'POST', path: '/v1/items', body: payload));
    await _refreshPending();
    notifyListeners();
    if (syncNow) nudge(Duration.zero);
    return item;
  }

  // ---------------------------------------------------------------- changes to existing items

  Future<void> setStarred(Item i, bool v) => _update(i, i.copyWith(starred: v), 'PATCH', '/v1/items/${i.id}', {'starred': v, 'base_version': i.version});
  Future<void> setPinned(Item i, bool v) => _update(i, i.copyWith(pinned: v), 'PATCH', '/v1/items/${i.id}', {'pinned': v, 'base_version': i.version});
  Future<void> setArchived(Item i, bool v) => _update(
        i,
        v ? i.copyWith(archivedAt: DateTime.now().toUtc()) : i.copyWith(clearArchived: true),
        'PATCH',
        '/v1/items/${i.id}',
        {'archived': v, 'base_version': i.version},
      );
  Future<void> edit(Item i, {String? title, String? body}) =>
      _update(i, i.copyWith(title: title, body: body), 'PATCH', '/v1/items/${i.id}', {'title': title, 'body': body, 'base_version': i.version});
  Future<void> moveToTrash(Item i) async {
    if (i.isLocalOnly) return deleteForever(i);
    await _update(i, i.copyWith(deletedAt: DateTime.now().toUtc(), pinned: false), 'DELETE', '/v1/items/${i.id}', null);
  }

  Future<void> restore(Item i) => _update(i, i.copyWith(clearDeleted: true), 'POST', '/v1/items/${i.id}/restore', null);

  Future<void> setTags(Item i, List<String> names) => _update(i, i, 'PUT', '/v1/items/${i.id}/tags', {'tags': names});
  Future<void> setCollections(Item i, List<String> ids) => _update(i, i, 'PUT', '/v1/items/${i.id}/collections', {'collection_ids': ids});

  /// Removes an item for good. Items never sent to the server are just dropped here.
  Future<void> deleteForever(Item i) async {
    _items.remove(i.id);
    _failed.remove(i.id);
    await store.deleteItems([i.id]);
    final wasLocal = i.isLocalOnly;
    await store.removeOpsFor(i.id);
    for (final f in i.files) {
      if (f.localPath != null) await File(f.localPath!).delete().catchError((_) => File(f.localPath!));
    }
    if (!wasLocal) await store.enqueue(Op(itemId: i.id, kind: 'update', method: 'DELETE', path: '/v1/items/${i.id}?permanent=true'));
    await _refreshPending();
    notifyListeners();
    nudge(Duration.zero);
  }

  Future<void> _update(Item before, Item optimistic, String method, String path, Map<String, dynamic>? body) async {
    _items[before.id] = optimistic;
    await store.putItems([optimistic]);
    await store.enqueue(Op(itemId: before.id, kind: 'update', method: method, path: path, body: body));
    await _refreshPending();
    notifyListeners();
    nudge(Duration.zero);
  }

  // ---------------------------------------------------------------- sync

  /// Runs one sync, or joins the one already running (which then makes one more pass for this request).
  Future<void> sync() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = _syncOnce().whenComplete(() => _running = null);
  }

  Future<void> _syncOnce() async {
    _syncing = true;
    notifyListeners();
    try {
      do {
        _again = false;
        final flushed = await _flush();
        if (!flushed) break;
        await _pull();
        lastSyncError = null;
        if (!_online) {
          _online = true;
        }
      } while (_again);
    } on ApiException catch (e) {
      if (e.isOffline) {
        _online = false;
      } else {
        lastSyncError = e.message;
      }
    } finally {
      _syncing = false;
      await _refreshPending();
      notifyListeners();
    }
  }

  /// Sends queued changes in order. Returns false when the device is offline (the rest waits).
  Future<bool> _flush() async {
    for (final op in await store.pendingOps()) {
      try {
        await _send(op);
        await store.removeOp(op.seq!);
        _failed.remove(op.itemId);
      } on ApiException catch (e) {
        if (e.isOffline) {
          _online = false;
          return false;
        }
        if (e.isRetryable) {
          await store.markOpFailed(op.seq!, e.message);
          return false;
        }
        // The server refused this change for good: drop it and show why on the item.
        await store.removeOp(op.seq!);
        _failed[op.itemId] = e.message;
        if (op.kind == 'create') await store.removeOpsFor(op.itemId);
      }
    }
    _online = true;
    return true;
  }

  Future<void> _send(Op op) async {
    switch (op.kind) {
      case 'create':
        await _apply([await api.createItem(op.body!)], sendingSeq: op.seq);
      case 'upload':
        final file = File(op.filePath!);
        if (!await file.exists()) throw ApiException(410, 'gone', 'The file is no longer on this device');
        final digest = await sha256.bind(file.openRead()).first;
        final r = await api.uploadFile(
          itemId: op.itemId,
          file: file,
          fileName: op.body!['file_name'] as String,
          mimeType: op.body!['mime_type'] as String,
          sha256: digest.toString(),
        );
        await file.delete().catchError((_) => file);
        await _apply([r.item], sendingSeq: op.seq);
      default:
        final data = await api.request(op.method, op.path, body: op.body);
        if (op.method == 'DELETE' && op.path.contains('permanent=true')) return;
        final item = data['item'];
        if (item is Map<String, dynamic>) await _apply([Item.fromJson(item)], sendingSeq: op.seq);
    }
  }

  Future<void> _pull() async {
    var since = await store.getMeta('since');
    for (var page = 0; page < 200; page++) {
      final r = await api.changes(since);
      if (r.reset) {
        await store.setMeta('since', null);
        since = null;
        continue;
      }
      await _apply(r.items);
      if (r.deletedIds.isNotEmpty) {
        for (final id in r.deletedIds) {
          _items.remove(id);
        }
        await store.deleteItems(r.deletedIds);
      }
      since = r.nextSince;
      await store.setMeta('since', since);
      if (!r.hasMore) break;
    }
    notifyListeners();
  }

  /// [sendingSeq] is the queued change whose answer this is; it does not count as "still waiting".
  Future<void> _apply(List<Item> incoming, {int? sendingSeq}) async {
    final ops = (await store.pendingOps()).where((o) => o.seq != sendingSeq).toList();
    final waitingUpload = ops.where((o) => o.kind == 'upload').map((o) => o.itemId).toSet();
    final waitingUpdate = ops.where((o) => o.kind == 'update').map((o) => o.itemId).toSet();
    final toSave = <Item>[];
    for (final it in incoming) {
      final have = _items[it.id];
      if (have != null && have.version > it.version) continue;
      // A newer local change is still queued: keep showing it until it is sent.
      if (have != null && waitingUpdate.contains(it.id)) continue;
      var next = it;
      if (have != null && it.files.isEmpty && waitingUpload.contains(it.id)) next = it.copyWith(files: have.files);
      _items[it.id] = next;
      toSave.add(next);
    }
    await store.putItems(toSave);
    notifyListeners();
  }

  Future<void> _refreshPending() async {
    _pendingIds
      ..clear()
      ..addAll((await store.pendingOps()).map((o) => o.itemId));
  }

  /// Sign-out: forget everything on this device, including queued files.
  Future<void> wipe() async {
    _debounce?.cancel();
    await store.clearAll();
    _items.clear();
    _failed.clear();
    _pendingIds.clear();
    if (await filesDir.exists()) await filesDir.delete(recursive: true);
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
