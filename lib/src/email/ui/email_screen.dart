import 'dart:async';

import 'package:flutter/material.dart';

import '../../api.dart';
import '../../planner/planner_engine.dart';
import '../email_models.dart';
import 'email_thread_screen.dart';
import 'email_widgets.dart';

/// The Email tab: Gmail conversations brought in by the Gmail script, same data as the web app's Email section.
/// Changes from any device arrive through [hub] (live events) and a timed check while the tab is in front.
class EmailScreen extends StatefulWidget {
  const EmailScreen({super.key, required this.api, required this.planner, required this.hub, required this.active});
  final ApiClient api;
  final PlannerEngine planner;
  final EmailHub hub;

  /// True while this tab is the one on screen (the bottom bar keeps every tab alive).
  final bool active;

  @override
  State<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends State<EmailScreen> with WidgetsBindingObserver {
  EmailFilter _filter = const EmailFilter();
  String _query = '';
  bool _searching = false;
  final _search = TextEditingController();
  Timer? _typing;
  Timer? _poll;

  List<EmailThread> _threads = [];
  String? _cursor;
  int _pages = 1;
  bool _loading = false;
  String? _error;
  EmailCounts? _counts;
  int _seq = 0;
  Timer? _nudge;
  final _scaffold = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.hub.addListener(_onHub);
    _startPolling();
    if (widget.active) _reload();
  }

  @override
  void didUpdateWidget(EmailScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _refreshTop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.hub.removeListener(_onHub);
    _poll?.cancel();
    _typing?.cancel();
    _nudge?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) _refreshTop();
  }

  void _onHub() {
    _nudge?.cancel();
    _nudge = Timer(const Duration(milliseconds: 400), () {
      if (mounted && widget.active) _refreshTop();
    });
  }

  /// Safety net for networks where live events cannot connect: check every 20 s while this tab is in front.
  void _startPolling() {
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && widget.active && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) _refreshTop();
    });
  }

  String _fail(Object e) => e is ApiException ? (e.isOffline ? 'Email needs a connection.' : e.message) : 'Something went wrong';

  Future<void> _loadCounts() async {
    try {
      final c = await widget.api.emailCounts();
      if (mounted) setState(() => _counts = c);
    } catch (_) {
      // counts are a nice-to-have
    }
  }

  Future<void> _reload() async {
    final mine = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    unawaited(_loadCounts());
    try {
      final r = await widget.api.emailThreads(_filter, query: _query);
      if (!mounted || mine != _seq) return;
      setState(() {
        _threads = r.threads;
        _cursor = r.next;
        _pages = 1;
      });
    } catch (e) {
      if (mounted && mine == _seq) setState(() => _error = _fail(e));
    } finally {
      if (mounted && mine == _seq) setState(() => _loading = false);
    }
  }

  Future<void> _more() async {
    if (_cursor == null || _loading) return;
    final mine = ++_seq;
    setState(() => _loading = true);
    try {
      final r = await widget.api.emailThreads(_filter, query: _query, cursor: _cursor);
      if (!mounted || mine != _seq) return;
      final have = _threads.map((t) => t.id).toSet();
      setState(() {
        _threads = [..._threads, ...r.threads.where((t) => !have.contains(t.id))];
        _cursor = r.next;
        _pages++;
      });
    } catch (e) {
      if (mounted && mine == _seq) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_fail(e))));
    } finally {
      if (mounted && mine == _seq) setState(() => _loading = false);
    }
  }

  /// Background refresh: page 1 again, merged so pages loaded with scrolling stay. Never shows an error.
  Future<void> _refreshTop() async {
    final at = _seq;
    unawaited(_loadCounts());
    try {
      final r = await widget.api.emailThreads(_filter, query: _query);
      if (!mounted || at != _seq) return;
      setState(() {
        if (_pages <= 1) {
          _threads = r.threads;
          _cursor = r.next;
        } else {
          final ids = r.threads.map((t) => t.id).toSet();
          final oldest = r.threads.isEmpty ? null : r.threads.last.lastMessageAt;
          _threads = [...r.threads, ..._threads.where((p) => !ids.contains(p.id) && (oldest == null || !p.lastMessageAt.isAfter(oldest)))];
        }
        _error = null;
      });
    } catch (_) {
      // a failed background check changes nothing
    }
  }

  void _setFilter(EmailFilter f) {
    _scaffold.currentState?.closeDrawer();
    if (f == _filter) return;
    setState(() {
      _filter = f;
      _threads = [];
    });
    _reload();
  }

  void _onSearch(String v) {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 350), () {
      if (_query == v.trim()) return;
      _query = v.trim();
      _reload();
    });
  }

  Future<void> _open(EmailThread t) async {
    final result = await Navigator.of(context).push<EmailThreadResult>(
      MaterialPageRoute(builder: (_) => EmailThreadScreen(api: widget.api, planner: widget.planner, threadId: t.id)),
    );
    if (!mounted) return;
    if (result?.label != null) {
      _setFilter(EmailFilter(label: result!.label));
      return;
    }
    setState(() {
      if (result?.deleted == true) {
        _threads = _threads.where((x) => x.id != t.id).toList();
      } else if (result?.thread != null) {
        final u = result!.thread!;
        final gone = (_filter.view == 'archived') == u.inInbox || (_filter.view == 'pinned' && !u.pinned);
        _threads = gone ? _threads.where((x) => x.id != u.id).toList() : [for (final x in _threads) x.id == u.id ? u : x];
      }
    });
    unawaited(_loadCounts());
  }

  @override
  Widget build(BuildContext context) {
    final noMailAtAll = _counts != null && _counts!.all.total == 0 && _counts!.archived == 0;
    return Scaffold(
      key: _scaffold,
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                onChanged: _onSearch,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(hintText: 'Search subject, people, text', border: InputBorder.none, filled: false),
              )
            : Text(_filter.title),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search mail',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() => _searching = !_searching);
              if (!_searching && _query.isNotEmpty) {
                _search.clear();
                _query = '';
                _reload();
              }
            },
          ),
        ],
      ),
      drawer: Drawer(child: SafeArea(child: EmailFolders(counts: _counts, current: _filter, onPick: _setFilter))),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: Builder(builder: (context) {
          if (noMailAtAll) return const _Empty();
          if (_error != null && _threads.isEmpty) {
            return ListView(children: [
              const SizedBox(height: 80),
              Center(child: Text(_error!, textAlign: TextAlign.center)),
              Center(child: TextButton(onPressed: _reload, child: const Text('Try again'))),
            ]);
          }
          if (_threads.isEmpty) {
            return ListView(children: [
              const SizedBox(height: 80),
              Center(child: _loading ? const CircularProgressIndicator() : Text(_query.isNotEmpty ? 'No conversations match.' : 'Nothing here.')),
            ]);
          }
          return NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) _more();
              return false;
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _threads.length + 1,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                if (i == _threads.length) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const SizedBox.shrink()),
                  );
                }
                return EmailRow(thread: _threads[i], onTap: () => _open(_threads[i]));
              },
            ),
          );
        }),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const SizedBox(height: 40),
        Icon(Icons.mail_outline, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Text('No email yet', style: t.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          'Connect Gmail once from a computer: open DumpBox on the web → Settings → Email → Make import key → Copy script, '
          'then paste it at script.google.com. Your labelled conversations then show here and on the web.',
          style: t.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
