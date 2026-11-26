import 'package:flutter/material.dart';

import '../email_models.dart';

Color priorityColor(BuildContext context, int p) => switch (p) {
      1 => Theme.of(context).colorScheme.error,
      2 => const Color(0xFFD18A1F),
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };

/// Priority, "Important" and label chips, as on the web.
class EmailChips extends StatelessWidget {
  const EmailChips({super.key, required this.thread, this.max, this.onLabel});
  final EmailThread thread;
  final int? max;
  final void Function(String label)? onLabel;

  @override
  Widget build(BuildContext context) {
    final t = thread;
    if (t.priority == null && !t.important && t.labels.isEmpty) return const SizedBox.shrink();
    final c = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.labelSmall;
    final shown = max == null ? t.labels : t.labels.take(max!).toList();
    Widget chip(String text, {Color? fg, Color? bg, VoidCallback? onTap}) {
      final box = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: bg == null ? Border.all(color: c.outlineVariant) : null,
        ),
        child: Text(text, style: small?.copyWith(color: fg ?? c.onSurfaceVariant), overflow: TextOverflow.ellipsis),
      );
      return onTap == null ? box : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(6), child: box);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(spacing: 4, runSpacing: 4, children: [
        if (t.priority != null) chip(priorityLabel(t.priority!), fg: priorityColor(context, t.priority!), bg: priorityColor(context, t.priority!).withValues(alpha: 0.12)),
        if (t.important) chip('Important', fg: const Color(0xFFD18A1F), bg: c.surfaceContainerHighest),
        for (final l in shown) chip(l, onTap: onLabel == null ? null : () => onLabel!(l)),
        if (max != null && t.labels.length > max!) chip('+${t.labels.length - max!}'),
      ]),
    );
  }
}

/// One conversation in the list: senders, date, subject, snippet, chips; bold with a dot when new.
class EmailRow extends StatelessWidget {
  const EmailRow({super.key, required this.thread, required this.onTap});
  final EmailThread thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = thread;
    final c = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final strong = t.fresh ? FontWeight.w700 : FontWeight.w400;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: t.fresh ? c.primary : Colors.transparent)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(t.senders, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium?.copyWith(fontWeight: strong, color: t.fresh ? c.onSurface : c.onSurfaceVariant)),
                ),
                if (t.pinned) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.push_pin, size: 14, color: c.primary, semanticLabel: 'Pinned')),
                if (t.hasAttachments) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.attach_file, size: 14, color: c.onSurfaceVariant, semanticLabel: 'Has attachments')),
                const SizedBox(width: 6),
                Text(shortDate(t.lastMessageAt), style: text.labelSmall?.copyWith(fontWeight: strong, color: t.fresh ? c.onSurface : c.onSurfaceVariant)),
                if (t.starred) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.star, size: 16, color: Color(0xFFE0A526), semanticLabel: 'Starred')),
              ]),
              const SizedBox(height: 2),
              Text(t.subject.isEmpty ? '(no subject)' : t.subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium?.copyWith(fontWeight: strong)),
              if (t.snippet.isNotEmpty)
                Text(t.snippet, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: c.onSurfaceVariant)),
              EmailChips(thread: t, max: 3),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The folders drawer: views, priority, the label tree, with counts and new-mail badges.
class EmailFolders extends StatelessWidget {
  const EmailFolders({super.key, required this.counts, required this.current, required this.onPick});
  final EmailCounts? counts;
  final EmailFilter current;
  final void Function(EmailFilter f) onPick;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final k = counts;
    Widget item(EmailFilter f, String label, Widget icon, {int? count, int? fresh, int depth = 0, bool muted = false}) {
      final active = f == current;
      return ListTile(
        dense: true,
        selected: active,
        selectedTileColor: c.primary.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: EdgeInsets.only(left: 16.0 + depth * 16, right: 12),
        leading: icon,
        minLeadingWidth: 20,
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted && !active ? c.onSurfaceVariant : null)),
        trailing: (fresh ?? 0) > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(10)),
                child: Text('$fresh', style: TextStyle(color: c.onPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
              )
            : ((count ?? 0) > 0 ? Text('$count', style: Theme.of(context).textTheme.labelSmall) : null),
        onTap: () => onPick(f),
      );
    }

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.onSurfaceVariant, letterSpacing: 0.8)),
        );

    final tree = labelTree(k?.labels ?? const {});
    return ListView(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: Text('Email', style: Theme.of(context).textTheme.titleLarge)),
      item(const EmailFilter(), 'Inbox', const Icon(Icons.inbox_outlined, size: 20), count: k?.all.total, fresh: k?.all.fresh),
      item(const EmailFilter(view: 'new'), 'New', const Icon(Icons.notifications_none, size: 20), count: k?.all.fresh),
      item(const EmailFilter(view: 'unread'), 'Unread in Gmail', const Icon(Icons.circle_outlined, size: 20), count: k?.unread),
      item(const EmailFilter(view: 'starred'), 'Starred', const Icon(Icons.star_border, size: 20), count: k?.starred),
      item(const EmailFilter(view: 'pinned'), 'Pinned', const Icon(Icons.push_pin_outlined, size: 20), count: k?.pinned),
      item(const EmailFilter(view: 'archived'), 'Archived', const Icon(Icons.archive_outlined, size: 20), count: k?.archived),
      heading('Priority'),
      for (final p in const [1, 2, 3])
        item(
          EmailFilter(priority: p),
          priorityLabel(p),
          Icon(Icons.circle, size: 12, color: priorityColor(context, p)),
          count: k?.priorities[p]?.total,
          fresh: k?.priorities[p]?.fresh,
        ),
      heading('Labels'),
      if (tree.isEmpty)
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('Labels from Gmail show here.', style: Theme.of(context).textTheme.bodySmall))
      else
        for (final l in tree)
          item(EmailFilter(label: l.name), l.short, const Icon(Icons.label_outline, size: 20), count: l.count?.total, fresh: l.count?.fresh, depth: l.depth, muted: l.count == null),
    ]);
  }
}
