import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nova_paris/shared/services/backup_codec.dart';
import 'package:nova_paris/user_management/services/sqlite_user_repository.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_api.dart';
import 'package:nova_paris/housekeeping/services/room_catalog_backend.dart';
import 'package:nova_paris/housekeeping/services/sqlite_housekeeping.dart';
import 'package:nova_paris/housekeeping/services/sqlite_room_catalog.dart';

import 'photo_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SqliteUserRepository store;
  late Directory directory;
  late String dbPath;
  Future<SqliteUserRepository> open() =>
      SqliteUserRepository.open(factory: databaseFactoryFfi, path: dbPath);
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nova_sqlite_test_');
    dbPath = p.join(directory.path, 'nova.db');
    store = await open();
  });
  tearDown(() async {
    await store.dispose();
    await directory.delete(recursive: true);
  });
  Future<void> login(String name) =>
      store.login('$name@nova.test', SqliteUserRepository.demoPassword);
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
      final reopened = await open();
      addTearDown(reopened.dispose);
      expect(reopened.sessionUserId, 'manager');
      await reopened.login('new@nova.test', 'secret1');
      expect((await reopened.currentProfile()).role, 'supervisor');
      user = (await store.allProfiles()).firstWhere((u) => u.id == user.id);
      await store.deleteProfile(user);
      await expectLater(store.login('new@nova.test', 'secret1'), denied);
      final fresh = await open();
      addTearDown(fresh.dispose);
      await expectLater(fresh.login('new@nova.test', 'secret1'), denied);
      final rows = await store.storage.database.query('users');
      expect(rows.any((row) => row.values.contains('secret1')), isFalse);
      expect(rows.map((row) => row['salt']).toSet().length, rows.length);
    },
  );

  test('users change their password and managers reset others', () async {
    await login('sarah');
    await expectLater(store.changePassword('wrong!', 'nouveau1'), denied);
    await expectLater(
      store.changePassword(SqliteUserRepository.demoPassword, 'court'),
      denied,
    );
    await store.changePassword(SqliteUserRepository.demoPassword, 'nouveau1');
    await store.logout();
    await expectLater(login('sarah'), denied);
    await store.login('sarah@nova.test', 'nouveau1');

    var sarah = (await store.currentProfile());
    await expectLater(store.resetPassword(sarah, 'temp123'), denied);
    await login('manager');
    final manager = await store.currentProfile();
    await expectLater(store.resetPassword(manager, 'temp123'), denied);
    sarah = (await store.allProfiles()).firstWhere((u) => u.id == 'sarah');
    await store.resetPassword(sarah, 'temp123');
    await expectLater(store.resetPassword(sarah, 'stale12'), denied);
    expect(store.sessionUserId, 'manager');

    final reopened = await open();
    addTearDown(reopened.dispose);
    await expectLater(reopened.login('sarah@nova.test', 'nouveau1'), denied);
    await reopened.login('sarah@nova.test', 'temp123');
    final rows = await store.storage.database.query('users');
    expect(
      rows.any(
        (row) => row.values.any(
          (v) => v.toString().contains('temp123') ||
              v.toString().contains('nouveau1'),
        ),
      ),
      isFalse,
    );
  });

  test('manager priorities are seeded, versioned and manager only', () async {
    await login('sarah');
    await expectLater(store.priorities(), denied);
    await expectLater(
      store.savePriority(
        null,
        icon: 'bed',
        title: 'Agent',
        subtitle: '',
        colorType: 'danger',
      ),
      denied,
    );
    await login('manager');
    var items = await store.priorities();
    expect(items.map((p) => p.title), contains('Arrivée VIP'));
    await store.savePriority(
      null,
      icon: 'spa',
      title: 'Spa fermé',
      subtitle: 'Jusqu’à 14h',
      colorType: 'terra',
    );
    await expectLater(
      store.savePriority(
        null,
        icon: 'unknown',
        title: 'Bad',
        subtitle: '',
        colorType: 'danger',
      ),
      denied,
    );
    items = await store.priorities();
    final spa = items.first;
    expect(spa.title, 'Spa fermé');
    await store.savePriority(
      spa,
      icon: 'spa',
      title: 'Spa rouvert',
      subtitle: '',
      colorType: 'success',
    );
    await expectLater(store.deletePriority(spa), denied);
    final reopened = await open();
    addTearDown(reopened.dispose);
    final updated = (await reopened.priorities()).firstWhere(
      (p) => p.id == spa.id,
    );
    expect((updated.title, updated.version), ('Spa rouvert', 2));
    await reopened.deletePriority(updated);
    expect((await store.priorities()).any((p) => p.id == spa.id), isFalse);
    final snapshot = await store.backupSnapshot();
    expect(snapshot['priorities'], isNotEmpty);
    expect(() => BackupCodec.validate(snapshot), returnsNormally);
    snapshot.remove('priorities');
    expect(() => BackupCodec.validate(snapshot), returnsNormally);
  });

  test(
    'registration is guest only and agents cannot manage users or stock',
    () async {
      await store.register('client@nova.test', 'secret1', 'Client');
      expect((await store.currentProfile()).role, 'guest');
      await expectLater(SqliteHousekeeping(store).snapshot(), denied);
      await expectLater(store.allProfiles(), denied);
      await login('sarah');
      await expectLater(
        store.createUser('bad@nova.test', 'secret1', 'Bad', 'manager'),
        denied,
      );
      await expectLater(
        SqliteHousekeeping(store)
            .mutate('/v1/supplies/sheets/movement', {'version': 1, 'delta': 2}),
        denied,
      );
      await expectLater(
        SqliteHousekeeping(store).mutate('/v1/rooms/305/assign', {
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
      final backend = SqliteHousekeeping(store);
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
          'photo': photoBase64(),
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
      final reopened = await open();
      addTearDown(reopened.dispose);
      await reopened.login(
        'amina@nova.test',
        SqliteUserRepository.demoPassword,
      );
      final snapshot = await SqliteHousekeeping(reopened).snapshot();
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
    final backend = SqliteHousekeeping(store);
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

  test(
    'room catalog persists archives and restoration and enforces roles',
    () async {
      await login('manager');
      final catalog = SqliteRoomCatalog(store);
      await catalog.mutate(RoomCatalogAction.create, {
        'number': '901',
        'category': 'Suite',
      });
      await catalog.mutate(RoomCatalogAction.update, {
        'number': '901',
        'category': 'Suite Prestige',
        'version': 1,
      });
      await catalog.mutate(RoomCatalogAction.archive, {
        'number': '901',
        'version': 2,
      });
      await expectLater(
        catalog.mutate(RoomCatalogAction.create, {
          'number': '901',
          'category': 'Duplicate',
        }),
        denied,
      );
      for (final number in ['112', '224', '214', '109']) {
        await expectLater(
          catalog.mutate(RoomCatalogAction.archive, {
            'number': number,
            'version': 1,
          }),
          denied,
        );
      }
      final reopened = await open();
      addTearDown(reopened.dispose);
      await reopened.login(
        'manager@nova.test',
        SqliteUserRepository.demoPassword,
      );
      expect(
        (await SqliteRoomCatalog(
          reopened,
        ).snapshot()).archivedRooms.single.category,
        'Suite Prestige',
      );
      await SqliteRoomCatalog(reopened)
          .mutate(RoomCatalogAction.restore, {'number': '901', 'version': 3});
      final room = (await catalog.snapshot()).rooms.firstWhere(
        (r) => r.number == '901',
      );
      expect(room.version, 4);
      expect(room.needsCleaning, true);
      await login('sarah');
      await expectLater(catalog.snapshot(), denied);
      await expectLater(
        catalog.mutate(RoomCatalogAction.create, {
          'number': '902',
          'category': 'Suite',
        }),
        denied,
      );
    },
  );

  test(
    'two connections reject stale changes without losing committed data',
    () async {
      await login('amina');
      final second = await open();
      addTearDown(second.dispose);
      await second.login('amina@nova.test', SqliteUserRepository.demoPassword);
      await SqliteHousekeeping(store)
          .mutate('/v1/supplies/sheets/movement', {'version': 1, 'delta': -2});
      await expectLater(
        SqliteHousekeeping(
          second,
        ).mutate('/v1/supplies/sheets/movement', {'version': 1, 'delta': -3}),
        denied,
      );
      await SqliteHousekeeping(second)
          .mutate('/v1/supplies/sheets/movement', {'version': 2, 'delta': 1});
      final rows =
          (await SqliteHousekeeping(store).snapshot())['supplies'] as List;
      expect(rows.firstWhere((r) => r['id'] == 'sheets')['quantity'], 41);
    },
  );

  test(
    'failed SQL write rolls back room, history and notification together',
    () async {
      await login('sarah');
      final backend = SqliteHousekeeping(store);
      for (var i = 0; i < 4; i++) {
        await backend.mutate('/v1/rooms/214/checklist', {
          'version': 1 + i,
          'index': i,
          'value': true,
          'photo': photoBase64(),
        });
      }
      final before = await backend.snapshot();
      final historyLength =
          ((before['rooms'] as List).firstWhere(
                    (r) => r['number'] == '214',
                  )['history']
                  as List)
              .length;
      await store.storage.database.execute(
        '''CREATE TRIGGER fail_notification
      BEFORE INSERT ON notifications BEGIN SELECT RAISE(ABORT, 'test failure'); END''',
      );
      await expectLater(
        backend.mutate('/v1/rooms/214/submit', {'version': 5}),
        denied,
      );
      var snapshot = await backend.snapshot();
      final room = (snapshot['rooms'] as List).firstWhere(
        (r) => r['number'] == '214',
      );
      expect(room['version'], 5);
      expect(room['cleaning'], 'inProgress');
      expect((room['history'] as List).length, historyLength);
      expect(
        await store.storage.database.query(
          'notifications',
          where: 'id = ?',
          whereArgs: ['review-214-5'],
        ),
        isEmpty,
      );
      expect(
        (snapshot['notifications'] as List).any(
          (n) => n['id'] == 'review-214-5',
        ),
        false,
      );
      await store.storage.database.execute('DROP TRIGGER fail_notification');
      await backend.mutate('/v1/rooms/214/submit', {'version': 5});
      snapshot = await backend.snapshot();
      expect(
        (snapshot['rooms'] as List).firstWhere(
          (r) => r['number'] == '214',
        )['cleaning'],
        'review',
      );
    },
  );
}
