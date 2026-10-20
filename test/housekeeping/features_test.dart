import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/housekeeping/models/cleaning_stats.dart';
import 'package:nova_paris/housekeeping/services/app_exception.dart';
import 'package:nova_paris/housekeeping/services/hotel_event_handlers.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_store.dart';
import 'package:nova_paris/housekeeping/services/room_catalog_backend.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_events.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'housekeeping_store_test.dart' show TestStaff;
import 'photo_fixture.dart';
import 'test_backends.dart';

// Rules of the stock items, refusal, recouche, lost and found, statistics
// and the Manager's catalog, on a real SQLite database.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppSession session;
  late HousekeepingStore store;
  late TestHousekeeping backend;
  late TestCatalog catalog;
  final emitted = <AppEvent>[];
  final denied = throwsA(isA<AppServiceException>());

  setUp(() async {
    emitted.clear();
    directory = await Directory.systemTemp.createTemp('nova_features_');
    final database = await AppDatabase.open(
      schemas: [housekeepingSchema],
      factory: databaseFactoryFfi,
      path: p.join(directory.path, 'test.db'),
    );
    session = AppSession(database: database, staff: TestStaff());
    session.events.on<AppEvent>().listen(emitted.add);
    store = HousekeepingStore(session);
    listenToHotelEvents(session.events, store);
    backend = TestHousekeeping(store, events: session.events);
    catalog = TestCatalog(store);
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
  Future<void> act(
    String number,
    String name, [
    Map<String, dynamic> extra = const {},
  ]) async => backend.mutate('/v1/rooms/$number/$name', {
    'version': (await room(number))['version'],
    ...extra,
  });
  Future<void> assign(String number, String agent) =>
      act(number, 'assign', {'employeeId': agent, 'note': '', 'urgent': false});
  Future<void> cleanAndSubmit(String number, String agent) async {
    login(agent);
    if ((await room(number))['cleaning'] == 'waiting') {
      await act(number, 'start');
    }
    final tasks = (await room(number))['tasks'] as List;
    for (var i = 0; i < tasks.length; i++) {
      if ((await room(number))['checklist'][i] == true) continue;
      await act(number, 'checklist', {
        'index': i,
        'value': true,
        'photo': photoBase64(),
      });
    }
    await act(number, 'submit');
  }

  Future<List<Map<String, dynamic>>> notes() async => [
    for (final n in (await backend.snapshot())['notifications'] as List)
      Map<String, dynamic>.from(n as Map),
  ];

  group('stock items', () {
    Future<Map> supply(String name) async =>
        ((await store.readState())['supplies'] as List).firstWhere(
          (s) => s['name'] == name,
        );

    test(
      'the supervisor creates, edits and deletes items; agents cannot',
      () async {
        login('sarah');
        await expectLater(
          backend.mutate('/v1/supplies/new/create', {
            'name': 'Gants',
            'unit': 'paires',
            'quantity': 10,
            'minimum': 4,
          }),
          denied,
        );
        login('amina');
        await backend.mutate('/v1/supplies/new/create', {
          'name': 'Gants',
          'unit': 'paires',
          'quantity': 10,
          'minimum': 4,
        });
        await expectLater(
          backend.mutate('/v1/supplies/new/create', {
            'name': 'gants',
            'unit': 'paires',
            'quantity': 1,
            'minimum': 1,
          }),
          denied,
          reason: 'names are unique, whatever the case',
        );
        var gloves = await supply('Gants');
        await backend.mutate('/v1/supplies/${gloves['id']}/update', {
          'version': gloves['version'],
          'name': 'Gants nitrile',
          'unit': 'paires',
          'minimum': 8,
        });
        gloves = await supply('Gants nitrile');
        expect((gloves['minimum'], gloves['quantity']), (8, 10));
        await expectLater(
          backend.mutate('/v1/supplies/${gloves['id']}/delete', {'version': 1}),
          throwsA(
            isA<AppServiceException>().having((e) => e.status, 'status', 409),
          ),
        );
        await backend.mutate('/v1/supplies/${gloves['id']}/delete', {
          'version': gloves['version'],
        });
        expect(
          ((await store.readState())['supplies'] as List).any(
            (s) => s['name'] == 'Gants nitrile',
          ),
          isFalse,
        );
      },
    );
  });

  group('refusal', () {
    test(
      'a refused cleaning goes back to the agent with the comment',
      () async {
        login('amina');
        await assign('305', 'sarah');
        await cleanAndSubmit('305', 'sarah');
        login('sarah');
        await expectLater(act('305', 'refuse', {'comment': 'Non'}), denied);
        login('amina');
        await expectLater(act('305', 'refuse', {'comment': '  '}), denied);
        await act('305', 'refuse', {'comment': 'Miroir de la salle de bain'});
        final refused = await room('305');
        expect(
          (refused['cleaning'], refused['feedback']),
          ('inProgress', 'Miroir de la salle de bain'),
        );
        login('sarah');
        final forSarah = await notes();
        expect(forSarah.first['title'], 'Nettoyage à reprendre');
        expect(forSarah.first['message'], contains('Miroir'));
        await act('305', 'submit');
        login('amina');
        await act('305', 'approve');
        final approved = await room('305');
        expect((approved['status'], approved['feedback']), ('ready', null));
        final log = ((await store.readState())['cleanings'] as List).single;
        expect((log['refusals'], log['agent_id']), (1, 'sarah'));
        expect(log['approved_at'], isNotNull);
        expect(log['started_at'], isNotNull);
      },
    );
  });

  group('recouche', () {
    test('an occupied room is cleaned and stays occupied', () async {
      login('sarah');
      await expectLater(
        act('112', 'stayover', {'value': true}),
        denied,
        reason: 'supervisor only',
      );
      login('amina');
      await expectLater(
        act('305', 'stayover', {'value': true}),
        denied,
        reason: 'room not occupied',
      );
      await act('112', 'stayover', {'value': true, 'note': 'Client absent'});
      expect((await room('112'))['stayover'], isTrue);
      await assign('112', 'lina');
      await cleanAndSubmit('112', 'lina');
      login('amina');
      emitted.clear();
      await act('112', 'approve');
      final done = await room('112');
      expect(
        (done['status'], done['stayover'], done['cleaning']),
        ('occupied', false, 'completed'),
      );
      expect(emitted.whereType<RoomReady>(), isEmpty);
      final log = ((await store.readState())['cleanings'] as List).single;
      expect(log['kind'], 'stayover');
    });

    test('cancelling, and a check-out during a recouche', () async {
      login('amina');
      await act('112', 'stayover', {'value': true});
      await assign('112', 'lina');
      await act('112', 'stayover', {'value': false});
      final cancelled = await room('112');
      expect((cancelled['stayover'], cancelled['employeeId']), (false, null));
      expect((await store.readState())['cleanings'], isEmpty);

      await act('112', 'stayover', {'value': true});
      session.events.emit(const GuestCheckedOut('112'));
      await pumpEventQueue();
      final out = await room('112');
      expect((out['status'], out['stayover']), ('dirty', false));
    });
  });

  group('lost and found', () {
    test(
      'agents record items in their rooms; the supervisor gives them back',
      () async {
        login('sarah');
        await expectLater(
          backend.mutate('/v1/lost/new/create', {
            'roomNumber': '305',
            'description': 'Montre',
          }),
          denied,
          reason: '305 is not assigned to Sarah',
        );
        await backend.mutate('/v1/lost/new/create', {
          'roomNumber': '214',
          'description': 'Montre dorée',
          'photo': photoBase64(),
        });
        final item = Map<String, dynamic>.from(
          ((await backend.snapshot())['lostItems'] as List).single as Map,
        );
        expect((item['room_number'], item['found_by_name']), ('214', 'Sarah'));
        expect(
          await backend.lostItemPhoto(item['id'] as String),
          photoBase64(),
        );
        login('lina');
        expect((await backend.snapshot())['lostItems'], isEmpty);
        await expectLater(backend.lostItemPhoto(item['id'] as String), denied);
        login('amina');
        expect((await notes()).first['title'], 'Objet trouvé');
        await backend.mutate('/v1/lost/${item['id']}/return', {
          'version': item['version'],
          'returnedTo': 'M. Martin',
        });
        await expectLater(
          backend.mutate('/v1/lost/${item['id']}/return', {
            'version': 2,
            'returnedTo': 'Encore',
          }),
          denied,
        );
        final returned =
            ((await backend.snapshot())['lostItems'] as List).single as Map;
        expect(returned['returned_to'], 'M. Martin');
        expect(returned['returned_at'], isNotNull);
      },
    );
  });

  group('statistics', () {
    test(
      'per agent: approved cleanings, refusals and first-time right',
      () async {
        login('amina');
        await assign('305', 'sarah');
        await assign('101', 'sarah');
        await assign('118', 'lina');
        await cleanAndSubmit('305', 'sarah');
        await cleanAndSubmit('101', 'sarah');
        await cleanAndSubmit('118', 'lina');
        login('amina');
        await act('305', 'refuse', {'comment': 'Poussière'});
        await cleanAndSubmit('305', 'sarah');
        login('amina');
        for (final number in ['305', '101', '118']) {
          await act(number, 'approve');
        }
        final records = [
          for (final c in (await backend.snapshot())['cleanings'] as List)
            CleaningRecord.fromMap(c as Map),
        ];
        final stats = CleaningStats.compute(records, {
          'sarah': 'Sarah',
          'lina': 'Lina',
        }, since: DateTime.now().subtract(const Duration(hours: 1)));
        expect((stats.approved, stats.refusals, stats.firstTime), (3, 1, 2));
        expect(stats.agents.first.name, 'Sarah');
        expect(
          (stats.agents.first.approved, stats.agents.first.refusals),
          (2, 1),
        );
        expect(stats.averageTime, isNotNull);
        expect(
          CleaningStats.compute(records, {}, since: DateTime(2999)).approved,
          0,
        );
        login('sarah');
        expect(
          ((await backend.snapshot())['cleanings'] as List).every(
            (c) => c['agent_id'] == 'sarah',
          ),
          isTrue,
        );
      },
    );
  });

  group('catalog', () {
    test(
      'the manager creates a floor of rooms at once, names floors',
      () async {
        login('manager');
        await catalog.mutate(RoomCatalogAction.createRange, {
          'floor': 5,
          'from': 1,
          'to': 5,
          'category': 'Suite',
        });
        var snap = await catalog.snapshot();
        expect(snap.rooms.where((r) => r.floor == 5).map((r) => r.number), [
          '501',
          '502',
          '503',
          '504',
          '505',
        ]);
        await expectLater(
          catalog.mutate(RoomCatalogAction.createRange, {
            'floor': 5,
            'from': 5,
            'to': 6,
            'category': 'Suite',
          }),
          denied,
          reason: '505 already exists',
        );
        await expectLater(
          catalog.mutate(RoomCatalogAction.createRange, {
            'floor': 6,
            'from': 0,
            'to': 60,
            'category': 'Suite',
          }),
          denied,
        );
        await catalog.mutate(RoomCatalogAction.renameFloor, {
          'floor': 5,
          'name': 'Étage 5 · Suites panoramiques',
        });
        snap = await catalog.snapshot();
        expect(snap.floorName(5), 'Étage 5 · Suites panoramiques');
        expect(snap.floorName(7), 'Étage 7');
        expect(snap.floors, containsAll([1, 2, 3, 4, 5]));
        login('amina');
        await expectLater(catalog.snapshot(), denied);
      },
    );

    test('category task lists apply to new and idle rooms only', () async {
      login('manager');
      await catalog.mutate(RoomCatalogAction.createRange, {
        'floor': 5,
        'from': 1,
        'to': 2,
        'category': 'Suite',
      });
      login('amina');
      await assign('502', 'sarah');
      login('sarah');
      await act('502', 'start');
      login('manager');
      await catalog.mutate(RoomCatalogAction.setCategoryTasks, {
        'category': 'Suite',
        'labels': ['Linge', 'Salle de bain', 'Minibar', 'Terrasse', 'Sol'],
      });
      expect((await room('501'))['tasks'], hasLength(5));
      expect(
        (await room('502'))['tasks'],
        hasLength(4),
        reason: 'being cleaned: unchanged',
      );
      await catalog.mutate(RoomCatalogAction.create, {
        'number': '503',
        'category': 'Suite',
      });
      final created = await room('503');
      expect((created['tasks'] as List).map((t) => t['label']), [
        'Linge',
        'Salle de bain',
        'Minibar',
        'Terrasse',
        'Sol',
      ]);
      expect(created['checklist'], hasLength(5));
      final standard = await room('101');
      await catalog.mutate(RoomCatalogAction.update, {
        'number': '101',
        'category': 'Suite',
        'version': standard['version'],
      });
      expect((await room('101'))['tasks'], hasLength(5));
      await expectLater(
        catalog.mutate(RoomCatalogAction.setCategoryTasks, {
          'category': 'Suite',
          'labels': ['Sol', 'sol'],
        }),
        denied,
      );
      expect(
        (await catalog.snapshot()).categoryTasks['Suite']!.labels,
        hasLength(5),
      );
    });
  });
}
