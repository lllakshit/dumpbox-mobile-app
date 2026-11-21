import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';

import '../models.dart';
import '../sync_engine.dart';
import 'item_actions.dart';
import 'item_card.dart';

/// Chat-style list of items for one view, newest at the bottom, with the capture bar.
class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key, required this.engine, required this.view, this.isRoot = false});
  final SyncEngine engine;
  final FeedView view;
  final bool isRoot;

  @override
  Widget build(BuildContext context) {
    final trash = view is FlagView && (view as FlagView).flag == 'trash';
    return Scaffold(
      appBar: AppBar(
        title: Text(view.title),
        actions: [
          ListenableBuilder(
            listenable: engine,
            builder: (context, _) {
              if (!engine.online) {
                return const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Chip(avatar: Icon(Icons.cloud_off, size: 16), label: Text('Offline'), visualDensity: VisualDensity.compact),
                );
              }
              if (engine.syncing) {
                return const Padding(padding: EdgeInsets.only(right: 16), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)));
              }
              return IconButton(tooltip: 'Sync now', onPressed: engine.sync, icon: const Icon(Icons.sync));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: engine,
              builder: (context, _) {
                final items = engine.itemsFor(view);
                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        trash
                            ? 'Trash is empty. Deleted items stay here for 30 days.'
                            : isRoot
                                ? 'Your DumpBox is empty. Type below, paste a link, or attach a file to start.'
                                : 'Nothing here yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: engine.sync,
                  child: ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      final older = i + 1 < items.length ? items[i + 1] : null;
                      final newDay = older == null || !_sameDay(older.createdAt, item.createdAt);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (newDay) _DaySeparator(date: item.createdAt),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: ItemCard(
                              item: item,
                              pending: engine.isPending(item.id),
                              error: engine.failureFor(item.id),
                              onTap: () => showItemActions(context, engine, item),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                );
              },
            ),
          ),
          if (!trash) _Composer(engine: engine, view: view),
        ],
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) {
    final x = a.toLocal(), y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }
}

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final d = date.toLocal();
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    bool same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
    final label = same(d, now)
        ? 'Today'
        : same(d, yesterday)
            ? 'Yesterday'
            : DateFormat(d.year == now.year ? 'EEE, d MMM' : 'd MMM y').format(d);
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(99), border: Border.all(color: c.outlineVariant)),
          child: Text(label, style: TextStyle(fontSize: 12, color: c.onSurfaceVariant)),
        ),
      ),
    );
  }
}

/// Capture bar: text (Enter sends), attach files, camera, current location.
class _Composer extends StatefulWidget {
  const _Composer({required this.engine, required this.view});
  final SyncEngine engine;
  final FeedView view;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _text = TextEditingController();
  bool _locating = false;

  /// Capturing inside a tag or collection view files the item there.
  List<String> get _tags => widget.view is TagView ? [(widget.view as TagView).name] : const [];
  List<String> get _collections => widget.view is CollectionView ? [(widget.view as CollectionView).id] : const [];

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    await widget.engine.captureText(t, tags: _tags, collectionIds: _collections);
  }

  Future<void> _attach() async {
    final files = await FilePicker.pickFiles();
    for (final f in files.take(10)) {
      final path = f.path;
      if (path == null) continue;
      await _addFile(File(path), f.name);
    }
  }

  Future<void> _camera() async {
    final shot = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2400);
    if (shot == null) return;
    await _addFile(File(shot.path), shot.name);
  }

  Future<void> _addFile(File file, String name) async {
    final size = await file.length();
    if (size > 50 * 1024 * 1024) {
      _snack('“$name” is over 50 MB and cannot be added.');
      return;
    }
    final caption = _text.text.trim();
    _text.clear();
    await widget.engine.captureFile(
      file,
      fileName: name,
      mimeType: lookupMimeType(name) ?? 'application/octet-stream',
      caption: caption.isEmpty ? null : caption,
      tags: _tags,
      collectionIds: _collections,
    );
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _snack('Turn on location to add a place.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _snack('Location permission was denied.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
      final label = _text.text.trim();
      _text.clear();
      await widget.engine.capturePlace(pos.latitude, pos.longitude, label, tags: _tags, collectionIds: _collections);
    } catch (_) {
      _snack('Could not get your location.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Material(
      color: c.surface,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.outlineVariant))),
          padding: const EdgeInsets.fromLTRB(6, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(tooltip: 'Attach files', onPressed: _attach, icon: const Icon(Icons.attach_file)),
              IconButton(tooltip: 'Take a photo', onPressed: _camera, icon: const Icon(Icons.photo_camera_outlined)),
              IconButton(tooltip: 'Add current location', onPressed: _locating ? null : _locate, icon: const Icon(Icons.place_outlined)),
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 6,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'Dump anything…', isDense: true),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(tooltip: 'Send', onPressed: _send, icon: const Icon(Icons.send_rounded)),
            ],
          ),
        ),
      ),
    );
  }
}
