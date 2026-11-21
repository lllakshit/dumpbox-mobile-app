import '../api.dart';

/// Short-lived signed file URLs, cached for 50 minutes (they are valid for 60).
class FileUrls {
  static ApiClient? api;
  static final _cache = <String, (DateTime, ({String view, String download}))>{};

  static Future<({String view, String download})> get(String fileId) async {
    final hit = _cache[fileId];
    if (hit != null && DateTime.now().difference(hit.$1) < const Duration(minutes: 50)) return hit.$2;
    final client = api;
    if (client == null) throw StateError('FileUrls.api not set');
    final urls = await client.fileUrls(fileId);
    _cache[fileId] = (DateTime.now(), urls);
    return urls;
  }

  static void clear() => _cache.clear();
}
