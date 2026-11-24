/// Events, tasks, calendars and task lists, as returned by /v1/planner.
library;

class PlannerList {
  PlannerList({
    required this.id,
    required this.kind,
    required this.name,
    required this.color,
    this.isDefault = false,
    this.hidden = false,
    this.position = 0,
    this.version = 1,
  });

  final String id;

  /// calendar | tasks
  final String kind;
  final String name;
  final String color;
  final bool isDefault;
  final bool hidden;
  final int position;
  final int version;

  bool get isCalendar => kind == 'calendar';

  factory PlannerList.fromJson(Map<String, dynamic> j) => PlannerList(
        id: j['id'] as String,
        kind: j['kind'] as String,
        name: j['name'] as String,
        color: j['color'] as String? ?? '#3a5bd9',
        isDefault: j['is_default'] as bool? ?? false,
        hidden: j['hidden'] as bool? ?? false,
        position: (j['position'] as num?)?.toInt() ?? 0,
        version: (j['version'] as num?)?.toInt() ?? 1,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'name': name,
        'color': color,
        'is_default': isDefault,
        'hidden': hidden,
        'position': position,
        'version': version,
      };

  PlannerList copyWith({String? name, String? color, bool? hidden}) => PlannerList(
        id: id,
        kind: kind,
        name: name ?? this.name,
        color: color ?? this.color,
        isDefault: isDefault,
        hidden: hidden ?? this.hidden,
        position: position,
        version: version,
      );
}

class Entry {
  Entry({
    required this.id,
    required this.kind,
    required this.title,
    this.listId,
    this.parentId,
    this.notes,
    this.location,
    this.allDay = false,
    this.startAt,
    this.endAt,
    this.startDate,
    this.endDate,
    this.timeZone,
    this.rrule,
    this.exdates = const [],
    this.reminders = const [],
    this.color,
    this.completedAt,
    this.starred = false,
    this.position = 0,
    this.sourceItemId,
    this.externalId,
    this.deletedAt,
    this.version = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// event | task
  final String kind;
  final String title;
  final String? listId;
  final String? parentId;
  final String? notes;
  final String? location;
  final bool allDay;

  /// Timed entries (UTC instants).
  final DateTime? startAt;
  final DateTime? endAt;

  /// All-day / date-only entries: "YYYY-MM-DD" (end inclusive).
  final String? startDate;
  final String? endDate;
  final String? timeZone;
  final String? rrule;
  final List<String> exdates;
  final List<int> reminders;
  final String? color;
  final DateTime? completedAt;
  final bool starred;
  final double position;
  final String? sourceItemId;
  final String? externalId;
  final DateTime? deletedAt;

  /// 0 means "made on this device, not confirmed by the server yet".
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isEvent => kind == 'event';
  bool get isTask => kind == 'task';
  bool get isDone => completedAt != null;
  bool get isDeleted => deletedAt != null;
  bool get hasDate => startAt != null || startDate != null;
  bool get repeats => rrule != null && rrule!.isNotEmpty;

  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
        id: j['id'] as String,
        kind: j['kind'] as String? ?? 'task',
        title: j['title'] as String? ?? '',
        listId: j['list_id'] as String?,
        parentId: j['parent_id'] as String?,
        notes: j['notes'] as String?,
        location: j['location'] as String?,
        allDay: j['all_day'] as bool? ?? false,
        startAt: _instant(j['start_at']),
        endAt: _instant(j['end_at']),
        startDate: j['start_date'] as String?,
        endDate: j['end_date'] as String?,
        timeZone: j['time_zone'] as String?,
        rrule: j['rrule'] as String?,
        exdates: ((j['exdates'] as List?) ?? const []).cast<String>(),
        reminders: ((j['reminders'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
        color: j['color'] as String?,
        completedAt: _instant(j['completed_at']),
        starred: j['starred'] as bool? ?? false,
        position: (j['position'] as num?)?.toDouble() ?? 0,
        sourceItemId: j['source_item_id'] as String?,
        externalId: j['external_id'] as String?,
        deletedAt: _instant(j['deleted_at']),
        version: (j['version'] as num?)?.toInt() ?? 0,
        createdAt: _instant(j['created_at']) ?? DateTime.now().toUtc(),
        updatedAt: _instant(j['updated_at']) ?? DateTime.now().toUtc(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'list_id': listId,
        'parent_id': parentId,
        'notes': notes,
        'location': location,
        'all_day': allDay,
        'start_at': startAt?.toUtc().toIso8601String(),
        'end_at': endAt?.toUtc().toIso8601String(),
        'start_date': startDate,
        'end_date': endDate,
        'time_zone': timeZone,
        'rrule': rrule,
        'exdates': exdates,
        'reminders': reminders,
        'color': color,
        'completed_at': completedAt?.toUtc().toIso8601String(),
        'starred': starred,
        'position': position,
        'source_item_id': sourceItemId,
        'external_id': externalId,
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
        'version': version,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  /// Applies a request body (the same fields the API takes) to this entry, for showing a change before it is sent.
  Entry applyPatch(Map<String, dynamic> p) {
    final j = toJson();
    for (final k in p.keys) {
      if (k == 'completed') {
        j['completed_at'] = p[k] == true ? (completedAt ?? DateTime.now().toUtc()).toIso8601String() : null;
      } else if (k == 'deleted') {
        j['deleted_at'] = p[k] == true ? DateTime.now().toUtc().toIso8601String() : null;
      } else if (k != 'base_version') {
        j[k] = p[k];
      }
    }
    return Entry.fromJson(j);
  }
}

DateTime? _instant(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toUtc() : null;

class PlannerPrefs {
  const PlannerPrefs({
    this.weekStart = 1,
    this.defaultEventMinutes = 60,
    this.defaultEventReminders = const [10],
    this.defaultTaskReminders = const [0],
    this.allDayReminderTime = '09:00',
  });

  final int weekStart;
  final int defaultEventMinutes;
  final List<int> defaultEventReminders;
  final List<int> defaultTaskReminders;
  final String allDayReminderTime;

  factory PlannerPrefs.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const PlannerPrefs();
    List<int> ints(Object? v, List<int> d) => v is List ? v.map((e) => (e as num).toInt()).toList() : d;
    return PlannerPrefs(
      weekStart: (j['week_start'] as num?)?.toInt() ?? 1,
      defaultEventMinutes: (j['default_event_minutes'] as num?)?.toInt() ?? 60,
      defaultEventReminders: ints(j['default_event_reminders'], const [10]),
      defaultTaskReminders: ints(j['default_task_reminders'], const [0]),
      allDayReminderTime: j['all_day_reminder_time'] as String? ?? '09:00',
    );
  }

  Map<String, dynamic> toJson() => {
        'week_start': weekStart,
        'default_event_minutes': defaultEventMinutes,
        'default_event_reminders': defaultEventReminders,
        'default_task_reminders': defaultTaskReminders,
        'all_day_reminder_time': allDayReminderTime,
      };
}

/// "15 minutes before", "1 hour before", "1 day before", "At start time".
String reminderLabel(int min, {bool allDay = false}) {
  if (min == 0) return allDay ? 'On the day' : 'At start time';
  if (min % 10080 == 0) return '${min ~/ 10080} week${min == 10080 ? '' : 's'} before';
  if (min % 1440 == 0) return '${min ~/ 1440} day${min == 1440 ? '' : 's'} before';
  if (min % 60 == 0) return '${min ~/ 60} hour${min == 60 ? '' : 's'} before';
  return '$min minutes before';
}

const reminderChoices = [0, 5, 10, 15, 30, 60, 120, 1440, 2880, 10080];
