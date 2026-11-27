import 'dart:io';

import 'package:dumpbox/src/models.dart';
import 'package:dumpbox/src/ui/image_album.dart';
import 'package:dumpbox/src/ui/image_viewer.dart';
import 'package:dumpbox/src/ui/item_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime.utc(2026, 11, 27, 6, 0, 0);

Item photo(String id, int secondsAfter, {String? caption, List<String> tags = const [], String? localPath, int? w, int? h}) => Item(
  id: id,
  type: ItemType.image,
  body: caption,
  createdAt: _t0.add(Duration(seconds: secondsAfter)),
  updatedAt: _t0.add(Duration(seconds: secondsAfter)),
  tags: [for (final t in tags) TagRef(id: t, name: t)],
  files: [FileMeta(id: 'f-$id', fileName: '$id.png', mimeType: 'image/png', sizeBytes: 10, localPath: localPath, width: w, height: h)],
);

Item note(String id, int secondsAfter) => Item(
  id: id,
  type: ItemType.note,
  body: 'hello',
  createdAt: _t0.add(Duration(seconds: secondsAfter)),
  updatedAt: _t0.add(Duration(seconds: secondsAfter)),
);

List<String> ids(List<List<Item>> rows) => [for (final r in rows) r.map((i) => i.id).join('+')];

void main() {
  group('groupIntoAlbums (newest first)', () {
    test('photos sent together become one album; a note in between splits them', () {
      final rows = groupIntoAlbums([photo('p4', 40), photo('p3', 30), note('n', 20), photo('p2', 10), photo('p1', 0)]);
      expect(ids(rows), ['p4+p3', 'n', 'p2+p1']);
    });

    test('a single photo stays a normal item', () {
      expect(ids(groupIntoAlbums([note('n', 10), photo('p1', 0)])), ['n', 'p1']);
    });

    test('photos more than 2 minutes apart are not grouped', () {
      expect(ids(groupIntoAlbums([photo('b', 200), photo('a', 0)])), ['b', 'a']);
    });

    test('different tags are not grouped', () {
      expect(
        ids(
          groupIntoAlbums([
            photo('b', 5, tags: ['x']),
            photo('a', 0),
          ]),
        ),
        ['b', 'a'],
      );
    });

    test('the caption sits on the first photo of a batch and closes the album', () {
      final rows = groupIntoAlbums([photo('p3', 20), photo('p2', 10), photo('p1', 5, caption: 'trip'), photo('p0', 0)]);
      expect(ids(rows), ['p3+p2+p1', 'p0']);
    });

    test('a captioned photo that is the newest is not merged with older ones', () {
      expect(ids(groupIntoAlbums([photo('p2', 10, caption: 'new'), photo('p1', 0)])), ['p2', 'p1']);
    });
  });

  group('screens', () {
    late Directory dir;
    late String png;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('album');
      png = '${dir.path}/1.png';
      // A valid 1×1 PNG.
      await File(png).writeAsBytes(const [
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
        0x00,
        0x0D,
        0x49,
        0x48,
        0x44,
        0x52,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x01,
        0x08,
        0x06,
        0x00,
        0x00,
        0x00,
        0x1F,
        0x15,
        0xC4,
        0x89,
        0x00,
        0x00,
        0x00,
        0x0D,
        0x49,
        0x44,
        0x41,
        0x54,
        0x78,
        0x9C,
        0x63,
        0xF8,
        0xCF,
        0xC0,
        0xF0,
        0x1F,
        0x00,
        0x05,
        0x00,
        0x01,
        0xFF,
        0x89,
        0x99,
        0x3D,
        0x1D,
        0x00,
        0x00,
        0x00,
        0x00,
        0x49,
        0x45,
        0x4E,
        0x44,
        0xAE,
        0x42,
        0x60,
        0x82,
      ]);
    });
    tearDownAll(() => dir.delete(recursive: true));

    Widget host(Widget child) => MaterialApp(
      theme: ThemeData(
        cardTheme: const CardThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16)))),
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

    testWidgets('album shows a 2×2 grid with +N, tap opens the viewer on that photo, long-press opens actions', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final row = [for (var k = 5; k >= 0; k--) photo('p$k', k, localPath: png)]; // newest first
      Item? actionsFor;
      await tester.pumpWidget(host(AlbumCard(newestFirst: row, onItemActions: (i) => actionsFor = i)));

      expect(find.text('6 photos'), findsOneWidget);
      expect(find.text('+2'), findsOneWidget);
      expect(find.byType(FileImageView), findsNWidgets(4));

      await tester.longPress(find.bySemanticsLabel('Photo 2 of 6'));
      expect(actionsFor?.id, 'p1'); // sent order: p0 is photo 1

      await tester.tap(find.bySemanticsLabel('Photo 2 of 6'));
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewerScreen), findsOneWidget);
      expect(find.text('2 / 6'), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(-250, 0));
      await tester.pumpAndSettle();
      expect(find.text('3 / 6'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewerScreen), findsNothing);
    });

    testWidgets('a single photo keeps its own shape (no crop) and opens full screen on tap', (tester) async {
      final item = photo('tall', 0, localPath: png, w: 1000, h: 2000);
      var cardTapped = false;
      await tester.pumpWidget(host(ItemCard(item: item, onTap: () => cardTapped = true)));

      final ratio = tester.widget<AspectRatio>(find.byType(AspectRatio).first).aspectRatio;
      expect(ratio, closeTo(0.5, 0.001));
      expect(tester.widget<Image>(find.byType(Image).first).fit, BoxFit.contain);

      await tester.tap(find.byType(FileImageView));
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewerScreen), findsOneWidget);
      expect(cardTapped, isFalse);
    });
  });
}
