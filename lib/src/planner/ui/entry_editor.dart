import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../planner_engine.dart';
import '../planner_models.dart';
import '../recurrence.dart';
import 'planner_widgets.dart';

/// Which occurrence of a repeating event was opened.
class OccurrenceRef {
  const OccurrenceRef({required this.key, required this.startDate, required this.endDate, this.startTime, this.endTime});
  final String key;
  final String startDate;
  final String endDate;
  final String? startTime;
  final String? endTime;

  factory OccurrenceRef.of(Occurrence o) => OccurrenceRef(key: o.key, startDate: o.startDate, endDate: o.endDate, startTime: o.startTime, endTime: o.endTime);
}

/// Opens the editor. [entry] edits an existing one; otherwise [draft] (API-shaped fields) prefills a new one.
Future<void> openEntryEditor(BuildContext context, PlannerEngine engine, {Entry? entry, OccurrenceRef? occurrence, Map<String, dynamic>? draft}) =>
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => EntryEditor(engine: engine, entry: entry, occurrence: occurrence, draft: draft)));

class EntryEditor extends StatefulWidget {
  const EntryEditor({super.key, required this.engine, this.entry, this.occurrence, this.draft});
  final PlannerEngine engine;
  final Entry? entry;
  final OccurrenceRef? occurrence;
  final Map<String, dynamic>? draft;

  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();
  late String _kind;
  late bool _allDay;
  late bool _hasDate;
  late String _startDate;
  late String _startTime;
  late String _endDate;
  late String _endTime;
  String? _rrule;
  late List<int> _reminders;
  String? _listId;
  String? _color;
  bool _starred = false;
  bool _done = false;
  bool _busy = false;
  late final String _tz;

  PlannerEngine get engine => widget.engine;
  bool get _isNew => widget.entry == null;
  bool get _repeating => widget.entry?.repeats == true && widget.occurrence != null;

  @override
  void initState() {
    super.initState();
    final e = widget.entry ?? (widget.draft == null ? null : Entry.fromJson({'id': 'draft', 'kind': 'event', 'title': '', ...widget.draft!}));
    _kind = e?.kind ?? 'event';
    _tz = e?.timeZone ?? localZoneName;
    final loc = location(_tz) ?? localZone;
    final now = toWall(DateTime.now());
    _startDate = now.date;
    _startTime = timeFromMinutes(((minutesOf(now.time) ~/ 30) + 1) * 30);
    _endDate = _startDate;
    _endTime = timeFromMinutes(minutesOf(_startTime) + engine.prefs.defaultEventMinutes);
    _allDay = false;
    _hasDate = _kind == 'event' || (e?.hasDate ?? false);
    if (e?.startAt != null) {
      final s = toWall(e!.startAt!, loc);
      _startDate = s.date;
      _startTime = s.time;
      if (e.endAt != null) {
        final en = toWall(e.endAt!, loc);
        _endDate = en.date;
        _endTime = en.time;
      } else {
        _endDate = s.date;
        _endTime = timeFromMinutes(minutesOf(s.time) + (_kind == 'event' ? engine.prefs.defaultEventMinutes : 0));
      }
    } else if (e?.startDate != null) {
      _startDate = e!.startDate!;
      _endDate = e.endDate ?? e.startDate!;
      _allDay = true;
    } else if (_kind == 'task') {
      _allDay = true;
    }
    final o = widget.occurrence;
    if (o != null) {
      _startDate = o.startDate;
      _endDate = o.endDate;
      if (o.startTime != null) _startTime = o.startTime!;
      if (o.endTime != null) _endTime = o.endTime!;
    }
    if (_endDate.compareTo(_startDate) < 0) _endDate = _startDate;
    _title.text = e?.title ?? '';
    _location.text = e?.location ?? '';
    _notes.text = e?.notes ?? '';
    _rrule = e?.rrule;
    _reminders = List.of(widget.entry?.reminders ??
        (widget.draft?['reminders'] as List?)?.map((x) => (x as num).toInt()).toList() ??
        (_kind == 'event' ? engine.prefs.defaultEventReminders : (_hasDate ? engine.prefs.defaultTaskReminders : <int>[])));
    _listId = e?.listId ?? engine.defaultListId(_kind);
    _color = e?.color;
    _starred = e?.starred ?? false;
    _done = e?.isDone ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  Map<String, dynamic> _body() {
    final b = <String, dynamic>{
      'kind': _kind,
      'title': _title.text.trim(),
      'list_id': _listId,
      'location': _location.text.trim().isEmpty ? null : _location.text.trim(),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      'color': _color,
      'starred': _starred,
      'reminders': _hasDate ? (List.of(_reminders)..sort()) : <int>[],
      'rrule': _hasDate ? _rrule : null,
      'time_zone': _tz,
    };
    final loc = location(_tz) ?? localZone;
    if (!_hasDate) {
      b.addAll({'all_day': true, 'start_at': null, 'end_at': null, 'start_date': null, 'end_date': null});
    } else if (_allDay) {
      b.addAll({
        'all_day': true,
        'start_at': null,
        'end_at': null,
        'start_date': _startDate,
        'end_date': _kind == 'event' && _endDate.compareTo(_startDate) > 0 ? _endDate : null,
      });
    } else {
      final s = fromWall(_startDate, _startTime, loc);
      var en = fromWall(_endDate, _endTime, loc);
      if (en.isBefore(s)) en = s;
      b.addAll({
        'all_day': false,
        'start_date': null,
        'end_date': null,
        'start_at': s.toIso8601String(),
        'end_at': _kind == 'event' ? en.toIso8601String() : null,
      });
    }
    return b;
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return _snack('Add a title');
    if (_hasDate && !_allDay && _kind == 'event') {
      final loc = location(_tz) ?? localZone;
      if (fromWall(_endDate, _endTime, loc).isBefore(fromWall(_startDate, _startTime, loc))) return _snack('The end is before the start');
    }
    var mode = 'all';
    if (_repeating) {
      final m = await askScope(context, 'Save changes to');
      if (m == null) return;
      mode = m;
    }
    setState(() => _busy = true);
    final body = _body();
    final e = widget.entry;
    if (e == null) {
      await engine.create({
        ...body,
        if (widget.draft?['source_item_id'] != null) 'source_item_id': widget.draft!['source_item_id'],
        if (widget.draft?['parent_id'] != null) 'parent_id': widget.draft!['parent_id'],
      });
    } else if (mode == 'all') {
      final patch = {...body, if (_kind == 'task') 'completed': _done};
      final o = widget.occurrence;
      if (_repeating && o != null) {
        // "All events": shift the whole series by how far this occurrence moved.
        final loc = location(_tz) ?? localZone;
        if (_allDay && e.startDate != null) {
          final shift = diffDays(o.startDate, _startDate);
          final span = diffDays(_startDate, _endDate).clamp(0, 3650);
          final s = addDays(e.startDate!, shift);
          patch['start_date'] = s;
          patch['end_date'] = span > 0 ? addDays(s, span) : null;
        } else if (!_allDay && e.startAt != null && o.startTime != null) {
          final shift = fromWall(_startDate, _startTime, loc).difference(fromWall(o.startDate, o.startTime!, loc));
          final len = fromWall(_endDate, _endTime, loc).difference(fromWall(_startDate, _startTime, loc));
          final s = e.startAt!.add(shift);
          patch['start_at'] = s.toIso8601String();
          patch['end_at'] = _kind == 'event' ? s.add(len.isNegative ? Duration.zero : len).toIso8601String() : null;
        }
      }
      await engine.update(e, patch);
    } else if (mode == 'this') {
      await engine.create({...body, 'rrule': null});
      await engine.update(e, {'exdates': {...e.exdates, widget.occurrence!.key}.toList()});
    } else {
      final rule = parseRule(e.rrule);
      final occDate = widget.occurrence!.startDate;
      final nr = parseRule(_rrule);
      await engine.create({...body, 'rrule': nr == null ? null : (rule?.count != null ? nr.copyWith(clearCount: true).toString() : nr.toString())});
      final first = e.startDate ?? (e.startAt != null ? toWall(e.startAt!, location(_tz)).date : occDate);
      if (addDays(occDate, -1).compareTo(first) < 0) {
        await engine.remove(e);
      } else {
        await engine.update(e, {'rrule': endRuleBefore(e.rrule!, occDate)});
      }
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final e = widget.entry!;
    var mode = 'all';
    if (_repeating) {
      final m = await askScope(context, 'Delete');
      if (m == null) return;
      mode = m;
    } else {
      final ok = await confirm(context, 'Delete “${e.title}”?', e.isTask && engine.entries.any((c) => c.parentId == e.id) ? 'Its subtasks are deleted too.' : null, 'Delete');
      if (!ok) return;
    }
    if (mode == 'all') {
      await engine.remove(e);
    } else if (mode == 'this') {
      await engine.update(e, {'exdates': {...e.exdates, widget.occurrence!.key}.toList()});
    } else {
      final occDate = widget.occurrence!.startDate;
      final first = e.startDate ?? (e.startAt != null ? toWall(e.startAt!, location(_tz)).date : occDate);
      if (addDays(occDate, -1).compareTo(first) < 0) {
        await engine.remove(e);
      } else {
        await engine.update(e, {'rrule': endRuleBefore(e.rrule!, occDate)});
      }
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickDate(bool start) async {
    final cur = parseDate(start ? _startDate : _endDate);
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(cur.year, cur.month, cur.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    final s = makeDate(d.year, d.month, d.day);
    setState(() {
      if (start) {
        final span = diffDays(_startDate, _endDate);
        _startDate = s;
        _endDate = addDays(s, span < 0 ? 0 : span);
      } else {
        _endDate = s.compareTo(_startDate) < 0 ? _startDate : s;
      }
    });
  }

  Future<void> _pickTime(bool start) async {
    final cur = start ? _startTime : _endTime;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: minutesOf(cur) ~/ 60, minute: minutesOf(cur) % 60));
    if (t == null) return;
    final v = timeFromMinutes(t.hour * 60 + t.minute);
    setState(() {
      if (start) {
        // Moving the start moves the end with it.
        final len = diffDays(_startDate, _endDate) * 1440 + minutesOf(_endTime) - minutesOf(_startTime);
        _startTime = v;
        final endMin = minutesOf(v) + (len < 0 ? 0 : len);
        _endDate = addDays(_startDate, endMin ~/ 1440);
        _endTime = timeFromMinutes(endMin);
      } else {
        _endTime = v;
        if (_endDate == _startDate && minutesOf(v) <= minutesOf(_startTime)) _endDate = addDays(_startDate, 1);
      }
    });
  }

  String _fmtDate(String d) => DateFormat('EEE, d MMM yyyy').format(parseDate(d));
  String _fmtTime(String t) => DateFormat.jm().format(DateTime(2000, 1, 1, minutesOf(t) ~/ 60, minutesOf(t) % 60));

  Future<void> _pickRepeat() async {
    final presets = rulePresets(_startDate);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final p in presets)
              ListTile(
                title: Text(p.label),
                trailing: p.rrule == _rrule ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(c, p.rrule ?? ''),
              ),
            ListTile(leading: const Icon(Icons.tune), title: const Text('Custom…'), onTap: () => Navigator.pop(c, '__custom')),
          ]),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == '__custom') {
      final r = await showDialog<String>(context: context, builder: (_) => CustomRepeatDialog(start: _startDate, initial: _rrule));
      if (r != null) setState(() => _rrule = r);
    } else {
      setState(() => _rrule = choice.isEmpty ? null : choice);
    }
  }

  Future<void> _addReminder() async {
    final m = await pickReminder(context, have: _reminders, allDay: _allDay);
    if (m != null) setState(() => _reminders = ({..._reminders, m}.toList()..sort()));
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final lists = _kind == 'event' ? engine.calendars : engine.taskLists;
    if (_listId != null && !lists.any((l) => l.id == _listId)) _listId = engine.defaultListId(_kind);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => Navigator.pop(context)),
        title: Text(_isNew ? (_kind == 'event' ? 'New event' : 'New task') : (_kind == 'event' ? 'Edit event' : 'Edit task')),
        actions: [
          if (!_isNew) IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete', onPressed: _busy ? null : _delete),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'event', label: Text('Event'), icon: Icon(Icons.event)),
              ButtonSegment(value: 'task', label: Text('Task'), icon: Icon(Icons.check_circle_outline)),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() {
              _kind = s.first;
              _listId = engine.defaultListId(_kind);
              if (_kind == 'event') _hasDate = true;
              if (_isNew) _reminders = List.of(_kind == 'event' ? engine.prefs.defaultEventReminders : engine.prefs.defaultTaskReminders);
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            autofocus: _isNew,
            textCapitalization: TextCapitalization.sentences,
            style: Theme.of(context).textTheme.titleLarge,
            decoration: InputDecoration(hintText: _kind == 'event' ? 'Add title' : 'Task title', border: InputBorder.none, filled: false),
          ),
          const Divider(),
          if (_kind == 'task')
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.event_outlined),
              title: const Text('Date'),
              value: _hasDate,
              onChanged: (v) => setState(() {
                _hasDate = v;
                if (v && _reminders.isEmpty && _isNew) _reminders = List.of(engine.prefs.defaultTaskReminders);
              }),
            ),
          if (_hasDate) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.schedule),
              title: Text(_kind == 'event' ? 'All day' : 'Time of day'),
              value: _kind == 'event' ? _allDay : !_allDay,
              onChanged: (v) => setState(() => _allDay = _kind == 'event' ? v : !v),
            ),
            _dateRow(_kind == 'event' ? 'Starts' : 'Due', true),
            if (_kind == 'event') _dateRow('Ends', false),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.repeat),
              title: Text(describeRule(parseRule(_rrule), _startDate)),
              onTap: _pickRepeat,
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Notifications'),
              subtitle: _allDay ? Text('All-day reminders count from ${engine.prefs.allDayReminderTime} on the day') : null,
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final m in _reminders)
                  InputChip(label: Text(reminderLabel(m, allDay: _allDay)), onDeleted: () => setState(() => _reminders.remove(m))),
                if (_reminders.length < 5) ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Add notification'), onPressed: _addReminder),
              ],
            ),
            const Divider(),
          ],
          DropdownButtonFormField<String>(
            initialValue: _listId,
            decoration: InputDecoration(labelText: _kind == 'event' ? 'Calendar' : 'List', prefixIcon: const Icon(Icons.folder_outlined)),
            items: [for (final l in lists) DropdownMenuItem(value: l.id, child: Row(children: [ColorDot(hex: l.color), const SizedBox(width: 8), Text(l.name)]))],
            onChanged: (v) => setState(() => _listId = v),
          ),
          const SizedBox(height: 12),
          TextField(controller: _location, decoration: const InputDecoration(labelText: 'Location', prefixIcon: Icon(Icons.place_outlined))),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true, prefixIcon: Icon(Icons.notes)),
          ),
          const SizedBox(height: 16),
          Text('Colour', style: TextStyle(color: c.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(spacing: 10, children: [
            for (final hex in [null, ...entryColors])
              InkWell(
                onTap: () => setState(() => _color = hex),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hexColor(hex ?? engine.listById(_listId)?.color ?? '#3a5bd9'),
                    border: Border.all(color: _color == hex ? c.primary : Colors.transparent, width: 3),
                  ),
                  child: hex == null ? const Center(child: Text('A', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))) : null,
                ),
              ),
          ]),
          if (_kind == 'task') ...[
            const SizedBox(height: 8),
            SwitchListTile(contentPadding: EdgeInsets.zero, secondary: const Icon(Icons.star_outline), title: const Text('Starred'), value: _starred, onChanged: (v) => setState(() => _starred = v)),
            if (!_isNew)
              SwitchListTile(contentPadding: EdgeInsets.zero, secondary: const Icon(Icons.task_alt), title: const Text('Done'), value: _done, onChanged: (v) => setState(() => _done = v)),
          ],
        ],
      ),
    );
  }

  Widget _dateRow(String label, bool start) {
    final date = start ? _startDate : _endDate;
    final time = start ? _startTime : _endTime;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 56, child: Text(label)),
        Expanded(child: OutlinedButton(onPressed: () => _pickDate(start), child: Text(_fmtDate(date)))),
        if (!_allDay && (_kind == 'event' || start)) ...[
          const SizedBox(width: 8),
          OutlinedButton(onPressed: () => _pickTime(start), child: Text(_fmtTime(time))),
        ],
      ]),
    );
  }
}

/// "This event / This and following / All events".
Future<String?> askScope(BuildContext context, String title) => showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(title),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'this'), child: const Text('This event')),
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'following'), child: const Text('This and following events')),
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'all'), child: const Text('All events')),
        ],
      ),
    );

Future<int?> pickReminder(BuildContext context, {required List<int> have, bool allDay = false}) async {
  final v = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final m in reminderChoices.where((m) => !have.contains(m))) ListTile(title: Text(reminderLabel(m, allDay: allDay)), onTap: () => Navigator.pop(c, m)),
          ListTile(leading: const Icon(Icons.tune), title: const Text('Custom…'), onTap: () => Navigator.pop(c, -1)),
        ]),
      ),
    ),
  );
  if (v != -1 || !context.mounted) return v;
  final amount = TextEditingController(text: '30');
  var unit = 1;
  return showDialog<int>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('Custom notification'),
        content: Row(children: [
          SizedBox(width: 80, child: TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount'))),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButton<int>(
              value: unit,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 1, child: Text('minutes before')),
                DropdownMenuItem(value: 60, child: Text('hours before')),
                DropdownMenuItem(value: 1440, child: Text('days before')),
                DropdownMenuItem(value: 10080, child: Text('weeks before')),
              ],
              onChanged: (x) => set(() => unit = x ?? 1),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(amount.text.trim());
              if (n == null || n < 0 || n * unit > 40320) return;
              Navigator.pop(c, n * unit);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}

class CustomRepeatDialog extends StatefulWidget {
  const CustomRepeatDialog({super.key, required this.start, this.initial});
  final String start;
  final String? initial;

  @override
  State<CustomRepeatDialog> createState() => _CustomRepeatDialogState();
}

class _CustomRepeatDialogState extends State<CustomRepeatDialog> {
  late Rule r;
  final _interval = TextEditingController();
  final _count = TextEditingController();

  @override
  void initState() {
    super.initState();
    r = parseRule(widget.initial) ?? Rule(freq: 'WEEKLY', byday: [ByDay(weekdayOf(widget.start))]);
    _interval.text = '${r.interval}';
    _count.text = '${r.count ?? 10}';
  }

  @override
  void dispose() {
    _interval.dispose();
    _count.dispose();
    super.dispose();
  }

  String get _ends => r.count != null ? 'count' : (r.until != null ? 'until' : 'never');

  @override
  Widget build(BuildContext context) {
    final day = parseDate(widget.start).day;
    final nth = ((day - 1) ~/ 7) + 1;
    return AlertDialog(
      title: const Text('Repeat'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Every'),
            const SizedBox(width: 8),
            SizedBox(
              width: 56,
              child: TextField(
                controller: _interval,
                keyboardType: TextInputType.number,
                onChanged: (v) => setState(() => r = r.copyWith(interval: (int.tryParse(v) ?? 1).clamp(1, 999))),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: r.freq,
              items: const [
                DropdownMenuItem(value: 'DAILY', child: Text('day(s)')),
                DropdownMenuItem(value: 'WEEKLY', child: Text('week(s)')),
                DropdownMenuItem(value: 'MONTHLY', child: Text('month(s)')),
                DropdownMenuItem(value: 'YEARLY', child: Text('year(s)')),
              ],
              onChanged: (f) => setState(() => r = r.copyWith(
                    freq: f,
                    byday: f == 'WEEKLY' ? [ByDay(weekdayOf(widget.start))] : null,
                    clearByday: f != 'WEEKLY',
                    clearBymonthday: true,
                  )),
            ),
          ]),
          if (r.freq == 'WEEKLY') ...[
            const SizedBox(height: 12),
            Wrap(spacing: 4, children: [
              for (final wd in [1, 2, 3, 4, 5, 6, 0])
                FilterChip(
                  label: Text(wdShort[wd].substring(0, 2)),
                  selected: r.byday?.any((b) => b.wd == wd) ?? false,
                  onSelected: (on) => setState(() {
                    final cur = r.byday?.map((b) => b.wd).toSet() ?? <int>{};
                    if (on) {
                      cur.add(wd);
                    } else {
                      cur.remove(wd);
                    }
                    if (cur.isEmpty) cur.add(weekdayOf(widget.start));
                    final ordered = cur.toList()..sort((a, b) => ((a + 6) % 7).compareTo((b + 6) % 7));
                    r = r.copyWith(byday: ordered.map(ByDay.new).toList());
                  }),
                ),
            ]),
          ],
          if (r.freq == 'MONTHLY')
            DropdownButton<String>(
              value: (r.byday?.isNotEmpty ?? false) ? 'nth' : 'day',
              isExpanded: true,
              items: [
                DropdownMenuItem(value: 'day', child: Text('On day $day')),
                DropdownMenuItem(value: 'nth', child: Text('On the ${nth > 4 ? 'last' : const ['', 'first', 'second', 'third', 'fourth'][nth]} ${wdLong[weekdayOf(widget.start)]}')),
              ],
              onChanged: (v) => setState(() => r = v == 'nth'
                  ? r.copyWith(byday: [ByDay(weekdayOf(widget.start), nth > 4 ? -1 : nth)], clearBymonthday: true)
                  : r.copyWith(clearByday: true, bymonthday: [day])),
            ),
          const SizedBox(height: 12),
          const Text('Ends'),
          RadioGroup<String>(
            groupValue: _ends,
            onChanged: (v) => setState(() {
              if (v == 'never') r = r.copyWith(clearCount: true, clearUntil: true);
              if (v == 'count') r = r.copyWith(count: int.tryParse(_count.text) ?? 10, clearUntil: true);
              if (v == 'until') r = r.copyWith(clearCount: true, until: addDays(widget.start, 90));
            }),
            child: Column(children: [
              const RadioListTile(value: 'never', title: Text('Never'), contentPadding: EdgeInsets.zero),
              RadioListTile(
                value: 'until',
                contentPadding: EdgeInsets.zero,
                title: Row(children: [
                  const Text('On '),
                  TextButton(
                    onPressed: () async {
                      final cur = parseDate(r.until ?? addDays(widget.start, 90));
                      final d = await showDatePicker(context: context, initialDate: DateTime(cur.year, cur.month, cur.day), firstDate: DateTime(2000), lastDate: DateTime(2100));
                      if (d != null) setState(() => r = r.copyWith(clearCount: true, until: makeDate(d.year, d.month, d.day)));
                    },
                    child: Text(r.until ?? 'pick date'),
                  ),
                ]),
              ),
              RadioListTile(
                value: 'count',
                contentPadding: EdgeInsets.zero,
                title: Row(children: [
                  const Text('After '),
                  SizedBox(
                    width: 56,
                    child: TextField(
                      controller: _count,
                      keyboardType: TextInputType.number,
                      onChanged: (v) => setState(() => r = r.copyWith(count: (int.tryParse(v) ?? 1).clamp(1, 5000), clearUntil: true)),
                    ),
                  ),
                  const Text(' times'),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Text(describeRule(r, widget.start), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, r.toString()), child: const Text('Done')),
      ],
    );
  }
}
