import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nova_paris/shared/services/app_exception.dart';
import 'package:nova_paris/shared/services/backup_codec.dart';
import 'package:nova_paris/shared/services/evidence_photo.dart';
import 'package:nova_paris/housekeeping/services/sqlite_housekeeping.dart';
import 'package:nova_paris/housekeeping/services/sqlite_room_catalog.dart';
import 'package:nova_paris/housekeeping/services/room_catalog_backend.dart';
import 'package:nova_paris/user_management/services/sqlite_user_repository.dart';

import 'photo_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late SqliteUserRepository store;
  late Directory directory;
  late String path;
  late SqliteHousekeeping backend;
  Future<void> login(String name) => store.login('$name@nova.test', 'Nova123!');
  Future<Map<String, dynamic>> room([String number = '214']) async =>
      ((await backend.snapshot())['rooms'] as List)
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
  final denied = throwsA(isA<AppServiceException>());
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nova_evidence_');
    path = p.join(directory.path, 'test.db');
    store = await SqliteUserRepository.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    backend = SqliteHousekeeping(store);
  });
  tearDown(() async {
    await store.dispose();
    await directory.delete(recursive: true);
  });
  test(
    'gouvernante adds room-specific tasks; agents and manager cannot',
    () async {
      await login('sarah');
      await expectLater(
        action('add-task', extra: {'label': 'Nettoyer les vitres'}),
        denied,
      );
      await login('manager');
      await expectLater(
        backend.mutate('/v1/rooms/214/add-task', {'version': 1, 'label': 'X'}),
        denied,
      );
      await login('amina');
      await action('add-task', extra: {'label': 'Nettoyer les vitres'});
      final r = await room();
      expect((r['tasks'] as List).length, 5);
      expect((r['checklist'] as List).length, 5);
      expect(((await room('305'))['tasks'] as List).length, 4);
      await expectLater(
        action('add-task', extra: {'label': ' nettoyer LES VITRES '}),
        denied,
      );
      await expectLater(action('add-task', extra: {'label': '  '}), denied);
      await expectLater(
        backend.mutate('/v1/rooms/214/add-task', {
          'version': 1,
          'label': 'Autre tâche',
        }),
        denied,
      );
      await store.dispose();
      store = await SqliteUserRepository.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      backend = SqliteHousekeeping(store);
      expect((await room())['tasks'].last['label'], 'Nettoyer les vitres');
    },
  );
  test('completion requires real photo, persists atomically, and access follows ownership', () async {
    await login('sarah');
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
    expect((await room())['checklist'][0], false);
    await action(
      'checklist',
      extra: {'taskId': 'standard-0', 'value': true, 'photo': photoBase64()},
    );
    expect((await room())['checklist'][0], true);
    expect(await backend.taskPhoto('214', 'standard-0'), photoBase64());
    final snapshot = await backend.snapshot();
    expect(snapshot.containsKey('photoData'), false);
    expect(jsonEncode(snapshot).contains(photoBase64()), false);
    await expectLater(action('submit'), denied);
    await login('lina');
    await expectLater(backend.taskPhoto('214', 'standard-0'), denied);
    await login('amina');
    expect(await backend.taskPhoto('214', 'standard-0'), photoBase64());
    await action(
      'assign',
      extra: {
        'employeeId': 'lina',
        'note': 'Nouvelle attribution',
        'urgent': false,
      },
    );
    expect((await room())['checklist'].every((v) => v == false), true);
    expect(await store.storage.database.query('task_photos'), isEmpty);
    await login('sarah');
    await expectLater(
      action(
        'checklist',
        extra: {'index': 0, 'value': true, 'photo': photoBase64()},
      ),
      denied,
    );
  });
  test(
    'all custom tasks need photos; additions reopen inspection and ready rooms',
    () async {
      await login('amina');
      await action('add-task', extra: {'label': 'Vérifier le balcon'});
      await login('sarah');
      for (var i = 0; i < 4; i++) {
        await action(
          'checklist',
          extra: {'index': i, 'value': true, 'photo': photoBase64()},
        );
      }
      await expectLater(action('submit'), denied);
      await action(
        'checklist',
        extra: {'index': 4, 'value': true, 'photo': photoBase64()},
      );
      await action('submit');
      await login('amina');
      await action('add-task', extra: {'label': 'Nettoyer le miroir'});
      expect((await room())['cleaning'], 'inProgress');
      expect((await room())['checklist'].take(5).every((v) => v == true), true);
      await expectLater(action('approve'), denied);
      await login('sarah');
      await action(
        'checklist',
        extra: {'index': 5, 'value': true, 'photo': photoBase64()},
      );
      await action('submit');
      await login('amina');
      await action('approve');
      expect((await room())['status'], 'ready');
      await action('add-task', extra: {'label': 'Dépoussiérer les rideaux'});
      expect((await room())['status'], 'dirty');
      expect((await room())['checklist'].every((v) => v == false), true);
      expect(await store.storage.database.query('task_photos'), isEmpty);
      await action(
        'add-task',
        number: '112',
        extra: {'label': 'Nettoyer le balcon'},
      );
      expect((await room('112'))['status'], 'occupied');
    },
  );
  test('unchecking removes evidence and SQL failure rolls photo and checkbox back together', () async {
    await login('sarah');
    await store.storage.database.execute(
      "CREATE TRIGGER fail_photo BEFORE INSERT ON task_photos BEGIN SELECT RAISE(ABORT, 'test'); END",
    );
    await expectLater(
      action(
        'checklist',
        extra: {'index': 0, 'value': true, 'photo': photoBase64()},
      ),
      denied,
    );
    expect((await room())['checklist'][0], false);
    expect((await room())['tasks'][0]['photoId'], null);
    await store.storage.database.execute('DROP TRIGGER fail_photo');
    await action(
      'checklist',
      extra: {'index': 0, 'value': true, 'photo': photoBase64()},
    );
    await action('checklist', extra: {'index': 0, 'value': false});
    expect(await store.storage.database.query('task_photos'), isEmpty);
  });
  test('encrypted backup restores photos and custom tasks, rejects missing evidence, and supports old files', () async {
    await login('amina');
    await action('add-task', extra: {'label': 'Vitres'});
    await login('sarah');
    await action(
      'checklist',
      extra: {'index': 0, 'value': true, 'photo': photoBase64()},
    );
    await login('manager');
    final state = await store.backupSnapshot();
    final bytes = await BackupCodec.encode(state, 'backup-secret');
    final decoded = await BackupCodec.decode(bytes, 'backup-secret');
    final relabelled = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    relabelled['version'] = 1;
    final compatible = await BackupCodec.decode(
      utf8.encode(jsonEncode(relabelled)),
      'backup-secret',
    );
    expect(
      (compatible.state['rooms'] as List).firstWhere(
        (r) => r['number'] == '214',
      )['checklist'][0],
      true,
    );
    final bad = decoded.state..['photoData'] = <String, dynamic>{};
    await expectLater(Future.sync(() => store.restoreSnapshot(bad)), denied);
    await store.restoreSnapshot(decoded.state);
    await login('sarah');
    expect(await backend.taskPhoto('214', 'standard-0'), photoBase64());
    expect((await room())['tasks'].length, 5);
    await login('manager');
    final legacy = await store.backupSnapshot();
    legacy.remove('photoData');
    for (final r in [
      ...legacy['rooms'] as List,
      ...legacy['roomArchives'] as List,
    ]) {
      r.remove('tasks');
      r['checklist'] = [true, true, true, true];
    }
    final envelope = jsonDecode(
      utf8.decode(await BackupCodec.encode(legacy, 'backup-secret')),
    ) as Map<String, dynamic>;
    envelope['version'] = 1;
    final old = await BackupCodec.decode(
      utf8.encode(jsonEncode(envelope)),
      'backup-secret',
    );
    await store.restoreSnapshot(old.state);
    await login('sarah');
    expect((await room())['tasks'].length, 4);
    expect((await room())['checklist'].every((v) => v == false), true);
    expect(await store.storage.database.query('task_photos'), isEmpty);
  });
  test('v1 database upgrades to variable tasks without keeping unverified dirty completions', () async {
    await login('sarah');
    await store.storage.database.execute('DROP TABLE task_photos');
    await store.storage.database.execute('ALTER TABLE rooms DROP COLUMN tasks');
    await store.storage.database.execute('PRAGMA user_version = 1');
    await store.dispose();
    store = await SqliteUserRepository.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    backend = SqliteHousekeeping(store);
    expect((await room())['tasks'].length, 4);
    expect((await room())['cleaning'], 'waiting');
    expect(await store.storage.database.getVersion(), 2);
    expect(store.sessionUserId, 'sarah');
  });
  test('archived rooms keep their task definitions and restoring clears old evidence', () async {
    await login('amina');
    await action('add-task', number: '101', extra: {'label': 'Vitres'});
    await login('manager');
    final catalog = SqliteRoomCatalog(store);
    await catalog.mutate(RoomCatalogAction.archive, {
      'number': '101',
      'version': 2,
    });
    await catalog.mutate(RoomCatalogAction.restore, {
      'number': '101',
      'version': 3,
    });
    await login('amina');
    expect((await room('101'))['tasks'].length, 5);
    expect((await room('101'))['checklist'].length, 5);
  });
  test('photo processing emits bounded JPEG and rejects non-images', () async {
    final bytes = await EvidencePhoto.prepare(photoBytes());
    expect(EvidencePhoto.validate(base64Encode(bytes)), bytes);
    await expectLater(
      EvidencePhoto.prepare(utf8.encode('not a photo')),
      denied,
    );
  });
}
