/// Dates, time zones, repeat rules and occurrences. Same rules as the web app (src/lib/planner/recurrence.ts):
/// a subset of RFC 5545 RRULE (FREQ, INTERVAL, BYDAY, BYMONTHDAY, BYMONTH, COUNT, UNTIL), expanded on wall dates in
/// the entry's own zone so "every Monday 10:00" stays at 10:00.
library;

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'planner_models.dart';

bool _tzReady = false;

/// Loads the zone database once. [local] is the device zone (from flutter_timezone), when known.
void initTimeZones([String? local]) {
  if (!_tzReady) {
    tzdata.initializeTimeZones();
    _tzReady = true;
  }
  if (local != null) {
    final loc = location(local);
    if (loc != null) tz.setLocalLocation(loc);
  }
}

tz.Location? location(String? name) {
  if (name == null || name.isEmpty) return null;
  initTimeZones();
  try {
    return tz.getLocation(name);
  } catch (_) {
    // Old aliases some devices report.
    const aliases = {'Asia/Calcutta': 'Asia/Kolkata', 'Asia/Saigon': 'Asia/Ho_Chi_Minh', 'Asia/Katmandu': 'Asia/Kathmandu'};
    final a = aliases[name];
    return a == null ? null : tz.getLocation(a);
  }
}

tz.Location get localZone {
  initTimeZones();
  return tz.local;
}

String get localZoneName => localZone.name;

// ---------------------------------------------------------------------------- wall dates ("YYYY-MM-DD")

String makeDate(int y, int m, int d) {
  final x = DateTime.utc(y, m, d);
  return '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
}

DateTime parseDate(String d) => DateTime.utc(int.parse(d.substring(0, 4)), int.parse(d.substring(5, 7)), int.parse(d.substring(8, 10)));

String fmtDate(DateTime d) => makeDate(d.year, d.month, d.day);

String addDays(String d, int n) {
  final p = parseDate(d);
  return makeDate(p.year, p.month, p.day + n);
}

int diffDays(String a, String b) => parseDate(b).difference(parseDate(a)).inDays;

/// 0 = Sunday … 6 = Saturday.
int weekdayOf(String d) => parseDate(d).weekday % 7;

int daysInMonth(int y, int m) => DateTime.utc(y, m + 1, 0).day;

String startOfWeek(String d, [int weekStart = 1]) => addDays(d, -((weekdayOf(d) - weekStart + 7) % 7));

int minutesOf(String t) => int.parse(t.substring(0, 2)) * 60 + int.parse(t.substring(3, 5));

String timeFromMinutes(int min) {
  final m = ((min % 1440) + 1440) % 1440;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// Wall clock reading of an instant in a zone.
({String date, String time}) toWall(DateTime instant, [tz.Location? loc]) {
  final t = tz.TZDateTime.from(instant.toUtc(), loc ?? localZone);
  return (date: makeDate(t.year, t.month, t.day), time: timeFromMinutes(t.hour * 60 + t.minute));
}

/// The instant at which the zone's clock shows date + time.
DateTime fromWall(String date, String time, [tz.Location? loc]) {
  final p = parseDate(date);
  final m = minutesOf(time);
  return tz.TZDateTime(loc ?? localZone, p.year, p.month, p.day, m ~/ 60, m % 60).toUtc();
}

String todayLocal() => toWall(DateTime.now()).date;

// ---------------------------------------------------------------------------- rules

const wdCodes = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];
const wdShort = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const wdLong = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

class ByDay {
  const ByDay(this.wd, [this.n]);
  final int wd;
  final int? n;
}

class Rule {
  Rule({required this.freq, this.interval = 1, this.byday, this.bymonthday, this.bymonth, this.count, this.until});
  final String freq; // DAILY | WEEKLY | MONTHLY | YEARLY
  final int interval;
  final List<ByDay>? byday;
  final List<int>? bymonthday;
  final List<int>? bymonth;
  final int? count;
  final String? until;

  Rule copyWith({String? freq, int? interval, List<ByDay>? byday, bool clearByday = false, List<int>? bymonthday, bool clearBymonthday = false, int? count, bool clearCount = false, String? until, bool clearUntil = false}) => Rule(
        freq: freq ?? this.freq,
        interval: interval ?? this.interval,
        byday: clearByday ? null : (byday ?? this.byday),
        bymonthday: clearBymonthday ? null : (bymonthday ?? this.bymonthday),
        bymonth: bymonth,
        count: clearCount ? null : (count ?? this.count),
        until: clearUntil ? null : (until ?? this.until),
      );

  @override
  String toString() {
    final out = ['FREQ=$freq'];
    if (interval > 1) out.add('INTERVAL=$interval');
    if (byday?.isNotEmpty ?? false) out.add('BYDAY=${byday!.map((b) => '${b.n ?? ''}${wdCodes[b.wd]}').join(',')}');
    if (bymonthday?.isNotEmpty ?? false) out.add('BYMONTHDAY=${bymonthday!.join(',')}');
    if (bymonth?.isNotEmpty ?? false) out.add('BYMONTH=${bymonth!.join(',')}');
    if (count != null) {
      out.add('COUNT=$count');
    } else if (until != null) {
      out.add('UNTIL=${until!.replaceAll('-', '')}');
    }
    return out.join(';');
  }
}

Rule? parseRule(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final s = raw.trim().replaceFirst(RegExp(r'^RRULE:', caseSensitive: false), '');
  final parts = <String, String>{};
  for (final kv in s.split(';')) {
    if (kv.isEmpty) continue;
    final i = kv.indexOf('=');
    if (i <= 0) return null;
    parts[kv.substring(0, i).toUpperCase()] = kv.substring(i + 1).toUpperCase();
  }
  final freq = parts['FREQ'];
  if (!const ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'].contains(freq)) return null;
  var interval = 1;
  if (parts['INTERVAL'] != null) {
    final n = int.tryParse(parts['INTERVAL']!);
    if (n == null || n < 1 || n > 999) return null;
    interval = n;
  }
  List<ByDay>? byday;
  if (parts['BYDAY'] != null) {
    byday = [];
    for (final tok in parts['BYDAY']!.split(',')) {
      final m = RegExp(r'^([+-]?\d{1,2})?(SU|MO|TU|WE|TH|FR|SA)$').firstMatch(tok);
      if (m == null) return null;
      final n = m.group(1) == null ? null : int.parse(m.group(1)!);
      byday.add(ByDay(wdCodes.indexOf(m.group(2)!), n));
    }
  }
  List<int>? ints(String? v) => v?.split(',').map(int.tryParse).whereType<int>().toList();
  final bmd = ints(parts['BYMONTHDAY']);
  final bm = ints(parts['BYMONTH']);
  final count = parts['COUNT'] == null ? null : int.tryParse(parts['COUNT']!);
  String? until;
  final u = parts['UNTIL'];
  if (u != null) {
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})').firstMatch(u);
    if (m == null) return null;
    until = '${m.group(1)}-${m.group(2)}-${m.group(3)}';
  }
  return Rule(freq: freq!, interval: interval, byday: byday, bymonthday: bmd, bymonth: bm, count: until != null ? null : count, until: until);
}

String _ordinal(int n) => n == -1 ? 'last' : (const ['', 'first', 'second', 'third', 'fourth', 'fifth'])[n.clamp(0, 5)];

String describeRule(Rule? r, [String? start]) {
  if (r == null) return 'Does not repeat';
  const unit = {'DAILY': 'day', 'WEEKLY': 'week', 'MONTHLY': 'month', 'YEARLY': 'year'};
  const single = {'DAILY': 'Daily', 'WEEKLY': 'Weekly', 'MONTHLY': 'Monthly', 'YEARLY': 'Yearly'};
  var s = r.interval == 1 ? single[r.freq]! : 'Every ${r.interval} ${unit[r.freq]}s';
  final weekdaysOnly = r.byday != null && r.byday!.length == 5 && [1, 2, 3, 4, 5].every((d) => r.byday!.any((b) => b.wd == d && b.n == null));
  if (r.freq == 'WEEKLY' && weekdaysOnly && r.interval == 1) {
    s = 'Every weekday (Mon–Fri)';
  } else if (r.freq == 'WEEKLY' && (r.byday?.isNotEmpty ?? false)) {
    s += ' on ${r.byday!.map((b) => wdShort[b.wd]).join(', ')}';
  } else if (r.freq == 'WEEKLY' && start != null) {
    s += ' on ${wdShort[weekdayOf(start)]}';
  }
  if (r.freq == 'MONTHLY') {
    if ((r.byday?.isNotEmpty ?? false) && r.byday!.first.n != null) {
      s += ' on the ${_ordinal(r.byday!.first.n!)} ${wdLong[r.byday!.first.wd]}';
    } else if (r.bymonthday?.isNotEmpty ?? false) {
      s += ' on day ${r.bymonthday!.map((d) => d == -1 ? 'last' : '$d').join(', ')}';
    } else if (start != null) {
      s += ' on day ${parseDate(start).day}';
    }
  }
  if (r.freq == 'YEARLY' && start != null) {
    final p = parseDate(start);
    s += ' on ${monthNames[p.month - 1]} ${p.day}';
  }
  if (r.count != null) {
    s += ', ${r.count} time${r.count == 1 ? '' : 's'}';
  } else if (r.until != null) {
    s += ', until ${r.until}';
  }
  return s;
}

String? _nthWeekday(int y, int m, int wd, int n) {
  final dim = daysInMonth(y, m);
  if (n > 0) {
    final first = weekdayOf(makeDate(y, m, 1));
    final day = 1 + ((wd - first + 7) % 7) + (n - 1) * 7;
    return day <= dim ? makeDate(y, m, day) : null;
  }
  final last = weekdayOf(makeDate(y, m, dim));
  final day = dim - ((last - wd + 7) % 7) + (n + 1) * 7;
  return day >= 1 ? makeDate(y, m, day) : null;
}

List<String> _monthDates(int y, int m, Rule r, String start) {
  final dim = daysInMonth(y, m);
  final out = <String>{};
  if (r.byday?.isNotEmpty ?? false) {
    for (final b in r.byday!) {
      if (b.n != null) {
        final d = _nthWeekday(y, m, b.wd, b.n!);
        if (d != null) out.add(d);
      } else {
        for (var day = 1; day <= dim; day++) {
          if (weekdayOf(makeDate(y, m, day)) == b.wd) out.add(makeDate(y, m, day));
        }
      }
    }
  } else if (r.bymonthday?.isNotEmpty ?? false) {
    for (final md in r.bymonthday!) {
      final day = md > 0 ? md : dim + md + 1;
      if (day >= 1 && day <= dim) out.add(makeDate(y, m, day));
    }
  } else {
    final day = parseDate(start).day;
    if (day <= dim) out.add(makeDate(y, m, day));
  }
  return out.toList()..sort();
}

/// Occurrence dates from [start] (always the first) up to [to] inclusive.
List<String> ruleDates(String start, Rule r, String to, [int limit = 5000]) {
  final out = <String>[start];
  final last = r.until != null && r.until!.compareTo(to) < 0 ? r.until! : to;
  final max = r.count != null && r.count! < limit ? r.count! : limit;
  final sp = parseDate(start);
  for (var k = 0; k < 20000 && out.length < max; k++) {
    String periodStart;
    List<String> dates;
    switch (r.freq) {
      case 'DAILY':
        periodStart = addDays(start, k * r.interval);
        dates = [periodStart];
      case 'WEEKLY':
        periodStart = addDays(startOfWeek(start, 1), k * 7 * r.interval);
        final wds = (r.byday?.isNotEmpty ?? false) ? r.byday!.map((b) => b.wd).toList() : [weekdayOf(start)];
        dates = wds.map((wd) => addDays(periodStart, (wd - 1 + 7) % 7)).toList()..sort();
      case 'MONTHLY':
        periodStart = makeDate(sp.year, sp.month + k * r.interval, 1);
        final p = parseDate(periodStart);
        dates = _monthDates(p.year, p.month, r, start);
      default:
        final y = sp.year + k * r.interval;
        periodStart = makeDate(y, 1, 1);
        dates = [];
        for (final m in (r.bymonth?.isNotEmpty ?? false) ? r.bymonth! : [sp.month]) {
          if ((r.byday?.isNotEmpty ?? false) || (r.bymonthday?.isNotEmpty ?? false)) {
            dates.addAll(_monthDates(y, m, r, start));
          } else if (sp.day <= daysInMonth(y, m)) {
            dates.add(makeDate(y, m, sp.day));
          }
        }
        dates.sort();
    }
    if (periodStart.compareTo(last) > 0) break;
    for (final d in dates) {
      if (d.compareTo(start) > 0 && d.compareTo(last) <= 0 && out.length < max) out.add(d);
    }
  }
  return out;
}

class Occurrence {
  Occurrence({
    required this.entry,
    required this.key,
    required this.allDay,
    required this.start,
    required this.end,
    required this.startDate,
    required this.endDate,
    this.startTime,
    this.endTime,
    required this.recurring,
  });
  final Entry entry;
  final String key;
  final bool allDay;
  final DateTime start;
  final DateTime end;
  final String startDate;
  final String endDate;
  final String? startTime;
  final String? endTime;
  final bool recurring;
}

/// Minute-precision UTC ISO key for a timed occurrence ("2026-12-01T04:30Z"), same as the web app.
String timeKey(DateTime d) {
  final u = d.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}T${two(u.hour)}:${two(u.minute)}Z';
}

/// Occurrences of [e] touching the wall-date range [from]..[to] in the device zone.
List<Occurrence> occurrences(Entry e, String from, String to, [int limit = 1000]) {
  final rule = parseRule(e.rrule);
  final ex = e.exdates.toSet();
  final out = <Occurrence>[];
  if (e.allDay || (e.startAt == null && e.startDate != null)) {
    final s = e.startDate;
    if (s == null) return out;
    final span = e.endDate == null ? 0 : diffDays(s, e.endDate!).clamp(0, 3650);
    for (final d in rule == null ? [s] : ruleDates(s, rule, to)) {
      final end = addDays(d, span);
      if (end.compareTo(from) < 0) continue;
      if (d.compareTo(to) > 0) break;
      if (ex.contains(d)) continue;
      out.add(Occurrence(
        entry: e,
        key: d,
        allDay: true,
        start: fromWall(d, '00:00'),
        end: fromWall(addDays(end, 1), '00:00'),
        startDate: d,
        endDate: end,
        recurring: rule != null,
      ));
      if (out.length >= limit) break;
    }
    return out;
  }
  final startAt = e.startAt;
  if (startAt == null) return out;
  final loc = location(e.timeZone) ?? localZone;
  final dur = e.endAt == null ? Duration.zero : e.endAt!.difference(startAt);
  final w = toWall(startAt, loc);
  for (final d in rule == null ? [w.date] : ruleDates(w.date, rule, addDays(to, 1))) {
    final s = rule == null ? startAt : fromWall(d, w.time, loc);
    final en = s.add(dur.isNegative ? Duration.zero : dur);
    final sw = toWall(s);
    final ew = toWall(dur > Duration.zero ? en.subtract(const Duration(milliseconds: 1)) : en);
    if (ew.date.compareTo(from) < 0) continue;
    if (sw.date.compareTo(to) > 0) {
      if (d.compareTo(addDays(to, 1)) > 0) break;
      continue;
    }
    final key = timeKey(s);
    if (ex.contains(key)) continue;
    out.add(Occurrence(
      entry: e,
      key: key,
      allDay: false,
      start: s,
      end: en,
      startDate: sw.date,
      endDate: ew.date,
      startTime: sw.time,
      endTime: toWall(en).time,
      recurring: rule != null,
    ));
    if (out.length >= limit) break;
  }
  return out;
}

/// Presets for the editor's Repeat menu.
List<({String label, String? rrule})> rulePresets(String start) {
  final wd = weekdayOf(start);
  final p = parseDate(start);
  final nth = ((p.day - 1) ~/ 7) + 1;
  final isLast = p.day + 7 > daysInMonth(p.year, p.month);
  return [
    (label: 'Does not repeat', rrule: null),
    (label: 'Daily', rrule: 'FREQ=DAILY'),
    (label: 'Weekly on ${wdLong[wd]}', rrule: 'FREQ=WEEKLY;BYDAY=${wdCodes[wd]}'),
    (label: 'Every weekday (Mon–Fri)', rrule: 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR'),
    (label: 'Monthly on day ${p.day}', rrule: 'FREQ=MONTHLY;BYMONTHDAY=${p.day}'),
    (label: 'Monthly on the ${_ordinal(nth)} ${wdLong[wd]}', rrule: 'FREQ=MONTHLY;BYDAY=$nth${wdCodes[wd]}'),
    if (isLast && nth != 5) (label: 'Monthly on the last ${wdLong[wd]}', rrule: 'FREQ=MONTHLY;BYDAY=-1${wdCodes[wd]}'),
    (label: 'Yearly on ${monthNames[p.month - 1]} ${p.day}', rrule: 'FREQ=YEARLY'),
  ];
}

/// Ends a rule the day before [date] ("this and following" changes).
String? endRuleBefore(String raw, String date) {
  final r = parseRule(raw);
  if (r == null) return null;
  return r.copyWith(clearCount: true, until: addDays(date, -1)).toString();
}

// ---------------------------------------------------------------------------- reminders

class DueReminder {
  DueReminder({required this.id, required this.entry, required this.occurrence, required this.minutes, required this.at});
  final String id;
  final Entry entry;
  final Occurrence occurrence;
  final int minutes;
  final DateTime at;
}

/// Reminders firing in [from]..[to]. All-day / date-only entries count from [allDayTime] on the day.
List<DueReminder> remindersBetween(Iterable<Entry> entries, DateTime from, DateTime to, {String allDayTime = '09:00'}) {
  final out = <DueReminder>[];
  final fromDate = toWall(from).date;
  final toDate = addDays(toWall(to).date, 29);
  for (final e in entries) {
    if (e.isDeleted || e.isDone || e.reminders.isEmpty) continue;
    for (final o in occurrences(e, addDays(fromDate, -1), toDate, 400)) {
      final base = o.allDay ? fromWall(o.startDate, allDayTime) : o.start;
      for (final m in e.reminders) {
        final at = base.subtract(Duration(minutes: m));
        if (!at.isBefore(from) && !at.isAfter(to)) {
          out.add(DueReminder(id: '${e.id}|${o.key}|$m', entry: e, occurrence: o, minutes: m, at: at));
        }
      }
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}
