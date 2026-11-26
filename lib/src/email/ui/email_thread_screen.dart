import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api.dart';
import '../../planner/planner_engine.dart';
import '../email_models.dart';
import 'email_widgets.dart';

/// What the list should do after the conversation closes.
class EmailThreadResult {
  const EmailThreadResult({this.thread, this.deleted = false, this.label});
  final EmailThread? thread;
  final bool deleted;

  /// A label chip was tapped: show that label.
  final String? label;
}

/// One conversation: messages oldest → newest, older ones folded like Gmail. Opening it marks it seen on every device.
class EmailThreadScreen extends StatefulWidget {
  const EmailThreadScreen({super.key, required this.api, required this.planner, required this.threadId});
  final ApiClient api;
  final PlannerEngine planner;
  final String threadId;

  @override
  State<EmailThreadScreen> createState() => _EmailThreadScreenState();
}

class _EmailThreadScreenState extends State<EmailThreadScreen> {
  EmailThread? _thread;
  List<EmailMessage> _messages = [];
  final Set<String> _open = {};
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.emailThread(widget.threadId);
      if (!mounted) return;
      setState(() {
        _thread = r.thread;
        _messages = r.messages;
        _error = null;
        // The last message and anything unread in Gmail start open.
        _open
          ..clear()
          ..addAll(r.messages.where((m) => m.unread || m == r.messages.last).map((m) => m.id));
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.isOffline ? 'This conversation needs a connection.' : e.message);
    }
  }

  void _close([EmailThreadResult? r]) => Navigator.of(context).pop(r ?? EmailThreadResult(thread: _thread));

  Future<void> _act(Future<void> Function() run) async {
    setState(() => _busy = true);
    try {
      await run();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.isOffline ? 'You are offline. Try again when connected.' : e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pin() => _act(() async {
        final t = await widget.api.updateEmailThread(_thread!.id, pinned: !_thread!.pinned);
        if (mounted) setState(() => _thread = t);
      });

  Future<void> _archive() => _act(() async {
        final t = await widget.api.updateEmailThread(_thread!.id, archived: _thread!.archivedAt == null);
        if (!mounted) return;
        setState(() => _thread = t);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.archivedAt != null ? 'Archived in DumpBox (Gmail unchanged)' : 'Back in the inbox')));
      });

  Future<void> _task() => _act(() async {
        final t = _thread!;
        final from = t.fromName ?? t.fromEmail ?? '';
        await widget.planner.create({
          'kind': 'task',
          'title': t.subject.isEmpty ? 'Email' : (t.subject.length > 1000 ? t.subject.substring(0, 1000) : t.subject),
          'notes': '${from.isNotEmpty ? 'From $from\n' : ''}${t.gmailUrl}',
          'starred': t.priority == 1,
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task added')));
      });

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete from DumpBox?'),
        content: const Text('Its text is removed here for good and the Gmail script will not bring it back. Gmail is not changed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await _act(() async {
      await widget.api.deleteEmailThread(_thread!.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted from DumpBox')));
      _close(const EmailThreadResult(deleted: true));
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = _thread;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _close),
          actions: t == null
              ? null
              : [
                  IconButton(
                    tooltip: t.pinned ? 'Unpin' : 'Pin',
                    isSelected: t.pinned,
                    icon: const Icon(Icons.push_pin_outlined),
                    selectedIcon: const Icon(Icons.push_pin),
                    onPressed: _busy ? null : _pin,
                  ),
                  IconButton(
                    tooltip: t.archivedAt != null ? 'Move to inbox' : 'Archive',
                    icon: Icon(t.archivedAt != null ? Icons.unarchive_outlined : Icons.archive_outlined),
                    onPressed: _busy ? null : _archive,
                  ),
                  IconButton(tooltip: 'Make a task', icon: const Icon(Icons.task_alt), onPressed: _busy ? null : _task),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'gmail') launchUrl(t.gmailUrl, mode: LaunchMode.externalApplication);
                      if (v == 'delete') _delete();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'gmail', child: ListTile(leading: Icon(Icons.open_in_new), title: Text('Open in Gmail'))),
                      PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete from DumpBox'))),
                    ],
                  ),
                ],
        ),
        body: _error != null
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!), TextButton(onPressed: _load, child: const Text('Try again'))]))
            : t == null
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 32), children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: Text(t.subject.isEmpty ? '(no subject)' : t.subject, style: Theme.of(context).textTheme.titleLarge)),
                        if (t.starred) const Padding(padding: EdgeInsets.only(left: 6, top: 4), child: Icon(Icons.star, color: Color(0xFFE0A526), semanticLabel: 'Starred in Gmail')),
                      ]),
                      EmailChips(thread: t, onLabel: (l) => _close(EmailThreadResult(thread: _thread, label: l))),
                      if (!t.inScope)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
                          child: Text('This conversation no longer has a label the Gmail script brings in, so it is kept under Archived.', style: Theme.of(context).textTheme.bodySmall),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: Row(children: [
                          Text(
                            '${t.messageCount} message${t.messageCount == 1 ? '' : 's'}${t.messageCount > _messages.length ? ' (latest ${_messages.length} here)' : ''}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          const Spacer(),
                          if (_messages.length > 1)
                            TextButton(
                              onPressed: () => setState(() {
                                final all = _open.length == _messages.length;
                                _open
                                  ..clear()
                                  ..addAll(all ? [_messages.last.id] : _messages.map((m) => m.id));
                              }),
                              child: Text(_open.length == _messages.length ? 'Collapse all' : 'Expand all'),
                            ),
                        ]),
                      ),
                      for (final m in _messages)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _MessageCard(
                            message: m,
                            open: _open.contains(m.id),
                            onToggle: () => setState(() => _open.contains(m.id) ? _open.remove(m.id) : _open.add(m.id)),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Center(
                          child: TextButton.icon(
                            onPressed: () => launchUrl(t.gmailUrl, mode: LaunchMode.externalApplication),
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('Reply and attachments are in Gmail'),
                          ),
                        ),
                      ),
                    ]),
                  ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, required this.open, required this.onToggle});
  final EmailMessage message;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final c = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final initial = RegExp(r'[\p{L}\p{N}]', unicode: true).firstMatch(m.sender)?.group(0)?.toUpperCase() ?? '?';
    final preview = m.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Container(
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 17, backgroundColor: c.primary.withValues(alpha: 0.14), child: Text(initial, style: TextStyle(color: c.primary, fontWeight: FontWeight.w600))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(m.sender, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                    Text(DateFormat('d MMM, h:mm a').format(m.sentAt.toLocal()), style: text.labelSmall?.copyWith(color: c.onSurfaceVariant)),
                  ]),
                  Text(
                    open ? 'to ${m.to ?? '—'}${m.cc != null && m.cc!.isNotEmpty ? ' · cc ${m.cc}' : ''}' : preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
                  ),
                ]),
              ),
            ]),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (m.fromName != null && m.fromEmail != null) Text(m.fromEmail!, style: text.labelSmall?.copyWith(color: c.onSurfaceVariant)),
              const SizedBox(height: 6),
              m.body.isEmpty ? Text('(no text)', style: text.bodyMedium?.copyWith(color: c.onSurfaceVariant)) : LinkedText(m.body),
              if (m.attachments.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final a in m.attachments)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.attach_file, size: 14),
                      label: Text('${a.name}${a.size != null ? ' · ${(a.size! / 1024).ceil()} KB' : ''}', overflow: TextOverflow.ellipsis),
                    ),
                ]),
              ],
            ]),
          ),
      ]),
    );
  }
}

/// Selectable text with web links that open in the browser.
class LinkedText extends StatefulWidget {
  const LinkedText(this.text, {super.key});
  final String text;

  @override
  State<LinkedText> createState() => _LinkedTextState();
}

class _LinkedTextState extends State<LinkedText> {
  final List<TapGestureRecognizer> _taps = [];
  static final _url = RegExp(r'''https?://[^\s<>"']+''');

  @override
  void dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45);
    final link = style?.copyWith(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline);
    final spans = <TextSpan>[];
    var at = 0;
    for (final m in _url.allMatches(widget.text)) {
      if (m.start > at) spans.add(TextSpan(text: widget.text.substring(at, m.start)));
      final url = m.group(0)!;
      final tap = TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      _taps.add(tap);
      spans.add(TextSpan(text: url, style: link, recognizer: tap));
      at = m.end;
    }
    if (at < widget.text.length) spans.add(TextSpan(text: widget.text.substring(at)));
    return SelectableText.rich(TextSpan(style: style, children: spans));
  }
}
