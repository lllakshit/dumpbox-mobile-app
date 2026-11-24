import 'package:flutter/material.dart';

import '../../api.dart';
import '../planner_engine.dart';
import '../planner_models.dart';
import '../recurrence.dart';
import 'calendar_screen.dart';
import 'entry_editor.dart';
import 'planner_widgets.dart';

/// Shows `all`, `starred`, `today`, `upcoming` or `list:ID`.
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key, required this.engine});
  final PlannerEngine engine;

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  String? _pick;
  String _sort = 'order';
  bool _showDone = false;
  final Set<String> _open = {};

  PlannerEngine get engine => widget.engine;

  String get pick => _pick ?? (engine.defaultListId('task') != null ? 'list:${engine.defaultListId('task')}' : 'all');

  String? _due(Entry t) => t.startDate ?? (t.startAt != null ? toWall(t.startAt!).date : null);

  bool _matches(String p, Entry t) {
    final today = todayLocal();
    if (p == 'all') return true;
    if (p == 'starred') return t.starred;
    if (p == 'today') {
      final d = _due(t);
      return d != null && d.compareTo(today) <= 0;
    }
    if (p == 'upcoming') {
      final d = _due(t);
      return d != null && d.compareTo(today) > 0 && d.compareTo(addDays(today, 7)) <= 0;
    }
    return t.listId == p.substring(5);
  }

  String _label(String p) => switch (p) {
        'all' => 'All tasks',
        'starred' => 'Starred',
        'today' => 'Today & overdue',
        'upcoming' => 'Next 7 days',
        _ => engine.listById(p.substring(5))?.name ?? 'Tasks',
      };

  int _sorter(Entry a, Entry b) {
    if (_sort == 'title') return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    if (_sort == 'date') {
      String k(Entry e) => e.startAt?.toIso8601String() ?? (e.startDate != null ? '${e.startDate}T99' : '9999');
      final c = k(a).compareTo(k(b));
      return c != 0 ? c : a.position.compareTo(b.position);
    }
    final c = a.position.compareTo(b.position);
    return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
  }

  Future<void> _toggle(Entry t) async {
    await engine.toggleDone(t);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(t.isDone ? 'Marked not done' : (t.repeats ? 'Done. Next one scheduled.' : 'Done')),
      action: SnackBarAction(label: 'Undo', onPressed: () => engine.update(engine.byId(t.id) ?? t, {'completed': t.isDone})),
    ));
  }

  Future<void> _listMenu() async {
    final listId = pick.startsWith('list:') ? pick.substring(5) : null;
    final l = engine.listById(listId);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('Sort by', style: TextStyle(fontWeight: FontWeight.w600))),
          for (final s in const [('order', 'My order'), ('date', 'Date'), ('title', 'Title')])
            ListTile(title: Text(s.$2), trailing: _sort == s.$1 ? const Icon(Icons.check) : null, onTap: () => Navigator.pop(c, 'sort:${s.$1}')),
          const Divider(),
          ListTile(leading: const Icon(Icons.add), title: const Text('New list'), onTap: () => Navigator.pop(c, 'new')),
          if (l != null) ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Rename list'), onTap: () => Navigator.pop(c, 'rename')),
          if (l != null && !l.isDefault) ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Delete list'), onTap: () => Navigator.pop(c, 'delete')),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (action.startsWith('sort:')) {
        setState(() => _sort = action.substring(5));
      } else if (action == 'new') {
        final name = await askListName(context, 'New list');
        if (name != null) {
          final made = await engine.createList('tasks', name);
          setState(() => _pick = 'list:${made.id}');
        }
      } else if (action == 'rename' && l != null) {
        final name = await askListName(context, 'Rename list', l.name);
        if (name != null) await engine.updateList(l, name: name);
      } else if (action == 'delete' && l != null) {
        final n = engine.entries.where((t) => t.listId == l.id).length;
        if (!mounted) return;
        final ok = await confirm(context, 'Delete “${l.name}”?', '$n tasks in it go to the bin.', 'Delete');
        if (ok) {
          await engine.deleteList(l);
          setState(() => _pick = null);
        }
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.isOffline ? 'Lists need a connection. Try again online.' : e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        tooltip: 'New task',
        onPressed: () => openEntryEditor(context, engine, draft: {'kind': 'task', 'list_id': pick.startsWith('list:') ? pick.substring(5) : null}),
        child: const Icon(Icons.add_task),
      ),
      body: ListenableBuilder(
        listenable: engine,
        builder: (context, _) {
          final tasks = engine.entries.where((e) => e.isTask).toList();
          final kids = <String, List<Entry>>{};
          for (final t in tasks) {
            if (t.parentId != null) (kids[t.parentId!] ??= []).add(t);
          }
          for (final v in kids.values) {
            v.sort((a, b) => a.position.compareTo(b.position));
          }
          final top = tasks.where((t) => t.parentId == null && _matches(pick, t)).toList();
          final open = top.where((t) => !t.isDone).toList()..sort(_sorter);
          final done = top.where((t) => t.isDone).toList()..sort((a, b) => (b.completedAt ?? b.updatedAt).compareTo(a.completedAt ?? a.updatedAt));
          final picks = ['all', 'today', 'upcoming', 'starred', for (final l in engine.taskLists) 'list:${l.id}'];
          return Column(children: [
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: [
                  for (final p in picks)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text('${_label(p)} ${tasks.where((t) => t.parentId == null && !t.isDone && _matches(p, t)).length}'),
                        selected: pick == p,
                        avatar: p.startsWith('list:') ? ColorDot(hex: engine.listById(p.substring(5))?.color ?? '#3a5bd9') : null,
                        onSelected: (_) => setState(() => _pick = p),
                      ),
                    ),
                  ActionChip(avatar: const Icon(Icons.more_horiz, size: 18), label: const Text('List'), onPressed: _listMenu),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: QuickAddField(
                engine: engine,
                kind: 'task',
                listId: pick.startsWith('list:') ? pick.substring(5) : null,
                day: pick == 'today' ? todayLocal() : null,
              ),
            ),
            Divider(height: 1, color: c.outlineVariant),
            Expanded(
              child: RefreshIndicator(
                onRefresh: engine.sync,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 96),
                  children: [
                    if (open.isEmpty && done.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'No tasks here. Type one above — dates, times, “every monday” and “remind me 10 min before” are understood.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.onSurfaceVariant),
                        ),
                      ),
                    for (final t in open) ..._taskTile(context, t, kids[t.id] ?? const []),
                    if (done.isNotEmpty)
                      ListTile(
                        title: Text('Completed (${done.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
                        trailing: Icon(_showDone ? Icons.expand_less : Icons.expand_more),
                        onTap: () => setState(() => _showDone = !_showDone),
                      ),
                    if (_showDone) for (final t in done) ..._taskTile(context, t, kids[t.id] ?? const []),
                  ],
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }

  List<Widget> _taskTile(BuildContext context, Entry t, List<Entry> children, {bool child = false}) {
    final c = Theme.of(context).colorScheme;
    final color = hexColor(engine.colorOf(t));
    final due = dueLabel(t);
    final expanded = _open.contains(t.id);
    final list = engine.listById(t.listId);
    return [
      Dismissible(
        key: ValueKey('task-${t.id}'),
        background: Container(alignment: Alignment.centerLeft, padding: const EdgeInsets.only(left: 20), color: Colors.green.withValues(alpha: 0.2), child: const Icon(Icons.check)),
        secondaryBackground: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), color: c.error.withValues(alpha: 0.2), child: const Icon(Icons.delete_outline)),
        confirmDismiss: (dir) async {
          if (dir == DismissDirection.startToEnd) {
            await _toggle(t);
          } else {
            await engine.remove(t);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Task deleted'), action: SnackBarAction(label: 'Undo', onPressed: () => engine.restore(engine.byId(t.id) ?? t))));
            }
          }
          return false;
        },
        child: InkWell(
          onTap: () => openEntryEditor(context, engine, entry: t),
          child: Padding(
            padding: EdgeInsets.fromLTRB(child ? 40 : 4, 6, 4, 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _toggle(t),
                icon: Icon(t.isDone ? Icons.check_circle : Icons.radio_button_unchecked, color: color),
                tooltip: t.isDone ? 'Mark not done' : 'Mark done',
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.title, style: TextStyle(decoration: t.isDone ? TextDecoration.lineThrough : null, color: t.isDone ? c.onSurfaceVariant : null)),
                    if (t.notes != null && t.notes!.isNotEmpty) Text(t.notes!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.onSurfaceVariant)),
                    if (engine.failureFor(t.id) != null) Text(engine.failureFor(t.id)!, style: TextStyle(fontSize: 12, color: c.error)),
                    Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (due.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: isOverdue(t) ? c.error : c.outlineVariant)),
                          child: Text(due, style: TextStyle(fontSize: 12, color: isOverdue(t) ? c.error : c.onSurfaceVariant)),
                        ),
                      if (t.repeats) Icon(Icons.repeat, size: 14, color: c.onSurfaceVariant),
                      if (t.reminders.isNotEmpty && t.hasDate) Icon(Icons.notifications_none, size: 14, color: c.onSurfaceVariant),
                      if (!pick.startsWith('list:') && list != null) Text(list.name, style: TextStyle(fontSize: 12, color: c.onSurfaceVariant)),
                      if (children.isNotEmpty)
                        InkWell(
                          onTap: () => setState(() => expanded ? _open.remove(t.id) : _open.add(t.id)),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('${children.where((k) => k.isDone).length}/${children.length} subtasks ${expanded ? '▾' : '▸'}', style: TextStyle(fontSize: 12, color: c.primary)),
                          ),
                        ),
                    ]),
                  ]),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: t.starred ? 'Unstar' : 'Star',
                onPressed: () => engine.update(t, {'starred': !t.starred}),
                icon: Icon(t.starred ? Icons.star : Icons.star_border, color: t.starred ? Colors.amber : c.onSurfaceVariant),
              ),
              if (!child)
                PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (v) {
                    if (v == 'sub') setState(() => _open.add(t.id));
                    if (v == 'up' || v == 'down') _move(t, v == 'up' ? -1 : 1);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'sub', child: Text('Add subtask')),
                    if (_sort == 'order' && !t.isDone) const PopupMenuItem(value: 'up', child: Text('Move up')),
                    if (_sort == 'order' && !t.isDone) const PopupMenuItem(value: 'down', child: Text('Move down')),
                  ],
                ),
            ]),
          ),
        ),
      ),
      if (!child && expanded) ...[
        for (final k in children) ..._taskTile(context, k, const [], child: true),
        Padding(
          padding: const EdgeInsets.fromLTRB(56, 0, 8, 8),
          child: QuickAddField(engine: engine, kind: 'task', listId: t.listId, parentId: t.id, hint: 'Add a subtask'),
        ),
      ],
    ];
  }

  void _move(Entry t, int dir) {
    final list = engine.entries.where((e) => e.isTask && e.parentId == null && !e.isDone && _matches(pick, e)).toList()..sort(_sorter);
    final i = list.indexWhere((x) => x.id == t.id);
    final j = i + dir;
    if (i < 0 || j < 0 || j >= list.length) return;
    final other = list[j];
    final next = j + dir >= 0 && j + dir < list.length ? list[j + dir] : null;
    final pos = next != null ? (other.position + next.position) / 2 : other.position + dir;
    engine.update(t, {'position': pos});
  }
}
