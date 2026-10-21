import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/housekeeping/models/cleaning_stats.dart';
import 'package:nova_paris/housekeeping/services/app_exception.dart';
import 'package:nova_paris/housekeeping/services/hotel_event_handlers.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_store.dart';
import 'package:nova_paris/housekeeping/services/inspection_scoring.dart';
import 'package:nova_paris/housekeeping/services/room_catalog_backend.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_events.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'housekeeping_store_test.dart' show TestStaff;
import 'photo_fixture.dart';
import 'schema_downgrade.dart';
import 'test_backends.dart';

void main() {
  group('scoring', () {
    RatedItem item(int weight, InspectionRating rating) =>
        (weight: weight, rating: rating);

    test('weighted score from 0 to 100, partial counts half', () {
      expect(inspectionScore([]), 100);
      expect(
        inspectionScore([
          item(1, InspectionRating.ok),
          item(1, InspectionRating.ok),
        ]),
        100,
      );
      expect(
        inspectionScore([
          item(1, InspectionRating.ok),
          item(1, InspectionRating.failed),
        ]),
        50,
      );
      // Weights: 3 ok + 1 partial (0.5) out of 4 = 87.5 → 88.
      expect(
        inspectionScore([
          item(3, InspectionRating.ok),
          item(1, InspectionRating.partial),
        ]),
        88,
      );
      // A heavy failed item weighs more: (1 + 1) / (1 + 1 + 5) = 29.
      expect(
        inspectionScore([
          item(1, InspectionRating.ok),
          item(1, InspectionRating.ok),
          item(5, InspectionRating.failed),
        ]),
        29,
      );
    });

    test('threshold is reached at equality; unknown labels weigh 1', () {
      expect(passes(80, 80), isTrue);
      expect(passes(79, 80), isFalse);
      const rules = InspectionRules(
        threshold: 90,
        weights: {'Salle de bain': 4},
      );
      expect((rules.weightOf('Salle de bain'), rules.weightOf('Sol')), (4, 1));
      expect(const InspectionRules().threshold, defaultInspectionThreshold);
      expect(invalidRules(101, {}), isNotNull);
      expect(invalidRules(80, {'Sol': 0}), isNotNull);
      expect(invalidRules(80, {'Sol': 6}), isNotNull);
      expect(invalidRules(80, {'  ': 2}), isNotNull);
      expect(invalidRules(80, {'Sol': 5}), isNull);
    });
  });

  group('inspection rules on SQLite', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    setUpAll(sqfliteFfiInit);
    late Directory directory;
    late String path;
    late AppSession session;
    late HousekeepingStore store;
    late TestHousekeeping backend;
    late TestCatalog catalog;
    final emitted = <AppEvent>[];
    final denied = throwsA(isA<AppServiceException>());
    final conflict = throwsA(
      isA<AppServiceException>().having((e) => e.status, 'status', 409),
    );

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
      backend = TestHousekeeping(store, events: session.events);
      catalog = TestCatalog(store);
    }

    setUp(() async {
      emitted.clear();
      directory = await Directory.systemTemp.createTemp('nova_inspection_');
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

    // Ratings for every task: [overrides] by task index.
    Future<List<Map<String, dynamic>>> ratings(
      String number, [
      Map<int, String> overrides = const {},
    ]) async {
      final tasks = (await room(number))['tasks'] as List;
      return [
        for (var i = 0; i < tasks.length; i++)
          {'taskId': tasks[i]['id'], 'rating': overrides[i] ?? 'ok'},
      ];
    }

    Future<List<Map>> inspections() async => [
      for (final i in (await store.readState())['inspections'] as List)
        i as Map,
    ];

    Future<void> prepared(String number) async {
      login('amina');
      await act(number, 'assign', {
        'employeeId': 'sarah',
        'note': '',
        'urgent': false,
      });
      await cleanAndSubmit(number, 'sarah');
      login('amina');
    }

    test('approving with ratings records the score; below the threshold it is refused', () async {
      await prepared('305');
      await expectLater(
        act('305', 'approve', {
          'ratings': await ratings('305', {0: 'failed'}),
        }),
        conflict,
        reason: '75/100 is under the default 80 threshold',
      );
      emitted.clear();
      await act('305', 'approve', {
        'ratings': await ratings('305', {3: 'partial'}),
      });
      final done = await room('305');
      expect((done['status'], done['cleaning']), ('ready', 'completed'));
      expect(emitted.whereType<RoomReady>().single.roomNumber, '305');
      final round = (await inspections()).single;
      expect(
        (round['score'], round['outcome'], round['round']),
        (88, 'approved', 1),
      );
      expect((round['items'] as List), hasLength(4));
      final log = ((await store.readState())['cleanings'] as List).single;
      expect((log['inspection_score'], log['inspection_rounds']), (88, 1));
      final stats = CleaningStats.compute(
        [CleaningRecord.fromMap(log as Map)],
        {},
        since: DateTime(2000),
      );
      expect(stats.averageScore, 88);
    });

    test(
      'send-back loop: failed items reopened, same agent, three rounds',
      () async {
        await prepared('305');
        // Round 1: two items fail.
        await act('305', 'refuse', {
          'ratings': await ratings('305', {1: 'failed', 2: 'partial'}),
        });
        var r = await room('305');
        expect(
          (r['cleaning'], r['employeeId'], r['urgent']),
          ('inProgress', 'sarah', true),
        );
        expect((r['checklist'] as List), [true, false, false, true]);
        expect((r['tasks'] as List)[1]['photoId'], isNull);
        expect((r['tasks'] as List)[0]['photoId'], isNotNull);
        expect(r['feedback'], contains('2 points à reprendre'));
        login('sarah');
        final note =
            ((await backend.snapshot())['notifications'] as List).first;
        expect(note['title'], 'Nettoyage à reprendre');
        expect(note['message'], contains('Nettoyer la salle de bain'));
        // Sarah sees the round that failed, with its items.
        final seen = ((await backend.snapshot())['inspections'] as List).single;
        expect(
          (seen['items'] as List).where((i) => i['rating'] != 'ok'),
          hasLength(2),
        );
        await expectLater(
          act('305', 'submit'),
          denied,
          reason: 'items to redo',
        );

        // Round 2: Sarah redoes them; one still fails.
        await cleanAndSubmit('305', 'sarah');
        login('amina');
        await act('305', 'refuse', {
          'ratings': await ratings('305', {2: 'failed'}),
          'comment': 'Les surfaces collent encore',
        });
        expect((await room('305'))['feedback'], 'Les surfaces collent encore');

        // Round 3: approved.
        await cleanAndSubmit('305', 'sarah');
        login('amina');
        await act('305', 'approve', {'ratings': await ratings('305')});
        final rounds = await inspections();
        expect(
          [for (final i in rounds) (i['round'], i['outcome'])],
          [(1, 'sentBack'), (2, 'sentBack'), (3, 'approved')],
        );
        expect((rounds[1]['score'], rounds[2]['score']), (75, 100));
        final log = ((await store.readState())['cleanings'] as List).single;
        expect((log['inspection_rounds'], log['inspection_score']), (3, 100));
        expect(log['refusals'], 2);
        expect((await room('305'))['urgent'], isFalse);

        // A new cleaning of the room starts again at round 1.
        session.events.emit(const GuestCheckedIn('305', guestName: 'M. Leroy'));
        session.events.emit(const GuestCheckedOut('305'));
        await pumpEventQueue();
        await prepared('305');
        await act('305', 'approve', {'ratings': await ratings('305')});
        expect((await inspections()).last['round'], 1);
      },
    );

    test('roles, ownership, versions and complete ratings', () async {
      await prepared('305');
      final all = await ratings('305');
      login('sarah');
      await expectLater(act('305', 'approve', {'ratings': all}), denied);
      await expectLater(act('305', 'refuse', {'ratings': all}), denied);
      login('lina');
      await expectLater(act('305', 'refuse', {'ratings': all}), denied);
      login('manager');
      await expectLater(act('305', 'approve', {'ratings': all}), denied);
      login('amina');
      await expectLater(
        act('305', 'refuse', {'ratings': all.take(3).toList()}),
        denied,
        reason: 'every task must be rated',
      );
      await expectLater(
        act('305', 'refuse', {
          'ratings': [...all.take(3), all.first],
        }),
        denied,
        reason: 'a task rated twice',
      );
      await expectLater(
        act('305', 'refuse', {
          'ratings': [
            ...all.take(3),
            {'taskId': all.last['taskId'], 'rating': 'excellent'},
          ],
        }),
        denied,
      );
      await expectLater(
        act('305', 'refuse', {'ratings': all}),
        denied,
        reason: 'all OK: a comment is needed to send back',
      );
      final version = (await room('305'))['version'];
      await act('305', 'refuse', {
        'ratings': await ratings('305', {0: 'failed'}),
      });
      await expectLater(
        backend.mutate('/v1/rooms/305/approve', {
          'version': version,
          'ratings': all,
        }),
        conflict,
        reason: 'stale version',
      );
      await expectLater(
        act('305', 'approve', {'ratings': all}),
        denied,
        reason: 'no longer awaiting inspection',
      );
      expect(await inspections(), hasLength(1));
    });

    test(
      'a refusal or approval without ratings still works as before',
      () async {
        await prepared('305');
        await act('305', 'refuse', {'comment': 'Poussière'});
        expect((await room('305'))['feedback'], 'Poussière');
        final round = (await inspections()).single;
        expect((round['score'], round['outcome']), (null, 'sentBack'));
        await cleanAndSubmit('305', 'sarah');
        login('amina');
        await act('305', 'approve');
        expect((await room('305'))['status'], 'ready');
        expect(await inspections(), hasLength(1), reason: 'quick approve');
      },
    );

    test(
      'weights and threshold per category, by the supervisor or the manager',
      () async {
        login('sarah');
        await expectLater(
          backend.mutate('/v1/inspection-rules/Chambre%20Deluxe/set', {
            'threshold': 90,
            'weights': {},
          }),
          denied,
        );
        login('amina');
        await backend.mutate('/v1/inspection-rules/Chambre%20Deluxe/set', {
          'threshold': 90,
          'weights': {'Nettoyer la salle de bain': 5},
        });
        await expectLater(
          backend.mutate('/v1/inspection-rules/Chambre%20Deluxe/set', {
            'threshold': 70,
            'weights': {},
            'version': 0,
          }),
          conflict,
        );
        login('manager');
        await catalog.mutate(RoomCatalogAction.setInspectionRules, {
          'category': 'Chambre Deluxe',
          'threshold': 85,
          'weights': {'Nettoyer la salle de bain': 5},
          'version': 1,
        });
        expect(
          (await catalog.snapshot()).rulesFor('Chambre Deluxe').threshold,
          85,
        );
        await expectLater(
          catalog.mutate(RoomCatalogAction.setInspectionRules, {
            'category': 'Chambre Deluxe',
            'threshold': 85,
            'weights': {'Sol': 9},
          }),
          denied,
        );
        // The bathroom now weighs 5: a partial bathroom gives (1+2.5+1+1)/8.
        await prepared('305');
        await act('305', 'refuse', {
          'ratings': await ratings('305', {1: 'partial'}),
        });
        final round = (await inspections()).single;
        expect((round['score'], round['threshold']), (69, 85));
      },
    );

    test(
      'item photos are kept and private to the supervisor and the agent',
      () async {
        await prepared('305');
        final rated = await ratings('305', {0: 'failed'});
        rated[0]['comment'] = 'Draps tachés';
        rated[0]['photo'] = photoBase64();
        await act('305', 'refuse', {'ratings': rated});
        final round = (await inspections()).single;
        final item = (round['items'] as List).first as Map;
        expect(item['comment'], 'Draps tachés');
        expect(item['photo_id'], isNotNull);
        expect(
          await backend.inspectionPhoto(
            round['id'] as String,
            item['id'] as String,
          ),
          photoBase64(),
        );
        login('sarah');
        expect(
          await backend.inspectionPhoto(
            round['id'] as String,
            item['id'] as String,
          ),
          photoBase64(),
        );
        login('lina');
        await expectLater(
          backend.inspectionPhoto(round['id'] as String, item['id'] as String),
          denied,
        );
        // The photo survives later writes (it is referenced by the history).
        login('amina');
        await act('101', 'priority', {'value': 'vip'});
        login('sarah');
        expect(
          await backend.inspectionPhoto(
            round['id'] as String,
            item['id'] as String,
          ),
          photoBase64(),
        );
      },
    );

    test('a version 3 database upgrades in place', () async {
      login('amina');
      await act('305', 'assign', {
        'employeeId': 'sarah',
        'note': 'Garder',
        'urgent': false,
      });
      final db = session.database.database;
      await dropVersion5(db);
      for (final table in [
        'housekeeping_inspection_items',
        'housekeeping_inspections',
        'housekeeping_inspection_rules',
      ]) {
        await db.execute('DROP TABLE $table');
      }
      await db.execute(
        'ALTER TABLE housekeeping_cleanings DROP COLUMN inspection_score',
      );
      await db.execute(
        'ALTER TABLE housekeeping_cleanings DROP COLUMN inspection_rounds',
      );
      await db.update('module_versions', {
        'version': 3,
      }, where: "module = 'housekeeping'");
      await session.database.close();
      await open();
      expect(await session.database.versionOf('housekeeping'), 7);
      expect((await room('305'))['note'], 'Garder');
      expect(await inspections(), isEmpty);
      await cleanAndSubmit('305', 'sarah');
      login('amina');
      await act('305', 'approve', {'ratings': await ratings('305')});
      expect((await inspections()).single['score'], 100);
    });
  });
}
