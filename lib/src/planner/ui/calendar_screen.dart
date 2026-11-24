import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../planner_engine.dart';
import '../recurrence.dart';
import 'entry_editor.dart';
import 'planner_widgets.dart';

enum CalMode { month, day, schedule }

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.engine});
  final PlannerEngine engine;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalMode _mode = CalMode.month;
  late String _selected = todayLocal();
  late String _month = _monthOf(todayLocal());
  int _scheduleDays = 60;

  PlannerEngine get engine => widget.engine;

  static String _monthOf(String d) {
    final p = parseDate(d);
    return makeDate(p.year, p.month, 1);
  }

  void _go(int dir) => setState(() {
        if (_mode == CalMode.month) {
          final p = parseDate(_month);
          _month = makeDate(p.year, p.month + dir, 1);
        } else if (_mode == CalMode.day) {
          _selected = addDays(_selected, dir);
        } else {
          _selected = addDays(_selected, dir * 30);
        }
      });

  void _today() => setState(() {
        _selected = todayLocal();
        _month = _monthOf(_selected);
      });

  String get _title {
    if (_mode == CalMode.month) return DateFormat('MMMM yyyy').format(parseDate(_month));
    if (_mode == CalMode.day) return DateFormat('EEE, d MMM yyyy').format(parseDate(_selected));
    return 'From ${DateFormat('d MMM').format(parseDate(_selected))}';
  }

  void _newEvent({String? date, String? time}) {
    final d = date ?? _selected;
    Map<String, dynamic> draft;
    if (time == null) {
      final now = toWall(DateTime.now());
      final t = d == now.date ? timeFromMinutes(((minutesOf(now.time) ~/ 30) + 1) * 30) : '09:00';
      final s = fromWall(d, t);
      draft = {'kind': 'event', 'all_day': false, 'start_at': s.toIso8601String(), 'end_at': s.add(Duration(minutes: engine.prefs.defaultEventMinutes)).toIso8601String()};
    } else {
      final s = fromWall(d, time);
      draft = {'kind': 'event', 'all_day': false, 'start_at': s.toIso8601String(), 'end_at': s.add(Duration(minutes: engine.prefs.defaultEventMinutes)).toIso8601String()};
    }
    openEntryEditor(context, engine, draft: draft);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: () => _newEvent(), tooltip: 'New event', child: const Icon(Icons.add)),
      body: ListenableBuilder(
        listenable: engine,
        builder: (context, _) => Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(children: [
              TextButton(onPressed: _today, child: const Text('Today')),
              IconButton(onPressed: () => _go(-1), icon: const Icon(Icons.chevron_left), tooltip: 'Previous'),
              IconButton(onPressed: () => _go(1), icon: const Icon(Icons.chevron_right), tooltip: 'Next'),
              Expanded(child: Text(_title, style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
              PopupMenuButton<CalMode>(
                tooltip: 'View',
                initialValue: _mode,
                onSelected: (m) => setState(() => _mode = m),
                icon: Icon(switch (_mode) { CalMode.month => Icons.calendar_view_month, CalMode.day => Icons.view_day, CalMode.schedule => Icons.view_agenda }),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: CalMode.month, child: Text('Month')),
                  PopupMenuItem(value: CalMode.day, child: Text('Day')),
                  PopupMenuItem(value: CalMode.schedule, child: Text('Schedule')),
                ],
              ),
              IconButton(tooltip: 'Calendars', icon: const Icon(Icons.layers_outlined), onPressed: () => _calendarsSheet(context)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: QuickAddField(engine: engine, kind: 'event', day: _selected, hint: 'Quick add: “Dentist tomorrow 5pm remind 1h before”'),
          ),
          Divider(height: 1, color: c.outlineVariant),
          Expanded(
            child: switch (_mode) {
              CalMode.month => _monthView(context),
              CalMode.day => _dayView(context),
              CalMode.schedule => _scheduleView(context),
            },
          ),
        ]),
      ),
    );
  }

  Widget _monthView(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final weekStart = engine.prefs.weekStart;
    final first = startOfWeek(_month, weekStart);
    final days = List.generate(42, (i) => addDays(first, i));
    final occ = engine.occurrencesIn(days.first, days.last);
    final byDay = <String, List<Occurrence>>{};
    for (final o in occ) {
      for (var d = o.startDate; d.compareTo(o.endDate) <= 0 && diffDays(o.startDate, d) <= 60; d = addDays(d, 1)) {
        (byDay[d] ??= []).add(o);
      }
    }
    final today = todayLocal();
    final month = parseDate(_month).month;
    final selectedList = byDay[_selected] ?? const [];
    return Column(children: [
      Row(children: [
        for (var i = 0; i < 7; i++)
          Expanded(child: Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(wdShort[weekdayOf(days[i])].substring(0, 1), style: TextStyle(fontSize: 12, color: c.onSurfaceVariant))))),
      ]),
      for (var w = 0; w < 6; w++)
        Row(children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Builder(builder: (context) {
                final d = days[w * 7 + i];
                final list = byDay[d] ?? const [];
                final sel = d == _selected;
                final isToday = d == today;
                return InkWell(
                  onTap: () => setState(() => _selected = d),
                  onLongPress: () => _newEvent(date: d),
                  child: SizedBox(
                    height: 52,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: isToday ? c.primary : (sel ? c.primary.withValues(alpha: 0.15) : null)),
                        child: Text(
                          '${parseDate(d).day}',
                          style: TextStyle(
                            color: isToday ? c.onPrimary : (parseDate(d).month != month ? c.onSurfaceVariant.withValues(alpha: 0.6) : null),
                            fontWeight: sel || isToday ? FontWeight.w600 : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        for (final o in list.take(3))
                          Container(margin: const EdgeInsets.symmetric(horizontal: 1), width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: hexColor(engine.colorOf(o.entry)))),
                      ]),
                    ]),
                  ),
                );
              }),
            ),
        ]),
      Divider(height: 1, color: c.outlineVariant),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(children: [
          Expanded(child: Text(DateFormat('EEEE, d MMMM').format(parseDate(_selected)), style: const TextStyle(fontWeight: FontWeight.w600))),
          TextButton.icon(onPressed: () => setState(() => _mode = CalMode.day), icon: const Icon(Icons.view_day, size: 18), label: const Text('Day view')),
        ]),
      ),
      Expanded(
        child: selectedList.isEmpty
            ? Center(child: Text('Nothing on this day. Long-press a day or tap + to add.', style: TextStyle(color: c.onSurfaceVariant)))
            : ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 88), children: [for (final o in selectedList) OccurrenceTile(engine: engine, o: o)]),
      ),
    ]);
  }

  Widget _dayView(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    const hour = 56.0;
    final occ = engine.occurrencesIn(_selected, _selected);
    final allDay = occ.where((o) => o.allDay || o.startTime == null).toList();
    final timed = occ.where((o) => !o.allDay && o.startTime != null).toList();
    // Side-by-side columns for overlaps.
    final items = <({Occurrence o, int s, int e, int col, int cols})>[];
    final sorted = timed.map((o) {
      final s = o.startDate.compareTo(_selected) < 0 ? 0 : minutesOf(o.startTime!);
      var e = o.endDate.compareTo(_selected) > 0 ? 1440 : minutesOf(o.endTime ?? o.startTime!);
      if (e <= s) e = s + 30;
      return (o: o, s: s, e: e);
    }).toList()
      ..sort((a, b) => a.s.compareTo(b.s));
    var cluster = <({Occurrence o, int s, int e, int col})>[];
    var clusterEnd = -1;
    void flush() {
      final cols = cluster.isEmpty ? 1 : cluster.map((x) => x.col + 1).reduce((a, b) => a > b ? a : b);
      for (final x in cluster) {
        items.add((o: x.o, s: x.s, e: x.e, col: x.col, cols: cols));
      }
      cluster = [];
    }

    for (final it in sorted) {
      if (it.s >= clusterEnd && cluster.isNotEmpty) flush();
      final used = cluster.where((x) => x.e > it.s).map((x) => x.col).toSet();
      var col = 0;
      while (used.contains(col)) {
        col++;
      }
      final p = (o: it.o, s: it.s, e: it.e, col: col);
      cluster.add(p);
      if (it.e > clusterEnd) clusterEnd = it.e;
    }
    flush();
    final isToday = _selected == todayLocal();
    final nowMin = minutesOf(toWall(DateTime.now()).time);
    return Column(children: [
      if (allDay.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Column(children: [for (final o in allDay) OccurrenceTile(engine: engine, o: o)]),
        ),
      if (allDay.isNotEmpty) Divider(height: 1, color: c.outlineVariant),
      Expanded(
        child: SingleChildScrollView(
          controller: ScrollController(initialScrollOffset: ((isToday ? nowMin / 60 - 1.5 : 7.0).clamp(0, 18)) * hour),
          child: SizedBox(
            height: 24 * hour,
            child: LayoutBuilder(builder: (context, box) {
              const left = 52.0;
              final width = box.maxWidth - left - 8;
              return Stack(children: [
                for (var h = 0; h < 24; h++) ...[
                  Positioned(top: h * hour, left: left, right: 0, child: Divider(height: 1, color: c.outlineVariant.withValues(alpha: 0.6))),
                  Positioned(top: h * hour - 7, left: 4, width: 44, child: Text(h == 0 ? '' : fmtTime(timeFromMinutes(h * 60)), textAlign: TextAlign.right, style: TextStyle(fontSize: 10, color: c.onSurfaceVariant))),
                ],
                // Tap an empty slot to add an event there.
                Positioned.fill(
                  left: left,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapUp: (d) => _newEvent(date: _selected, time: timeFromMinutes(((d.localPosition.dy / hour) * 2).floor() * 30)),
                  ),
                ),
                for (final it in items)
                  Positioned(
                    top: it.s / 60 * hour + 1,
                    height: ((it.e - it.s) / 60 * hour - 2).clamp(20, 24 * hour),
                    left: left + 2 + width * it.col / it.cols,
                    width: width / it.cols - 4,
                    child: Material(
                      color: hexColor(engine.colorOf(it.o.entry)),
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => openEntryEditor(context, engine, entry: it.o.entry, occurrence: it.o.recurring ? OccurrenceRef.of(it.o) : null),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          child: Text(
                            '${it.o.entry.isTask ? (it.o.entry.isDone ? '✓ ' : '○ ') : ''}${it.o.entry.title}\n${fmtTime(timeFromMinutes(it.s))}${it.o.entry.isEvent ? ' – ${fmtTime(timeFromMinutes(it.e % 1440))}' : ''}${it.o.entry.location != null ? ' · ${it.o.entry.location}' : ''}',
                            overflow: TextOverflow.fade,
                            style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.25),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (isToday)
                  Positioned(top: nowMin / 60 * hour, left: left - 4, right: 0, child: Row(children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                    Expanded(child: Container(height: 2, color: Colors.red)),
                  ])),
              ]);
            }),
          ),
        ),
      ),
    ]);
  }

  Widget _scheduleView(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final to = addDays(_selected, _scheduleDays - 1);
    final occ = engine.occurrencesIn(_selected, to);
    final byDay = <String, List<Occurrence>>{};
    for (final o in occ) {
      final d = o.startDate.compareTo(_selected) < 0 ? _selected : o.startDate;
      (byDay[d] ??= []).add(o);
    }
    final dates = byDay.keys.toList()..sort();
    final today = todayLocal();
    if (dates.isEmpty) {
      return Center(child: Text('Nothing planned. Use quick add above or +.', style: TextStyle(color: c.onSurfaceVariant)));
    }
    return RefreshIndicator(
      onRefresh: engine.sync,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 88),
        itemCount: dates.length + 1,
        itemBuilder: (context, i) {
          if (i == dates.length) {
            return Center(child: TextButton(onPressed: () => setState(() => _scheduleDays += 60), child: const Text('Show more')));
          }
          final d = dates[i];
          final p = parseDate(d);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 52,
                child: Column(children: [
                  Text(wdShort[weekdayOf(d)].toUpperCase(), style: TextStyle(fontSize: 11, color: d == today ? c.primary : c.onSurfaceVariant)),
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: d == today ? c.primary : null),
                    child: Text('${p.day}', style: TextStyle(fontSize: 17, color: d == today ? c.onPrimary : null)),
                  ),
                  Text(DateFormat('MMM').format(p), style: TextStyle(fontSize: 10, color: c.onSurfaceVariant)),
                ]),
              ),
              Expanded(child: Column(children: [for (final o in byDay[d]!) OccurrenceTile(engine: engine, o: o)])),
            ]),
          );
        },
      ),
    );
  }

  Future<void> _calendarsSheet(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (c) => ListenableBuilder(
          listenable: engine,
          builder: (c, _) => SafeArea(
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 4), child: Text('Show on the calendar', style: TextStyle(fontWeight: FontWeight.w600))),
                for (final l in engine.lists)
                  CheckboxListTile(
                    value: !l.hidden,
                    secondary: ColorDot(hex: l.color, size: 14),
                    title: Text(l.name),
                    subtitle: Text(l.isCalendar ? 'Calendar' : 'Task list'),
                    onChanged: (v) => engine.updateList(l, hidden: !(v ?? true)).catchError((_) {}),
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('New calendar'),
                  onTap: () async {
                    final name = await _askName(c, 'New calendar');
                    if (name != null) await engine.createList('calendar', name).catchError((_) => engine.lists.first);
                  },
                ),
              ]),
            ),
          ),
        ),
      );
}

Future<String?> _askName(BuildContext context, String title, [String initial = '']) {
  final t = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(controller: t, autofocus: true, maxLength: 80, decoration: const InputDecoration(labelText: 'Name')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, t.text.trim().isEmpty ? null : t.text.trim()), child: const Text('Save')),
      ],
    ),
  );
}

/// Shared with the tasks screen.
Future<String?> askListName(BuildContext context, String title, [String initial = '']) => _askName(context, title, initial);
