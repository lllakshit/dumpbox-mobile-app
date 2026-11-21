import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../sync_engine.dart';
import 'item_actions.dart';
import 'item_card.dart';

/// Server search (typo tolerant, filters) when online; on-device search when offline.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.engine});
  final SyncEngine engine;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _q = TextEditingController();
  final Set<ItemType> _types = {};
  bool _starred = false;
  List<SearchHit>? _results;
  bool _busy = false;
  bool _offline = false;
  Timer? _debounce;
  int _seq = 0;

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _run);
  }

  Future<void> _run() async {
    final q = _q.text.trim();
    if (q.isEmpty && _types.isEmpty && !_starred) {
      setState(() => _results = null);
      return;
    }
    final mine = ++_seq;
    setState(() => _busy = true);
    try {
      final hits = await widget.engine.api.search({
        if (q.isNotEmpty) 'q': q,
        if (_types.isNotEmpty) 'type': _types.map((t) => t.name).join(','),
        if (_starred) 'starred': 'true',
        'limit': '50',
      });
      if (mine != _seq) return;
      setState(() {
        _results = hits;
        _offline = false;
      });
    } on ApiException catch (e) {
      if (mine != _seq) return;
      if (e.isOffline) {
        final local = widget.engine
            .searchLocal(q)
            .where((i) => (_types.isEmpty || _types.contains(i.type)) && (!_starred || i.starred))
            .map((i) => SearchHit(i, ''))
            .toList();
        setState(() {
          _results = local;
          _offline = true;
        });
      }
    } finally {
      if (mine == _seq && mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _q,
              onChanged: (_) => _changed(),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Notes, links, files, places, tags…', suffixIcon: _busy ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final t in ItemType.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(t.label),
                      selected: _types.contains(t),
                      onSelected: (v) {
                        setState(() => v ? _types.add(t) : _types.remove(t));
                        _run();
                      },
                    ),
                  ),
                FilterChip(
                  label: const Text('Starred'),
                  selected: _starred,
                  onSelected: (v) {
                    setState(() => _starred = v);
                    _run();
                  },
                ),
              ],
            ),
          ),
          if (_offline) Padding(padding: const EdgeInsets.all(8), child: Text('Offline: showing matches saved on this phone.', style: TextStyle(color: c.tertiary))),
          Expanded(
            child: _results == null
                ? Center(child: Text('Type to search. Spelling mistakes are fine.', style: TextStyle(color: c.onSurfaceVariant)))
                : _results!.isEmpty
                    ? Center(child: Text('Nothing found.', style: TextStyle(color: c.onSurfaceVariant)))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _results!.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final hit = _results![i];
                          final current = widget.engine.byId(hit.item.id) ?? hit.item;
                          return ItemCard(
                            item: current,
                            highlight: hit.highlight.contains('<mark>') ? _Highlighted(hit.highlight) : null,
                            onTap: () => showItemActions(context, widget.engine, current),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// Renders the API's <mark>…</mark> snippet with highlighted matches; everything else is plain text.
class _Highlighted extends StatelessWidget {
  const _Highlighted(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text.rich(TextSpan(style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant), children: highlightSpans(text)));
  }
}

const _markStyle = TextStyle(backgroundColor: Color(0x66FFD54F), fontWeight: FontWeight.w600);

/// Splits "a <mark>b</mark> c" into plain and highlighted spans.
List<TextSpan> highlightSpans(String text) {
  final spans = <TextSpan>[];
  var last = 0;
  for (final m in RegExp(r'<mark>(.*?)</mark>', dotAll: true).allMatches(text)) {
    if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
    spans.add(TextSpan(text: m.group(1), style: _markStyle));
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return spans;
}
