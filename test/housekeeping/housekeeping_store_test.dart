import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/housekeeping/services/app_exception.dart';
import 'package:nova_paris/housekeeping/services/hotel_event_handlers.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_store.dart';
import 'package:nova_paris/housekeeping/services/room_catalog_backend.dart';
import 'package:nova_paris/housekeeping/services/sqlite_housekeeping.dart';
import 'package:nova_paris/housekeeping/services/sqlite_room_catalog.dart';
import 'package:nova_paris/shared/models/app_user.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_events.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:nova_paris/shared/services/staff_directory.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'photo_fixture.dart';

// Fictional team, independent of the user_management module.
class TestStaff implements StaffDirectory {
  static const people = [
    AppUser(id: 'manager', fullName: 'Manager Test', role: AppRole.manager),
    AppUser(id: 'amina', fullName: 'Amina', role: AppRole.supervisor),
    AppUser(id: 'sarah', fullName: 'Sarah', role: AppRole.staff),
    AppUser(id: 'lina', fullName: 'Lina', role: AppRole.staff),
    AppUser(id: 'youssef', fullName: 'Youssef', role: AppRole.staff),
    AppUser(id: 'guest', fullName: 'Client', role: AppRole.guest),
  ];
  @override
  Future<List<AppUser>> users({Set<String>? roles}) async => [
    for (final u in people)
      if (roles == null || roles.contains(u.role)) u,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late String path;
  late AppSession session;
  late HousekeepingStore store;
  late SqliteHousekeeping backend;
  late SqliteRoomCatalog catalog;
  final emitted = <AppEvent>[];
  final denied = throwsA(isA<AppServiceException>());

  Future<void> open() async {
    final database = await AppDatabase.open(
      schemas: [housekeepingSchema],
      factory: databaseFactoryFfi,
      path: path,
    );
    session = AppSession(database: database, staff: TestStaff());
    session.events.on<AppEvent>().listen(emitted.add);
    store = HousekeepingStore(session);
    listenToHotelEvents(session.events, store);
    backend = SqliteHousekeeping(store, events: session.events);
    catalog = SqliteRoomCatalog(store);
  }

  Future<void> reopen() async {
    final user = session.user;
    await session.database.close();
    await open();
    if (user != null) session.signIn(user);
  }

  void login(String id) =>
      session.signIn(TestStaff.people.firstWhere((u) => u.id == id));
  Future<Map<String, dynamic>> room([String number = '214']) async =>
      ((await store.readState())['rooms'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((r) => r['number'] == number);
  Future<void> action(
    String name, {
    String number = '214',
    Map<String, dynamic> extra = const {},
  }) async => backend.mutate('/v1/rooms/$number/$name', {
    'version': (await room(number))['version'],
    ...extra,
  });
  Future<void> photo(int index, {String number = '214'}) => action(
    'checklist',
    number: number,
    extra: {'index': index, 'value': true, 'photo': photoBase64()},
  );
  // Lets event listeners finish their queued database change.
  Future<void> settle() async {
    await pumpEventQueue();
    await store.readState();
  }

  setUp(() async {
    emitted.clear();
    directory = await Directory.systemTemp.createTemp('nova_housekeeping_');
    path = p.join(directory.path, 'test.db');
    await open();
  });
  tearDown(() async {
    await session.database.close();
    await directory.delete(recursive: true);
  });

  test('a new install has the sample rooms, stock and notifications in its own tables', () async {
    final tables = (await session.database.database.query(
      'sqlite_master',
      where: "type = 'table' AND name LIKE 'housekeeping_%'",
    )).map((t) => t['name']).toSet();
    expect(tables, {
      'housekeeping_rooms',
      'housekeeping_photos',
      'housekeeping_supplies',
      'housekeeping_notifications',
      'housekeeping_notification_reads',
      'housekeeping_cleanings',
      'housekeeping_lost_items',
      'housekeeping_category_tasks',
      'housekeeping_floors',
    });
    expect(await session.database.versionOf('housekeeping'), 2);
    login('amina');
    final state = await backend.snapshot();
    expect((state['rooms'] as List), hasLength(16));
    expect((state['supplies'] as List), hasLength(5));
    expect(
      (state['staff'] as List).map((s) => s['id']),
      containsAll(['amina', 'sarah', 'lina', 'youssef']),
    );
    expect((await room('109'))['cleaning'], 'waiting');
    expect(state.containsKey('users'), isFalse);
  });

  test(
    'the empty-hotel build option starts with nothing; the admin adds rooms',
    () async {
      final empty = housekeepingSeedState(samples: false);
      for (final key in [
        'rooms',
        'roomArchives',
        'supplies',
        'notifications',
      ]) {
        expect(empty[key], isEmpty, reason: key);
      }
      await session.database.close();
      final database = await AppDatabase.open(
        schemas: [
          ModuleSchema(
            module: 'housekeeping',
            version: 1,
            migrate: (tx, from, to) async {
              await housekeepingSchema.migrate(tx, from, to);
              for (final table in [
                'housekeeping_notifications',
                'housekeeping_supplies',
                'housekeeping_rooms',
              ]) {
                await tx.delete(table);
              }
            },
          ),
        ],
        factory: databaseFactoryFfi,
        path: p.join(directory.path, 'empty.db'),
      );
      session = AppSession(database: database, staff: TestStaff());
      store = HousekeepingStore(session);
      catalog = SqliteRoomCatalog(store);
      session.signIn(
        const AppUser(id: 'admin', fullName: 'Admin', role: AppRole.admin),
      );
      expect((await catalog.snapshot()).rooms, isEmpty);
      await catalog.mutate(RoomCatalogAction.create, {
        'number': '101',
        'category': 'Chambre Deluxe',
      });
      expect((await catalog.snapshot()).rooms.single.number, '101');
    },
  );

  test(
    'a version 1 database (phones already installed) upgrades in place',
    () async {
      login('amina');
      await action(
        'assign',
        number: '305',
        extra: {'employeeId': 'sarah', 'note': 'Avant midi', 'urgent': true},
      );
      final db = session.database.database;
      for (final table in [
        'housekeeping_cleanings',
        'housekeeping_lost_items',
        'housekeeping_category_tasks',
        'housekeeping_floors',
      ]) {
        await db.execute('DROP TABLE $table');
      }
      await db.execute('ALTER TABLE housekeeping_rooms DROP COLUMN feedback');
      await db.execute('ALTER TABLE housekeeping_rooms DROP COLUMN stayover');
      await db.update('module_versions', {
        'version': 1,
      }, where: "module = 'housekeeping'");
      await reopen();
      expect(await session.database.versionOf('housekeeping'), 2);
      final kept = await room('305');
      expect((kept['employeeId'], kept['note']), ('sarah', 'Avant midi'));
      expect((kept['stayover'], kept['feedback']), (false, null));
      login('sarah');
      await action('start', number: '305');
      expect((await room('305'))['cleaning'], 'inProgress');
    },
  );

  test('full cleaning cycle persists and announces the ready room', () async {
    login('amina');
    await action(
      'assign',
      number: '305',
      extra: {'employeeId': 'sarah', 'note': 'Avant 12h', 'urgent': true},
    );
    login('sarah');
    await action('start', number: '305');
    for (var i = 0; i < 3; i++) {
      await photo(i, number: '305');
    }
    await expectLater(action('submit', number: '305'), denied);
    await photo(3, number: '305');
    await action('submit', number: '305');
    await reopen();
    login('amina');
    final review = (await backend.snapshot())['notifications'] as List;
    expect(review.first['title'], 'Nettoyage à valider');
    await action('approve', number: '305');
    await reopen();
    final ready = await room('305');
    expect(
      (ready['status'], ready['cleaning'], ready['approvedBy']),
      ('ready', 'completed', 'Amina'),
    );
    expect(emitted.whereType<RoomReady>().single.roomNumber, '305');
  });

  test(
    'roles: agents clean only their rooms, the supervisor assigns and approves',
    () async {
      login('sarah');
      await expectLater(
        action(
          'assign',
          number: '305',
          extra: {'employeeId': 'sarah', 'note': '', 'urgent': false},
        ),
        denied,
      );
      await expectLater(
        backend.mutate('/v1/supplies/sheets/movement', {
          'version': 1,
          'delta': 2,
        }),
        denied,
      );
      login('lina');
      await expectLater(action('checklist', extra: {'index': 0}), denied);
      login('amina');
      await expectLater(action('start'), denied);
      await expectLater(
        action(
          'assign',
          number: '305',
          extra: {'employeeId': 'amina', 'note': '', 'urgent': false},
        ),
        denied,
        reason: 'only agents can be assigned',
      );
      login('manager');
      await expectLater(backend.snapshot(), denied);
      login('guest');
      await expectLater(backend.snapshot(), denied);
      await expectLater(catalog.snapshot(), denied);
    },
  );

  test('photos are required, private to the room’s agent and supervisor, and removed when unused', () async {
    login('sarah');
    await expectLater(
      action('checklist', extra: {'index': 0, 'value': true}),
      denied,
    );
    await expectLater(
      action(
        'checklist',
        extra: {
          'index': 0,
          'value': true,
          'photo': base64Encode([1, 2, 3]),
        },
      ),
      denied,
    );
    await photo(0);
    expect(await backend.taskPhoto('214', 'standard-0'), photoBase64());
    expect(
      jsonEncode(await backend.snapshot()).contains(photoBase64()),
      isFalse,
    );
    login('lina');
    await expectLater(backend.taskPhoto('214', 'standard-0'), denied);
    login('amina');
    expect(await backend.taskPhoto('214', 'standard-0'), photoBase64());
    await action(
      'assign',
      extra: {'employeeId': 'lina', 'note': '', 'urgent': false},
    );
    expect((await room())['checklist'].every((v) => v == false), isTrue);
    expect(
      await session.database.database.query('housekeeping_photos'),
      isEmpty,
    );
  });

  test(
    'the supervisor adds room tasks; a ready room needs cleaning again',
    () async {
      login('sarah');
      await expectLater(action('add-task', extra: {'label': 'Vitres'}), denied);
      login('amina');
      await action('add-task', extra: {'label': 'Nettoyer les vitres'});
      expect((await room())['tasks'], hasLength(5));
      await expectLater(
        action('add-task', extra: {'label': ' nettoyer LES VITRES '}),
        denied,
      );
      await action('add-task', number: '402', extra: {'label': 'Balcon'});
      expect((await room('402'))['status'], 'dirty');
      await action('add-task', number: '112', extra: {'label': 'Balcon'});
      expect((await room('112'))['status'], 'occupied');
    },
  );

  test(
    'stale versions are refused and a failed write changes nothing',
    () async {
      login('amina');
      final version = (await room('305'))['version'];
      await action(
        'assign',
        number: '305',
        extra: {'employeeId': 'sarah', 'note': '', 'urgent': false},
      );
      await expectLater(
        backend.mutate('/v1/rooms/305/assign', {
          'version': version,
          'employeeId': 'lina',
          'note': '',
          'urgent': false,
        }),
        throwsA(
          isA<AppServiceException>().having((e) => e.status, 'status', 409),
        ),
      );
      login('sarah');
      await session.database.database.execute(
        "CREATE TRIGGER fail_photo BEFORE INSERT ON housekeeping_photos BEGIN SELECT RAISE(ABORT, 'test'); END",
      );
      await expectLater(photo(0), denied);
      expect((await room())['checklist'][0], isFalse);
      expect((await room())['tasks'][0]['photoId'], isNull);
    },
  );

  test('stock moves are bounded and only for the supervisor', () async {
    login('amina');
    await backend.mutate('/v1/supplies/cleaner/movement', {
      'version': 1,
      'delta': 6,
    });
    await expectLater(
      backend.mutate('/v1/supplies/cleaner/movement', {
        'version': 2,
        'delta': -100,
      }),
      denied,
    );
    await reopen();
    final supplies = (await store.readState())['supplies'] as List;
    expect(supplies.firstWhere((s) => s['id'] == 'cleaner')['quantity'], 10);
  });

  test('low stock alerts the supervisor once each time an item crosses its minimum', () async {
    login('amina');
    Future<void> move(String id, int delta) async {
      final supplies = (await store.readState())['supplies'] as List;
      final s = supplies.firstWhere((s) => s['id'] == id);
      await backend.mutate('/v1/supplies/$id/movement', {
        'version': s['version'],
        'delta': delta,
      });
    }

    Future<List<String>> alerts() async => [
      for (final n in (await backend.snapshot())['notifications'] as List)
        if ('${n['title']}'.contains('tock')) '${n['title']} | ${n['message']}',
    ];

    // Draps propres: 42, minimum 15.
    await move('sheets', -20);
    expect(await alerts(), isEmpty);
    await move('sheets', -7);
    expect(await alerts(), [
      'Stock bas | Draps propres : il reste 15 pièces (minimum 15). Pensez à réapprovisionner.',
    ]);
    await move('sheets', -5);
    expect(await alerts(), hasLength(1), reason: 'already below the minimum');
    await move('sheets', 30);
    await move('sheets', -40);
    final all = await alerts();
    expect(all, hasLength(2));
    expect(
      all.first,
      startsWith('Rupture de stock | Draps propres : stock épuisé'),
    );
    final notes = (await backend.snapshot())['notifications'] as List;
    expect(notes.first['roomNumber'], '');
    expect(notes.first['audience'], 'supervisor');

    login('sarah');
    final forAgent = (await backend.snapshot())['notifications'] as List;
    expect(forAgent.any((n) => '${n['title']}'.contains('tock')), isFalse);
  });

  test('notification reads belong to each user', () async {
    login('amina');
    final ids = [
      for (final n in (await backend.snapshot())['notifications'] as List)
        n['id'],
    ];
    await backend.mutate('/v1/notifications/read', {'ids': ids});
    login('sarah');
    final forSarah = (await backend.snapshot())['notifications'] as List;
    expect(forSarah.every((n) => n['audience'] != 'supervisor'), isTrue);
    expect(forSarah.any((n) => n['read'] == false), isTrue);
  });

  test('the manager creates, edits, archives and restores rooms', () async {
    login('manager');
    await catalog.mutate(RoomCatalogAction.create, {
      'number': '501',
      'category': 'Suite',
    });
    await expectLater(
      catalog.mutate(RoomCatalogAction.create, {
        'number': '501',
        'category': 'Suite',
      }),
      denied,
    );
    var rooms = await catalog.snapshot();
    final created = rooms.rooms.firstWhere((r) => r.number == '501');
    expect(created.status.name, 'dirty');
    await catalog.mutate(RoomCatalogAction.update, {
      'number': '501',
      'category': 'Suite Prestige',
      'version': created.version,
    });
    rooms = await catalog.snapshot();
    final occupied = rooms.rooms.firstWhere((r) => r.number == '112');
    await expectLater(
      catalog.mutate(RoomCatalogAction.archive, {
        'number': '112',
        'version': occupied.version,
      }),
      denied,
    );
    final ready = rooms.rooms.firstWhere((r) => r.number == '402');
    await catalog.mutate(RoomCatalogAction.archive, {
      'number': '402',
      'version': ready.version,
    });
    await reopen();
    rooms = await catalog.snapshot();
    expect(rooms.archivedRooms.map((r) => r.number), ['402']);
    expect(
      rooms.rooms.firstWhere((r) => r.number == '501').category,
      'Suite Prestige',
    );
    login('amina');
    expect(
      ((await backend.snapshot())['rooms'] as List).any(
        (r) => r['number'] == '402',
      ),
      isFalse,
    );
    login('manager');
    await catalog.mutate(RoomCatalogAction.restore, {
      'number': '402',
      'version': rooms.archivedRooms.single.version,
    });
    expect((await room('402'))['status'], 'dirty');
  });

  test('reservations events: check-in occupies, check-out sends the room to cleaning', () async {
    session.events.emit(const GuestCheckedIn('402', guestName: 'M. Martin'));
    await settle();
    expect((await room('402'))['status'], 'occupied');
    session.events.emit(const GuestCheckedOut('402'));
    session.events.emit(const GuestCheckedOut('999'));
    await settle();
    final r = await room('402');
    expect(
      (r['status'], r['cleaning'], r['employeeId']),
      ('dirty', 'waiting', null),
    );
    login('amina');
    final notes = (await backend.snapshot())['notifications'] as List;
    expect(notes.first['title'], 'Départ client');
  });

  test('maintenance events and reports from housekeeping', () async {
    session.events.emit(
      const MaintenanceRequested('305', description: 'Fuite', urgent: true),
    );
    await settle();
    expect((await room('305'))['status'], 'maintenance');
    session.events.emit(const MaintenanceResolved('305'));
    await settle();
    expect((await room('305'))['status'], 'dirty');

    login('sarah');
    await expectLater(
      action(
        'report',
        number: '305',
        extra: {'description': 'Lampe', 'urgent': false},
      ),
      denied,
      reason: 'not assigned to Sarah',
    );
    await action(
      'report',
      extra: {'description': 'Lavabo bouché', 'urgent': true},
    );
    await settle();
    final reported = await room();
    expect((reported['status'], reported['employeeId']), ('maintenance', null));
    final request = emitted.whereType<MaintenanceRequested>().last;
    expect(
      (request.roomNumber, request.description, request.urgent),
      ('214', 'Lavabo bouché', true),
    );
    login('amina');
    await action(
      'report',
      number: '112',
      extra: {'description': 'Télévision', 'urgent': false},
    );
    await settle();
    final occupied = await room('112');
    expect(occupied['status'], 'occupied');
    expect(
      (occupied['history'] as List).where((h) => '$h'.contains('Télévision')),
      hasLength(1),
      reason: 'the own event is not applied twice',
    );
    await expectLater(
      action('report', extra: {'description': 'Encore', 'urgent': false}),
      denied,
    );
  });
}
