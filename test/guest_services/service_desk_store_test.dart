import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nova_paris/shared/models/app_user.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:nova_paris/shared/services/staff_directory.dart';
import 'package:nova_paris/guest_services/services/guest_service_store.dart';
import 'package:nova_paris/guest_services/services/room_service_exchange.dart';
import 'package:nova_paris/guest_services/services/service_desk_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Staff implements StaffDirectory {
  @override
  Future<List<AppUser>> users({Set<String>? roles}) async => [
    reception,
    manager,
    guest,
    other,
  ].where((u) => roles == null || roles.contains(u.role)).toList();
}

const guest = AppUser(id: 'alice', fullName: 'Alice', role: AppRole.guest);
const other = AppUser(id: 'bob', fullName: 'Bob', role: AppRole.guest);
const manager = AppUser(
  id: 'manager',
  fullName: 'Direction',
  role: AppRole.manager,
);
const reception = AppUser(
  id: 'reception',
  fullName: 'Accueil',
  role: AppRole.receptionist,
);
void main() {
  late AppSession session;
  late ServiceDeskStore store;
  final now = DateTime.utc(2026, 10, 28, 10);
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    final db = await AppDatabase.open(
      schemas: [GuestServiceStore.schema],
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    session = AppSession(database: db, staff: _Staff())..signIn(manager);
    store = ServiceDeskStore(session, clock: () => now);
  });
  tearDown(() async {
    await session.events.dispose();
    session.dispose();
    await session.database.close();
  });
  Future<Map<String, Object?>> slot({
    String name = 'Restaurant',
    int capacity = 2,
  }) async {
    await store.saveSlot(
      kind: 'restaurant',
      name: name,
      start: now.add(const Duration(hours: 2)),
      end: now.add(const Duration(hours: 3)),
      capacity: capacity,
      priceCents: 2500,
    );
    return (await store.slots()).last;
  }

  Future<Map<String, Object?>> record(int id) =>
      store.accessible(session.database.database, id);

  test(
    'restaurant bookings without slots block the table for two hours',
    () async {
      final start = now.add(const Duration(hours: 1));
      Future<int> book(DateTime time) => store.saveRecord(
        kind: 'restaurant',
        title: 'Réservation restaurant',
        details: '',
        restaurantStart: time,
        diningTableId: 2,
        units: 2,
      );
      session.signIn(guest);
      await expectLater(book(now), throwsStateError);
      final id = await book(start);
      expect((await record(id))['slot_id'], isNull);
      session.signIn(other);
      final overlap = start.add(const Duration(hours: 1));
      final tables = await store.restaurantTableChoicesAt(overlap);
      expect(tables.singleWhere((table) => table['id'] == 2)['reserved'], 1);
      await expectLater(book(overlap), throwsStateError);
      await book(start.add(const Duration(hours: 2)));
      session.signIn(reception);
      await store.status(await record(id), 'confirmed');
      await store.registerRestaurantArrival(id);
      await store.seatRestaurantParty(id, 2);
      expect((await record(id))['status'], 'in_progress');
    },
  );

  test('exchange preview reuses a dated rate when offline', () async {
    final db = session.database.database;
    final exchange = RoomServiceExchange(db);
    final live = await http.runWithClient(
      exchange.load,
      () => MockClient((request) async {
        expect(request.url.path, '/v2/rate/EUR/TND');
        return http.Response('{"date":"2026-11-10","rate":3.4}', 200);
      }),
    );
    expect(live.cached, isFalse);
    await db.update('guest_services_currency_rates', {
      'fetched_at': '2026-01-01T00:00:00.000Z',
    });
    final cached = await http.runWithClient(
      exchange.load,
      () => MockClient((_) async => throw http.ClientException('offline')),
    );
    expect(cached, (rate: 3.4, date: '2026-11-10', cached: true));
  });

  test('a failed email leaves the restaurant booking confirmed', () async {
    final shift = await slot(capacity: 4);
    session.signIn(guest);
    final id = await store.saveRecord(
      kind: 'restaurant',
      title: 'Réservation restaurant',
      details: '',
      slotId: shift['id'] as int,
      diningTableId: 2,
      units: 2,
      confirmationEmail: 'guest@example.test',
    );
    expect((await record(id))['confirmation_email_status'], isNull);
    session.signIn(reception);
    await store.status(await record(id), 'confirmed');
    final confirmed = await record(id);
    expect(confirmed['status'], 'confirmed');
    expect(confirmed['confirmation_email_status'], 'failed');
    await store.sendRestaurantConfirmation(id);
    expect(
      (await record(id))['confirmation_email_key'],
      confirmed['confirmation_email_key'],
    );
  });

  test('a visitor booking needs no account and reserves the table', () async {
    final shift = await slot(capacity: 8);
    Future<int> bookVisitor() => store.saveRecord(
      kind: 'restaurant',
      title: 'Réservation restaurant',
      details: '',
      slotId: shift['id'] as int,
      diningTableId: 2,
      units: 4,
      visitorName: ' Sam Martin ',
    );
    final id = await bookVisitor();
    final booking = await record(id);
    expect(booking['status'], 'confirmed');
    expect(booking['guest_name'], 'Sam Martin');
    await expectLater(bookVisitor(), throwsStateError);
    session.signIn(guest);
    expect(await store.records(), isEmpty);
    await expectLater(bookVisitor(), throwsStateError);
  });

  test('management books the fixed floor on behalf of a client', () async {
    final shift = await slot(capacity: 12);
    final slotId = shift['id'] as int;
    final plan = await store.restaurantTableChoices(slotId);
    expect(plan.map((table) => table['seats']).toSet(), {2, 4, 6, 8});
    expect(plan.map((table) => table['shape']).toSet(), {
      'square',
      'rectangle',
      'circle',
    });
    final tableId =
        plan.singleWhere((table) => table['name'] == '104')['id'] as int;
    final id = await store.saveRecord(
      kind: 'restaurant',
      title: 'Dîner',
      details: 'Réservation par la direction',
      slotId: slotId,
      diningTableId: tableId,
      units: 6,
      guestId: guest.id,
    );
    expect((await record(id))['status'], 'confirmed');
    session.signIn(other);
    expect(await store.records(), isEmpty);
    final updated = await store.restaurantTableChoices(slotId);
    expect(
      updated.singleWhere((table) => table['id'] == tableId)['reserved'],
      1,
    );
    session.signIn(guest);
    expect((await store.records()).single['dining_table_name'], '104');
  });
  test('slot CRUD validates overlap, capacity and stale versions', () async {
    final s = await slot();
    await expectLater(slot(), throwsStateError);
    await store.saveSlot(
      previous: s,
      kind: 'restaurant',
      name: 'Restaurant',
      start: now.add(const Duration(hours: 3)),
      end: now.add(const Duration(hours: 4)),
      capacity: 4,
      priceCents: 3000,
    );
    await expectLater(store.archiveSlot(s, true), throwsStateError);
    final updated = (await store.slots()).single;
    await store.archiveSlot(updated, true);
    expect(await store.slots(), isEmpty);
    await store.archiveSlot((await store.slots(archived: true)).single, false);
    session.signIn(reception);
    await expectLater(
      store.archiveSlot((await store.slots()).single, true),
      throwsStateError,
    );
  });
  test(
    'bookings reserve capacity atomically and cancellation releases it',
    () async {
      final s = await slot();
      session.signIn(guest);
      final id = await store.saveRecord(
        kind: 'restaurant',
        title: 'Dîner',
        details: 'Deux personnes',
        slotId: s['id'] as int,
        diningTableId: 1,
        units: 2,
      );
      expect((await record(id))['price_cents'], 5000);
      session.signIn(other);
      await expectLater(
        store.saveRecord(
          kind: 'restaurant',
          title: 'Dîner',
          details: 'Une personne',
          slotId: s['id'] as int,
          diningTableId: 1,
        ),
        throwsStateError,
      );
      await expectLater(record(id), throwsStateError);
      session.signIn(manager);
      await expectLater(store.archiveSlot(s, true), throwsStateError);
      session.signIn(guest);
      final pending = await record(id);
      await store.status(pending, 'cancelled');
      await expectLater(
        store.saveRecord(
          previous: pending,
          kind: 'restaurant',
          title: 'Changement',
          details: 'Test',
          slotId: s['id'] as int,
          diningTableId: 1,
        ),
        throwsStateError,
      );
      session.signIn(other);
      await store.saveRecord(
        kind: 'restaurant',
        title: 'Dîner',
        details: 'Une personne',
        slotId: s['id'] as int,
        diningTableId: 1,
      );
    },
  );
  test('guest booking conflicts and past slots are rejected', () async {
    final first = await slot(name: 'Salle A', capacity: 10);
    final second = await slot(name: 'Salle B', capacity: 10);
    session.signIn(guest);
    await store.saveRecord(
      kind: 'restaurant',
      title: 'Dîner',
      details: 'Dîner',
      slotId: first['id'] as int,
      diningTableId: 1,
    );
    await expectLater(
      store.saveRecord(
        kind: 'restaurant',
        title: 'Autre dîner',
        details: 'Même horaire',
        slotId: second['id'] as int,
        diningTableId: 2,
      ),
      throwsStateError,
    );
    final later = ServiceDeskStore(
      session,
      clock: () => now.add(const Duration(days: 1)),
    );
    await expectLater(
      later.saveRecord(
        kind: 'restaurant',
        title: 'Dîner',
        details: 'Dîner',
        slotId: second['id'] as int,
        diningTableId: 2,
      ),
      throwsStateError,
    );
  });
  test('request CRUD, lifecycle, messages and review ownership', () async {
    session.signIn(guest);
    final id = await store.saveRecord(
      kind: 'request',
      title: 'Serviettes',
      details: 'Deux serviettes',
    );
    final pending = await record(id);
    await store.saveRecord(
      previous: pending,
      kind: 'request',
      title: 'Serviettes propres',
      details: 'Trois serviettes',
    );
    await expectLater(
      store.saveRecord(
        previous: pending,
        kind: 'request',
        title: 'Ancien formulaire',
        details: 'Détails',
      ),
      throwsStateError,
    );
    await store.saveMessage(id, 'Merci de sonner');
    final m = (await store.messages(id)).single;
    await store.saveMessage(id, 'Merci de frapper', previous: m);
    await expectLater(
      store.saveMessage(id, 'Ancienne modification', previous: m),
      throwsStateError,
    );
    final edited = (await store.messages(id)).single;
    session.signIn(reception);
    await expectLater(
      store.saveMessage(id, '', previous: edited, delete: true),
      throwsStateError,
    );
    await store.saveMessage(id, 'Bien reçu');
    await store.status(await record(id), 'confirmed');
    await store.status(await record(id), 'in_progress');
    await store.status(await record(id), 'completed');
    session.signIn(guest);
    await expectLater(
      store.saveMessage(id, 'Message tardif'),
      throwsStateError,
    );
    await store.saveReview(id, 5, 'Excellent service');
    final review = (await store.review(id))!;
    await store.saveReview(id, 4, 'Service agréable', previous: review);
    session.signIn(other);
    await expectLater(store.review(id), throwsStateError);
    session.signIn(guest);
    await store.saveReview(
      id,
      1,
      '',
      previous: await store.review(id),
      delete: true,
    );
    expect(await store.review(id), isNull);
    session.signIn(reception);
    await store.archiveRecord(await record(id), true);
    expect(await store.records(), isEmpty);
    await store.archiveRecord(
      (await store.records(archived: true)).single,
      false,
    );
    expect((await store.history(id)).length, greaterThanOrEqualTo(6));
  });
  test(
    'complaints require rejection reason and clients cannot escalate privileges',
    () async {
      session.signIn(guest);
      final id = await store.saveRecord(
        kind: 'complaint',
        title: 'Bruit',
        details: 'Bruit dans le couloir',
      );
      await expectLater(
        store.status(await record(id), 'completed'),
        throwsStateError,
      );
      await expectLater(store.saveReview(id, 5, 'Trop tôt'), throwsStateError);
      session.signIn(reception);
      await expectLater(
        store.status(await record(id), 'rejected'),
        throwsStateError,
      );
      await store.status(
        await record(id),
        'rejected',
        reason: 'Dossier ouvert en double',
      );
      session.signIn(guest);
      expect((await record(id))['reason'], 'Dossier ouvert en double');
    },
  );
  test('concurrent clients cannot overbook the last place', () async {
    final s = await slot(capacity: 1);
    final secondSession = AppSession(
      database: session.database,
      staff: _Staff(),
    )..signIn(other);
    final secondStore = ServiceDeskStore(secondSession, clock: () => now);
    session.signIn(guest);
    Future<bool> book(ServiceDeskStore target) async {
      try {
        await target.saveRecord(
          kind: 'restaurant',
          title: 'Dîner',
          details: 'Une personne',
          slotId: s['id'] as int,
          diningTableId: 1,
        );
        return true;
      } on StateError {
        return false;
      }
    }

    try {
      final results = await Future.wait([book(store), book(secondStore)]);
      expect(results.where((success) => success).length, 1);
      session.signIn(manager);
      expect((await store.slots()).single['reserved'], 1);
    } finally {
      await secondSession.events.dispose();
      secondSession.dispose();
    }
  });
  test(
    'assignment validates personnel and rejects outdated or closed records',
    () async {
      session.signIn(guest);
      final id = await store.saveRecord(
        kind: 'request',
        title: 'Serviettes',
        details: 'Deux serviettes',
      );
      final old = await record(id);
      await expectLater(store.assign(old, 'reception'), throwsStateError);
      session.signIn(reception);
      await expectLater(store.assign(old, 'unknown'), throwsStateError);
      await store.assign(old, 'reception');
      expect((await record(id))['assigned_to'], 'reception');
      await expectLater(store.assign(old, null), throwsStateError);
      await store.assign(await record(id), null);
      expect((await record(id))['assigned_to'], isNull);
    },
  );
  test(
    'restaurant arrival, table assignment and release protect occupied tables',
    () async {
      final shift = await slot(capacity: 8);

      final tables = await store.diningTables();
      final small =
          tables.singleWhere((table) => table['name'] == '101')['id'] as int;
      final large =
          tables.singleWhere((table) => table['name'] == '102')['id'] as int;
      session.signIn(guest);
      final a = await store.saveRecord(
        kind: 'restaurant',
        title: 'Déjeuner',
        details: 'Trois personnes',
        slotId: shift['id'] as int,
        diningTableId: large,
        units: 3,
      );
      await expectLater(store.registerRestaurantArrival(a), throwsStateError);
      session.signIn(other);
      final choices = await store.restaurantTableChoices(shift['id'] as int);
      expect(
        choices.singleWhere((table) => table['id'] == large)['reserved'],
        1,
      );
      await expectLater(
        store.saveRecord(
          kind: 'restaurant',
          title: 'Déjeuner',
          details: 'Deux personnes',
          slotId: shift['id'] as int,
          diningTableId: large,
          units: 2,
        ),
        throwsStateError,
      );
      final b = await store.saveRecord(
        kind: 'restaurant',
        title: 'Déjeuner',
        details: 'Deux personnes',
        slotId: shift['id'] as int,
        diningTableId: small,
        units: 2,
      );
      session.signIn(reception);
      await store.status(await record(a), 'confirmed');
      await store.status(await record(b), 'confirmed');
      expect(await store.restaurantArrivals(), hasLength(2));
      await expectLater(store.seatRestaurantParty(a, large), throwsStateError);
      await store.registerRestaurantArrival(a);
      await store.registerRestaurantArrival(b);
      await expectLater(store.seatRestaurantParty(a, small), throwsStateError);
      await store.seatRestaurantParty(a, large);
      await expectLater(store.seatRestaurantParty(b, large), throwsStateError);
      expect((await record(b))['status'], 'confirmed');
      expect((await store.restaurantArrivals()).single['id'], b);
      await store.finishRestaurantService(a);
      expect((await record(a))['status'], 'completed');
      await store.seatRestaurantParty(b, large);
      expect(
        (await store.diningTables()).singleWhere(
          (table) => table['id'] == large,
        )['record_id'],
        b,
      );
      await store.status(
        await record(b),
        'cancelled',
        reason: 'Départ anticipé',
      );
      expect(
        (await store.diningTables()).every((t) => t['record_id'] == null),
        isTrue,
      );
    },
  );
}
