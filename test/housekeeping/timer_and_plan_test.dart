import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/housekeeping/models/room.dart';
import 'package:nova_paris/housekeeping/services/app_exception.dart';
import 'package:nova_paris/housekeeping/services/hotel_event_handlers.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_store.dart';
import 'package:nova_paris/housekeeping/services/mutation_meta.dart';
import 'package:nova_paris/housekeeping/services/room_catalog_backend.dart';
import 'package:nova_paris/housekeeping/services/sqlite_housekeeping.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_events.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'housekeeping_store_test.dart' show TestStaff;
import 'photo_fixture.dart';
import 'test_backends.dart';

// Cleaning timer, mutation ids, priorities, availability, plan application
// and category estimates, on a real SQLite database with a controlled clock.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late String path;
  late AppSession session;
  late HousekeepingStore store;
  late TestHousekeeping backend;
  late TestCatalog catalog;
  var now = DateTime(2026, 10, 20, 9);
  final denied = throwsA(isA<AppServiceException>());
  Matcher refused(int status) => throwsA(
    isA<AppServiceException>().having((e) => e.status, 'status', status),
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
    catalog = TestCatalog(store, clock: () => now);
  }

  setUp(() async {
    now = DateTime(2026, 10, 20, 9);
    directory = await Directory.systemTemp.createTemp('nova_timer_');
    path = p.join(directory.path, 'test.db');
    await open();
  });
  tearDown(() async {
    await session.database.close();
    await directory.delete(recursive: true);
  });

  void login(String id) =>
      session.signIn(TestStaff.people.firstWhere((u) => u.id == id));
  Future<Map<String, dynamic>> room(String number) async =>
      ((await store.readState())['rooms'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((r) => r['number'] == number);
  Future<Map<String, dynamic>> viewed(String number) async =>
      ((await backend.snapshot())['rooms'] as List)
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
  Future<void> assign(String number, String agent) async {
    login('amina');
    await act(number, 'assign', {
      'employeeId': agent,
      'note': '',
      'urgent': false,
    });
  }

  Future<void> photos(String number) async {
    final tasks = (await room(number))['tasks'] as List;
    for (var i = 0; i < tasks.length; i++) {
      await act(number, 'checklist', {
        'index': i,
        'value': true,
        'photo': photoBase64(),
      });
    }
  }

  Future<Map<String, dynamic>> cleaning(String number) async =>
      ((await store.readState())['cleanings'] as List)
          .cast<Map<String, dynamic>>()
          .lastWhere((c) => c['room_number'] == number);

  group('cleaning timer', () {
    test('double start and a second running timer are refused', () async {
      await assign('305', 'sarah');
      await assign('101', 'sarah');
      login('sarah');
      await act('305', 'start');
      expect((await viewed('305'))['timer']['state'], 'running');
      await expectLater(act('305', 'start'), refused(409));
      await expectLater(
        act('101', 'start'),
        throwsA(
          isA<AppServiceException>()
              .having((e) => e.status, 'status', 409)
              .having((e) => e.message, 'message', contains('305')),
        ),
      );
      await act('305', 'pause');
      await act('101', 'start');
      await expectLater(act('305', 'resume'), refused(409));
      await act('101', 'pause');
      await act('305', 'resume');
      expect((await viewed('305'))['timer']['state'], 'running');
      expect((await viewed('101'))['timer']['state'], 'paused');
    });

    test('stop or pause without start is refused', () async {
      await assign('305', 'sarah');
      login('sarah');
      await expectLater(act('305', 'stop'), refused(409));
      await expectLater(act('305', 'pause'), refused(409));
      await act('305', 'start');
      await act('305', 'pause');
      await expectLater(act('305', 'pause'), refused(409));
      // A cleaning started before the timer existed (no segment).
      await store.systemChange((s) => (s['timerSegments'] as List).clear());
      await expectLater(act('305', 'stop'), refused(409));
    });

    test('pauses are excluded from the measured time', () async {
      await assign('305', 'sarah');
      login('sarah');
      now = DateTime(2026, 10, 20, 10);
      await act('305', 'start');
      now = DateTime(2026, 10, 20, 10, 20);
      await act('305', 'pause');
      now = DateTime(2026, 10, 20, 10, 50);
      await act('305', 'resume');
      now = DateTime(2026, 10, 20, 11);
      await act('305', 'stop');
      final c = await cleaning('305');
      expect(c['duration_ms'], const Duration(minutes: 30).inMilliseconds);
      expect(c['finished_at'], DateTime(2026, 10, 20, 11).toIso8601String());
      expect((await viewed('305'))['timer']['state'], 'stopped');
      await expectLater(act('305', 'stop'), refused(409));
    });

    test('a timer across midnight counts the real time', () async {
      await assign('305', 'sarah');
      login('sarah');
      now = DateTime(2026, 10, 20, 23, 50);
      await act('305', 'start');
      now = DateTime(2026, 10, 21, 0, 20);
      await act('305', 'stop');
      expect(
        (await cleaning('305'))['duration_ms'],
        const Duration(minutes: 30).inMilliseconds,
      );

      await assign('101', 'sarah');
      login('sarah');
      now = DateTime(2026, 10, 21, 23, 40);
      await act('101', 'start');
      now = DateTime(2026, 10, 21, 23, 55);
      await act('101', 'pause');
      now = DateTime(2026, 10, 22, 0, 5);
      await act('101', 'resume');
      now = DateTime(2026, 10, 22, 0, 10);
      await photos('101');
      await act('101', 'submit');
      expect(
        (await cleaning('101'))['duration_ms'],
        const Duration(minutes: 20).inMilliseconds,
      );
    });

    test('a running timer survives an app restart', () async {
      await assign('305', 'sarah');
      login('sarah');
      now = DateTime(2026, 10, 20, 9);
      await act('305', 'start');
      await session.database.close();
      now = DateTime(2026, 10, 20, 9, 45);
      await open();
      login('sarah');
      final timer = (await viewed('305'))['timer'] as Map;
      expect(timer['state'], 'running');
      final room = Room('305')..applyTimer(timer);
      expect(room.elapsed(now), const Duration(minutes: 45));
      await expectLater(
        act('101', 'start'),
        denied,
        reason: '101 is not assigned, and a timer still runs',
      );
    });

    test(
      'submit stops the timer; a refusal reopens it for the rework',
      () async {
        await assign('305', 'sarah');
        login('sarah');
        now = DateTime(2026, 10, 20, 9);
        await act('305', 'start');
        now = DateTime(2026, 10, 20, 9, 20);
        await photos('305');
        await act('305', 'submit');
        expect(
          (await cleaning('305'))['duration_ms'],
          const Duration(minutes: 20).inMilliseconds,
        );
        login('amina');
        await act('305', 'refuse', {'comment': 'Miroir'});
        expect((await cleaning('305'))['finished_at'], isNull);
        login('sarah');
        now = DateTime(2026, 10, 20, 10);
        await act('305', 'resume');
        now = DateTime(2026, 10, 20, 10, 10);
        await act('305', 'submit');
        expect(
          (await cleaning('305'))['duration_ms'],
          const Duration(minutes: 30).inMilliseconds,
        );
      },
    );

    test('only the assigned agent controls the timer', () async {
      await assign('305', 'sarah');
      login('sarah');
      await act('305', 'start');
      login('lina');
      await expectLater(act('305', 'pause'), refused(403));
      login('amina');
      await expectLater(act('305', 'pause'), refused(403));
      session.signIn(TestStaff.people.firstWhere((u) => u.id == 'manager'));
      await expectLater(act('305', 'pause'), refused(403));
    });

    test('reassigning a cleaning forgets the old timer', () async {
      await assign('305', 'sarah');
      login('sarah');
      await act('305', 'start');
      await act('305', 'pause');
      await assign('305', 'lina');
      expect((await viewed('305'))['timer'], isNull);
      login('lina');
      await act('305', 'start');
      expect((await viewed('305'))['timer']['state'], 'running');
    });
  });

  group('mutation ids', () {
    test('a replayed mutation id is applied once', () async {
      login('amina');
      final meta = mutationMeta();
      Future<void> receive() => backend.mutate('/v1/supplies/sheets/movement', {
        'version': 1,
        'delta': 5,
        ...meta,
      });
      await receive();
      await receive();
      final sheets = ((await store.readState())['supplies'] as List).firstWhere(
        (s) => s['id'] == 'sheets',
      );
      expect((sheets['quantity'], sheets['version']), (47, 2));
      final log = await session.database.database.query(
        'housekeeping_mutations',
        where: 'id = ?',
        whereArgs: [meta['mutationId']],
      );
      expect(log.single['client_timestamp'], meta['clientTimestamp']);
    });

    test('a mutation without a valid id or timestamp is refused', () async {
      login('amina');
      final raw = SqliteHousekeeping(store, clock: () => now);
      await expectLater(
        raw.mutate('/v1/supplies/sheets/movement', {'version': 1, 'delta': 1}),
        denied,
      );
      await expectLater(
        raw.mutate('/v1/supplies/sheets/movement', {
          'version': 1,
          'delta': 1,
          'mutationId': 'not-a-uuid',
          'clientTimestamp': now.toIso8601String(),
        }),
        denied,
      );
      await expectLater(
        raw.mutate('/v1/supplies/sheets/movement', {
          'version': 1,
          'delta': 1,
          'mutationId': uuidV4(),
        }),
        denied,
      );
      expect(isUuid(uuidV4()), isTrue);
      expect(uuidV4(), isNot(uuidV4()));
    });
  });

  group('priorities', () {
    test(
      'the supervisor sets priorities; check-out marks departures',
      () async {
        login('sarah');
        await expectLater(
          act('101', 'priority', {'value': 'vip'}),
          refused(403),
        );
        login('amina');
        await expectLater(act('101', 'priority', {'value': 'urgent'}), denied);
        await act('101', 'priority', {'value': 'vip'});
        expect((await room('101'))['priority'], 'vip');
        session.events.emit(const GuestCheckedOut('112'));
        await pumpEventQueue();
        expect((await room('112'))['priority'], 'checkout');
        await assign('101', 'sarah');
        login('sarah');
        await act('101', 'start');
        await photos('101');
        await act('101', 'submit');
        login('amina');
        await act('101', 'approve');
        expect((await room('101'))['priority'], 'normal');
      },
    );
  });

  group('availability', () {
    test('the supervisor records who works and how long', () async {
      login('amina');
      Future<void> set(String agent, Map<String, dynamic> body) =>
          backend.mutate('/v1/availability/$agent/set', body);
      await set('sarah', {
        'date': '2026-10-20',
        'available': true,
        'capacityMinutes': 240,
      });
      await set('sarah', {
        'date': '2026-10-20',
        'available': false,
        'capacityMinutes': 0,
      });
      await expectLater(
        set('lina', {
          'date': '2026-10-20',
          'available': true,
          'capacityMinutes': 900,
        }),
        denied,
      );
      await expectLater(
        set('amina', {
          'date': '2026-10-20',
          'available': true,
          'capacityMinutes': 60,
        }),
        denied,
        reason: 'only agents',
      );
      await expectLater(
        set('lina', {
          'date': '20/10/2026',
          'available': true,
          'capacityMinutes': 60,
        }),
        denied,
      );
      final rows = (await backend.snapshot())['availability'] as List;
      expect(rows.single['available'], isFalse);
      login('sarah');
      await expectLater(
        set('sarah', {
          'date': '2026-10-20',
          'available': true,
          'capacityMinutes': 60,
        }),
        refused(403),
      );
      expect((await backend.snapshot()).containsKey('availability'), isFalse);
    });
  });

  group('plan application', () {
    Future<void> apply(List<Map<String, dynamic>> items) =>
        backend.mutate('/v1/plans/new/apply', {'assignments': items});
    Future<Map<String, dynamic>> item(String number, String agent) async => {
      'roomNumber': number,
      'employeeId': agent,
      'version': (await room(number))['version'],
    };

    test('applies every assignment, or none', () async {
      await assign('305', 'sarah');
      login('amina');
      await expectLater(
        apply([await item('101', 'lina'), await item('305', 'lina')]),
        refused(409),
        reason: '305 is already assigned',
      );
      expect((await room('101'))['employeeId'], isNull);
      await apply([await item('101', 'lina'), await item('118', 'youssef')]);
      expect((await room('101'))['employeeId'], 'lina');
      expect((await room('118'))['employeeId'], 'youssef');
      final logged = ((await store.readState())['cleanings'] as List)
          .map((c) => c['room_number'])
          .toSet();
      expect(logged, containsAll(['101', '118']));
    });

    test('stale versions, unknown agents and agents are refused', () async {
      login('amina');
      final stale = await item('101', 'lina');
      await act('101', 'priority', {'value': 'vip'});
      await expectLater(apply([stale]), refused(409));
      await expectLater(apply([await item('101', 'amina')]), denied);
      await expectLater(apply([]), denied);
      login('lina');
      await expectLater(apply([await item('101', 'lina')]), refused(403));
    });
  });

  group('category estimates', () {
    test('the manager sets the estimated time of a room type', () async {
      session.signIn(TestStaff.people.firstWhere((u) => u.id == 'manager'));
      await catalog.mutate(RoomCatalogAction.setCategoryEstimate, {
        'category': 'Chambre Deluxe',
        'minutes': 40,
      });
      await expectLater(
        catalog.mutate(RoomCatalogAction.setCategoryEstimate, {
          'category': 'Suite',
          'minutes': 2,
        }),
        denied,
      );
      final snap = await catalog.snapshot();
      expect(snap.estimates['Chambre Deluxe']!.minutes, 40);
      expect(snap.categories, contains('Chambre Deluxe'));
      login('amina');
      expect(
        ((await backend.snapshot())['estimates']
            as Map)['Chambre Deluxe']['minutes'],
        40,
      );
      await expectLater(
        catalog.mutate(RoomCatalogAction.setCategoryEstimate, {
          'category': 'Suite',
          'minutes': 30,
        }),
        refused(403),
      );
    });
  });
}
