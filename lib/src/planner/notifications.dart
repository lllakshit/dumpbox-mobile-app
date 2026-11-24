import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;

import 'planner_models.dart';
import 'recurrence.dart';

/// Phone notifications for event and task reminders.
///
/// Every reminder in the next two weeks is handed to Android's alarm manager, so it fires even when the app is
/// closed or the phone restarted. The list is rebuilt after every change and every sync (and by the background
/// check every ~15 minutes), so edits made on the web reach the phone without opening the app.
class PlannerNotifications {
  PlannerNotifications._();
  static final instance = PlannerNotifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Actions tapped in a notification (`done:ID`, `snooze:ID`, `open:ID`), handled by the app.
  final ValueNotifier<String?> tapped = ValueNotifier(null);

  static const _channelId = 'reminders';
  static const _channelName = 'Event and task reminders';
  static const _maxScheduled = 120;
  static const _horizon = Duration(days: 14);

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> init({bool background = false}) async {
    if (_ready) return;
    String? zone;
    try {
      zone = (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      zone = null;
    }
    initTimeZones(zone);
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_reminder')),
      onDidReceiveNotificationResponse: background ? null : _onResponse,
    );
    await _android?.createNotificationChannel(const AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Reminders you set on events and tasks',
      importance: Importance.high,
    ));
    _ready = true;
    if (!background) {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final r = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && r != null) _onResponse(r);
    }
  }

  void _onResponse(NotificationResponse r) {
    final payload = r.payload;
    if (payload == null) return;
    String? id;
    try {
      id = (jsonDecode(payload) as Map<String, dynamic>)['id'] as String?;
    } catch (_) {
      id = null;
    }
    if (id == null) return;
    final action = r.actionId ?? 'open';
    tapped.value = '$action:$id:${DateTime.now().microsecondsSinceEpoch}';
  }

  /// Asks for permission to post notifications (Android 13+) and for exact alarms when needed.
  Future<bool> requestPermission() async {
    await init();
    final a = _android;
    if (a == null) return false;
    final granted = await a.requestNotificationsPermission() ?? false;
    if (await a.canScheduleExactNotifications() == false) await a.requestExactAlarmsPermission();
    return granted;
  }

  Future<({bool notifications, bool exact})> status() async {
    await init();
    final a = _android;
    if (a == null) return (notifications: false, exact: false);
    return (notifications: await a.areNotificationsEnabled() ?? false, exact: await a.canScheduleExactNotifications() ?? false);
  }

  NotificationDetails _details(Entry e) => NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Reminders you set on events and tasks',
          importance: Importance.high,
          priority: Priority.high,
          category: e.isEvent ? AndroidNotificationCategory.event : AndroidNotificationCategory.reminder,
          color: _color(e.color),
          actions: [
            if (e.isTask) const AndroidNotificationAction('done', 'Mark done', showsUserInterface: true),
            const AndroidNotificationAction('snooze', 'Snooze 10 min', showsUserInterface: true),
          ],
        ),
      );

  Color? _color(String? hex) {
    if (hex == null || hex.length != 7) return null;
    final v = int.tryParse(hex.substring(1), radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  String _body(DueReminder r) {
    final parts = <String>[];
    if (r.occurrence.allDay) {
      parts.add(r.minutes >= 1440 ? r.occurrence.startDate : 'Today');
    } else {
      final s = r.occurrence.startTime ?? '';
      final e = r.entry.endAt != null ? '–${r.occurrence.endTime}' : '';
      if (r.minutes == 0) {
        parts.add('Now · $s$e');
      } else {
        final mins = r.minutes >= 60 ? '${(r.minutes / 60).toStringAsFixed(r.minutes % 60 == 0 ? 0 : 1)} h' : '${r.minutes} min';
        parts.add('In $mins · $s$e');
      }
    }
    if (r.entry.location != null && r.entry.location!.isNotEmpty) parts.add(r.entry.location!);
    return parts.join(' · ');
  }

  /// Brings the scheduled reminders in line with the next two weeks, changing only what differs: reminders already
  /// scheduled (same entry, time and text) are left alone, nothing due within the next minute is cancelled, and
  /// snoozed reminders are never touched. Safe to call after every change and every sync.
  Future<int> reschedule(Iterable<Entry> entries, PlannerPrefs prefs) async {
    await init();
    final now = DateTime.now().toUtc();
    // From a minute ago, so a reminder about to fire is still "wanted" and is not cancelled under it.
    final due = remindersBetween(entries, now.subtract(const Duration(minutes: 1)), now.add(_horizon), allDayTime: prefs.allDayReminderTime).take(_maxScheduled).toList();
    final wanted = {for (final r in due) _idFor('${r.id}|${r.at.millisecondsSinceEpoch}|${r.entry.title}|${_body(r)}'): r};
    final pending = await _plugin.pendingNotificationRequests();
    final have = <int>{};
    for (final p in pending) {
      have.add(p.id);
      if (wanted.containsKey(p.id)) continue;
      if (p.payload != null && p.payload!.contains('"snooze":true')) continue;
      if (p.id == 1) continue; // the test notification
      await _plugin.cancel(id: p.id);
    }
    final mode = (await _android?.canScheduleExactNotifications() ?? false) ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;
    var n = 0;
    for (final entry in wanted.entries) {
      final r = entry.value;
      if (have.contains(entry.key)) {
        n++;
        continue;
      }
      if (!r.at.isAfter(now.add(const Duration(seconds: 2)))) continue;
      try {
        await _plugin.zonedSchedule(
          id: entry.key,
          title: r.entry.title,
          body: _body(r),
          scheduledDate: tz.TZDateTime.from(r.at, tz.UTC),
          notificationDetails: _details(r.entry),
          androidScheduleMode: mode,
          payload: jsonEncode({'id': r.entry.id, 'key': r.occurrence.key}),
        );
        n++;
      } catch (e) {
        debugPrint('Could not schedule ${r.id}: $e');
      }
    }
    return n;
  }

  Future<void> snooze(Entry e, {Duration by = const Duration(minutes: 10)}) async {
    await init();
    final at = DateTime.now().toUtc().add(by);
    final mode = (await _android?.canScheduleExactNotifications() ?? false) ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;
    await _plugin.zonedSchedule(
      id: _idFor('snooze|${e.id}|${at.millisecondsSinceEpoch}'),
      title: e.title,
      body: 'Snoozed reminder',
      scheduledDate: tz.TZDateTime.from(at, tz.UTC),
      notificationDetails: _details(e),
      androidScheduleMode: mode,
      payload: jsonEncode({'id': e.id, 'snooze': true}),
    );
  }

  Future<void> test() async {
    await init();
    await _plugin.show(
      id: 1,
      title: 'DumpBox reminders are on',
      body: 'This is how event and task reminders will look.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(_channelId, _channelName, importance: Importance.high, priority: Priority.high),
      ),
    );
  }

  Future<void> cancelAll() async {
    if (!_ready) return;
    await _plugin.cancelAll();
  }

  /// Stable 31-bit id from a string (FNV-1a).
  int _idFor(String s) {
    var h = 0x811c9dc5;
    for (final c in utf8.encode(s)) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h & 0x7FFFFFFF;
  }
}
