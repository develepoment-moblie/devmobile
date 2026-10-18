import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_paris/demo/offline_store.dart';
import 'package:nova_paris/main.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OfflineStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await OfflineStore.open();
  });
  tearDown(() => store.dispose());
  Future<void> login(String name) =>
      store.login('$name@nova.test', OfflineStore.demoPassword);
  final denied = throwsA(isA<HousekeepingException>());

  test(
    'manager creates and updates persistent users without changing session',
    () async {
      await login('manager');
      await store.createUser('new@nova.test', 'secret1', 'New Agent', 'staff');
      expect(store.sessionUserId, 'manager');
      var user = (await store.allProfiles()).firstWhere(
        (u) => u.fullName == 'New Agent',
      );
      await store.updateUser(user, 'New Supervisor', 'supervisor');
      await expectLater(store.updateUser(user, 'Stale', 'guest'), denied);
      final reopened = await OfflineStore.open();
      addTearDown(reopened.dispose);
      expect(reopened.sessionUserId, isNull);
      await reopened.login('new@nova.test', 'secret1');
      expect((await reopened.currentProfile()).role, 'supervisor');
      user = (await store.allProfiles()).firstWhere((u) => u.id == user.id);
      await store.deleteProfile(user);
      await expectLater(store.login('new@nova.test', 'secret1'), denied);
      final fresh = await OfflineStore.open();
      addTearDown(fresh.dispose);
      await expectLater(fresh.login('new@nova.test', 'secret1'), denied);
      final raw = (await SharedPreferences.getInstance()).getString(
        OfflineStore.storageKey,
      )!;
      expect(raw.contains('secret1'), isFalse);
      expect(jsonDecode(raw)['users'], isNotEmpty);
    },
  );

  test(
    'registration is guest only and agents cannot manage users or stock',
    () async {
      await store.register('client@nova.test', 'secret1', 'Client');
      expect((await store.currentProfile()).role, 'guest');
      await expectLater(store.housekeeping().snapshot(), denied);
      await expectLater(store.allProfiles(), denied);
      await login('sarah');
      await expectLater(
        store.createUser('bad@nova.test', 'secret1', 'Bad', 'manager'),
        denied,
      );
      await expectLater(
        store.housekeeping().mutate('/v1/supplies/sheets/movement', {
          'version': 1,
          'delta': 2,
        }),
        denied,
      );
      await expectLater(
        store.housekeeping().mutate('/v1/rooms/305/assign', {
          'version': 1,
          'employeeId': 'sarah',
          'note': '',
          'urgent': false,
        }),
        denied,
      );
    },
  );

  test(
    'assignment, agent checklist, approval and stock survive relaunch',
    () async {
      final backend = store.housekeeping();
      await login('amina');
      await backend.mutate('/v1/rooms/305/assign', {
        'version': 1,
        'employeeId': 'sarah',
        'note': 'Test',
        'urgent': true,
      });
      await expectLater(
        backend.mutate('/v1/rooms/305/start', {'version': 2}),
        denied,
      );
      await login('lina');
      await expectLater(
        backend.mutate('/v1/rooms/305/start', {'version': 2}),
        denied,
      );
      await login('sarah');
      await backend.mutate('/v1/rooms/305/start', {'version': 2});
      await expectLater(
        backend.mutate('/v1/rooms/305/submit', {'version': 3}),
        denied,
      );
      for (var i = 0; i < 4; i++) {
        await backend.mutate('/v1/rooms/305/checklist', {
          'version': 3 + i,
          'index': i,
          'value': true,
        });
      }
      await backend.mutate('/v1/rooms/305/submit', {'version': 7});
      await expectLater(
        backend.mutate('/v1/rooms/305/approve', {'version': 8}),
        denied,
      );
      await login('amina');
      await backend.mutate('/v1/rooms/305/approve', {'version': 8});
      await backend.mutate('/v1/supplies/sheets/movement', {
        'version': 1,
        'delta': -2,
      });
      await expectLater(
        backend.mutate('/v1/supplies/sheets/movement', {
          'version': 1,
          'delta': 2,
        }),
        denied,
      );
      await expectLater(
        backend.mutate('/v1/supplies/sheets/movement', {
          'version': 2,
          'delta': -100,
        }),
        denied,
      );
      final reopened = await OfflineStore.open();
      addTearDown(reopened.dispose);
      await reopened.login('amina@nova.test', OfflineStore.demoPassword);
      final snapshot = await reopened.housekeeping().snapshot();
      expect(
        (snapshot['rooms'] as List).firstWhere(
          (r) => r['number'] == '305',
        )['status'],
        'ready',
      );
      expect(
        (snapshot['supplies'] as List).firstWhere(
          (r) => r['id'] == 'sheets',
        )['quantity'],
        40,
      );
    },
  );

  test('notification reads remain scoped to the local user', () async {
    final backend = store.housekeeping();
    await login('sarah');
    await backend.mutate('/v1/notifications/read', {
      'ids': ['vip305', 'review109'],
    });
    var notifications = (await backend.snapshot())['notifications'] as List;
    expect(notifications.any((n) => n['id'] == 'review109'), false);
    expect(notifications.firstWhere((n) => n['id'] == 'vip305')['read'], true);
    await login('lina');
    notifications = (await backend.snapshot())['notifications'] as List;
    expect(notifications.firstWhere((n) => n['id'] == 'vip305')['read'], false);
  });

  testWidgets(
    'offline launch offers accounts and opens the real housekeeping screen',
    (tester) async {
      await store.dispose();
      store = await OfflineStore.open();
      await tester.pumpWidget(
        NovaParisApp(
          auth: store,
          housekeepingFactory: store.housekeeping,
          offline: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Démo hors ligne · données sur cet appareil'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(ActionChip, 'Gouvernante'));
      await tester.pumpAndSettle();
      expect(find.text('amina@nova.test'), findsOneWidget);
      final button = find.widgetWithText(FilledButton, 'Se connecter');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Comptes de démonstration'), findsNothing);
      expect(
        find.text('Démo hors ligne · données sur cet appareil'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
