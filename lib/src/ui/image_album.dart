import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import 'image_viewer.dart';

/// Photos sent close together are shown as one album, like WhatsApp.
const albumGap = Duration(minutes: 2);

/// A photo item that can join an album: one image, no title.
bool isAlbumPhoto(Item i) => i.type == ItemType.image && i.files.length == 1 && i.files.first.isImage && (i.title == null || i.title!.isEmpty);

String _tagKey(Item i) => (i.tags.map((t) => t.name).toList()..sort()).join('|');

/// Groups a newest-first list into rows: one item, or an album of 2+ photos (also newest first).
/// Photos join when they were added within [albumGap] of the next one, on the same day, with the same tags.
/// Only the first photo of a batch can carry the caption (the composer puts it there), so a captioned photo
/// closes its album.
List<List<Item>> groupIntoAlbums(List<Item> newestFirst) {
  final rows = <List<Item>>[];
  var i = 0;
  while (i < newestFirst.length) {
    final first = newestFirst[i];
    final group = [first];
    final firstHasCaption = first.body != null && first.body!.trim().isNotEmpty;
    if (isAlbumPhoto(first) && !firstHasCaption) {
      var j = i + 1;
      while (j < newestFirst.length) {
        final newer = newestFirst[j - 1], older = newestFirst[j];
        if (!isAlbumPhoto(older)) break;
        final gap = newer.createdAt.difference(older.createdAt).abs();
        final a = newer.createdAt.toLocal(), b = older.createdAt.toLocal();
        if (gap > albumGap || a.day != b.day || a.month != b.month || a.year != b.year || _tagKey(newer) != _tagKey(older)) break;
        group.add(older);
        j++;
        if (older.body != null && older.body!.trim().isNotEmpty) break;
      }
    }
    rows.add(group);
    i += group.length;
  }
  return rows;
}

/// A WhatsApp-style grid bubble. Tap a photo to open it full screen and swipe through the album;
/// long-press a photo for its actions.
class AlbumCard extends StatelessWidget {
  const AlbumCard({super.key, required this.newestFirst, required this.onItemActions, this.pending = false, this.error});
  final List<Item> newestFirst;
  final void Function(Item item) onItemActions;
  final bool pending;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final meta = TextStyle(fontSize: 12, color: c.onSurfaceVariant);
    final items = newestFirst.reversed.toList(); // in the order they were sent
    final files = [for (final i in items) i.files.first];
    final caption = items.map((i) => i.body?.trim() ?? '').firstWhere((b) => b.isNotEmpty, orElse: () => '');
    final width = MediaQuery.sizeOf(context).width * 0.72;
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: width,
        child: Card(
          shape: (Theme.of(context).cardTheme.shape as RoundedRectangleBorder).copyWith(side: BorderSide(color: error != null ? c.error : c.outlineVariant)),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(10), child: _grid(context, items, files)),
                if (caption.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(8, 6, 8, 0), child: Text(caption)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  child: Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${items.length} photos', style: meta),
                      for (final t in items.first.tags) Text('#${t.name}', style: TextStyle(fontSize: 12, color: c.primary)),
                      if (error != null)
                        Text('Not saved: $error', style: meta.copyWith(color: c.error))
                      else if (pending)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.schedule, size: 13, color: c.onSurfaceVariant),
                            const SizedBox(width: 3),
                            Text('Waiting to sync', style: meta),
                          ],
                        ),
                      Text(DateFormat.jm().format(items.last.createdAt.toLocal()), style: meta),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 2 → side by side; 3 → one wide on top, two below; 4+ → 2×2 with "+N" on the last tile.
  Widget _grid(BuildContext context, List<Item> items, List<FileMeta> files) {
    const gap = 3.0;
    Widget tile(int index, {double aspect = 1, int more = 0}) => AspectRatio(
      aspectRatio: aspect,
      child: Semantics(
        button: true,
        label: 'Photo ${index + 1} of ${files.length}',
        child: GestureDetector(
          onTap: () => showImageViewer(context, files, initial: index),
          onLongPress: () => onItemActions(items[index]),
          child: Stack(
            fit: StackFit.expand,
            children: [
              FileImageView(file: files[index], fit: BoxFit.cover),
              if (more > 0)
                Container(
                  color: Colors.black54,
                  alignment: Alignment.center,
                  child: Text(
                    '+$more',
                    style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    Widget row(List<Widget> children) => Row(
      children: [
        for (var k = 0; k < children.length; k++) ...[if (k > 0) const SizedBox(width: gap), Expanded(child: children[k])],
      ],
    );
    final n = files.length;
    if (n == 2) return row([tile(0), tile(1)]);
    if (n == 3) {
      return Column(
        children: [
          tile(0, aspect: 2),
          const SizedBox(height: gap),
          row([tile(1), tile(2)]),
        ],
      );
    }
    return Column(
      children: [
        row([tile(0), tile(1)]),
        const SizedBox(height: gap),
        row([tile(2), tile(3, more: n - 4)]),
      ],
    );
  }
}
