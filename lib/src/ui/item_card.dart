import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import 'file_urls.dart';

/// One item as a chat bubble on the right. Tap for actions.
class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.item, this.pending = false, this.error, this.onTap, this.highlight});
  final Item item;
  final bool pending;
  final String? error;
  final VoidCallback? onTap;
  final Widget? highlight;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final meta = TextStyle(fontSize: 12, color: c.onSurfaceVariant);
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.88),
        child: Card(
          shape: (Theme.of(context).cardTheme.shape as RoundedRectangleBorder).copyWith(
            side: BorderSide(color: error != null ? c.error : c.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.title != null && item.type != ItemType.link)
                    Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(item.title!, style: const TextStyle(fontWeight: FontWeight.w600))),
                  _Body(item: item),
                  if (highlight != null) ...[const Divider(height: 16), highlight!],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final t in item.tags)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
                          child: Text('#${t.name}', style: TextStyle(fontSize: 12, color: c.primary)),
                        ),
                      if (item.pinned) Icon(Icons.push_pin, size: 14, color: c.onSurfaceVariant, semanticLabel: 'Pinned'),
                      if (item.starred) const Icon(Icons.star, size: 14, color: Color(0xFFE0A100), semanticLabel: 'Starred'),
                      if (error != null)
                        Text('Not saved: $error', style: meta.copyWith(color: c.error))
                      else if (pending)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.schedule, size: 13, color: c.onSurfaceVariant),
                          const SizedBox(width: 3),
                          Text('Waiting to sync', style: meta),
                        ]),
                      Text(DateFormat.jm().format(item.createdAt.toLocal()), style: meta),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.item});
  final Item item;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    switch (item.type) {
      case ItemType.note:
        return SelectableText(item.body ?? '', style: const TextStyle(height: 1.4));
      case ItemType.link:
        final l = item.link;
        return InkWell(
          onTap: () => launchUrl(Uri.parse(item.url!), mode: LaunchMode.externalApplication),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: c.outlineVariant)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (l?.imageUrl != null)
                  Image.network(l!.imageUrl!, height: 150, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l?.site ?? Uri.tryParse(item.url ?? '')?.host ?? '', style: TextStyle(fontSize: 12, color: c.onSurfaceVariant)),
                      Text(l?.title ?? item.url ?? '', style: const TextStyle(fontWeight: FontWeight.w500)),
                      if (l?.description != null)
                        Text(l!.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      case ItemType.location:
        final loc = item.location!;
        return InkWell(
          onTap: () => launchUrl(
            Uri.parse('https://www.openstreetmap.org/?mlat=${loc.latitude}&mlon=${loc.longitude}#map=17/${loc.latitude}/${loc.longitude}'),
            mode: LaunchMode.externalApplication,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.place, color: c.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(loc.label ?? 'Dropped pin', style: const TextStyle(fontWeight: FontWeight.w500)),
                    Text('${loc.latitude.toStringAsFixed(5)}, ${loc.longitude.toStringAsFixed(5)} · Open map', style: TextStyle(fontSize: 12, color: c.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        );
      case ItemType.image:
      case ItemType.file:
      case ItemType.voice:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.body != null && item.body!.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(item.body!)),
            for (final f in item.files) _FileView(file: f),
            if (item.files.isEmpty) Text('Uploading…', style: TextStyle(color: c.onSurfaceVariant)),
          ],
        );
    }
  }
}

class _FileView extends StatelessWidget {
  const _FileView({required this.file});
  final FileMeta file;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    if (file.isImage) {
      final ratio = (file.width != null && file.height != null && file.height! > 0) ? file.width! / file.height! : 4 / 3;
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: AspectRatio(
            aspectRatio: ratio,
            child: file.localPath != null
                ? Image.file(File(file.localPath!), fit: BoxFit.cover)
                : FutureBuilder(
                    future: FileUrls.get(file.id),
                    builder: (context, snap) => snap.hasData
                        ? Image.network(snap.data!.view, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined))
                        : Container(color: c.surfaceContainerHighest),
                  ),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: c.outlineVariant)),
      child: Row(
        children: [
          Icon(file.isAudio ? Icons.mic_none : Icons.insert_drive_file_outlined, color: c.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(_size(file.sizeBytes), style: TextStyle(fontSize: 12, color: c.onSurfaceVariant)),
              ],
            ),
          ),
          if (file.localPath == null)
            IconButton(
              tooltip: 'Open',
              icon: const Icon(Icons.open_in_new),
              onPressed: () async {
                final u = await FileUrls.get(file.id);
                await launchUrl(Uri.parse(u.view), mode: LaunchMode.externalApplication);
              },
            ),
        ],
      ),
    );
  }

  static String _size(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(0)} KB';
    return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
