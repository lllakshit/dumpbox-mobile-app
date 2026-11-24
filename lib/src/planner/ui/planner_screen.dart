import 'package:flutter/material.dart';

import '../../models.dart';
import '../notifications.dart';
import '../planner_engine.dart';
import '../planner_models.dart';
import 'calendar_screen.dart';
import 'entry_editor.dart';
import 'import_screen.dart';
import 'planner_widgets.dart';
import 'tasks_screen.dart';

/// Makes the planner reachable from anywhere below (item actions use it for "Make event / Make task").
class PlannerScope extends InheritedWidget {
  const PlannerScope({super.key, required this.engine, required super.child});
  final PlannerEngine engine;

  static PlannerEngine? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PlannerScope>()?.engine;

  @override
  bool updateShouldNotify(PlannerScope oldWidget) => oldWidget.engine != engine;
}

/// The Planner tab: Calendar and Tasks.
class PlannerScreen extends StatelessWidget {
  const PlannerScreen({super.key, required this.engine, this.initialTab = 0});
  final PlannerEngine engine;
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Planner'),
          actions: [
            ListenableBuilder(
              listenable: engine,
              builder: (context, _) => engine.syncing
                  ? const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(
                      tooltip: engine.online ? 'Sync now' : 'Offline — changes are kept and sent later',
                      onPressed: engine.sync,
                      icon: Icon(engine.online ? Icons.sync : Icons.cloud_off),
                    ),
            ),
            IconButton(
              tooltip: 'Import & export',
              icon: const Icon(Icons.upload_file),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ImportScreen(engine: engine))),
            ),
          ],
          bottom: const TabBar(tabs: [Tab(icon: Icon(Icons.calendar_month), text: 'Calendar'), Tab(icon: Icon(Icons.task_alt), text: 'Tasks')]),
        ),
        body: TabBarView(children: [CalendarScreen(engine: engine), TasksScreen(engine: engine)]),
      ),
    );
  }
}

/// Opens the editor for an item turned into an event or task: its text is read like quick add.
Future<void> makeFromItem(BuildContext context, PlannerEngine engine, Item item, String kind) async {
  final first = (item.title ?? item.body ?? item.link?.title ?? item.url ?? item.location?.label ?? item.type.label).split('\n').first.trim();
  final full = [item.title, item.body, item.link?.title, item.url].whereType<String>().join('\n').trim();
  final body = await quickBody(engine, first.length > 300 ? first.substring(0, 300) : first, kind);
  final rest = full.split('\n').skip(item.title != null ? 0 : 1).join('\n').trim();
  if (!context.mounted) return;
  await openEntryEditor(context, engine, draft: {
    ...body,
    'notes': rest.isEmpty ? null : rest,
    'location': body['location'] ?? item.location?.label,
    'source_item_id': item.isLocalOnly ? null : item.id,
  });
}

/// Calendar & tasks part of Settings.
class PlannerSettingsSection extends StatefulWidget {
  const PlannerSettingsSection({super.key, required this.engine});
  final PlannerEngine engine;

  @override
  State<PlannerSettingsSection> createState() => _PlannerSettingsSectionState();
}

class _PlannerSettingsSectionState extends State<PlannerSettingsSection> {
  ({bool notifications, bool exact})? _status;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final s = await PlannerNotifications.instance.status();
      if (mounted) setState(() => _status = s);
    } catch (_) {
      // not available on this platform
    }
  }

  Future<void> _reminderList(String title, List<int> value, void Function(List<int>) save) async {
    final list = List.of(value);
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(title),
          content: Wrap(spacing: 8, runSpacing: 4, children: [
            for (final m in list) InputChip(label: Text(reminderLabel(m)), onDeleted: () => set(() => list.remove(m))),
            if (list.length < 5)
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
                onPressed: () async {
                  final m = await pickReminder(c, have: list);
                  if (m != null) {
                    set(() => list
                      ..add(m)
                      ..sort());
                  }
                },
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                save(list.toSet().toList()..sort());
                Navigator.pop(c);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.engine;
    final p = e.prefs;
    PlannerPrefs withP({int? weekStart, int? minutes, List<int>? ev, List<int>? task, String? allDay}) => PlannerPrefs(
          weekStart: weekStart ?? p.weekStart,
          defaultEventMinutes: minutes ?? p.defaultEventMinutes,
          defaultEventReminders: ev ?? p.defaultEventReminders,
          defaultTaskReminders: task ?? p.defaultTaskReminders,
          allDayReminderTime: allDay ?? p.allDayReminderTime,
        );
    final s = _status;
    return ListenableBuilder(
      listenable: e,
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('Calendar & tasks', style: TextStyle(fontWeight: FontWeight.w600))),
        ListTile(
          leading: Icon(s?.notifications == true ? Icons.notifications_active_outlined : Icons.notifications_off_outlined),
          title: const Text('Notifications'),
          subtitle: Text(s == null
              ? 'Checking…'
              : s.notifications
                  ? (s.exact ? 'On, at the exact time' : 'On (Android may delay them a little; allow “Alarms & reminders” for exact times)')
                  : 'Off. Turn on to be reminded of events and tasks.'),
          trailing: s?.notifications == true && s?.exact == true
              ? TextButton(onPressed: () => PlannerNotifications.instance.test(), child: const Text('Test'))
              : FilledButton(
                  onPressed: () async {
                    await PlannerNotifications.instance.requestPermission();
                    await _refresh();
                    await PlannerNotifications.instance.reschedule(e.entries, e.prefs);
                  },
                  child: const Text('Turn on'),
                ),
        ),
        ListTile(
          leading: const Icon(Icons.view_week_outlined),
          title: const Text('Week starts on'),
          trailing: DropdownButton<int>(
            value: p.weekStart,
            items: const [DropdownMenuItem(value: 1, child: Text('Monday')), DropdownMenuItem(value: 0, child: Text('Sunday')), DropdownMenuItem(value: 6, child: Text('Saturday'))],
            onChanged: (v) => e.savePrefs(withP(weekStart: v)),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.timelapse),
          title: const Text('Default event length'),
          trailing: DropdownButton<int>(
            value: const [15, 30, 45, 60, 90, 120].contains(p.defaultEventMinutes) ? p.defaultEventMinutes : 60,
            items: [for (final m in const [15, 30, 45, 60, 90, 120]) DropdownMenuItem(value: m, child: Text(m < 60 ? '$m min' : '${m / 60} h'))],
            onChanged: (v) => e.savePrefs(withP(minutes: v)),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.event_note_outlined),
          title: const Text('Default notifications for events'),
          subtitle: Text(p.defaultEventReminders.isEmpty ? 'None' : p.defaultEventReminders.map(reminderLabel).join(', ')),
          onTap: () => _reminderList('Events', p.defaultEventReminders, (v) => e.savePrefs(withP(ev: v))),
        ),
        ListTile(
          leading: const Icon(Icons.task_alt),
          title: const Text('Default notifications for tasks with a date'),
          subtitle: Text(p.defaultTaskReminders.isEmpty ? 'None' : p.defaultTaskReminders.map((m) => reminderLabel(m, allDay: true)).join(', ')),
          onTap: () => _reminderList('Tasks', p.defaultTaskReminders, (v) => e.savePrefs(withP(task: v))),
        ),
        ListTile(
          leading: const Icon(Icons.wb_sunny_outlined),
          title: const Text('All-day reminders at'),
          trailing: TextButton(
            onPressed: () async {
              final parts = p.allDayReminderTime.split(':');
              final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])));
              if (t != null) await e.savePrefs(withP(allDay: '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'));
            },
            child: Text(p.allDayReminderTime),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.upload_file),
          title: const Text('Import & export events and tasks'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ImportScreen(engine: e))),
        ),
      ]),
    );
  }
}
