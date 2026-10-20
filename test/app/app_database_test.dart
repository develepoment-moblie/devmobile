import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_events.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory directory;
  late String path;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nova_db_test_');
    path = p.join(directory.path, 'nova.db');
  });
  tearDown(() => directory.delete(recursive: true));

  Future<AppDatabase> open(List<ModuleSchema> schemas) => AppDatabase.open(
    schemas: schemas,
    factory: databaseFactoryFfi,
    path: path,
  );

  ModuleSchema bookings(int version) => ModuleSchema(
    module: 'reservations',
    version: version,
    migrate: (tx, from, to) async {
      if (from < 1) {
        await tx.execute(
          'CREATE TABLE reservations_bookings (id TEXT PRIMARY KEY, room TEXT NOT NULL)',
        );
      }
      // Simulates an older app version that only knew version 1.
      if (from < 2 && to >= 2) {
        await tx.execute(
          "ALTER TABLE reservations_bookings ADD COLUMN guest TEXT NOT NULL DEFAULT ''",
        );
      }
    },
  );
  final rooms = ModuleSchema(
    module: 'housekeeping',
    version: 1,
    migrate: (tx, from, to) =>
        tx.execute('CREATE TABLE housekeeping_rooms (number TEXT PRIMARY KEY)'),
  );

  test(
    'each module migrates its own tables and version independently',
    () async {
      var db = await open([bookings(1), rooms]);
      await db.database.insert('reservations_bookings', {
        'id': 'b1',
        'room': '305',
      });
      await db.database.insert('housekeeping_rooms', {'number': '305'});
      await db.close();

      db = await open([bookings(2), rooms]);
      expect(await db.versionOf('reservations'), 2);
      expect(await db.versionOf('housekeeping'), 1);
      final row = (await db.database.query('reservations_bookings')).single;
      expect((row['room'], row['guest']), ('305', ''));
      expect(await db.database.query('housekeeping_rooms'), hasLength(1));
      await db.close();
    },
  );

  test(
    'a failed migration changes nothing and data from a newer app is refused',
    () async {
      var db = await open([bookings(2)]);
      await db.close();
      final broken = ModuleSchema(
        module: 'maintenance',
        version: 1,
        migrate: (tx, from, to) async {
          await tx.execute(
            'CREATE TABLE maintenance_requests (id TEXT PRIMARY KEY)',
          );
          throw StateError('boom');
        },
      );
      await expectLater(open([bookings(2), broken]), throwsStateError);
      await expectLater(open([bookings(1)]), throwsStateError);
      db = await open([bookings(2)]);
      expect(await db.versionOf('maintenance'), 0);
      final tables = await db.database.query(
        'sqlite_master',
        where: "name = 'maintenance_requests'",
      );
      expect(tables, isEmpty);
      await db.close();
    },
  );

  test('events reach only the listeners of their type', () async {
    final events = AppEvents();
    final checkouts = <String>[];
    final subscription = events.on<GuestCheckedOut>().listen(
      (e) => checkouts.add(e.roomNumber),
    );
    events.emit(const GuestCheckedOut('305'));
    events.emit(const RoomReady('305'));
    await Future<void>.delayed(Duration.zero);
    expect(checkouts, ['305']);
    await subscription.cancel();
    await events.dispose();
  });
}
