import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../sync_engine.dart';
import 'feed_screen.dart';

/// Smart views, pinned/starred/archive/trash, collections and tags.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, required this.engine});
  final SyncEngine engine;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  List<Collection>? _collections;
  List<Tag>? _tags;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([widget.engine.api.collections(), widget.engine.api.tags()]);
      if (!mounted) return;
      setState(() {
        _collections = r[0] as List<Collection>;
        _tags = r[1] as List<Tag>;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.isOffline ? 'Collections and tags need a connection.' : e.message);
    }
  }

  void _open(FeedView v) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FeedScreen(engine: widget.engine, view: v))).then((_) => _load());

  Future<void> _newCollection() async {
    final name = TextEditingController();
    final n = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New collection'),
        content: TextField(controller: name, autofocus: true, decoration: const InputDecoration(hintText: 'e.g. Goa trip')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, name.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    if (n == null || n.isEmpty) return;
    try {
      await widget.engine.api.createCollection(n);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.code == 'conflict' ? 'That name exists' : e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
          child: Text(t.toUpperCase(), style: TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: c.onSurfaceVariant)),
        );
    final icons = {
      ItemType.note: Icons.notes,
      ItemType.link: Icons.link,
      ItemType.image: Icons.image_outlined,
      ItemType.file: Icons.description_outlined,
      ItemType.location: Icons.place_outlined,
      ItemType.voice: Icons.mic_none,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Browse'), actions: [IconButton(tooltip: 'New collection', onPressed: _newCollection, icon: const Icon(Icons.create_new_folder_outlined))]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            header('Smart views'),
            for (final t in ItemType.values) ListTile(leading: Icon(icons[t]), title: Text(t.label), onTap: () => _open(TypeView(t))),
            header('Quick'),
            ListTile(leading: const Icon(Icons.push_pin_outlined), title: const Text('Pinned'), onTap: () => _open(const FlagView('pinned'))),
            ListTile(leading: const Icon(Icons.star_border), title: const Text('Starred'), onTap: () => _open(const FlagView('starred'))),
            ListTile(leading: const Icon(Icons.archive_outlined), title: const Text('Archive'), onTap: () => _open(const FlagView('archived'))),
            ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Trash'), onTap: () => _open(const FlagView('trash'))),
            header('Collections'),
            if (_error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(_error!, style: TextStyle(color: c.onSurfaceVariant))),
            if (_collections != null && _collections!.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('No collections yet. Tap the folder icon to add one.')),
            for (final col in _collections ?? const <Collection>[])
              ListTile(leading: const Icon(Icons.folder_outlined), title: Text(col.name), trailing: Text('${col.itemCount}'), onTap: () => _open(CollectionView(col.id, col.name))),
            header('Tags'),
            if (_tags != null && _tags!.isEmpty) const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('No tags yet. Add tags from an item.')),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final t in _tags ?? const <Tag>[]) ActionChip(label: Text('#${t.name} · ${t.itemCount}'), onPressed: () => _open(TagView(t.id, t.name)))],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
