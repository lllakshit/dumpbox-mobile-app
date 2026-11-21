import 'package:flutter/material.dart';

import '../models.dart';
import '../sync_engine.dart';
import 'browse_screen.dart';
import 'feed_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

/// Bottom navigation: Feed, Search, Browse (smart views, tags, collections), Settings.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.engine, required this.email, required this.onSignOut});
  final SyncEngine engine;
  final String email;
  final Future<void> Function() onSignOut;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      FeedScreen(engine: widget.engine, view: const AllView(), isRoot: true),
      SearchScreen(engine: widget.engine),
      BrowseScreen(engine: widget.engine),
      SettingsScreen(engine: widget.engine, email: widget.email, onSignOut: widget.onSignOut),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Feed'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Browse'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
