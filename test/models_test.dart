import 'package:dumpbox/src/capture.dart';
import 'package:dumpbox/src/models.dart';
import 'package:dumpbox/src/ui/search_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses an API item and round-trips it', () {
    final json = {
      'id': 'a',
      'type': 'location',
      'title': null,
      'body': null,
      'url': null,
      'link': null,
      'location': {'latitude': 26.9, 'longitude': 75.8, 'label': 'Jaipur'},
      'pinned': true,
      'starred': false,
      'archived_at': null,
      'deleted_at': null,
      'version': 3,
      'created_at': '2026-11-21T10:00:00.123456+00:00',
      'updated_at': '2026-11-21T10:00:01+00:00',
      'tags': [
        {'id': 't', 'name': 'trip', 'color': null},
      ],
      'collection_ids': ['c'],
      'files': [],
      'source': 'web',
    };
    final item = Item.fromJson(json);
    expect(item.type, ItemType.location);
    expect(item.location!.label, 'Jaipur');
    expect(item.version, 3);
    expect(const TagView('t', 'trip').includes(item), isTrue);
    expect(const CollectionView('c', 'x').includes(item), isTrue);
    expect(const FlagView('pinned').includes(item), isTrue);
    expect(Item.fromJson(item.toJson()).toJson(), item.toJson());
  });

  test('classifies text', () {
    expect(classifyText('https://a.com/x').isLink, isTrue);
    expect(classifyText('see https://a.com').isLink, isFalse);
    expect(classifyText('javascript:alert(1)').isLink, isFalse);
    expect(classifyText('ftp://a.com').isLink, isFalse);
  });

  test('highlight spans keep text and mark matches', () {
    final spans = highlightSpans('paid <mark>electricity</mark> bill <mark>Oct</mark>');
    expect(spans.map((s) => s.text).join(), 'paid electricity bill Oct');
    expect(spans.where((s) => s.style != null).map((s) => s.text), ['electricity', 'Oct']);
  });
}
