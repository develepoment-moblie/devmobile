import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nova_paris/shared/custom/app_theme.dart';
import 'package:nova_paris/housekeeping/models/hotel_data.dart';
import 'package:nova_paris/housekeeping/screens/assign_task_screen.dart';
import 'package:nova_paris/housekeeping/screens/details_screen.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_api.dart';

Map<String, dynamic> fixture() =>
    jsonDecode(File('test/fixtures/snapshot.json').readAsStringSync())
        as Map<String, dynamic>;
HousekeepingApi api(MockClient client) => HousekeepingApi(
  baseUrl: Uri.parse('https://housekeeping.example'),
  tokenProvider: () async => 'verified-session',
  client: client,
);

http.Response reply(String body, int status) => http.Response(
  body,
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('Connected refresh uses token and preserves room references for open details', () async {
    final snapshot = fixture();
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer verified-session');
      return reply(jsonEncode(snapshot), 200);
    });
    final service = api(client);
    final data = HotelData(api: service);
    final room = data.roomByNumber('214');
    await data.refresh();
    expect(data.roomByNumber('214'), same(room));
    expect(data.currentUserId, 'sarah');
    expect(data.canClean(room), true);
    expect(data.canClean(data.roomByNumber('207')), false);
    snapshot['rooms'][1]['version'] = 2;
    snapshot['rooms'][1]['employeeId'] = 'lina';
    await data.refresh();
    expect(room.version, 2);
    expect(data.canClean(room), false);
    data.dispose();
    service.close();
  });
  test(
    'Lost POST response retries with same key so stock is not duplicated',
    () async {
      String? firstKey;
      var calls = 0;
      final service = api(
        MockClient((request) async {
          calls++;
          firstKey ??= request.headers['Idempotency-Key'];
          expect(request.headers['Idempotency-Key'], firstKey);
          expect(firstKey!.length, 48);
          if (calls == 1) throw http.ClientException('lost response');
          return reply('{"ok":true}', 200);
        }),
      );
      await service.mutate('/v1/supplies/sheets/movement', {
        'version': 1,
        'delta': -2,
      });
      expect(calls, 2);
      service.close();
    },
  );
  test('Expired session is surfaced without retry or local success', () async {
    var calls = 0;
    final service = api(
      MockClient((request) async {
        calls++;
        return reply('{"error":"Session expirée"}', 401);
      }),
    );
    final data = HotelData(api: service);
    await expectLater(
      data.refresh(),
      throwsA(
        isA<HousekeepingException>().having((e) => e.status, 'status', 401),
      ),
    );
    expect(data.connectionError, 'Session expirée');
    expect(calls, 1);
    data.dispose();
    service.close();
  });
  testWidgets(
    'Server conflict keeps assignment draft and sends captured version',
    (tester) async {
      final snapshot = fixture();
      snapshot['principal'] = {
        'id': 'amina',
        'name': 'Amina',
        'role': 'supervisor',
      };
      var writes = 0;
      final service = api(
        MockClient((request) async {
          if (request.method == 'POST') {
            writes++;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['version'], 1);
            expect(body['employeeId'], 'sarah');
            snapshot['rooms'][0]['version'] = 2;
            return reply(
              jsonEncode({
                'error': 'Données modifiées : vérifiez puis réessayez.',
              }),
              409,
            );
          }
          return reply(jsonEncode(snapshot), 200);
        }),
      );
      final data = HotelData(api: service);
      await data.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: novaTheme(),
          home: AssignTaskScreen(data: data, room: data.roomByNumber('305')),
        ),
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sarah').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField),
        'Garder cette consigne',
      );
      await tester.ensureVisible(find.text('Attribuer la tâche'));
      await tester.tap(find.text('Attribuer la tâche'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.text('Garder cette consigne'), findsOneWidget);
      expect(
        find.text('Données modifiées : vérifiez puis réessayez.'),
        findsOneWidget,
      );
      expect(find.byType(AssignTaskScreen), findsOneWidget);
      expect(data.roomByNumber('305').employee, isNull);
      await tester.pumpWidget(const SizedBox());
      data.dispose();
      service.close();
    },
  );
  testWidgets(
    'A server permission denial keeps checklist unchanged and shows error',
    (tester) async {
      final snapshot = fixture();
      final service = api(
        MockClient(
          (request) async => request.method == 'POST'
              ? reply('{"error":"Tâche réattribuée"}', 403)
              : reply(jsonEncode(snapshot), 200),
        ),
      );
      final data = HotelData(api: service);
      await data.refresh();
      final room = data.roomByNumber('214');
      await tester.pumpWidget(
        MaterialApp(
          theme: novaTheme(),
          home: DetailsScreen(data: data, room: room),
        ),
      );
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pumpAndSettle();
      expect(room.checklist.first, false);
      expect(find.text('Tâche réattribuée'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      data.dispose();
      service.close();
    },
  );
}
