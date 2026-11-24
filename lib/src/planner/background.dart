import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workmanager/workmanager.dart';

import 'notifications.dart';
import 'planner_models.dart';

const _task = 'planner-reminders';

/// Remembers, outside any account database, where the background check finds the signed-in user's calendar.
/// Holds only the calendar address (a revocable read-only key) and the database file name — never a sign-in token.
class BackgroundConfig {
  static Future<File> _file() async => File(p.join((await getApplicationSupportDirectory()).path, 'planner-background.json'));

  static Future<void> save({required String feedUrl, required String dbPath}) async {
    final f = await _file();
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode({'feed_url': feedUrl, 'db_path': dbPath}));
  }

  static Future<Map<String, dynamic>?> read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final f = await _file();
    if (await f.exists()) await f.delete();
  }
}

/// Starts the check that runs about every 15 minutes (Android decides the exact time, and runs it only online).
Future<void> startBackgroundReminders() async {
  await Workmanager().initialize(plannerBackgroundDispatcher);
  await Workmanager().registerPeriodicTask(
    _task,
    _task,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

Future<void> stopBackgroundReminders() async {
  try {
    await Workmanager().cancelByUniqueName(_task);
  } catch (_) {
    // not started
  }
  await BackgroundConfig.clear();
}

/// Runs in the background (app closed): reads the calendar through its secret address, keeps any changes still
/// waiting on this phone, and reschedules every reminder. It never signs in and never writes the account database.
@pragma('vm:entry-point')
void plannerBackgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final cfg = await BackgroundConfig.read();
      final url = cfg?['feed_url'] as String?;
      if (url == null) return true;
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) return true;
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final server = {
        for (final x in (data['entries'] as List? ?? const [])) (x as Map<String, dynamic>)['id'] as String: Entry.fromJson(x),
      };
      // Changes made on this phone that have not reached the server yet win over the server's copy.
      final dbPath = cfg?['db_path'] as String?;
      if (dbPath != null && await File(dbPath).exists()) {
        final db = await openDatabase(dbPath, readOnly: true, singleInstance: false);
        try {
          final pending = (await db.rawQuery('SELECT DISTINCT entry_id FROM outbox')).map((r) => r['entry_id'] as String).toSet();
          if (pending.isNotEmpty) {
            final rows = await db.query('entries', where: 'id IN (${List.filled(pending.length, '?').join(',')})', whereArgs: pending.toList());
            for (final r in rows) {
              final e = Entry.fromJson(jsonDecode(r['data'] as String) as Map<String, dynamic>);
              server[e.id] = e;
            }
          }
        } finally {
          await db.close();
        }
      }
      final prefs = PlannerPrefs.fromJson(data['prefs'] as Map<String, dynamic>?);
      await PlannerNotifications.instance.init(background: true);
      await PlannerNotifications.instance.reschedule(server.values.where((e) => !e.isDeleted), prefs);
    } catch (e) {
      debugPrint('Background reminder check failed: $e');
    }
    return true;
  });
}
