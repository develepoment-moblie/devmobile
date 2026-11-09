import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/housekeeping/models/dashboard_data.dart';
import 'package:nova_paris/housekeeping/models/hotel_data.dart';
import 'package:nova_paris/housekeeping/services/app_exception.dart';
import 'package:nova_paris/housekeeping/services/dashboard_queries.dart';
import 'package:nova_paris/housekeeping/services/hotel_event_handlers.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_store.dart';
import 'package:nova_paris/housekeeping/services/notification_rules.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_events.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'housekeeping_store_test.dart' show TestStaff;
import 'photo_fixture.dart';
import 'schema_downgrade.dart';
import 'test_backends.dart';

// Notification triggers, per-user preferences, the change signal and the
// dashboard's aggregation queries, on a real SQLite database.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late String path;
  late AppSession session;
  late HousekeepingStore store;
  late TestHousekeeping backend;
  var now = DateTime(2026, 10, 21, 9);
  Matcher refused(int status) => throwsA(
    isA<AppServiceException>().having((e) => e.status ?? 400, 'status', status),
  );

  Future<void> open() async {
    final database = await AppDatabase.open(
      schemas: [housekeepingSchema],
      factory: databaseFactoryFfi,
      path: path,
    );
    session = AppSession(database: database, staff: TestStaff());
    store = HousekeepingStore(session);
    listenToHotelEvents(session.events, store);
    backend = TestHousekeeping(store, events: session.events, clock: () => now);
  }

  setUp(() async {
    now = DateTime(2026, 10, 21, 9);
    directory = await Directory.systemTemp.createTemp('nova_notes_');
    path = p.join(directory.path, 'test.db');
    await open();
  });
  tearDown(() async {
    await session.database.close();
    await directory.delete(recursive: true);
  });

  void login(String id) =>
      session.signIn(TestStaff.people.firstWhere((u) => u.id == id));
  Future<void> settle() async {
    await pumpEventQueue();
    await store.readState();
  }

  Future<Map<String, dynamic>> room(String number) async =>
      ((await store.readState())['rooms'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((r) => r['number'] == number);
  Future<void> act(
    String number,
    String name, [
    Map<String, dynamic> extra = const {},
  ]) async => backend.mutate('/v1/rooms/$number/$name', {
    'version': (await room(number))['version'],
    ...extra,
  });
  Future<void> assign(String number, String agent, {bool urgent = false}) =>
      act(number, 'assign', {
        'employeeId': agent,
        'note': urgent ? 'Client VIP à 11 h' : '',
        'urgent': urgent,
      });
  Future<List<Map>> notesOf(String id) async {
    final user = session.user;
    login(id);
    final list = ((await backend.snapshot())['notifications'] as List)
        .cast<Map>();
    if (user != null) session.signIn(user);
    return list;
  }

  Future<Map?> latest(String id, String title) async =>
      (await notesOf(id)).where((n) => n['title'] == title).firstOrNull;
  Future<void> cleanAndSubmit(String number, String agent) async {
    login(agent);
    if ((await room(number))['cleaning'] == 'waiting') {
      await act(number, 'start');
    }
    final tasks = (await room(number))['tasks'] as List;
    for (var i = 0; i < tasks.length; i++) {
      await act(number, 'checklist', {
        'index': i,
        'value': true,
        'photo': photoBase64(),
      });
    }
    await act(number, 'submit');
  }

  group('notification triggers', () {
    test('an urgent task notifies its agent only', () async {
      login('amina');
      await assign('305', 'sarah');
      expect(await latest('sarah', 'Tâche urgente'), isNull);
      await assign('118', 'sarah', urgent: true);
      final note = await latest('sarah', 'Tâche urgente');
      expect(
        (note!['category'], note['message']),
        ('tasks', 'Chambre 118 à traiter en priorité · Client VIP à 11 h'),
      );
      expect(await latest('lina', 'Tâche urgente'), isNull);
      expect(await latest('amina', 'Tâche urgente'), isNull);
    });

    test('submitted for the supervisor, sent back for the agent', () async {
      login('amina');
      await assign('305', 'sarah');
      await cleanAndSubmit('305', 'sarah');
      final review = await latest('amina', 'Nettoyage à valider');
      expect(review!['category'], 'inspection');
      expect(await latest('sarah', 'Nettoyage à valider'), isNull);
      login('amina');
      await act('305', 'refuse', {'comment': 'Miroir'});
      final back = await latest('sarah', 'Nettoyage à reprendre');
      expect(
        (back!['category'], back['message']),
        ('tasks', 'Chambre 305 · Miroir'),
      );
      expect(await latest('lina', 'Nettoyage à reprendre'), isNull);
    });

    test('a departure, low stock and a resolved issue', () async {
      session.events.emit(const GuestCheckedOut('112'));
      await settle();
      for (final id in ['sarah', 'amina']) {
        expect((await latest(id, 'Départ client'))!['category'], 'departures');
      }
      login('amina');
      // 42 sheets, alert at 15.
      await backend.mutate('/v1/supplies/sheets/movement', {
        'version': 1,
        'delta': -27,
      });
      expect((await latest('amina', 'Stock bas'))!['category'], 'stock');
      session.events.emit(const MaintenanceResolved('224'));
      await settle();
      final done = await latest('amina', 'Maintenance terminée');
      expect(done!['category'], 'maintenance');
    });

    test(
      'a late cleaning alerts the supervisor once, at the right time',
      () async {
        login('amina');
        await assign('305', 'sarah');
        login('sarah');
        await act('305', 'start');
        // Default estimate 30 min + 25 %: late after 37 min 30 s.
        now = now.add(const Duration(minutes: 30));
        expect(await backend.checkLate(), DateTime(2026, 10, 21, 9, 37, 30));
        expect(await latest('amina', 'Nettoyage en retard'), isNull);
        now = now.add(const Duration(minutes: 8));
        expect(await backend.checkLate(), isNull);
        final late = await latest('amina', 'Nettoyage en retard');
        expect(late!['category'], 'late');
        expect(
          late['message'],
          'Chambre 305 : Sarah dépasse le temps prévu (38 min pour 37 min).',
        );
        now = now.add(const Duration(minutes: 30));
        await backend.checkLate();
        expect(
          (await notesOf('amina'))
              .where((n) => n['title'] == 'Nettoyage en retard'),
          hasLength(1),
        );
        expect(await latest('sarah', 'Nettoyage en retard'), isNull);
      },
    );

    test('a paused timer is not watched', () async {
      login('amina');
      await assign('305', 'sarah');
      login('sarah');
      await act('305', 'start');
      now = now.add(const Duration(minutes: 10));
      await act('305', 'pause');
      now = now.add(const Duration(hours: 2));
      expect(await backend.checkLate(), isNull);
      expect(await latest('amina', 'Nettoyage en retard'), isNull);
    });
  });

  group('preferences', () {
    Future<void> set(String category, bool on, int version) => backend.mutate(
      '/v1/notification-prefs/$category/set',
      {'enabled': on, 'version': version},
    );

    test('a muted category is hidden for that user only', () async {
      login('sarah');
      await set('tasks', false, 0);
      expect((await backend.snapshot())['notificationPrefs'], {
        'tasks': {'enabled': false, 'version': 1},
      });
      await expectLater(set('tasks', true, 0), refused(409));
      await expectLater(set('jardin', true, 0), refused(400));
      login('amina');
      await assign('118', 'sarah', urgent: true);
      await assign('305', 'lina', urgent: true);
      expect(await latest('sarah', 'Tâche urgente'), isNull);
      expect(await latest('lina', 'Tâche urgente'), isNotNull);
      expect(
        (await backend.snapshot())['notificationPrefs'],
        isEmpty,
        reason: 'preferences are per user',
      );
      login('sarah');
      await set('tasks', true, 1);
      expect(await latest('sarah', 'Tâche urgente'), isNotNull);
      login('manager');
      await expectLater(set('stock', false, 0), refused(403));
    });

    test(
      'HotelData sees neither the muted notifications nor their count',
      () async {
        login('amina');
        await assign('118', 'sarah', urgent: true);
        login('sarah');
        final data = HotelData(api: backend);
        await data.refresh();
        expect(
          data.notifications.map((n) => n.title),
          contains('Tâche urgente'),
        );
        final unread = data.unread;
        await data.setNotificationPref('tasks', false);
        expect(
          data.notifications.map((n) => n.title),
          isNot(contains('Tâche urgente')),
        );
        expect(data.unread, lessThan(unread));
        expect(data.notifies('tasks'), isFalse);
        data.dispose();
      },
    );
  });

  group('change signal', () {
    test(
      'fires after a user change and after another module\'s event',
      () async {
        var signals = 0;
        final sub = store.changes.listen((_) => signals++);
        login('amina');
        await assign('305', 'sarah');
        await settle();
        expect(signals, 1);
        session.events.emit(const GuestCheckedOut('112'));
        await settle();
        expect(signals, 2);
        await sub.cancel();
      },
    );

    test('HotelData refreshes by itself after an event (no polling)', () async {
      login('amina');
      final data = HotelData(api: backend);
      await data.refresh();
      expect(data.roomByNumber('112').status.name, 'occupied');
      var notified = 0;
      data.addListener(() => notified++);
      session.events.emit(const GuestCheckedOut('112'));
      for (var i = 0; i < 5; i++) {
        await settle();
      }
      expect(data.roomByNumber('112').status.name, 'dirty');
      expect(notified, greaterThan(0));
      data.dispose();
    });
  });

  group('dashboard', () {
    // Known cleanings written straight into the log.
    Future<void> fixture() async {
      String at(Duration ago) => now.subtract(ago).toIso8601String();
      Map<String, dynamic> cleaning(
        String id,
        String agent,
        Duration ago, {
        int? minutes,
        int? score,
      }) => {
        'id': id,
        'room_number': '101',
        'agent_id': agent,
        'kind': 'checkout',
        'assigned_at': at(ago + const Duration(hours: 1)),
        'started_at': at(ago + const Duration(hours: 1)),
        'submitted_at': at(ago),
        'approved_at': at(ago),
        'refusals': 0,
        'finished_at': minutes == null ? null : at(ago),
        'duration_ms': minutes == null ? null : minutes * 60000,
        'inspection_score': score,
        'inspection_rounds': score == null ? 0 : 1,
      };
      await store.systemChange(
        (s) => (s['cleanings'] as List).addAll(<Map<String, dynamic>>[
          cleaning(
            'a',
            'sarah',
            const Duration(hours: 2),
            minutes: 20,
            score: 90,
          ),
          cleaning(
            'b',
            'sarah',
            const Duration(hours: 1),
            minutes: 40,
            score: 70,
          ),
          cleaning('c', 'lina', const Duration(minutes: 30)),
          cleaning(
            'd',
            'lina',
            const Duration(days: 10),
            minutes: 60,
            score: 50,
          ),
        ]),
      );
    }

    test('aggregates rooms, cleanings, agents and open issues', () async {
      await fixture();
      login('sarah');
      await backend.mutate('/v1/rooms/214/report', {
        'version': (await room('214'))['version'],
        'category': 'plomberie',
        'description': 'Fuite',
        'priority': 'high',
        'outOfService': false,
      });
      session.events.emit(const MaintenanceResolved('224'));
      await settle();
      login('amina');
      final today = DateTime(now.year, now.month, now.day);
      final d = await DashboardQueries(store).load(today);
      expect(d.roomsByStatus, {
        'ready': 2,
        'occupied': 1,
        'dirty': 12,
        'maintenance': 1,
      });
      expect((d.cleaned, d.pending), (3, 12));
      expect(d.pendingByStage, {'inProgress': 3, 'waiting': 9});
      expect(
        (d.averageCleaning, d.timedCleanings),
        (const Duration(minutes: 30), 2),
      );
      expect(
        [
          for (final a in d.agents)
            (a.name, a.approved, a.roomsPerHour, a.averageScore),
        ],
        [('Sarah', 2, 2.0, 80), ('Lina', 1, null, null)],
      );
      expect(d.issuesByStatus, {'open': 1, 'resolved': 1});
      expect(
        d.recentIssues.map((i) => (i.roomNumber, i.status)),
        unorderedEquals([('214', 'open'), ('224', 'resolved')]),
      );

      final month = await DashboardQueries(store)
          .load(today.subtract(const Duration(days: 29)));
      expect(month.cleaned, 4);
      final lina = month.agents.firstWhere((a) => a.agentId == 'lina');
      expect((lina.roomsPerHour, lina.averageScore), (1.0, 50));
    });

    test('for the supervisor and the Manager only', () async {
      login('manager');
      expect((await DashboardQueries(store).load(now)).rooms, 16);
      login('sarah');
      await expectLater(DashboardQueries(store).load(now), refused(403));
    });

    test('DashboardData reloads after every saved change', () async {
      login('manager');
      final data = DashboardData(store, clock: () => now);
      await data.load();
      expect(data.dashboard!.pending, 12);
      session.events.emit(const GuestCheckedOut('402'));
      for (var i = 0; i < 5; i++) {
        await settle();
      }
      expect(data.dashboard!.pending, 13);
      data.dispose();
    });
  });

  test('a version 6 database upgrades in place', () async {
    login('amina');
    await assign('118', 'sarah', urgent: true);
    final db = session.database.database;
    await dropVersion7(db);
    await db.update('module_versions', {
      'version': 6,
    }, where: "module = 'housekeeping'");
    await session.database.close();
    await open();
    expect(await session.database.versionOf('housekeeping'), 7);
    expect((await latest('sarah', 'Tâche urgente'))!['category'], 'tasks');
    for (final id in ['sarah', 'amina']) {
      for (final n in await notesOf(id)) {
        expect(n['category'], isIn(notificationCategoryLabels.keys));
      }
    }
  });
}
