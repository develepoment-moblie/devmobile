import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/housekeeping/services/demo_hotel.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_store.dart';
import 'package:nova_paris/shared/models/app_user.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:nova_paris/user_management/services/demo_staff_directory.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// The presentation's demo hotel builds through the real rules, on SQLite.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late Directory dir;
  late AppDatabase database;
  late AppSession session;
  late HousekeepingStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('nova_demo_');
    database = await AppDatabase.open(
      schemas: [housekeepingSchema],
      factory: databaseFactoryFfi,
      path: p.join(dir.path, 'demo.db'),
    );
    session = AppSession(database: database, staff: const DemoStaffDirectory());
    store = HousekeepingStore(session);
    await clearHousekeeping(store); // the sample data of a new install
  });
  tearDown(() async {
    await database.close();
    await dir.delete(recursive: true);
  });

  Future<String?> marker() async {
    final rows = await database.database.query(
      'housekeeping_sync_state',
      where: "key = 'demo_hotel'",
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  // Every time recorded today, as text (ISO 8601 sorts like the time).
  Future<List<String>> todayTimes(Map<String, dynamic> state) async => [
    for (final c in state['cleanings'] as List)
      for (final k in ['assigned_at', 'started_at', 'submitted_at'])
        if (c[k] case final String t) t,
    for (final s in state['timerSegments'] as List)
      if (s['started_at'] case final String t) t,
    for (final i in state['issues'] as List) i['reported_at'] as String,
  ];

  test('the demo hotel fills every screen with coherent data', () async {
    // Signed in as someone else on the phone: the fill does not care
    // and does not change it.
    final reception = DemoStaffDirectory.people.firstWhere(
      (u) => u.role == AppRole.receptionist,
    );
    session.signIn(reception);
    var signals = 0;
    final sub = store.changes.listen((_) => signals++);
    final now = DateTime(2026, 11, 20, 15, 30);
    final summary = await fillDemoHotelIfEmpty(store, now: now);
    await sub.cancel();
    expect(summary, startsWith('26 chambres'));
    expect(session.user, reception);
    expect(signals, greaterThan(100), reason: 'the screens are told');
    expect(await marker(), 'done');

    final state = await store.readState();
    final rooms = (state['rooms'] as List).cast<Map<String, dynamic>>();
    Map<String, dynamic> room(String n) =>
        rooms.firstWhere((r) => r['number'] == n);
    expect(rooms, hasLength(26));
    expect(room('202')['cleaning'], 'review');
    expect(room('302')['cleaning'], 'inProgress');
    expect(room('304')['cleaning'], 'waiting');
    expect(room('208')['employeeId'], isNull);
    expect(room('305')['status'], 'maintenance');
    expect(state['cleanings'] as List, hasLength(29));
    expect(state['inspections'] as List, hasLength(24));
    expect(state['issues'] as List, hasLength(4));
    expect(state['lostItems'] as List, hasLength(3));
    expect(state['requests'] as List, hasLength(3));
    expect(state['minibar'] as List, hasLength(4));
    // Nothing is queued for a sync server.
    expect(await database.database.query('housekeeping_sync_outbox'), isEmpty);
    // Nothing happens after the real time of the fill.
    for (final t in await todayTimes(state)) {
      expect(
        DateTime.parse(t).isAfter(now),
        isFalse,
        reason: '$t is after the fill',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('early in the morning, today still happens before the fill; '
      'tomorrow is the next calendar day', () async {
    final now = DateTime(2026, 10, 25, 8); // daylight saving ends today
    await fillDemoHotelIfEmpty(store, now: now);
    final state = await store.readState();
    for (final t in await todayTimes(state)) {
      expect(DateTime.parse(t).isAfter(now), isFalse, reason: t);
    }
    final off = (state['availability'] as List).single;
    expect(off['agent_id'], 'youssef');
    expect(off['date'], '2026-10-26');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('the demo is filled once, never over the hotel\'s own data', () async {
    // The hotel already has its own room: left alone.
    session.signIn(
      DemoStaffDirectory.people.firstWhere((u) => u.id == 'manager'),
    );
    await store.change(
      (s) => (s['rooms'] as List).add({
        'number': '999',
        'category': 'Suite',
        'status': 'dirty',
        'cleaning': 'waiting',
        'employeeId': null,
        'checklist': [false],
        'tasks': [
          {'id': 'task-0', 'label': 'Ménage', 'photoId': null},
        ],
        'history': <String>[],
        'version': 1,
      }),
    );
    expect(await fillDemoHotelIfEmpty(store), isNull);
    expect(await marker(), isNull);
    expect((await store.readState())['rooms'] as List, hasLength(1));
  });

  test('a phone set to a sync server is not filled', () async {
    await database.database.insert('housekeeping_sync_state', {
      'key': 'server_url',
      'value': 'http://192.168.1.20:8080',
    });
    expect(await fillDemoHotelIfEmpty(store), isNull);
    expect((await store.readState())['rooms'] as List, isEmpty);
  });

  test('a fill cut off is redone from an empty hotel', () async {
    // What a fill stopped halfway leaves: the marker and some rooms.
    await database.database.insert('housekeeping_sync_state', {
      'key': 'demo_hotel',
      'value': 'started',
    });
    session.signIn(
      DemoStaffDirectory.people.firstWhere((u) => u.id == 'manager'),
    );
    await store.change(
      (s) => (s['rooms'] as List).add({
        'number': '101',
        'category': 'Ancienne',
        'status': 'dirty',
        'cleaning': 'waiting',
        'employeeId': null,
        'checklist': [false],
        'tasks': [
          {'id': 'task-0', 'label': 'Ménage', 'photoId': null},
        ],
        'history': <String>[],
        'version': 1,
      }),
    );
    expect(await fillDemoHotelIfEmpty(store), startsWith('26 chambres'));
    expect(await marker(), 'done');
    final rooms = (await store.readState())['rooms'] as List;
    expect(rooms, hasLength(26));
    expect(
      rooms.firstWhere((r) => r['number'] == '101')['category'],
      'Chambre Classique',
    );
    // Done: a later start leaves it alone.
    expect(await fillDemoHotelIfEmpty(store), isNull);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
