import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/housekeeping/models/hotel_data.dart';
import 'package:nova_paris/housekeeping/services/app_exception.dart';
import 'package:nova_paris/housekeeping/services/hotel_event_handlers.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_backup.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_store.dart';
import 'package:nova_paris/housekeeping/services/notification_rules.dart';
import 'package:nova_paris/housekeeping/services/phone_alerts.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'housekeeping_store_test.dart' show TestStaff;
import 'photo_fixture.dart';
import 'schema_downgrade.dart';
import 'test_backends.dart';

class FakeAlarms implements LateAlarms {
  final calls = <List<LateAlarm>>[];
  @override
  Future<void> sync(List<LateAlarm> alarms) async => calls.add(alarms);
}

// Backup and restore of the housekeeping tables, and the late alerts handed
// to Android, on a real SQLite database.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late Directory directory, appFolder;
  late String path;
  late AppSession session;
  late HousekeepingStore store;
  late TestHousekeeping backend;
  late HousekeepingBackup backup;
  var now = DateTime(2026, 10, 21, 9);
  Matcher refused(int status) => throwsA(
    isA<AppServiceException>().having((e) => e.status ?? 400, 'status', status),
  );
  const voice = 'housekeeping/voice/3f2b8c1e-9a4d-4c7e-b1f0-6d2e8a9c0b13.m4a';

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
    backup = HousekeepingBackup(
      store,
      appFolder: () async => appFolder,
      clock: () => now,
    );
  }

  setUp(() async {
    now = DateTime(2026, 10, 21, 9);
    directory = await Directory.systemTemp.createTemp('nova_backup_');
    appFolder = await Directory(p.join(directory.path, 'app')).create();
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
  Future<void> act(
    String number,
    String name, [
    Map<String, dynamic> extra = const {},
  ]) async => backend.mutate('/v1/rooms/$number/$name', {
    'version': (await room(number))['version'],
    ...extra,
  });

  // Every housekeeping table a backup holds (not the phone's sync tables),
  // rows sorted, for comparisons.
  Future<Map<String, List<String>>> dump() async {
    final db = session.database.database;
    final tables = await db.query(
      'sqlite_master',
      where:
          "type = 'table' AND name LIKE 'housekeeping\\_%' ESCAPE '\\' "
          "AND name NOT LIKE 'housekeeping\\_sync\\_%' ESCAPE '\\'",
    );
    return {
      for (final t in tables)
        t['name'] as String: [
          for (final row in await db.query(t['name'] as String))
            jsonEncode(row),
        ]..sort(),
    };
  }

  File voiceFile() => File(p.join(appFolder.path, voice));

  group('backup and restore', () {
    test('round trip: tables, photos and voice notes come back', () async {
      login('sarah');
      await voiceFile().create(recursive: true);
      await voiceFile().writeAsBytes([1, 2, 3, 4]);
      await act('214', 'report', {
        'category': 'plomberie',
        'description': 'Fuite',
        'priority': 'normal',
        'outOfService': false,
        'photos': [photoBase64()],
        'voicePath': voice,
        'voiceSeconds': 4,
      });
      login('amina');
      final before = await dump();
      final saved = await backup.backupNow();
      expect(saved.name, 'nova-paris-menage-2026-10-21-090000.json.gz');

      // Things change after the backup.
      await act('305', 'assign', {
        'employeeId': 'sarah',
        'note': '',
        'urgent': true,
      });
      await voiceFile().delete();
      expect(await dump(), isNot(before));

      login('manager');
      now = now.add(const Duration(minutes: 5));
      var signals = 0;
      final sub = store.changes.listen((_) => signals++);
      await backup.restore(await backup.readFile(saved.path));
      await pumpEventQueue();
      await sub.cancel();
      expect(await dump(), before);
      expect(await voiceFile().readAsBytes(), [1, 2, 3, 4]);
      expect(signals, 1, reason: 'the screens are told to re-read');
      expect(
        await session.database.database.query('housekeeping_sync_outbox'),
        isEmpty,
        reason: 'actions made after the backup are not sent to the server',
      );
      expect(
        (await backup.list()).map((b) => b.name),
        contains(
          'nova-paris-menage-2026-10-21-090500-avant-restauration.json.gz',
        ),
        reason: 'a safety backup is made first',
      );
      login('amina');
      expect((await room('305'))['employeeId'], isNull);
    });

    test('roles: agents nothing, the supervisor backs up only', () async {
      login('sarah');
      await expectLater(backup.backupNow(), refused(403));
      expect((backup.canBackup, backup.canRestore), (false, false));
      login('amina');
      final saved = await backup.backupNow();
      expect((backup.canBackup, backup.canRestore), (true, false));
      await expectLater(
        backup.restore(await backup.readFile(saved.path)),
        refused(403),
      );
      login('manager');
      expect(backup.canRestore, isTrue);
    });

    test(
      'a damaged, foreign or newer file is refused, nothing changes',
      () async {
        login('manager');
        final before = await dump();
        Future<void> bad(Object content) => backup.restore(
          content is List<int>
              ? Uint8List.fromList(content)
              : Uint8List.fromList(
                  gzip.encode(utf8.encode(jsonEncode(content))),
                ),
        );
        await expectLater(bad([1, 2, 3]), refused(400));
        await expectLater(
          bad({'format': 'autre', 'module': 'billing', 'version': 1}),
          refused(400),
        );
        final real = jsonDecode(
          utf8.decode(
            gzip.decode(await backup.readFile((await backup.backupNow()).path)),
          ),
        ) as Map<String, dynamic>;
        await expectLater(
          bad({...real, 'version': housekeepingSchema.version + 1}),
          throwsA(
            isA<AppServiceException>().having(
              (e) => e.message,
              'message',
              contains('version plus récente'),
            ),
          ),
        );
        await expectLater(
          bad({
            ...real,
            'tables': {
              'billing_invoices': {'sql': 'CREATE TABLE x (a)', 'rows': []},
            },
          }),
          refused(400),
          reason: 'only housekeeping tables',
        );
        // A broken row: the transaction rolls back, nothing is lost.
        final broken = jsonDecode(jsonEncode(real)) as Map<String, dynamic>;
        ((broken['tables'] as Map)['housekeeping_rooms']['rows'] as List).add({
          'number': '999',
        });
        await expectLater(bad(broken), throwsA(anything));
        expect(await dump(), before);
      },
    );

    test('a backup of an older version is upgraded in place', () async {
      login('amina');
      await act('305', 'assign', {
        'employeeId': 'sarah',
        'note': 'Ancienne',
        'urgent': true,
      });
      final db = session.database.database;
      await dropVersion7(db);
      await db.update('module_versions', {
        'version': 6,
      }, where: "module = 'housekeeping'");
      login('manager');
      final old = await backup.backupNow();
      await session.database.close();
      await open();
      expect(await session.database.versionOf('housekeeping'), 8);
      login('amina');
      await act('118', 'assign', {
        'employeeId': 'lina',
        'note': 'Nouvelle',
        'urgent': false,
      });
      login('manager');
      await backup.restore(await backup.readFile(old.path));
      expect(await session.database.versionOf('housekeeping'), 8);
      expect((await room('305'))['note'], 'Ancienne');
      expect((await room('118'))['employeeId'], isNull);
      login('sarah');
      final notes = ((await backend.snapshot())['notifications'] as List);
      expect(
        notes.firstWhere((n) => n['title'] == 'Tâche urgente')['category'],
        'tasks',
        reason: 'the version 7 step ran on the restored data',
      );
    });

    test('one automatic backup a day, the last 7 kept', () async {
      login('sarah');
      expect(await backup.dailyBackup(), isNotNull);
      now = now.add(const Duration(hours: 3));
      expect(await backup.dailyBackup(), isNull, reason: 'same day');
      for (var day = 1; day <= 9; day++) {
        now = DateTime(2026, 10, 21 + day, 8);
        await backup.dailyBackup();
      }
      final kept = await backup.list();
      expect(kept, hasLength(7));
      expect(kept.first.createdAt, DateTime(2026, 10, 30, 8));
      expect(kept.every((b) => b.automatic), isTrue);
    });
  });

  group('late alerts for Android', () {
    Future<List<LateAlarm>> alarms() async {
      login('sarah');
      return backend.lateAlarms();
    }

    test('planned on start and resume, removed on pause and stop', () async {
      login('amina');
      await act('305', 'assign', {
        'employeeId': 'sarah',
        'note': '',
        'urgent': false,
      });
      expect(await alarms(), isEmpty);
      await act('305', 'start');
      final planned = (await alarms()).single;
      expect(
        (
          planned.roomNumber,
          planned.agentName,
          planned.at,
          planned.limitMinutes,
        ),
        ('305', 'Sarah', DateTime(2026, 10, 21, 9, 37, 30), 37),
      );
      now = now.add(const Duration(minutes: 10));
      await act('305', 'pause');
      expect(await alarms(), isEmpty);
      now = now.add(const Duration(hours: 1));
      await act('305', 'resume');
      expect(
        (await alarms()).single.at,
        DateTime(2026, 10, 21, 10, 37, 30),
        reason: '27 min 30 s left after the pause',
      );
      await act('305', 'stop');
      expect(await alarms(), isEmpty);
    });

    test('nothing planned once late, nor when late alerts are off', () async {
      login('amina');
      await act('305', 'assign', {
        'employeeId': 'sarah',
        'note': '',
        'urgent': false,
      });
      login('sarah');
      await act('305', 'start');
      login('amina');
      await backend.mutate('/v1/notification-prefs/late/set', {
        'enabled': false,
        'version': 0,
      });
      expect(await backend.lateAlarms(), isEmpty);
      now = now.add(const Duration(minutes: 40));
      expect(await alarms(), isEmpty, reason: 'already late');
    });

    test('HotelData hands the alerts to Android after each change', () async {
      login('amina');
      await act('305', 'assign', {
        'employeeId': 'sarah',
        'note': '',
        'urgent': false,
      });
      login('sarah');
      final fake = FakeAlarms();
      final data = HotelData(api: backend)
        ..watchLate = true
        ..lateAlarms = fake;
      // The check runs after the change, on the real database.
      Future<void> until(bool Function() done) async {
        for (var i = 0; i < 50 && !done(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }

      await data.refresh();
      await until(() => fake.calls.isNotEmpty);
      expect(fake.calls.single, isEmpty);
      await data.startCleaning(data.roomByNumber('305'));
      await until(() => fake.calls.last.isNotEmpty);
      expect(fake.calls.last.single.roomNumber, '305');
      await data.pauseTimer(data.roomByNumber('305'));
      await until(() => fake.calls.last.isEmpty);
      expect(fake.calls.last, isEmpty);
      final count = fake.calls.length;
      await data.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(fake.calls, hasLength(count), reason: 'unchanged: not re-planned');
      data.dispose();
    });

    test('the alert Android delivers and the app\'s share one id per room', () {
      expect(lateAlertId('305'), lateAlertId('305'));
      expect(lateAlertId('305'), isNot(lateAlertId('306')));
    });
  });
}
