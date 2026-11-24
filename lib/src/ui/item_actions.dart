import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../models.dart';
import '../planner/ui/planner_screen.dart';
import '../sync_engine.dart';

/// Bottom sheet of actions for one item.
Future<void> showItemActions(BuildContext context, SyncEngine engine, Item item) async {
  final messenger = ScaffoldMessenger.of(context);
  void snack(String m) => messenger.showSnackBar(SnackBar(content: Text(m)));
  final planner = PlannerScope.maybeOf(context);

  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      Widget tile(String key, IconData icon, String label, {bool danger = false}) => ListTile(
            leading: Icon(icon, color: danger ? Theme.of(context).colorScheme.error : null),
            title: Text(label, style: danger ? TextStyle(color: Theme.of(context).colorScheme.error) : null),
            onTap: () => Navigator.pop(context, key),
          );
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: item.isTrashed
                ? [tile('restore', Icons.restore, 'Restore'), tile('forever', Icons.delete_forever, 'Delete forever', danger: true)]
                : [
                    tile('star', item.starred ? Icons.star : Icons.star_border, item.starred ? 'Unstar' : 'Star'),
                    tile('pin', Icons.push_pin_outlined, item.pinned ? 'Unpin' : 'Pin'),
                    tile('edit', Icons.edit_outlined, item.type == ItemType.note ? 'Edit' : 'Edit caption'),
                    if (!item.isLocalOnly) ...[
                      tile('tags', Icons.sell_outlined, 'Tags'),
                      tile('collections', Icons.folder_outlined, 'Collections'),
                      tile('share', Icons.ios_share, 'Share link'),
                    ],
                    tile('copy', Icons.copy, 'Copy text'),
                    if (planner != null) ...[
                      tile('event', Icons.event, 'Make event…'),
                      tile('task', Icons.add_task, 'Make task…'),
                    ],
                    tile('archive', Icons.archive_outlined, item.isArchived ? 'Unarchive' : 'Archive'),
                    tile('trash', Icons.delete_outline, 'Move to trash', danger: true),
                  ],
          ),
        ),
      );
    },
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case 'star':
      await engine.setStarred(item, !item.starred);
    case 'pin':
      await engine.setPinned(item, !item.pinned);
    case 'archive':
      await engine.setArchived(item, !item.isArchived);
      snack(item.isArchived ? 'Moved back to the feed' : 'Archived. Still searchable.');
    case 'trash':
      await engine.moveToTrash(item);
      messenger.showSnackBar(SnackBar(
        content: const Text('Moved to trash'),
        action: item.isLocalOnly ? null : SnackBarAction(label: 'Undo', onPressed: () => engine.restore(engine.byId(item.id) ?? item)),
      ));
    case 'restore':
      await engine.restore(item);
    case 'forever':
      final ok = await _confirm(context, 'Delete forever?', 'This item and its files will be removed for good.', 'Delete');
      if (ok) await engine.deleteForever(item);
    case 'copy':
      final text = [item.title, item.body, item.url, if (item.location != null) '${item.location!.latitude},${item.location!.longitude}'].whereType<String>().join('\n');
      await Clipboard.setData(ClipboardData(text: text));
      snack('Copied');
    case 'edit':
      if (!context.mounted) return;
      final r = await _editDialog(context, item);
      if (r != null) await engine.edit(item, title: r.$1, body: r.$2);
    case 'tags':
      if (!context.mounted) return;
      final names = await _tagsDialog(context, item);
      if (names != null) await engine.setTags(item, names);
    case 'collections':
      if (!context.mounted) return;
      await _collectionsDialog(context, engine, item);
    case 'share':
      if (!context.mounted) return;
      await _share(context, engine, item);
    case 'event':
    case 'task':
      if (!context.mounted || planner == null) return;
      await makeFromItem(context, planner, item, action);
  }
}

Future<bool> _confirm(BuildContext context, String title, String text, String label) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(label)),
        ],
      ),
    ) ??
    false;

Future<(String?, String?)?> _editDialog(BuildContext context, Item item) {
  final title = TextEditingController(text: item.title);
  final body = TextEditingController(text: item.body);
  return showDialog<(String?, String?)>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(item.type == ItemType.note ? 'Edit note' : 'Edit caption'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Title (optional)')),
          const SizedBox(height: 10),
          TextField(controller: body, minLines: 4, maxLines: 10, decoration: const InputDecoration(labelText: 'Text')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (item.type == ItemType.note && body.text.trim().isEmpty && title.text.trim().isEmpty) return;
            Navigator.pop(c, (title.text.trim().isEmpty ? null : title.text.trim(), body.text.isEmpty ? null : body.text));
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

Future<List<String>?> _tagsDialog(BuildContext context, Item item) {
  final input = TextEditingController(text: item.tags.map((t) => t.name).join(', '));
  return showDialog<List<String>>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Tags'),
      content: TextField(controller: input, autofocus: true, decoration: const InputDecoration(hintText: 'bills, travel, ideas', helperText: 'Separate tags with commas')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(
            c,
            input.text.split(',').map((t) => t.trim().replaceFirst(RegExp(r'^#'), '')).where((t) => t.isNotEmpty).take(20).toList(),
          ),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

Future<void> _collectionsDialog(BuildContext context, SyncEngine engine, Item item) async {
  List<Collection> all;
  try {
    all = await engine.api.collections();
  } on ApiException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.isOffline ? 'Collections need a connection' : e.message)));
    return;
  }
  if (!context.mounted) return;
  final chosen = {...item.collectionIds};
  final newName = TextEditingController();
  final result = await showDialog<Set<String>>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: const Text('Collections'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final col in all)
                CheckboxListTile(
                  value: chosen.contains(col.id),
                  title: Text(col.name),
                  onChanged: (v) => setState(() => v == true ? chosen.add(col.id) : chosen.remove(col.id)),
                ),
              Row(children: [
                Expanded(child: TextField(controller: newName, decoration: const InputDecoration(hintText: 'New collection'))),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () async {
                    final n = newName.text.trim();
                    if (n.isEmpty) return;
                    try {
                      final created = await engine.api.createCollection(n);
                      setState(() {
                        all = [...all, created];
                        chosen.add(created.id);
                        newName.clear();
                      });
                    } on ApiException catch (e) {
                      if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(e.code == 'conflict' ? 'That name exists' : e.message)));
                    }
                  },
                ),
              ]),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, chosen), child: const Text('Save')),
        ],
      ),
    ),
  );
  if (result != null) await engine.setCollections(item, result.toList());
}

Future<void> _share(BuildContext context, SyncEngine engine, Item item) async {
  final days = await showDialog<int?>(
    context: context,
    builder: (c) => SimpleDialog(
      title: const Text('Link stops working after'),
      children: [
        for (final d in const [1, 7, 30]) SimpleDialogOption(onPressed: () => Navigator.pop(c, d), child: Text('$d ${d == 1 ? 'day' : 'days'}')),
        SimpleDialogOption(onPressed: () => Navigator.pop(c, -1), child: const Text('Never (until you turn it off)')),
      ],
    ),
  );
  if (days == null) return;
  try {
    final url = await engine.api.createShare(itemId: item.id, expiresInDays: days > 0 ? days : null);
    await SharePlus.instance.share(ShareParams(text: url, subject: 'Shared from DumpBox'));
  } on ApiException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.isOffline ? 'Sharing needs a connection' : e.message)));
  }
}
