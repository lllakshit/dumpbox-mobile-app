import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api.dart';
import '../config.dart';
import '../local_store.dart';
import '../sync_engine.dart';
import 'file_urls.dart';
import 'home_shell.dart';
import 'login_screen.dart';

/// Shows sign-in or the app, and owns the sync engine for the signed-in user.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  final _auth = Supabase.instance.client.auth;
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<List<ConnectivityResult>>? _netSub;
  RealtimeChannel? _channel;
  Timer? _periodic;
  SyncEngine? _engine;
  String? _userId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _onSession(_auth.currentSession);
    _authSub = _auth.onAuthStateChange.listen((s) => _onSession(s.session));
  }

  Future<void> _onSession(Session? session) async {
    final uid = session?.user.id;
    if (uid == _userId) return;
    await _stopEngine();
    _userId = uid;
    if (uid == null) {
      if (mounted) setState(() {});
      return;
    }
    final docs = await getApplicationDocumentsDirectory();
    final store = await LocalStore.open(path: p.join(docs.path, 'dumpbox-$uid.db'));
    final api = ApiClient(tokenProvider: () async => _auth.currentSession?.accessToken);
    final engine = SyncEngine(store: store, api: api, filesDir: Directory(p.join(docs.path, 'outbox-$uid')));
    FileUrls.api = api;
    FileUrls.clear();
    await engine.init();
    if (!mounted || _userId != uid) return;
    setState(() => _engine = engine);

    if (AppConfig.realtimeAvailable) {
      _channel = Supabase.instance.client
          .channel('items:$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'items',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
            callback: (_) => engine.nudge(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'item_tombstones',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
            callback: (_) => engine.nudge(),
          )
          .subscribe();
    }
    _netSub = Connectivity().onConnectivityChanged.listen((r) => engine.setOnline(!r.contains(ConnectivityResult.none)));
    // With realtime, a slow safety check; through the proxy, check every 20 s while the app is in front.
    _periodic = Timer.periodic(AppConfig.realtimeAvailable ? const Duration(minutes: 1) : const Duration(seconds: 20), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) engine.nudge();
    });
    engine.nudge(Duration.zero);
  }

  Future<void> _stopEngine() async {
    _periodic?.cancel();
    await _netSub?.cancel();
    if (_channel != null) await Supabase.instance.client.removeChannel(_channel!);
    _channel = null;
    final e = _engine;
    _engine = null;
    if (e != null) {
      e.dispose();
      await e.store.close();
    }
  }

  Future<void> signOut() async {
    final e = _engine;
    if (e != null) await e.wipe();
    await _auth.signOut();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _engine?.nudge();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _stopEngine();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_userId == null) return const LoginScreen();
    final engine = _engine;
    if (engine == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return HomeShell(engine: engine, email: _auth.currentUser?.email ?? '', onSignOut: signOut);
  }
}

class NotConfiguredScreen extends StatelessWidget {
  const NotConfiguredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'This build has no server settings.\n\nBuild with --dart-define-from-file=config/<env>.json '
            '(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, API_BASE_URL).',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
