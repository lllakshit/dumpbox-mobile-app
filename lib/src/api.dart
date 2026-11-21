import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

/// Thrown for every failed API call. [isOffline] means the request never reached the server.
class ApiException implements Exception {
  ApiException(this.status, this.code, this.message);
  final int status;
  final String code;
  final String message;

  bool get isOffline => status == 0;

  /// Errors worth retrying later (network, rate limit, server trouble). Others mean the request itself is wrong.
  /// An expired session (401) is retried after the token refreshes, never dropped.
  bool get isRetryable => status == 0 || status == 401 || status == 408 || status == 429 || status >= 500;

  @override
  String toString() => message;
}

/// Client for the DumpBox /v1 API. [tokenProvider] returns the current Supabase access token.
class ApiClient {
  ApiClient({required this.tokenProvider, http.Client? client, String? baseUrl})
      : _http = client ?? http.Client(),
        _base = baseUrl ?? AppConfig.apiBase;

  final Future<String?> Function() tokenProvider;
  final http.Client _http;
  final String _base;
  static const _timeout = Duration(seconds: 30);

  Future<Map<String, dynamic>> request(String method, String path, {Object? body}) async {
    final token = await tokenProvider();
    if (token == null) throw ApiException(401, 'unauthorized', 'Sign in again');
    final req = http.Request(method, Uri.parse('$_base$path'))
      ..headers['authorization'] = 'Bearer $token'
      ..headers['accept'] = 'application/json';
    if (body != null) {
      req.headers['content-type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(_timeout));
    } on SocketException {
      throw ApiException(0, 'offline', 'You are offline');
    } on HttpException {
      throw ApiException(0, 'offline', 'Connection problem');
    } on http.ClientException {
      throw ApiException(0, 'offline', 'Connection problem');
    } on Exception catch (e) {
      if (e.toString().contains('TimeoutException')) throw ApiException(0, 'offline', 'The server took too long');
      rethrow;
    }
    if (res.statusCode == 204) return const {};
    Map<String, dynamic> data = const {};
    if (res.body.isNotEmpty) {
      try {
        data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      } on FormatException {
        throw ApiException(res.statusCode, 'bad_response', 'Unexpected response (${res.statusCode})');
      }
    }
    if (res.statusCode >= 400) {
      final err = data['error'] as Map<String, dynamic>?;
      throw ApiException(res.statusCode, err?['code'] as String? ?? 'error', err?['message'] as String? ?? 'Request failed (${res.statusCode})');
    }
    return data;
  }

  Future<Item> createItem(Map<String, dynamic> payload) async =>
      Item.fromJson((await request('POST', '/v1/items', body: payload))['item'] as Map<String, dynamic>);

  Future<Item> itemFrom(String method, String path, {Object? body}) async =>
      Item.fromJson((await request(method, path, body: body))['item'] as Map<String, dynamic>);

  Future<ChangesPage> changes(String? since) async {
    final q = since == null ? '' : '?since=${Uri.encodeQueryComponent(since)}';
    return ChangesPage.fromJson(await request('GET', '/v1/changes$q'));
  }

  Future<List<SearchHit>> search(Map<String, String> params) async {
    final uri = Uri(queryParameters: params).query;
    final data = await request('GET', '/v1/search?$uri');
    return ((data['results'] as List?) ?? const [])
        .map((r) => SearchHit(Item.fromJson((r as Map<String, dynamic>)['item'] as Map<String, dynamic>), r['highlight'] as String? ?? ''))
        .toList();
  }

  Future<List<Tag>> tags() async =>
      ((await request('GET', '/v1/tags'))['tags'] as List).map((t) => Tag.fromJson(t as Map<String, dynamic>)).toList();

  Future<List<Collection>> collections() async => ((await request('GET', '/v1/collections'))['collections'] as List)
      .map((c) => Collection.fromJson(c as Map<String, dynamic>))
      .toList();

  Future<Collection> createCollection(String name) async =>
      Collection.fromJson((await request('POST', '/v1/collections', body: {'name': name}))['collection'] as Map<String, dynamic>);

  Future<({String view, String download})> fileUrls(String fileId) async {
    final d = await request('GET', '/v1/files/$fileId');
    return (view: d['view_url'] as String, download: d['download_url'] as String);
  }

  Future<String> createShare({String? itemId, String? collectionId, int? expiresInDays, bool allowDownload = true}) async {
    final d = await request('POST', '/v1/shares', body: {
      'item_id': ?itemId,
      'collection_id': ?collectionId,
      'expires_in_days': ?expiresInDays,
      'allow_download': allowDownload,
    });
    return d['url'] as String;
  }

  Future<Map<String, dynamic>> me() => request('GET', '/v1/me');

  Future<void> deleteAccount() => request('DELETE', '/v1/me', body: {'confirm': 'DELETE'});

  /// Three-step upload: signed URL, PUT bytes, register. Returns the updated item.
  Future<({Item item, String? duplicateOf})> uploadFile({
    required String itemId,
    required File file,
    required String fileName,
    required String mimeType,
    required String sha256,
  }) async {
    final size = await file.length();
    final up = await request('POST', '/v1/uploads', body: {
      'item_id': itemId,
      'file_name': fileName,
      'mime_type': mimeType,
      'size_bytes': size,
      'sha256': sha256,
    });
    final put = http.StreamedRequest('PUT', Uri.parse(up['upload_url'] as String))
      ..headers['content-type'] = mimeType
      ..contentLength = size;
    file.openRead().listen(put.sink.add, onDone: put.sink.close, onError: put.sink.addError, cancelOnError: true);
    http.StreamedResponse res;
    try {
      res = await _http.send(put).timeout(const Duration(minutes: 10));
      await res.stream.drain<void>();
    } on SocketException {
      throw ApiException(0, 'offline', 'Upload interrupted');
    } on http.ClientException {
      throw ApiException(0, 'offline', 'Upload interrupted');
    }
    if (res.statusCode >= 300) throw ApiException(res.statusCode >= 500 ? 503 : res.statusCode, 'upload_failed', 'Upload failed (${res.statusCode})');
    final item = await itemFrom('POST', '/v1/items/$itemId/files', body: {
      'file_id': up['file_id'],
      'storage_path': up['storage_path'],
      'file_name': fileName,
      'mime_type': mimeType,
      'sha256': sha256,
    });
    final dup = up['duplicate_of'] as Map<String, dynamic>?;
    return (item: item, duplicateOf: dup?['item_id'] as String?);
  }
}

class ChangesPage {
  ChangesPage({required this.items, required this.deletedIds, required this.nextSince, required this.hasMore, required this.reset});
  final List<Item> items;
  final List<String> deletedIds;
  final String? nextSince;
  final bool hasMore;
  final bool reset;

  factory ChangesPage.fromJson(Map<String, dynamic> j) => ChangesPage(
        items: ((j['items'] as List?) ?? const []).map((i) => Item.fromJson(i as Map<String, dynamic>)).toList(),
        deletedIds: ((j['deleted_ids'] as List?) ?? const []).cast<String>(),
        nextSince: j['next_since'] as String?,
        hasMore: j['has_more'] as bool? ?? false,
        reset: j['reset'] as bool? ?? false,
      );
}

class SearchHit {
  SearchHit(this.item, this.highlight);
  final Item item;
  final String highlight;
}
