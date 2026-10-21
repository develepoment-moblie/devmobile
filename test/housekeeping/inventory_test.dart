import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/housekeeping/services/app_exception.dart';
import 'package:nova_paris/housekeeping/services/hotel_event_handlers.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_store.dart';
import 'package:nova_paris/housekeeping/services/mutation_meta.dart';
import 'package:nova_paris/housekeeping/services/room_catalog_backend.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_events.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'housekeeping_store_test.dart' show TestStaff;
import 'schema_downgrade.dart';
import 'test_backends.dart';

// Linen and amenities, laundry, supply requests and the minibar, on a real
// SQLite database.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late String path;
  late AppSession session;
  late HousekeepingStore store;
  late TestHousekeeping backend;
  late TestCatalog catalog;
  final emitted = <AppEvent>[];
  Matcher refused(int status) => throwsA(
    isA<AppServiceException>().having((e) => e.status ?? 400, 'status', status),
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
    directory = await Directory.systemTemp.createTemp('nova_inventory_');
    path = p.join(directory.path, 'test.db');
    await open();
  });
  tearDown(() async {
    await session.database.close();
    await directory.delete(recursive: true);
  });

  void login(String id) =>
      session.signIn(TestStaff.people.firstWhere((u) => u.id == id));
  Future<Map<String, dynamic>> snap() => backend.snapshot();
  Future<Map> supply(String id) async =>
      ((await store.readState())['supplies'] as List).firstWhere(
        (x) => x['id'] == id,
      ) as Map;
  Future<int> stock(String id) async => (await supply(id))['quantity'] as int;
  Future<List<Map>> notes() async =>
      ((await snap())['notifications'] as List).cast<Map>();
  Future<void> m(String path, [Map<String, dynamic> body = const {}]) =>
      backend.mutate(path, body);
  List<Map<String, dynamic>> lines(Map<String, int> items) => [
    for (final e in items.entries) {'supplyId': e.key, 'quantity': e.value},
  ];
  Iterable<ExtraCharged> charges() => emitted.whereType<ExtraCharged>();
  Future<void> settleEvents() async {
    await pumpEventQueue();
    await store.readState();
  }

  group('types and usage log', () {
    test('items are typed; a minibar item needs a price', () async {
      login('amina');
      final types = {
        for (final x in (await snap())['supplies'] as List)
          x['id']: x['category'],
      };
      expect(types['sheets'], 'linge');
      expect(types['soap'], 'accueil');
      expect(types['cleaner'], 'entretien');
      expect(types['minibar-soda'], 'minibar');
      Future<void> create(Map<String, dynamic> extra) =>
          m('/v1/supplies/new/create', {
            'name': 'Peignoirs',
            'unit': 'pièces',
            'quantity': 10,
            'minimum': 2,
            ...extra,
          });
      await expectLater(create({'category': 'jardin'}), refused(400));
      await expectLater(
        create({'category': 'minibar', 'name': 'Jus'}),
        refused(400),
        reason: 'no price',
      );
      await create({'category': 'linge'});
      await create({'category': 'minibar', 'name': 'Jus', 'priceCents': 500});
      final created = ((await snap())['supplies'] as List).where(
        (x) => ['Peignoirs', 'Jus'].contains(x['name']),
      );
      expect(
        [for (final x in created) (x['category'], x['priceCents'])],
        [('linge', null), ('minibar', 500)],
      );
    });

    test(
      'usage per room: stock, log, ownership, threshold alert once',
      () async {
        login('sarah');
        await m('/v1/supplies/towels/use', {
          'roomNumber': '214',
          'quantity': 2,
        });
        expect(await stock('towels'), 66);
        final move = ((await snap())['stockMovements'] as List).single;
        expect(
          (
            move['reason'],
            move['delta'],
            move['room_number'],
            move['floor'],
            move['actor_name'],
          ),
          ('usage', -2, '214', 2, 'Sarah'),
        );
        expect(isUuid(move['id']), isTrue);
        await expectLater(
          m('/v1/supplies/towels/use', {'roomNumber': '305', 'quantity': 1}),
          refused(403),
          reason: '305 is not assigned to Sarah',
        );
        await expectLater(
          m('/v1/supplies/towels/use', {'roomNumber': '214', 'quantity': 67}),
          refused(409),
          reason: 'not enough in stock',
        );
        expect(await stock('towels'), 66);
        // 42 sheets, alert at 15: crossing the threshold alerts once.
        await m('/v1/supplies/sheets/use', {
          'roomNumber': '214',
          'quantity': 27,
        });
        await m('/v1/supplies/sheets/use', {
          'roomNumber': '214',
          'quantity': 1,
        });
        login('amina');
        final low = (await notes()).where((n) => n['title'] == 'Stock bas');
        expect(low, hasLength(1));
        expect(low.single['message'], contains('Draps propres : il reste 15'));
        expect(await stock('sheets'), 14);
        login('lina');
        expect(
          (await snap())['stockMovements'],
          isEmpty,
          reason: 'agents see their own usage only',
        );
      },
    );

    test('the manual movement is logged too', () async {
      login('amina');
      await m('/v1/supplies/cleaner/movement', {
        'version': (await supply('cleaner'))['version'],
        'delta': 6,
      });
      expect(await stock('cleaner'), 10);
      expect(
        ((await snap())['stockMovements'] as List).single['reason'],
        'manual',
      );
    });
  });

  group('laundry', () {
    test('sent, then returned with damage and loss', () async {
      login('amina');
      await expectLater(
        m('/v1/laundry/new/send', {
          'lines': lines({'cleaner': 1}),
        }),
        refused(400),
        reason: 'only linen goes to the laundry',
      );
      await expectLater(
        m('/v1/laundry/new/send', {
          'lines': lines({'sheets': 20, 'towels': 69}),
        }),
        refused(409),
        reason: 'more towels than in stock',
      );
      expect(await stock('sheets'), 42, reason: 'all or nothing');
      await m('/v1/laundry/new/send', {
        'lines': lines({'sheets': 30, 'towels': 10}),
      });
      expect((await stock('sheets'), await stock('towels')), (12, 58));
      expect(
        (await notes()).first['message'],
        contains('Draps propres : il reste 12'),
        reason: 'the existing low-stock alert',
      );
      final batch = ((await snap())['laundry'] as List).single as Map;
      Future<void> back(Map<String, List<int>> counts, [int? version]) =>
          m('/v1/laundry/${batch['id']}/return', {
            'version': version ?? batch['version'],
            'lines': [
              for (final e in counts.entries)
                {
                  'supplyId': e.key,
                  'received': e.value[0],
                  'damaged': e.value[1],
                  'lost': e.value[2],
                },
            ],
          });
      await expectLater(
        back({
          'sheets': [27, 2, 0],
          'towels': [10, 0, 0],
        }),
        refused(400),
        reason: '27 + 2 + 0 is not 30',
      );
      await expectLater(
        back({
          'sheets': [30, 0, 0],
        }),
        refused(400),
        reason: 'every sent item must be returned',
      );
      login('sarah');
      await expectLater(
        back({
          'sheets': [30, 0, 0],
          'towels': [10, 0, 0],
        }),
        refused(403),
      );
      login('amina');
      await back({
        'sheets': [27, 2, 1],
        'towels': [10, 0, 0],
      });
      expect((await stock('sheets'), await stock('towels')), (39, 68));
      final returned = ((await snap())['laundry'] as List).single as Map;
      expect(returned['status'], 'returned');
      expect(
        [
          for (final l in returned['lines'] as List)
            (l['received'], l['damaged'], l['lost']),
        ],
        [(27, 2, 1), (10, 0, 0)],
      );
      final log = [
        for (final x in (await snap())['stockMovements'] as List)
          if (x['supply_id'] == 'sheets')
            (x['reason'], x['delta'], x['quantity']),
      ];
      expect(log, [
        ('laundry_out', -30, 30),
        ('laundry_in', 27, 27),
        ('laundry_damaged', 0, 2),
        ('laundry_lost', 0, 1),
      ]);
      await expectLater(
        back({
          'sheets': [30, 0, 0],
          'towels': [10, 0, 0],
        }, returned['version'] as int),
        refused(409),
        reason: 'already returned',
      );
    });
  });

  group('supply requests', () {
    Future<Map> request() async =>
        ((await snap())['requests'] as List).first as Map;
    Future<void> step(
      String action, [
      Map<String, dynamic> extra = const {},
    ]) async {
      final r = await request();
      await m('/v1/requests/${r['id']}/$action', {
        'version': r['version'],
        ...extra,
      });
    }

    Future<List<String>> sarahNotes() async {
      login('sarah');
      final titles = [for (final n in await notes()) n['title'] as String];
      login('amina');
      return titles;
    }

    test(
      'demandée → approuvée → préparée → livrée, stock out on delivery',
      () async {
        login('amina');
        await expectLater(
          m('/v1/requests/new/create', {
            'lines': lines({'soap': 1}),
          }),
          refused(403),
          reason: 'agents make the requests',
        );
        login('sarah');
        await expectLater(
          m('/v1/requests/new/create', {
            'lines': lines({'minibar-soda': 1}),
          }),
          refused(400),
        );
        await m('/v1/requests/new/create', {
          'lines': lines({'soap': 10, 'towels': 6}),
          'note': 'Pour le 2e étage',
        });
        login('amina');
        expect((await notes()).first['title'], 'Demande de fournitures');
        await expectLater(
          step('deliver'),
          refused(409),
          reason: 'not prepared',
        );
        await step('approve', {
          'lines': [
            {'supplyId': 'towels', 'quantity': 4},
          ],
        });
        await expectLater(step('approve'), refused(409));
        await step('prepare');
        expect(
          await stock('soap'),
          84,
          reason: 'nothing leaves before delivery',
        );
        await step('deliver');
        expect((await stock('soap'), await stock('towels')), (74, 64));
        final delivered = await request();
        expect(delivered['status'], 'delivered');
        expect(
          [for (final l in delivered['lines'] as List) l['approved']],
          [10, 4],
        );
        expect((await sarahNotes()).take(3), [
          'Fournitures livrées',
          'Demande préparée',
          'Demande approuvée',
        ]);
        login('lina');
        expect(
          (await notes()).where((n) => '${n['title']}'.startsWith('Demande')),
          isEmpty,
          reason: 'only the requesting agent is notified',
        );
        expect((await snap())['requests'], isEmpty);
      },
    );

    test(
      'insufficient stock is flagged, delivery refused, then refusal',
      () async {
        login('sarah');
        await m('/v1/requests/new/create', {
          'lines': lines({'cleaner': 3}),
        });
        login('amina');
        await m('/v1/supplies/cleaner/movement', {
          'version': (await supply('cleaner'))['version'],
          'delta': -2,
        });
        final open = await request();
        expect((open['lines'] as List).single['available'], 2);
        await step('approve');
        login('sarah');
        expect(
          (await notes()).first['message'],
          contains('Stock insuffisant : Nettoyant multi-surfaces'),
        );
        login('amina');
        await step('prepare');
        await expectLater(step('deliver'), refused(409));
        expect(await stock('cleaner'), 2);
        expect((await request())['status'], 'prepared');
        await expectLater(step('refuse', {'reason': ''}), refused(400));
        await step('refuse', {'reason': 'Rupture, commande en cours'});
        expect((await request())['status'], 'refused');
        expect((await sarahNotes()).first, 'Demande refusée');
        await expectLater(step('refuse', {'reason': 'Encore'}), refused(409));
      },
    );
  });

  group('minibar', () {
    Future<List<Map>> entries() async =>
        ((await snap())['minibar'] as List).cast<Map>();
    Future<Map> entry(String id) async =>
        (await entries()).firstWhere((e) => e['id'] == id);
    Future<void> post(String room, List<Object?> ids) =>
        m('/v1/minibar/$room/post', {'ids': ids});

    test('recorded, corrected before posting, posted once', () async {
      login('lina');
      await expectLater(
        m('/v1/minibar/new/record', {
          'roomNumber': '214',
          'itemId': 'minibar-soda',
          'quantity': 2,
        }),
        refused(403),
      );
      login('sarah');
      await expectLater(
        m('/v1/minibar/new/record', {
          'roomNumber': '214',
          'itemId': 'towels',
          'quantity': 2,
        }),
        refused(404),
      );
      await m('/v1/minibar/new/record', {
        'roomNumber': '214',
        'itemId': 'minibar-soda',
        'quantity': 2,
      });
      var soda = (await entries()).single;
      expect(isUuid(soda['id']), isTrue);
      expect((soda['status'], soda['amount_cents']), ('pending', 900));
      await m('/v1/minibar/${soda['id']}/correct', {
        'version': soda['version'],
        'quantity': 3,
      });
      soda = await entry(soda['id'] as String);
      expect((soda['quantity'], soda['amount_cents']), (3, 1350));
      await expectLater(
        post('214', [soda['id']]),
        refused(403),
        reason: 'the supervisor validates',
      );
      expect(charges(), isEmpty);

      login('amina');
      final meta = mutationMeta();
      for (var i = 0; i < 2; i++) {
        // Same client mutation twice (offline replay): applied once.
        await backend.mutate('/v1/minibar/214/post', {
          ...meta,
          'ids': [soda['id'], soda['id']],
        });
      }
      await post('214', [soda['id']]);
      await settleEvents();
      expect(charges().map((c) => (c.roomNumber, c.label, c.amountCents)), [
        ('214', 'Minibar · Soda 33 cl × 3', 1350),
      ]);
      soda = await entry(soda['id'] as String);
      expect(soda['status'], 'billed');
      await expectLater(
        m('/v1/minibar/${soda['id']}/correct', {
          'version': soda['version'],
          'quantity': 1,
        }),
        refused(409),
        reason: 'billed: only a compensating entry',
      );
    });

    test('after posting, a compensating entry corrects the bill', () async {
      login('amina');
      await m('/v1/minibar/new/record', {
        'roomNumber': '305',
        'itemId': 'minibar-water',
        'quantity': 3,
      });
      var water = (await entries()).single;
      await post('305', [water['id']]);
      water = await entry(water['id'] as String);
      await expectLater(
        m('/v1/minibar/${water['id']}/compensate', {
          'version': water['version'],
          'quantity': 3,
        }),
        refused(400),
        reason: 'nothing to correct',
      );
      await m('/v1/minibar/${water['id']}/compensate', {
        'version': water['version'],
        'quantity': 1,
      });
      final correction = (await entries()).firstWhere(
        (e) => e['corrects_id'] == water['id'],
      );
      expect(
        (
          correction['quantity'],
          correction['amount_cents'],
          correction['status'],
        ),
        (-2, -800, 'pending'),
      );
      water = await entry(water['id'] as String);
      await expectLater(
        m('/v1/minibar/${water['id']}/compensate', {
          'version': water['version'],
          'quantity': 0,
        }),
        refused(409),
        reason: 'one pending correction at a time',
      );
      await post('305', [correction['id']]);
      await post('305', [correction['id'], water['id']]);
      await settleEvents();
      expect(charges().map((c) => c.amountCents), [1200, -800]);
      expect(
        charges().last.label,
        'Minibar · correction Eau minérale 50 cl -2',
      );
      water = await entry(water['id'] as String);
      await m('/v1/minibar/${water['id']}/compensate', {
        'version': water['version'],
        'quantity': 2,
      });
      final second = (await entries()).firstWhere(
        (e) => e['corrects_id'] == water['id'] && e['status'] == 'pending',
      );
      expect(second['quantity'], 1, reason: 'billed total 1, target 2');
    });

    test('posting is refused once the guest of the entry has left', () async {
      session.events.emit(const GuestCheckedIn('402', guestName: 'M. Martin'));
      await settleEvents();
      login('amina');
      await m('/v1/minibar/new/record', {
        'roomNumber': '402',
        'itemId': 'minibar-chocolate',
        'quantity': 1,
      });
      final during = (await entries()).single;
      expect(during['stayChanged'], false);
      session.events.emit(const GuestCheckedOut('402'));
      await settleEvents();
      expect((await entry(during['id'] as String))['stayChanged'], true);
      await expectLater(post('402', [during['id']]), refused(409));
      expect(charges(), isEmpty);
      // Recorded at the departure cleaning: no guest any more, postable.
      await m('/v1/minibar/new/record', {
        'roomNumber': '402',
        'itemId': 'minibar-water',
        'quantity': 1,
      });
      final after = (await entries()).firstWhere(
        (e) => e['id'] != during['id'],
      );
      await post('402', [after['id']]);
      await settleEvents();
      expect(charges().single.amountCents, 400);
    });

    test('restocking the minibar takes it out of the storeroom', () async {
      login('sarah');
      await m('/v1/minibar/214/restock', {
        'lines': lines({'minibar-water': 2, 'minibar-soda': 1}),
      });
      expect(
        (await stock('minibar-water'), await stock('minibar-soda')),
        (22, 23),
      );
      final log = (await snap())['stockMovements'] as List;
      expect(
        [for (final x in log) (x['reason'], x['room_number'])],
        [('minibar_restock', '214'), ('minibar_restock', '214')],
      );
      await expectLater(
        m('/v1/minibar/214/restock', {
          'lines': lines({'towels': 1}),
        }),
        refused(400),
      );
    });

    test('the Manager manages the minibar catalog', () async {
      login('manager');
      await catalog.mutate(RoomCatalogAction.saveMinibarItem, {
        'name': 'Jus d’orange',
        'unit': 'bouteilles',
        'priceCents': 500,
        'quantity': 12,
        'minimum': 3,
      });
      var items = (await catalog.snapshot()).minibarItems;
      final juice = items.firstWhere((i) => i.name == 'Jus d’orange');
      expect((juice.priceCents, juice.category), (500, 'minibar'));
      await catalog.mutate(RoomCatalogAction.saveMinibarItem, {
        'id': juice.id,
        'version': juice.version,
        'name': 'Jus d’orange',
        'unit': 'bouteilles',
        'priceCents': 550,
        'minimum': 3,
      });
      await expectLater(
        catalog.mutate(RoomCatalogAction.saveMinibarItem, {
          'id': juice.id,
          'version': juice.version,
          'name': 'Jus',
          'unit': 'bouteilles',
          'priceCents': 600,
          'minimum': 3,
        }),
        refused(409),
      );
      items = (await catalog.snapshot()).minibarItems;
      final updated = items.firstWhere((i) => i.id == juice.id);
      expect(updated.priceCents, 550);
      await catalog.mutate(RoomCatalogAction.deleteMinibarItem, {
        'id': juice.id,
        'version': updated.version,
      });
      expect(
        (await catalog.snapshot()).minibarItems.map((i) => i.id),
        isNot(contains(juice.id)),
      );
      login('sarah');
      await expectLater(
        catalog.mutate(RoomCatalogAction.saveMinibarItem, {
          'name': 'Bière',
          'unit': 'bouteilles',
          'priceCents': 600,
          'quantity': 1,
          'minimum': 0,
        }),
        refused(403),
      );
    });
  });

  test('a version 5 database upgrades in place', () async {
    final db = session.database.database;
    await dropVersion6(db);
    await db.update('module_versions', {
      'version': 5,
    }, where: "module = 'housekeeping'");
    await session.database.close();
    await open();
    expect(await session.database.versionOf('housekeeping'), 7);
    expect((await supply('sheets'))['category'], 'linge');
    expect((await supply('soap'))['category'], 'accueil');
    expect((await supply('cleaner'))['category'], 'entretien');
    login('sarah');
    await m('/v1/supplies/towels/use', {'roomNumber': '214', 'quantity': 1});
    expect(await stock('towels'), 67);
  });
}
