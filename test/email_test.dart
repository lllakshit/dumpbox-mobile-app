import 'dart:convert';

import 'package:dumpbox/src/api.dart';
import 'package:dumpbox/src/email/email_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> threadJson([Map<String, dynamic> over = const {}]) => {
      'id': 't1',
      'external_id': '18c0ffee',
      'subject': 'Invoice',
      'snippet': 'Paid',
      'from_name': 'Ravi',
      'from_email': 'ravi@acme.com',
      'participants': ['Ravi', 'Me', 'Asha', 'Kiran'],
      'labels': ['Bills', 'Work/Clients/Acme'],
      'message_count': 4,
      'has_attachments': true,
      'starred': true,
      'important': false,
      'unread': true,
      'priority': 1,
      'in_scope': true,
      'in_inbox': true,
      'last_message_at': '2026-11-26T07:00:00Z',
      'pinned': false,
      'archived_at': null,
      'fresh': true,
      ...over,
    };

void main() {
  test('reads a conversation like the web app shows it', () {
    final t = EmailThread.fromJson(threadJson());
    expect(t.senders, 'Ravi, …, Asha, Kiran (4)');
    expect(t.priority, 1);
    expect(t.fresh, isTrue);
    expect(t.gmailUrl.toString(), 'https://mail.google.com/mail/u/0/#all/18c0ffee');
    expect(EmailThread.fromJson(threadJson({'participants': <String>[], 'message_count': 1})).senders, 'Ravi');
  });

  test('label tree fills in parents and keeps counts', () {
    final tree = labelTree({'Work/Clients/Acme': const EmailCount(2, 1), 'Bills': const EmailCount(3, 0)});
    expect(tree.map((l) => '${'  ' * l.depth}${l.short}${l.count == null ? '' : ' ${l.count!.total}'}').toList(), [
      'Bills 3',
      'Work',
      '  Clients',
      '    Acme 2',
    ]);
  });

  test('filters compare by value and have titles', () {
    expect(const EmailFilter(label: 'Bills'), const EmailFilter(label: 'Bills'));
    expect(const EmailFilter(priority: 1).title, 'High priority');
    expect(const EmailFilter(label: 'Work/Clients').title, 'Clients');
    expect(const EmailFilter(view: 'archived').title, 'Archived');
  });

  test('short dates', () {
    final now = DateTime(2026, 11, 26, 12);
    expect(shortDate(DateTime(2026, 11, 3, 9), now: now), '3 Nov');
    expect(shortDate(DateTime(2025, 1, 5, 9), now: now), '5 Jan 2025');
  });

  test('API calls send the filter and read counts', () async {
    final seen = <String>[];
    final api = ApiClient(
      tokenProvider: () async => 'tok',
      baseUrl: 'https://x.test',
      client: MockClient((req) async {
        seen.add('${req.method} ${req.url.path}?${req.url.query}');
        if (req.url.path == '/v1/email/counts') {
          return http.Response(
            '{"all":{"total":5,"fresh":2},"starred":1,"pinned":0,"unread":2,"archived":1,'
            '"priorities":[{"priority":1,"total":2,"fresh":1}],"labels":[{"name":"Bills","total":2,"fresh":0}]}',
            200,
          );
        }
        if (req.method == 'PATCH') return http.Response('{"thread":${_json(threadJson({'pinned': true}))}}', 200);
        return http.Response('{"threads":[${_json(threadJson())}],"next_cursor":"c2"}', 200);
      }),
    );
    final page = await api.emailThreads(const EmailFilter(label: 'Bills', priority: 1), query: ' invoice ');
    expect(page.threads.single.subject, 'Invoice');
    expect(page.next, 'c2');
    expect(seen.last, contains('label=Bills'));
    expect(seen.last, contains('priority=1'));
    expect(seen.last, contains('q=invoice'));
    final c = await api.emailCounts();
    expect(c.all.fresh, 2);
    expect(c.priorities[1]!.total, 2);
    expect(c.labels['Bills']!.total, 2);
    expect((await api.updateEmailThread('t1', pinned: true)).pinned, isTrue);
  });
}

String _json(Map<String, dynamic> m) => jsonEncode(m);
