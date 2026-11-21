/// A single bare http(s) URL becomes a link; anything else is a note.
class CaptureKind {
  const CaptureKind._(this.url);
  final String? url;
  bool get isLink => url != null;
}

CaptureKind classifyText(String text) {
  final t = text.trim();
  if (RegExp(r'^https?://\S+$', caseSensitive: false).hasMatch(t)) {
    final u = Uri.tryParse(t);
    if (u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty) return CaptureKind._(t);
  }
  return const CaptureKind._(null);
}
