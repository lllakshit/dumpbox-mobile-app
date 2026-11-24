import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api.dart';
import '../planner_engine.dart';
import '../planner_models.dart';
import '../recurrence.dart';
import 'entry_editor.dart';

const entryColors = ['#3a5bd9', '#1e8a52', '#c0392b', '#d97706', '#8e44ad', '#0e7490', '#db2777', '#4b5563'];

Color hexColor(String hex) {
  final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0x3a5bd9;
  return Color(0xFF000000 | v);
}

class ColorDot extends StatelessWidget {
  const ColorDot({super.key, required this.hex, this.size = 12});
  final String hex;
  final double size;
  @override
  Widget build(BuildContext context) => Container(width: size, height: size, decoration: BoxDecoration(color: hexColor(hex), shape: BoxShape.circle));
}

Future<bool> confirm(BuildContext context, String title, String? text, String action) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: text == null ? null : Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
        ],
      ),
    ) ??
    false;

String fmtTime(String t) => DateFormat.jm().format(DateTime(2000, 1, 1, minutesOf(t) ~/ 60, minutesOf(t) % 60));

String dueLabel(Entry e) {
  final today = todayLocal();
  String? d;
  String? t;
  if (e.startDate != null) d = e.startDate;
  if (e.startAt != null) {
    final w = toWall(e.startAt!);
    d = w.date;
    t = w.time;
  }
  if (d == null) return '';
  final day = d == today
      ? 'Today'
      : d == addDays(today, 1)
          ? 'Tomorrow'
          : d == addDays(today, -1)
              ? 'Yesterday'
              : DateFormat(parseDate(d).year == parseDate(today).year ? 'EEE d MMM' : 'd MMM yyyy').format(parseDate(d));
  return t == null ? day : '$day, ${fmtTime(t)}';
}

bool isOverdue(Entry e) {
  if (e.isDone) return false;
  if (e.startAt != null) return e.startAt!.isBefore(DateTime.now().toUtc());
  if (e.startDate != null) return e.startDate!.compareTo(todayLocal()) < 0;
  return false;
}

/// Quick add: types like "Dentist tomorrow 5pm remind me 1h before". Read by the server's parser when online;
/// offline it is saved with just the title (and the chosen day for events).
class QuickAddField extends StatefulWidget {
  const QuickAddField({super.key, required this.engine, required this.kind, this.listId, this.parentId, this.day, this.hint});
  final PlannerEngine engine;
  final String kind;
  final String? listId;
  final String? parentId;
  final String? day;
  final String? hint;

  @override
  State<QuickAddField> createState() => _QuickAddFieldState();
}

class _QuickAddFieldState extends State<QuickAddField> {
  final _c = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _c.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final body = await quickBody(widget.engine, text, widget.kind, day: widget.day, listId: widget.listId);
    if (widget.parentId != null) body['parent_id'] = widget.parentId;
    final e = await widget.engine.create(body);
    _c.clear();
    if (mounted) setState(() => _busy = false);
    final when = dueLabel(e);
    messenger.showSnackBar(SnackBar(
      content: Text('Added ${e.isEvent ? 'event' : 'task'}: ${e.title}${when.isEmpty ? '' : ' · $when'}${e.repeats ? ' · repeats' : ''}'),
      action: SnackBarAction(
        label: 'Edit',
        onPressed: () {
          if (context.mounted) openEntryEditor(context, widget.engine, entry: widget.engine.byId(e.id) ?? e);
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      textInputAction: TextInputAction.done,
      textCapitalization: TextCapitalization.sentences,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        hintText: widget.hint ?? (widget.kind == 'task' ? 'Add a task: “Pay rent on the 1st every month”' : 'Add: “Lunch with Rahul fri 1pm”'),
        isDense: true,
        suffixIcon: _busy
            ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
            : IconButton(icon: const Icon(Icons.add_circle), tooltip: 'Add', onPressed: _submit),
      ),
    );
  }
}

/// Text → request body. Online: the server reads dates, times, repeats, reminders, places and #lists.
Future<Map<String, dynamic>> quickBody(PlannerEngine engine, String text, String kind, {String? day, String? listId}) async {
  Map<String, dynamic> body;
  try {
    final r = await engine.api.request('POST', '/v1/planner/parse', body: {
      'text': text,
      'time_zone': localZoneName,
      'kind': kind,
      'week_start': engine.prefs.weekStart == 0 || engine.prefs.weekStart == 6 ? engine.prefs.weekStart : 1,
      'default_event_minutes': engine.prefs.defaultEventMinutes,
    });
    final e = Map<String, dynamic>.from(r['entry'] as Map);
    final listName = e.remove('list_name') as String?;
    final hasDate = e['start_at'] != null || e['start_date'] != null;
    body = {
      ...e,
      'reminders': e['reminders'] ?? (hasDate ? (e['kind'] == 'event' ? engine.prefs.defaultEventReminders : engine.prefs.defaultTaskReminders) : <int>[]),
    };
    if (listName != null) {
      final want = e['kind'] == 'event' ? 'calendar' : 'tasks';
      PlannerList? match;
      for (final l in engine.lists) {
        if (l.kind == want && l.name.toLowerCase() == listName.toLowerCase()) match = l;
      }
      if (match != null) {
        body['list_id'] = match.id;
      } else {
        body['title'] = '${e['title']} #$listName';
      }
    }
  } on ApiException {
    // Offline or the server refused: keep the text as the title.
    body = {'kind': kind, 'title': text};
  }
  if (body['kind'] == kind && listId != null && body['list_id'] == null) body['list_id'] = listId;
  if (body['kind'] == 'event' && body['start_at'] == null && body['start_date'] == null) {
    body['all_day'] = true;
    body['start_date'] = day ?? todayLocal();
    body['reminders'] = body['reminders'] ?? engine.prefs.defaultEventReminders;
  }
  return body;
}

/// One event or task line in a list (agenda, day list).
class OccurrenceTile extends StatelessWidget {
  const OccurrenceTile({super.key, required this.engine, required this.o, this.showDate = false});
  final PlannerEngine engine;
  final Occurrence o;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final e = o.entry;
    final color = hexColor(engine.colorOf(e));
    final time = o.allDay || o.startTime == null
        ? 'All day'
        : '${fmtTime(o.startTime!)}${e.isEvent && o.endTime != null && e.endAt != null ? ' – ${fmtTime(o.endTime!)}' : ''}';
    return InkWell(
      onTap: () => openEntryEditor(context, engine, entry: e, occurrence: o.recurring ? OccurrenceRef.of(o) : null),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(children: [
          if (e.isTask)
            InkResponse(
              onTap: () => engine.toggleDone(e),
              radius: 20,
              child: Icon(e.isDone ? Icons.check_circle : Icons.radio_button_unchecked, color: color, semanticLabel: e.isDone ? 'Mark not done' : 'Mark done'),
            )
          else
            Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle))),
          const SizedBox(width: 10),
          SizedBox(width: 92, child: Text(time, style: TextStyle(fontSize: 12, color: c.onSurfaceVariant))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                e.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(decoration: e.isDone ? TextDecoration.lineThrough : null, color: e.isDone ? c.onSurfaceVariant : null),
              ),
              if (e.location != null && e.location!.isNotEmpty) Text(e.location!, style: TextStyle(fontSize: 12, color: c.onSurfaceVariant)),
            ]),
          ),
          if (o.recurring) Icon(Icons.repeat, size: 16, color: c.onSurfaceVariant),
          if (e.reminders.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.notifications_none, size: 16, color: c.onSurfaceVariant)),
        ]),
      ),
    );
  }
}
