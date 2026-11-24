import 'dart:convert';
import 'dart:io';

import 'package:dumpbox/src/api.dart';
import 'package:dumpbox/src/planner/planner_engine.dart';
import 'package:dumpbox/src/planner/planner_models.dart';
import 'package:dumpbox/src/planner/recurrence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Entry entry(Map<String, dynamic> j) => Entry.fromJson({'id': 'e1', 'kind': 'event', 'title': 'x', 'version': 1, ...j});

void main() {
  setUpAll(() => initTimeZones('Asia/Kolkata'));

  group('time zones', () {
    test('round-trips wall time', () {
      final d = fromWall('2026-12-01', '10:00');
      expect(d.toIso8601String(), '2026-12-01T04:30:00.000Z');
      expect(toWall(d).time, '10:00');
    });
    test('keeps wall time across DST', () {
      final ny = location('America/New_York');
      expect(fromWall('2026-03-07', '10:00', ny).toIso8601String(), '2026-03-07T15:00:00.000Z');
      expect(fromWall('2026-03-09', '10:00', ny).toIso8601String(), '2026-03-09T14:00:00.000Z');
    });
    test('old zone aliases still work', () {
      expect(location('Asia/Calcutta'), isNotNull);
      expect(fromWall('2026-12-01', '10:00', location('Asia/Calcutta')).toIso8601String(), '2026-12-01T04:30:00.000Z');
    });
  });

  group('rules (same cases as the web app)', () {
    test('parse, format and describe', () {
      expect(parseRule('RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4').toString(), 'FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4');
      expect(parseRule('FREQ=HOURLY'), isNull);
      expect(describeRule(parseRule('FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE')), 'Every 2 weeks on Mon, Wed');
      expect(describeRule(parseRule('FREQ=MONTHLY;BYDAY=-1FR')), 'Monthly on the last Friday');
    });
    test('weekly with BYDAY and COUNT', () {
      expect(ruleDates('2026-11-23', parseRule('FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4')!, '2027-01-01'), ['2026-11-23', '2026-11-25', '2026-11-30', '2026-12-02']);
    });
    test('monthly day 31 skips short months', () {
      expect(ruleDates('2026-01-31', parseRule('FREQ=MONTHLY')!, '2026-06-30'), ['2026-01-31', '2026-03-31', '2026-05-31']);
    });
    test('last friday, nth weekday, leap day, until', () {
      expect(ruleDates('2026-11-27', parseRule('FREQ=MONTHLY;BYDAY=-1FR')!, '2027-01-31'), ['2026-11-27', '2026-12-25', '2027-01-29']);
      expect(ruleDates('2026-12-08', parseRule('FREQ=MONTHLY;BYDAY=2TU')!, '2027-02-28'), ['2026-12-08', '2027-01-12', '2027-02-09']);
      expect(ruleDates('2024-02-29', parseRule('FREQ=YEARLY')!, '2032-12-31'), ['2024-02-29', '2028-02-29', '2032-02-29']);
      expect(ruleDates('2026-12-01', parseRule('FREQ=DAILY;UNTIL=20261203')!, '2027-01-01'), ['2026-12-01', '2026-12-02', '2026-12-03']);
    });
  });

  group('occurrences and reminders', () {
    test('weekly timed event with an exdate', () {
      final e = entry({
        'start_at': '2026-11-23T04:30:00Z',
        'end_at': '2026-11-23T05:30:00Z',
        'time_zone': 'Asia/Kolkata',
        'rrule': 'FREQ=WEEKLY;BYDAY=MO',
        'exdates': ['2026-11-30T04:30Z'],
      });
      final occ = occurrences(e, '2026-11-23', '2026-12-14');
      expect(occ.map((o) => o.startDate), ['2026-11-23', '2026-12-07', '2026-12-14']);
      expect(occ.first.startTime, '10:00');
      expect(occ.first.endTime, '11:00');
    });
    test('all-day multi-day event overlapping the range', () {
      final occ = occurrences(entry({'all_day': true, 'start_date': '2026-11-20', 'end_date': '2026-11-25'}), '2026-11-23', '2026-11-29');
      expect(occ.length, 1);
      expect(occ.first.endDate, '2026-11-25');
    });
    test('reminders: timed and all-day, done tasks skipped', () {
      final ev = entry({'id': 'a', 'start_at': '2026-12-01T04:30:00Z', 'reminders': [10, 60]});
      final task = entry({'id': 'b', 'kind': 'task', 'all_day': true, 'start_date': '2026-12-01', 'reminders': [0]});
      final done = entry({'id': 'c', 'kind': 'task', 'all_day': true, 'start_date': '2026-12-01', 'reminders': [0], 'completed_at': '2026-11-30T00:00:00Z'});
      final r = remindersBetween([ev, task, done], DateTime.utc(2026, 11, 30), DateTime.utc(2026, 12, 2), allDayTime: '09:00');
      expect(r.map((x) => '${x.entry.id}@${x.at.toIso8601String()}').toSet(), {
        'b@2026-12-01T03:30:00.000Z',
        'a@2026-12-01T03:30:00.000Z',
        'a@2026-12-01T04:20:00.000Z',
      });
      expect(r.length, 3);
    });
  });

  group('planner engine', () {
    late Directory dir;
    setUp(() async {
      sqfliteFfiInit();
      dir = await Directory.systemTemp.createTemp('planner');
    });
    tearDown(() => dir.delete(recursive: true));

    test('offline create is kept, sent once online, and the server copy replaces it', () async {
      var offline = true;
      final server = <String, Map<String, dynamic>>{};
      var posts = 0;
      final client = MockClient((req) async {
        if (offline) throw const SocketException('offline');
        final path = req.url.path;
        if (req.method == 'POST' && path == '/v1/planner/entries') {
          posts++;
          final b = jsonDecode(req.body) as Map<String, dynamic>;
          final row = {...b, 'version': 1, 'created_at': '2026-11-24T00:00:00Z', 'updated_at': '2026-11-24T00:00:01Z', 'completed_at': null, 'deleted_at': null};
          server[b['id'] as String] = row;
          return http.Response(jsonEncode({'entry': row, 'created': true}), 201);
        }
        if (req.method == 'PATCH' && path.startsWith('/v1/planner/entries/')) {
          final id = path.split('/').last;
          final b = jsonDecode(req.body) as Map<String, dynamic>;
          final row = {...server[id]!, ...b..remove('base_version')};
          if (b['completed'] == true) row['completed_at'] = '2026-11-24T01:00:00Z';
          row.remove('completed');
          row['version'] = (row['version'] as int) + 1;
          server[id] = row;
          return http.Response(jsonEncode({'entry': row, 'next_entry': null, 'merged': false}), 200);
        }
        if (path == '/v1/planner/changes') {
          return http.Response(jsonEncode({
            'entries': server.values.toList(),
            'lists': [
              {'id': 'l1', 'kind': 'tasks', 'name': 'My Tasks', 'color': '#1e8a52', 'is_default': true},
            ],
            'next_since': 'tok',
            'has_more': false,
            'reset': false,
          }), 200);
        }
        if (path == '/v1/me') return http.Response(jsonEncode({'user': {'planner': {'week_start': 0}}}), 200);
        return http.Response('{}', 404);
      });
      final api = ApiClient(tokenProvider: () async => 't', client: client, baseUrl: 'http://x');
      final store = await PlannerStore.open('${dir.path}/p.db', factory: databaseFactoryFfi);
      final engine = PlannerEngine(store: store, api: api);
      await engine.init();

      final made = await engine.create({'kind': 'task', 'title': 'Buy milk', 'all_day': true, 'start_date': '2026-12-01'});
      await engine.sync();
      expect(engine.online, isFalse);
      expect(engine.byId(made.id)!.version, 0);
      await engine.toggleDone(engine.byId(made.id)!);
      expect(engine.byId(made.id)!.isDone, isTrue);

      offline = false;
      await engine.sync();
      expect(posts, 1);
      expect(engine.byId(made.id)!.version, greaterThanOrEqualTo(2));
      expect(engine.byId(made.id)!.isDone, isTrue);
      expect(engine.lists.single.name, 'My Tasks');
      expect(engine.prefs.weekStart, 0);
      expect(await store.ops(), isEmpty);

      // Survives a restart.
      final again = PlannerEngine(store: store, api: api);
      await again.init();
      expect(again.byId(made.id)!.title, 'Buy milk');
      await store.close();
    });
  });
}
