import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nova_paris/app/backup_service.dart';
import 'package:nova_paris/housekeeping/services/room_catalog_backend.dart';
import 'package:nova_paris/housekeeping/services/sqlite_housekeeping.dart';
import 'package:nova_paris/housekeeping/services/sqlite_room_catalog.dart';
import 'package:nova_paris/shared/services/app_exception.dart';
import 'package:nova_paris/shared/services/backup_codec.dart';
import 'package:nova_paris/user_management/services/sqlite_user_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late String path;
  late SqliteUserRepository store;
  Future<SqliteUserRepository> open() =>
      SqliteUserRepository.open(factory: databaseFactoryFfi, path: path);
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nova_backup_test_');
    path = p.join(directory.path, 'nova.db');
    store = await open();
  });
  tearDown(() async {
    await store.dispose();
    await directory.delete(recursive: true);
  });
  Future<void> login(String name) =>
      store.login('$name@nova.test', SqliteUserRepository.demoPassword);
  final denied = throwsA(isA<AppServiceException>());

  test('sign-in survives reopening, logout persists, and failed login saves nothing', () async {
    await login('sarah');
    await store.dispose();
    store = await open();
    expect(store.sessionUserId, 'sarah');
    expect((await store.currentProfile()).role, 'staff');
    await store.logout();
    await expectLater(store.login('sarah@nova.test', 'wrong'), denied);
    await store.dispose();
    store = await open();
    expect(store.sessionUserId, isNull);
    final metadata = await store.storage.database.query('metadata');
    expect(
      metadata.any((r) => r['value'] == SqliteUserRepository.demoPassword),
      false,
    );
  });

  test('restored session reads the current role and a deleted profile cannot return', () async {
    await login('sarah');
    final manager = await open();
    addTearDown(manager.dispose);
    await manager.login('manager@nova.test', SqliteUserRepository.demoPassword);
    var sarah = (await manager.allProfiles()).firstWhere(
      (u) => u.id == 'sarah',
    );
    await manager.updateUser(sarah, 'Sarah', 'supervisor');
    await login('sarah');
    final reopened = await open();
    addTearDown(reopened.dispose);
    expect((await reopened.currentProfile()).role, 'supervisor');
    sarah = (await manager.allProfiles()).firstWhere((u) => u.id == 'sarah');
    await manager.deleteProfile(sarah);
    await expectLater(reopened.currentProfile(), denied);
    expect(reopened.sessionUserId, isNull);
    final fresh = await open();
    addTearDown(fresh.dispose);
    expect(fresh.sessionUserId, isNull);
  });

  test(
    'unknown remembered identity is cleared instead of gaining access',
    () async {
      await store.storage.database.insert('metadata', {
        'key': 'session_user',
        'value': 'missing-user',
      });
      await store.dispose();
      store = await open();
      expect(store.sessionUserId, isNull);
      expect(
        await store.storage.database.query(
          'metadata',
          where: 'key = ?',
          whereArgs: ['session_user'],
        ),
        isEmpty,
      );
    },
  );

  test('encrypted backup restores accounts, rooms, archives, stock and read receipts', () async {
    await login('sarah');
    await SqliteHousekeeping(store).mutate('/v1/notifications/read', {
      'ids': ['vip305'],
    });
    await login('manager');
    await store.createUser(
      'backup@nova.test',
      'newsecret',
      'Saved agent',
      'staff',
    );
    await SqliteRoomCatalog(store)
        .mutate(RoomCatalogAction.archive, {'number': '402', 'version': 1});
    final service = LocalBackupService(store);
    final bytes = await service.create('backup-password');
    final text = utf8.decode(bytes);
    expect(text.contains('manager@nova.test'), false);
    expect(text.contains('newsecret'), false);
    expect(text.contains('session_user'), false);
    final preview = await service.inspect(bytes, 'backup-password');
    expect(preview.users, 7);
    expect(preview.archivedRooms, 1);
    await SqliteRoomCatalog(store).mutate(RoomCatalogAction.create, {
      'number': '901',
      'category': 'Later room',
    });
    await service.restore(preview);
    expect(store.sessionUserId, isNull);
    await store.dispose();
    store = await open();
    expect(store.sessionUserId, isNull);
    await store.login('backup@nova.test', 'newsecret');
    expect((await store.currentProfile()).fullName, 'Saved agent');
    await login('manager');
    final rooms = await SqliteRoomCatalog(store).snapshot();
    expect(rooms.rooms.any((r) => r.number == '901'), false);
    expect(rooms.archivedRooms.single.number, '402');
    await login('sarah');
    final snapshot = await SqliteHousekeeping(store).snapshot();
    expect(
      (snapshot['notifications'] as List).firstWhere(
        (n) => n['id'] == 'vip305',
      )['read'],
      true,
    );
    expect((snapshot['supplies'] as List).length, 5);
  });

  test('wrong password, tampered ciphertext and unsupported files never replace data', () async {
    await login('manager');
    final service = LocalBackupService(store);
    final bytes = await service.create('backup-password');
    final before = await store.backupSnapshot();
    await expectLater(service.inspect(bytes, 'wrong-password'), denied);
    final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final cipher = base64Decode(envelope['data'] as String);
    cipher[0] ^= 1;
    envelope['data'] = base64Encode(cipher);
    await expectLater(
      service.inspect(
        Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
        'backup-password',
      ),
      denied,
    );
    envelope['version'] = 999;
    await expectLater(
      service.inspect(
        Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
        'backup-password',
      ),
      denied,
    );
    await expectLater(
      service.inspect(Uint8List.fromList([1, 2, 3]), 'password1'),
      denied,
    );
    expect(await store.backupSnapshot(), before);
    expect(store.sessionUserId, 'manager');
  });

  test(
    'non-managers cannot export or restore, even with a decoded file',
    () async {
      await login('manager');
      final state = await store.backupSnapshot();
      for (final role in ['sarah', 'amina', 'guest']) {
        await login(role);
        await expectLater(store.backupSnapshot(), denied);
        await expectLater(store.restoreSnapshot(state), denied);
      }
    },
  );

  test(
    'invalid identities, orphan assignments and missing manager are rejected',
    () async {
      await login('manager');
      final state = await store.backupSnapshot();
      Map<String, dynamic> clone() =>
          jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
      final badStates = <Map<String, dynamic>>[];
      var bad = clone();
      (bad['users'] as List).add((bad['users'] as List).first);
      badStates.add(bad);
      bad = clone();
      (bad['rooms'] as List).first['employeeId'] = 'missing-agent';
      badStates.add(bad);
      bad = clone();
      (bad['users'] as List).firstWhere(
        (u) => u['id'] == 'manager',
      )['deleted'] = true;
      badStates.add(bad);
      bad = clone();
      (bad['rooms'] as List).first['checklist'] = [true];
      badStates.add(bad);
      for (final invalid in badStates) {
        await expectLater(
          Future.sync(() => store.restoreSnapshot(invalid)),
          denied,
        );
      }
      expect(await store.backupSnapshot(), state);
    },
  );

  test(
    'SQL failure during replacement rolls back all data and remembered sign-in',
    () async {
      await login('manager');
      final before = await store.backupSnapshot();
      await store.storage.database.execute(
        "CREATE TRIGGER fail_restore BEFORE INSERT ON supplies BEGIN SELECT RAISE(ABORT, 'test rollback'); END",
      );
      await expectLater(store.restoreSnapshot(before), denied);
      expect(await store.backupSnapshot(), before);
      expect(store.sessionUserId, 'manager');
      final reopened = await open();
      addTearDown(reopened.dispose);
      expect(reopened.sessionUserId, 'manager');
    },
  );

  test(
    'backup format rejects unbounded KDF parameters and oversized input',
    () async {
      await expectLater(
        BackupCodec.decode(Uint8List(BackupCodec.maxBytes + 1), 'password1'),
        denied,
      );
      final fake = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'format': 'nova-paris-backup',
            'version': 1,
            'iterations': 999999999,
          }),
        ),
      );
      await expectLater(BackupCodec.decode(fake, 'password1'), denied);
    },
  );
}
