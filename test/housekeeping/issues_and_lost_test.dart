import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/housekeeping/services/app_exception.dart';
import 'package:nova_paris/housekeeping/services/hotel_event_handlers.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_store.dart';
import 'package:nova_paris/housekeeping/services/mutation_meta.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_events.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'housekeeping_store_test.dart' show TestStaff;
import 'photo_fixture.dart';
import 'schema_downgrade.dart';
import 'test_backends.dart';

// Problem reports (voice note, photos, out of service, MaintenanceResolved)
// and the lost and found status flow, on a real SQLite database.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late String path;
  late AppSession session;
  late HousekeepingStore store;
  late TestHousekeeping backend;
  final emitted = <AppEvent>[];
  var now = DateTime(2026, 10, 21, 9);
  final denied = throwsA(isA<AppServiceException>());
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
    session.events.on<AppEvent>().listen(emitted.add);
    store = HousekeepingStore(session);
    listenToHotelEvents(session.events, store);
    backend = TestHousekeeping(store, events: session.events, clock: () => now);
  }

  setUp(() async {
    emitted.clear();
    now = DateTime(2026, 10, 21, 9);
    directory = await Directory.systemTemp.createTemp('nova_issues_');
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
  Future<void> report(String number, Map<String, dynamic> body) async =>
      backend.mutate('/v1/rooms/$number/report', {
        'version': (await room(number))['version'],
        'category': 'plomberie',
        'description': 'Fuite sous le lavabo',
        'priority': 'normal',
        'outOfService': false,
        ...body,
      });
  Future<List<Map>> issues() async =>
      ((await backend.snapshot())['issues'] as List).cast<Map>();
  Future<Map> issueOf(String number) async =>
      (await issues()).firstWhere((i) => i['room_number'] == number);
  Future<List<Map>> notes() async =>
      ((await backend.snapshot())['notifications'] as List).cast<Map>();

  group('problem reports', () {
    test(
      'with a voice note and photos, taking the room out of service',
      () async {
        login('sarah');
        await report('214', {
          'category': 'climatisation',
          'description': 'La climatisation goutte',
          'priority': 'high',
          'outOfService': true,
          'photos': [photoBase64(), photoBase64()],
          'voicePath': voice,
          'voiceSeconds': 12,
        });
        await settle();
        final issue = await issueOf('214');
        expect(
          (
            issue['category'],
            issue['priority'],
            issue['status'],
            issue['out_of_service'],
            issue['reported_by_name'],
          ),
          ('climatisation', 'high', 'open', true, 'Sarah'),
        );
        expect((issue['voice_path'], issue['voice_seconds']), (voice, 12));
        expect(issue['photos'], hasLength(2));
        expect(
          await backend.issuePhoto(issue['id'] as String, issue['photos'][0]),
          photoBase64(),
        );
        final r = await room('214');
        expect((r['status'], r['employeeId']), ('maintenance', null));
        // The shared event carries what it can: description and urgent.
        final request = emitted.whereType<MaintenanceRequested>().single;
        expect(
          (request.roomNumber, request.description, request.urgent),
          ('214', '[Climatisation] La climatisation goutte', true),
        );
        expect(
          (await room(
            '214',
          ))['history'].where((h) => '$h'.contains('Problème signalé')),
          hasLength(1),
          reason: 'the own event is not applied a second time',
        );
        // Saved for good: still there after the app restarts.
        await session.database.close();
        await open();
        login('amina');
        expect((await issueOf('214'))['voice_path'], voice);
        expect((await notes()).first['title'], 'Maintenance urgente');
        login('lina');
        expect(
          (await issues()).where((i) => i['room_number'] == '214'),
          isEmpty,
          reason: 'agents see only their own reports',
        );
        await expectLater(
          backend.issuePhoto(issue['id'] as String, issue['photos'][0]),
          refused(403),
        );
      },
    );

    test('without a voice note, the room keeps its cleaning', () async {
      login('sarah');
      await report('214', {'priority': 'low'});
      await settle();
      final issue = await issueOf('214');
      expect(issue['voice_path'], isNull);
      expect(issue['photos'], isEmpty);
      expect(issue['out_of_service'], false);
      final r = await room('214');
      expect((r['status'], r['employeeId']), ('dirty', 'sarah'));
      final request = emitted.whereType<MaintenanceRequested>().single;
      expect(request.urgent, false);
      expect(request.description, '[Plomberie] Fuite sous le lavabo');
    });

    test('checks fields, roles, ownership and versions', () async {
      login('sarah');
      await expectLater(
        report('305', {}),
        refused(403),
        reason: '305 is not assigned to Sarah',
      );
      for (final bad in <Map<String, dynamic>>[
        {'category': 'jardin'},
        {'priority': 'critique'},
        {'outOfService': 'oui'},
        {'description': ''},
        {'photos': List.filled(4, photoBase64())},
        {'voicePath': '/sdcard/note.m4a', 'voiceSeconds': 5},
        {'voicePath': voice, 'voiceSeconds': 61},
        {'voicePath': voice, 'voiceSeconds': 0},
        {'voiceSeconds': 5},
      ]) {
        await expectLater(report('214', bad), refused(400), reason: '$bad');
      }
      await expectLater(
        backend.mutate('/v1/rooms/214/report', {
          'version': (await room('214'))['version'] - 1,
          'category': 'autre',
          'description': 'Ancienne version',
          'priority': 'normal',
          'outOfService': false,
        }),
        refused(409),
      );
      login('amina');
      await expectLater(
        report('112', {'outOfService': true}),
        refused(409),
        reason: 'an occupied room cannot be taken out of service',
      );
      await expectLater(
        report('224', {'outOfService': true}),
        refused(409),
        reason: 'already in maintenance',
      );
      // A replayed mutation (same client id) creates one report only.
      final meta = mutationMeta();
      for (var i = 0; i < 2; i++) {
        await backend.mutate('/v1/rooms/112/report', {
          ...meta,
          'version': (await room('112'))['version'] - i,
          'category': 'television',
          'description': 'Pas de signal',
          'priority': 'normal',
          'outOfService': false,
        });
      }
      expect(
        (await issues()).where((i) => i['room_number'] == '112'),
        hasLength(1),
      );
      expect((await room('112'))['status'], 'occupied');
    });

    test('MaintenanceResolved resolves the reports; the supervisor brings the room back', () async {
      login('amina');
      await report('305', {'outOfService': true, 'priority': 'urgent'});
      await report('305', {
        'category': 'eclairage',
        'description': 'Lampe de chevet',
      });
      await settle();
      final first = await issueOf('305');
      await expectLater(
        backend.mutate('/v1/issues/${first['id']}/bring-back', {
          'version': first['version'],
        }),
        refused(409),
        reason: 'maintenance has not finished yet',
      );

      session.events.emit(const MaintenanceResolved('305'));
      await settle();
      final resolved = [
        for (final i in await issues())
          if (i['room_number'] == '305') i,
      ];
      expect(resolved.map((i) => i['status']), ['resolved', 'resolved']);
      expect(
        (await room('305'))['status'],
        'maintenance',
        reason: 'offered, not done automatically',
      );
      final notice = (await notes()).first;
      expect(notice['title'], 'Maintenance terminée');
      expect(notice['message'], contains('Remettez-la à nettoyer'));

      login('sarah');
      await expectLater(
        backend.mutate('/v1/issues/${first['id']}/bring-back', {
          'version': resolved.first['version'],
        }),
        refused(403),
      );
      login('amina');
      await expectLater(
        backend.mutate('/v1/issues/${first['id']}/bring-back', {'version': 1}),
        refused(409),
        reason: 'stale version',
      );
      await backend.mutate('/v1/issues/${resolved.first['id']}/bring-back', {
        'version': resolved.first['version'],
      });
      final r = await room('305');
      expect(
        (r['status'], r['cleaning'], r['note']),
        ('dirty', 'waiting', 'Nettoyage après intervention'),
      );
      expect(
        [
          for (final i in await issues())
            if (i['room_number'] == '305') (i['status'], i['closed_by_name']),
        ],
        [('closed', 'Amina'), ('closed', 'Amina')],
      );
    });

    test('another module\'s report is followed up; a room in maintenance '
        'from the start has its report', () async {
      login('amina');
      expect((await issueOf('224'))['status'], 'open');
      session.events.emit(
        const MaintenanceRequested('402', description: 'Prise', urgent: true),
      );
      await settle();
      final external = await issueOf('402');
      expect(
        (
          external['reported_by_name'],
          external['priority'],
          external['out_of_service'],
        ),
        ('Autre module', 'urgent', true),
      );
      expect((await room('402'))['status'], 'maintenance');
      // Closing a report does not change the room.
      await backend.mutate('/v1/issues/${external['id']}/close', {
        'version': external['version'],
      });
      expect((await issueOf('402'))['status'], 'closed');
      expect((await room('402'))['status'], 'maintenance');
      await expectLater(
        backend.mutate('/v1/issues/${external['id']}/close', {
          'version': external['version'] + 1,
        }),
        refused(409),
      );
    });

    test('a version 4 database upgrades in place', () async {
      login('sarah');
      await backend.mutate('/v1/lost/new/create', {
        'roomNumber': '214',
        'description': 'Montre',
      });
      login('amina');
      final item = ((await backend.snapshot())['lostItems'] as List).single;
      await backend.mutate('/v1/lost/${item['id']}/return', {
        'version': item['version'],
        'returnedTo': 'M. Martin',
      });
      final db = session.database.database;
      await dropVersion5(db);
      await db.update('module_versions', {
        'version': 4,
      }, where: "module = 'housekeeping'");
      await session.database.close();
      await open();
      expect(await session.database.versionOf('housekeeping'), 7);
      login('amina');
      final kept = ((await backend.snapshot())['lostItems'] as List).single;
      expect((kept['status'], kept['returned_to']), ('returned', 'M. Martin'));
      expect(
        [for (final e in kept['events'] as List) e['kind']],
        ['found', 'returned'],
      );
      final legacy = await issueOf('224');
      expect((legacy['status'], legacy['out_of_service']), ('open', true));
      session.events.emit(const MaintenanceResolved('224'));
      await settle();
      expect((await issueOf('224'))['status'], 'resolved');
    });
  });

  group('lost and found', () {
    Future<Map> found(String description) async {
      login('sarah');
      await backend.mutate('/v1/lost/new/create', {
        'roomNumber': '214',
        'description': description,
      });
      login('amina');
      return ((await backend.snapshot())['lostItems'] as List).firstWhere(
        (i) => i['description'] == description,
      ) as Map;
    }

    Future<Map> current(Map item) async =>
        ((await backend.snapshot())['lostItems'] as List).firstWhere(
          (i) => i['id'] == item['id'],
        ) as Map;
    Future<void> lost(Map item, String action, [Map<String, dynamic>? body]) =>
        backend.mutate('/v1/lost/${item['id']}/$action', {
          'version': item['version'],
          ...?body,
        });

    test('trouvé → client prévenu → remis, with the full history', () async {
      var item = await found('Montre dorée');
      expect(item['status'], 'found');
      login('sarah');
      await expectLater(
        lost(item, 'notify', {'channel': 'phone', 'message': 'Bonjour'}),
        refused(403),
      );
      login('amina');
      await expectLater(
        lost(item, 'notify', {'channel': 'pigeon', 'message': 'Bonjour'}),
        refused(400),
      );
      await expectLater(
        lost(item, 'notify', {'channel': 'phone', 'message': ' '}),
        refused(400),
      );
      await lost(item, 'notify', {
        'channel': 'phone',
        'message': 'Message laissé sur le répondeur',
      });
      item = await current(item);
      now = now.add(const Duration(days: 1));
      await lost(item, 'notify', {'channel': 'email', 'message': 'Relance'});
      item = await current(item);
      expect(item['status'], 'notified');
      await expectLater(
        lost({...item, 'version': 1}, 'return', {'returnedTo': 'M. Martin'}),
        refused(409),
        reason: 'stale version',
      );
      await lost(item, 'return', {'returnedTo': 'M. Martin'});
      item = await current(item);
      expect((item['status'], item['returned_to']), ('returned', 'M. Martin'));
      final events = item['events'] as List;
      expect(
        [for (final e in events) (e['kind'], e['channel'])],
        [
          ('found', null),
          ('notified', 'phone'),
          ('notified', 'email'),
          ('returned', null),
        ],
      );
      expect(events[1]['message'], 'Message laissé sur le répondeur');
      expect(events[2]['at'], DateTime(2026, 10, 22, 9).toIso8601String());
      for (final action in ['archive', 'notify', 'return']) {
        await expectLater(
          lost(item, action, {
            'channel': 'sms',
            'message': 'Encore',
            'returnedTo': 'Encore',
          }),
          refused(409),
          reason: 'a returned item is final ($action)',
        );
      }
    });

    test('archived by hand, then nothing else is possible', () async {
      var item = await found('Écharpe');
      await lost(item, 'archive');
      item = await current(item);
      expect(item['status'], 'archived');
      expect(item['archived_at'], now.toIso8601String());
      await expectLater(
        lost(item, 'return', {'returnedTo': 'Mme Durand'}),
        refused(409),
      );
    });

    test('unclaimed items are archived after the configured delay', () async {
      final kept = await found('Chargeur');
      final notified = await found('Livre');
      await lost(notified, 'notify', {'channel': 'sms', 'message': 'Bonjour'});
      final given = await found('Lunettes');
      await lost(given, 'return', {'returnedTo': 'M. Petit'});
      login('sarah');
      await expectLater(
        backend.mutate('/v1/settings/lost-archive-days/set', {
          'version': 0,
          'value': 7,
        }),
        refused(403),
      );
      login('amina');
      for (final days in [6, 366, 'dix']) {
        await expectLater(
          backend.mutate('/v1/settings/lost-archive-days/set', {
            'version': 0,
            'value': days,
          }),
          refused(400),
        );
      }
      await backend.mutate('/v1/settings/lost-archive-days/set', {
        'version': 0,
        'value': 7,
      });
      await expectLater(
        backend.mutate('/v1/settings/lost-archive-days/set', {
          'version': 0,
          'value': 10,
        }),
        refused(409),
      );
      expect((await backend.snapshot())['lostArchive'], {
        'days': 7,
        'version': 1,
      });
      now = now.add(const Duration(days: 6));
      expect(await backend.archiveUnclaimed(), 0);
      now = now.add(const Duration(days: 2));
      expect(await backend.archiveUnclaimed(), 2);
      expect(
        [
          for (final i in [kept, notified, given]) (await current(i))['status'],
        ],
        ['archived', 'archived', 'returned'],
      );
      final step = ((await current(kept))['events'] as List).last;
      expect(
        (step['kind'], step['actor_name'], step['message']),
        ('archived', 'Archivage automatique', 'Non réclamé après 7 jours'),
      );
      expect(await backend.archiveUnclaimed(), 0, reason: 'only once');
    });

    test('an agent sees the history of their own items only', () async {
      await found('Parapluie');
      login('sarah');
      final mine = ((await backend.snapshot())['lostItems'] as List).single;
      expect((mine['events'] as List).single['kind'], 'found');
      login('lina');
      expect((await backend.snapshot())['lostItems'], isEmpty);
      await expectLater(
        backend.mutate('/v1/lost/${mine['id']}/archive', {
          'version': mine['version'],
        }),
        denied,
      );
    });
  });
}
