import 'dart:convert';
import 'dart:io';

import 'package:dumpbox/src/api.dart';
import 'package:dumpbox/src/email/email_models.dart';
import 'package:dumpbox/src/email/ui/email_screen.dart';
import 'package:dumpbox/src/planner/planner_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Drives the real Email screens against a fake server: list, folders, open a conversation, pin, back.
void main() {
  testWidgets('list → conversation → pin → back shows the change', (tester) async {
    var pinned = false;
    final calls = <String>[];
    Map<String, dynamic> thread() => {
          'id': 't1',
          'external_id': 'g1',
          'subject': 'Electricity bill',
          'snippet': 'Payment received',
          'from_name': 'BESCOM',
          'participants': ['BESCOM', 'Me'],
          'labels': ['Bills', 'Home/Flat'],
          'message_count': 2,
          'unread': true,
          'priority': 1,
          'in_scope': true,
          'in_inbox': true,
          'last_message_at': '2026-11-26T07:00:00Z',
          'pinned': pinned,
          'fresh': !pinned,
        };
    final api = ApiClient(
      tokenProvider: () async => 'tok',
      baseUrl: 'https://x.test',
      client: MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        final p = req.url.path;
        if (p == '/v1/email/counts') {
          return http.Response(jsonEncode({'all': {'total': 1, 'fresh': 1}, 'starred': 0, 'pinned': 0, 'unread': 1, 'archived': 0, 'priorities': [{'priority': 1, 'total': 1, 'fresh': 1}], 'labels': [{'name': 'Bills', 'total': 1, 'fresh': 1}, {'name': 'Home/Flat', 'total': 1, 'fresh': 1}]}), 200);
        }
        if (p == '/v1/email/threads') return http.Response(jsonEncode({'threads': [thread()], 'next_cursor': null}), 200);
        if (p == '/v1/email/threads/t1' && req.method == 'GET') {
          return http.Response(jsonEncode({
            'thread': thread(),
            'messages': [
              {'id': 'm1', 'from_name': 'BESCOM', 'from_email': 'b@bescom.in', 'sent_at': '2026-11-25T07:00:00Z', 'body_text': 'Your bill is due. Pay at https://bescom.in/pay', 'attachments': [], 'unread': false},
              {'id': 'm2', 'from_name': 'BESCOM', 'from_email': 'b@bescom.in', 'sent_at': '2026-11-26T07:00:00Z', 'body_text': 'Payment received. Thank you.', 'attachments': [{'name': 'receipt.pdf', 'size': 4096}], 'unread': true},
            ],
          }), 200);
        }
        if (req.method == 'PATCH') {
          pinned = (jsonDecode(req.body) as Map)['pinned'] as bool;
          return http.Response(jsonEncode({'thread': thread()}), 200);
        }
        return http.Response('{}', 404);
      }),
    );
    late PlannerEngine planner;
    await tester.runAsync(() async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('email-ui');
      planner = PlannerEngine(store: await PlannerStore.open('${dir.path}/p.db', factory: databaseFactoryFfi), api: api);
    });
    // A phone screen (360 x 800): also fails the test on any layout overflow.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final hub = EmailHub();
    await tester.pumpWidget(MaterialApp(home: EmailScreen(api: api, planner: planner, hub: hub, active: true)));
    await tester.pumpAndSettle();

    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('Electricity bill'), findsOneWidget);
    expect(find.text('BESCOM, Me (2)'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);

    // Folders drawer shows priority and the label tree.
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.text('Unread in Gmail'), findsOneWidget);
    expect(find.text('Flat'), findsOneWidget);
    await tester.tap(find.text('Inbox').last);
    await tester.pumpAndSettle();

    // Open the conversation: newest message open, older folded.
    await tester.tap(find.text('Electricity bill'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Payment received. Thank you.'), findsWidgets);
    expect(find.text('Expand all'), findsOneWidget);
    expect(find.textContaining('receipt.pdf'), findsOneWidget);

    await tester.tap(find.byTooltip('Pin'));
    await tester.pumpAndSettle();
    expect(calls, contains('PATCH /v1/email/threads/t1'));
    expect(find.byTooltip('Unpin'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.push_pin), findsOneWidget); // the list shows it pinned
  });
}
