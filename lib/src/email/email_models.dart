import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../api.dart';

/// One email conversation (a Gmail thread), as GET /v1/email/threads returns it. Same fields as the web app.
class EmailThread {
  EmailThread({
    required this.id,
    required this.externalId,
    required this.subject,
    required this.snippet,
    required this.fromName,
    required this.fromEmail,
    required this.participants,
    required this.labels,
    required this.messageCount,
    required this.hasAttachments,
    required this.starred,
    required this.important,
    required this.unread,
    required this.priority,
    required this.inScope,
    required this.inInbox,
    required this.lastMessageAt,
    required this.pinned,
    required this.archivedAt,
    required this.fresh,
  });

  final String id;
  final String externalId;
  final String subject;
  final String snippet;
  final String? fromName;
  final String? fromEmail;
  final List<String> participants;
  final List<String> labels;
  final int messageCount;
  final bool hasAttachments;
  final bool starred;
  final bool important;
  final bool unread;

  /// 1 high, 2 medium, 3 low.
  final int? priority;

  /// False when it no longer has a label the Gmail script syncs (it then shows under Archived).
  final bool inScope;
  final bool inInbox;
  final DateTime lastMessageAt;
  final bool pinned;
  final DateTime? archivedAt;

  /// Unread in Gmail and has a message not yet seen in DumpBox (web or phone).
  final bool fresh;

  factory EmailThread.fromJson(Map<String, dynamic> j) => EmailThread(
        id: j['id'] as String,
        externalId: j['external_id'] as String? ?? '',
        subject: j['subject'] as String? ?? '',
        snippet: j['snippet'] as String? ?? '',
        fromName: j['from_name'] as String?,
        fromEmail: j['from_email'] as String?,
        participants: ((j['participants'] as List?) ?? const []).cast<String>(),
        labels: ((j['labels'] as List?) ?? const []).cast<String>(),
        messageCount: (j['message_count'] as num?)?.toInt() ?? 0,
        hasAttachments: j['has_attachments'] as bool? ?? false,
        starred: j['starred'] as bool? ?? false,
        important: j['important'] as bool? ?? false,
        unread: j['unread'] as bool? ?? false,
        priority: (j['priority'] as num?)?.toInt(),
        inScope: j['in_scope'] as bool? ?? true,
        inInbox: j['in_inbox'] as bool? ?? true,
        lastMessageAt: DateTime.parse(j['last_message_at'] as String),
        pinned: j['pinned'] as bool? ?? false,
        archivedAt: j['archived_at'] == null ? null : DateTime.parse(j['archived_at'] as String),
        fresh: j['fresh'] as bool? ?? false,
      );

  /// "Ravi, Me, Asha (4)" like Gmail's list.
  String get senders {
    final names = participants.isNotEmpty ? participants : [fromName ?? fromEmail ?? 'Unknown'];
    final shown = names.length > 3 ? [names.first, '…', ...names.sublist(names.length - 2)] : names;
    return '${shown.join(', ')}${messageCount > 1 ? ' ($messageCount)' : ''}';
  }

  Uri get gmailUrl => Uri.parse('https://mail.google.com/mail/u/0/#all/${Uri.encodeComponent(externalId)}');
}

class EmailAttachment {
  EmailAttachment(this.name, this.size);
  final String name;
  final int? size;
}

class EmailMessage {
  EmailMessage({
    required this.id,
    required this.fromName,
    required this.fromEmail,
    required this.to,
    required this.cc,
    required this.sentAt,
    required this.body,
    required this.attachments,
    required this.unread,
  });

  final String id;
  final String? fromName;
  final String? fromEmail;
  final String? to;
  final String? cc;
  final DateTime sentAt;
  final String body;
  final List<EmailAttachment> attachments;
  final bool unread;

  String get sender => fromName ?? fromEmail ?? 'Unknown';

  factory EmailMessage.fromJson(Map<String, dynamic> j) => EmailMessage(
        id: j['id'] as String,
        fromName: j['from_name'] as String?,
        fromEmail: j['from_email'] as String?,
        to: j['to_list'] as String?,
        cc: j['cc_list'] as String?,
        sentAt: DateTime.parse(j['sent_at'] as String),
        body: j['body_text'] as String? ?? '',
        attachments: ((j['attachments'] as List?) ?? const [])
            .map((a) => a as Map<String, dynamic>)
            .map((a) => EmailAttachment(a['name'] as String? ?? 'attachment', (a['size'] as num?)?.toInt()))
            .toList(),
        unread: j['unread'] as bool? ?? false,
      );
}

class EmailCount {
  const EmailCount(this.total, this.fresh);
  final int total;
  final int fresh;
  static EmailCount from(Map<String, dynamic>? j) => EmailCount((j?['total'] as num?)?.toInt() ?? 0, (j?['fresh'] as num?)?.toInt() ?? 0);
}

class EmailCounts {
  EmailCounts({required this.all, required this.starred, required this.pinned, required this.unread, required this.archived, required this.priorities, required this.labels});
  final EmailCount all;
  final int starred;
  final int pinned;
  final int unread;
  final int archived;
  final Map<int, EmailCount> priorities;
  final Map<String, EmailCount> labels;

  factory EmailCounts.fromJson(Map<String, dynamic> j) => EmailCounts(
        all: EmailCount.from(j['all'] as Map<String, dynamic>?),
        starred: (j['starred'] as num?)?.toInt() ?? 0,
        pinned: (j['pinned'] as num?)?.toInt() ?? 0,
        unread: (j['unread'] as num?)?.toInt() ?? 0,
        archived: (j['archived'] as num?)?.toInt() ?? 0,
        priorities: {
          for (final p in (j['priorities'] as List?) ?? const []) ((p as Map<String, dynamic>)['priority'] as num).toInt(): EmailCount.from(p),
        },
        labels: {for (final l in (j['labels'] as List?) ?? const []) (l as Map<String, dynamic>)['name'] as String: EmailCount.from(l)},
      );
}

/// What the list shows: a view, optionally narrowed to a label or a priority.
@immutable
class EmailFilter {
  const EmailFilter({this.view = 'inbox', this.label, this.priority});
  final String view; // inbox | new | unread | starred | pinned | archived
  final String? label;
  final int? priority;

  String get title {
    if (label != null) return label!.split('/').last;
    if (priority != null) return '${priorityLabel(priority!)} priority';
    return switch (view) {
      'new' => 'New',
      'unread' => 'Unread in Gmail',
      'starred' => 'Starred',
      'pinned' => 'Pinned',
      'archived' => 'Archived',
      _ => 'Inbox',
    };
  }

  @override
  bool operator ==(Object other) => other is EmailFilter && other.view == view && other.label == label && other.priority == priority;

  @override
  int get hashCode => Object.hash(view, label, priority);
}

String priorityLabel(int p) => switch (p) { 1 => 'High', 2 => 'Medium', _ => 'Low' };

/// Labels as a tree: "Work/Clients/Acme" sits under "Work/Clients" under "Work". Parents that are not labels
/// themselves are included (with no count) so the tree has no gaps.
List<({String name, String short, int depth, EmailCount? count})> labelTree(Map<String, EmailCount> labels) {
  final names = <String>{};
  for (final l in labels.keys) {
    final parts = l.split('/');
    for (var i = 1; i <= parts.length; i++) {
      names.add(parts.sublist(0, i).join('/'));
    }
  }
  final sorted = names.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [for (final n in sorted) (name: n, short: n.split('/').last, depth: n.split('/').length - 1, count: labels[n])];
}

/// List date: time today, "12 Nov" this year, "12 Nov 2025" before.
String shortDate(DateTime d, {DateTime? now}) {
  final l = d.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  if (l.year == n.year && l.month == n.month && l.day == n.day) return DateFormat.jm().format(l);
  return l.year == n.year ? DateFormat('d MMM').format(l) : DateFormat('d MMM y').format(l);
}

/// Email calls on the shared API client.
extension EmailApi on ApiClient {
  Future<({List<EmailThread> threads, String? next})> emailThreads(EmailFilter f, {String query = '', String? cursor}) async {
    final params = <String, String>{
      'view': f.view,
      'limit': '50',
      'label': ?f.label,
      if (f.priority != null) 'priority': '${f.priority}',
      if (query.trim().isNotEmpty) 'q': query.trim(),
      'cursor': ?cursor,
    };
    final d = await request('GET', '/v1/email/threads?${Uri(queryParameters: params).query}');
    return (
      threads: ((d['threads'] as List?) ?? const []).map((t) => EmailThread.fromJson(t as Map<String, dynamic>)).toList(),
      next: d['next_cursor'] as String?,
    );
  }

  Future<({EmailThread thread, List<EmailMessage> messages})> emailThread(String id) async {
    final d = await request('GET', '/v1/email/threads/$id');
    return (
      thread: EmailThread.fromJson(d['thread'] as Map<String, dynamic>),
      messages: ((d['messages'] as List?) ?? const []).map((m) => EmailMessage.fromJson(m as Map<String, dynamic>)).toList(),
    );
  }

  Future<EmailThread> updateEmailThread(String id, {bool? pinned, bool? archived}) async {
    final d = await request('PATCH', '/v1/email/threads/$id', body: {'pinned': ?pinned, 'archived': ?archived});
    return EmailThread.fromJson(d['thread'] as Map<String, dynamic>);
  }

  Future<void> deleteEmailThread(String id) => request('DELETE', '/v1/email/threads/$id');

  Future<EmailCounts> emailCounts() async => EmailCounts.fromJson(await request('GET', '/v1/email/counts'));
}

/// Tells the Email screens that something changed elsewhere (a live event, or the app coming back to the front).
class EmailHub extends ChangeNotifier {
  void changed() => notifyListeners();
}
