/// Changing part of a repeating series ("this event", "this and following", "all events"). Same rules as the web
/// app (src/lib/planner/series.ts): occurrence dates are taken in the entry's own zone, never the device's.
library;

import 'planner_models.dart';
import 'recurrence.dart';

String? seriesStart(Entry e) {
  if (e.startDate != null) return e.startDate;
  if (e.startAt != null) return toWall(e.startAt!, location(e.timeZone)).date;
  return null;
}

/// An occurrence's date in the entry's zone.
String occurrenceDate(Entry e, {required String key, required DateTime start}) {
  if (e.allDay || e.startDate != null) return key;
  return toWall(start, location(e.timeZone)).date;
}

DateTime _keyInstant(String k) => DateTime.parse(k.endsWith('Z') && k.length == 17 ? '${k.substring(0, 16)}:00Z' : k);

/// "This and following": the old series ends the day before [splitDate] (null rule = remove it entirely); the new
/// one carries the remaining COUNT and the skipped dates after the split.
({String? oldRule, List<String> oldExdates, String? newRule, List<String> newExdates}) splitSeries(Entry e, String splitDate, String? newRuleRaw) {
  final rule = parseRule(e.rrule);
  final first = seriesStart(e);
  if (rule == null || first == null) return (oldRule: null, oldExdates: e.exdates, newRule: newRuleRaw, newExdates: const <String>[]);
  final before = splitDate.compareTo(first) > 0 ? ruleDates(first, rule, addDays(splitDate, -1), 1000000).length : 0;
  final oldRule = before == 0 ? null : rule.copyWith(clearCount: true, until: addDays(splitDate, -1)).toString();
  var newRule = newRuleRaw;
  final nr = parseRule(newRuleRaw);
  if (nr != null && rule.count != null && nr.count == rule.count) {
    final left = rule.count! - before;
    newRule = left > 0 ? nr.copyWith(count: left).toString() : null;
  }
  bool isAfter(String k) => k.length == 10 ? k.compareTo(splitDate) >= 0 : toWall(_keyInstant(k), location(e.timeZone)).date.compareTo(splitDate) >= 0;
  return (oldRule: oldRule, oldExdates: e.exdates.where((k) => !isAfter(k)).toList(), newRule: newRule, newExdates: e.exdates.where(isAfter).toList());
}

/// "All events" moved: skipped dates move with it.
List<String> shiftExdates(List<String> exdates, {Duration by = Duration.zero, int days = 0}) => exdates.map((k) {
      if (k.length == 10) return days == 0 ? k : addDays(k, days);
      if (by == Duration.zero) return k;
      return timeKey(_keyInstant(k).add(by));
    }).toList();
