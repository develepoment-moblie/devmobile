import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/shared/models/app_user.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:nova_paris/shared/services/staff_directory.dart';
import 'package:nova_paris/guest_services/services/guest_service_store.dart';
import 'package:nova_paris/guest_services/services/service_desk_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Staff implements StaffDirectory {
  @override
  Future<List<AppUser>> users({Set<String>? roles}) async => [
    reception,
    manager,
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
        ),
        throwsStateError,
      );
      session.signIn(other);
      await store.saveRecord(
        kind: 'restaurant',
        title: 'Dîner',
        details: 'Une personne',
        slotId: s['id'] as int,
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
    );
    await expectLater(
      store.saveRecord(
        kind: 'restaurant',
        title: 'Autre dîner',
        details: 'Même horaire',
        slotId: second['id'] as int,
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
}
