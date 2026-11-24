import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../api.dart';
import '../planner_engine.dart';
import '../recurrence.dart';

const _example = '''{
  "events": [
    { "title": "Dentist", "date": "2026-12-01", "time": "10:00", "end_time": "11:00",
      "location": "City Clinic", "remind": ["1h", "10m"] },
    { "title": "Team standup", "date": "2026-12-01", "time": "9:30am", "duration": 15,
      "repeat": "weekdays", "remind": "5m" }
  ],
  "tasks": [
    { "title": "Pay rent", "due": "2026-12-01", "repeat": "monthly", "remind": "0" },
    { "title": "Renew passport", "due": "2027-01-15", "starred": true }
  ]
}''';

/// Import events and tasks from a file (.json, .ics, .txt) or pasted text, with a check before saving; export.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.engine});
  final PlannerEngine engine;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _text = TextEditingController();
  String _kind = 'event';
  String? _fileName;
  Map<String, dynamic>? _check;
  Map<String, dynamic>? _done;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    // Any file type: Android does not know every extension (.ics), so the content decides.
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty || picked.first.path == null) return;
    final f = picked.first;
    final bytes = await File(f.path!).readAsBytes();
    if (bytes.length > 4 * 1024 * 1024) {
      setState(() => _error = 'That file is over 4 MB. Split it into smaller files.');
      return;
    }
    setState(() {
      _fileName = f.name;
      _text.text = utf8.decode(bytes, allowMalformed: true);
      _check = null;
      _error = null;
    });
  }

  Future<void> _run(bool dry) async {
    if (_text.text.trim().isEmpty) {
      setState(() => _error = 'Choose a file or paste something first');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.engine.api.request('POST', '/v1/planner/import', body: {
        'text': _text.text,
        'dry_run': dry,
        'time_zone': localZoneName,
        'default_kind': _kind,
        'default_event_minutes': widget.engine.prefs.defaultEventMinutes,
      });
      setState(() => dry ? _check = r : _done = r);
      if (!dry) await widget.engine.sync();
    } on ApiException catch (e) {
      setState(() => _error = e.isOffline ? 'Importing needs a connection.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(String format) async {
    setState(() => _busy = true);
    try {
      final file = File(p.join((await getTemporaryDirectory()).path, 'dumpbox-planner-${DateTime.now().toIso8601String().substring(0, 10)}.$format'));
      if (format == 'json') {
        final d = await widget.engine.api.request('GET', '/v1/planner/export?format=json');
        await file.writeAsString(const JsonEncoder.withIndent('  ').convert(d));
      } else {
        // The .ics comes from the secret address (it is not JSON, so the JSON client cannot read it).
        final url = widget.engine.feedUrl;
        if (url == null) throw ApiException(0, 'offline', 'Sync once online, then try again.');
        final res = await HttpClient().getUrl(Uri.parse('$url&format=ics')).then((r) => r.close());
        await file.writeAsString(await res.transform(utf8.decoder).join());
      }
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: 'DumpBox calendar export'));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Export failed')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final done = _done;
    return Scaffold(
      appBar: AppBar(title: const Text('Import & export')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (done != null) ...[
          Text('Imported ${done['created']} new and updated ${done['updated']} (${done['events']} events, ${done['tasks']} tasks).', style: const TextStyle(fontSize: 16)),
          ..._errors(done),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => setState(() {
                _done = null;
                _check = null;
                _text.clear();
                _fileName = null;
              }), child: const Text('Import more')),
        ] else ...[
          Text('Google Calendar (.ics or JSON), Google Tasks JSON, a DumpBox export, your own JSON, or one item per line.', style: TextStyle(color: c.onSurfaceVariant)),
          const SizedBox(height: 12),
          Row(children: [
            FilledButton.tonalIcon(onPressed: _busy ? null : _pickFile, icon: const Icon(Icons.upload_file), label: const Text('Choose file')),
            const SizedBox(width: 8),
            TextButton(onPressed: () => setState(() => _text.text = _example), child: const Text('Insert example')),
          ]),
          if (_fileName != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_fileName!)),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 6,
            maxLines: 14,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            onChanged: (_) => setState(() => _check = null),
            decoration: const InputDecoration(labelText: 'Or paste / run JSON here', alignLabelWithHint: true),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'When the file does not say'),
            items: const [DropdownMenuItem(value: 'event', child: Text('Make events')), DropdownMenuItem(value: 'task', child: Text('Make tasks'))],
            onChanged: (v) => setState(() => _kind = v ?? 'event'),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: c.error))),
          if (_check != null) ...[
            const SizedBox(height: 12),
            Text('Found ${_check!['events']} events and ${_check!['tasks']} tasks (${_check!['format']}).', style: const TextStyle(fontWeight: FontWeight.w600)),
            for (final x in ((_check!['preview'] as List?) ?? const []).take(50))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon((x as Map)['kind'] == 'event' ? Icons.event : Icons.check_circle_outline, size: 18),
                title: Text('${x['title']}'),
                subtitle: Text(_when(x)),
              ),
            ..._errors(_check!),
          ],
          const SizedBox(height: 12),
          Row(children: [
            OutlinedButton(onPressed: _busy ? null : () => _run(true), child: const Text('Check')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy ? null : () => _run(false),
              child: Text(_busy ? 'Working…' : (_check != null ? 'Import ${(_check!['events'] as int) + (_check!['tasks'] as int)}' : 'Import')),
            ),
          ]),
        ],
        const Divider(height: 40),
        const Text('Export', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(onPressed: _busy ? null : () => _export('json'), icon: const Icon(Icons.data_object), label: const Text('JSON')),
          OutlinedButton.icon(onPressed: _busy ? null : () => _export('ics'), icon: const Icon(Icons.calendar_month), label: const Text('.ics (calendar apps)')),
        ]),
      ]),
    );
  }

  String _when(Map x) {
    if (x['start_at'] != null) {
      final s = toWall(DateTime.parse(x['start_at'] as String));
      final e = x['end_at'] != null ? '–${toWall(DateTime.parse(x['end_at'] as String)).time}' : '';
      return '${s.date} ${s.time}$e${x['rrule'] != null ? ' · repeats' : ''}';
    }
    if (x['start_date'] != null) return '${x['start_date']}${x['end_date'] != null ? ' → ${x['end_date']}' : ''}${x['rrule'] != null ? ' · repeats' : ''}';
    return 'No date';
  }

  List<Widget> _errors(Map<String, dynamic> r) {
    final errs = ((r['errors'] as List?) ?? const []).cast<String>();
    if (errs.isEmpty) return const [];
    return [
      const SizedBox(height: 8),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text('${errs.length} skipped or changed', style: const TextStyle(color: Colors.orange)),
        children: [for (final e in errs.take(100)) Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $e', style: const TextStyle(fontSize: 12))))],
      ),
    ];
  }
}
