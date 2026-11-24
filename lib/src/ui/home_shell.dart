import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../planner/notifications.dart';
import '../planner/planner_engine.dart';
import '../planner/ui/entry_editor.dart';
import '../planner/ui/planner_screen.dart';
import '../sync_engine.dart';
import 'browse_screen.dart';
import 'feed_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

/// Bottom navigation: Feed, Planner (calendar + tasks), Search, Browse (smart views, tags, collections), Settings.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.engine, required this.planner, required this.email, required this.onSignOut});
  final SyncEngine engine;
  final PlannerEngine planner;
  final String email;
  final Future<void> Function() onSignOut;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    PlannerNotifications.instance.tapped.addListener(_onNotification);
    // A tap that opened the app arrives before this screen exists.
    if (PlannerNotifications.instance.tapped.value != null) scheduleMicrotask(_onNotification);
  }

  @override
  void dispose() {
    PlannerNotifications.instance.tapped.removeListener(_onNotification);
    super.dispose();
  }

  /// "done", "snooze" or "open" from a reminder.
  Future<void> _onNotification() async {
    final v = PlannerNotifications.instance.tapped.value;
    if (v == null || !mounted) return;
    PlannerNotifications.instance.tapped.value = null;
    final parts = v.split(':');
    if (parts.length < 2) return;
    final action = parts[0];
    final planner = widget.planner;
    var e = planner.byId(parts[1]);
    if (e == null) {
      await planner.sync();
      e = planner.byId(parts[1]);
    }
    if (e == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    switch (action) {
      case 'done':
        if (!e.isDone) await planner.toggleDone(e);
        messenger.showSnackBar(SnackBar(content: Text('Done: ${e.title}')));
      case 'snooze':
        await PlannerNotifications.instance.snooze(e);
        messenger.showSnackBar(SnackBar(content: Text('Reminder in 10 minutes: ${e.title}')));
      default:
        setState(() => _tab = 1);
        await openEntryEditor(context, planner, entry: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      FeedScreen(engine: widget.engine, view: const AllView(), isRoot: true),
      PlannerScreen(engine: widget.planner),
      SearchScreen(engine: widget.engine),
      BrowseScreen(engine: widget.engine),
      SettingsScreen(engine: widget.engine, planner: widget.planner, email: widget.email, onSignOut: widget.onSignOut),
    ];
    return PlannerScope(
      engine: widget.planner,
      child: Scaffold(
        body: IndexedStack(index: _tab, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Feed'),
            NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Planner'),
            NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
            NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Browse'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}
