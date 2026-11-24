import 'package:flutter/material.dart';

import '../api.dart';
import '../config.dart';
import '../planner/planner_engine.dart';
import '../planner/ui/planner_screen.dart';
import '../sync_engine.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.engine, this.planner, required this.email, required this.onSignOut});
  final SyncEngine engine;
  final PlannerEngine? planner;
  final String email;
  final Future<void> Function() onSignOut;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? _usage;

  @override
  void initState() {
    super.initState();
    widget.engine.api.me().then((d) {
      if (mounted) setState(() => _usage = d['usage'] as Map<String, dynamic>?);
    }).catchError((_) {});
  }

  Future<void> _deleteAccount() async {
    final typed = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Every item, file, tag, collection and share link is removed for good.'),
          const SizedBox(height: 12),
          TextField(controller: typed, decoration: const InputDecoration(labelText: 'Type DELETE to confirm')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
            onPressed: () => Navigator.pop(c, typed.text == 'DELETE'),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.engine.api.deleteAccount();
      await widget.onSignOut();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final u = _usage;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(leading: const Icon(Icons.person_outline), title: const Text('Signed in as'), subtitle: Text(widget.email)),
          if (u != null)
            ListTile(
              leading: const Icon(Icons.storage_outlined),
              title: const Text('Usage'),
              subtitle: Text('${u['items']} items · ${u['files']} files · ${((u['storage_bytes'] as num) / 1024 / 1024).toStringAsFixed(1)} MB'),
            ),
          ListenableBuilder(
            listenable: widget.engine,
            builder: (context, _) => ListTile(
              leading: Icon(widget.engine.online ? Icons.cloud_done_outlined : Icons.cloud_off),
              title: Text(widget.engine.online ? 'Online' : 'Offline'),
              subtitle: Text(widget.engine.lastSyncError ?? 'Changes made offline are sent when you reconnect.'),
              trailing: TextButton(onPressed: widget.engine.sync, child: const Text('Sync now')),
            ),
          ),
          ListTile(leading: const Icon(Icons.dns_outlined), title: const Text('Server'), subtitle: Text(AppConfig.apiBase)),
          if (widget.planner != null) ...[const Divider(), PlannerSettingsSection(engine: widget.planner!)],
          const Divider(),
          ListTile(leading: const Icon(Icons.logout), title: const Text('Sign out'), subtitle: const Text('Removes the copy stored on this phone'), onTap: widget.onSignOut),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: c.error),
            title: Text('Delete account', style: TextStyle(color: c.error)),
            onTap: _deleteAccount,
          ),
        ],
      ),
    );
  }
}
