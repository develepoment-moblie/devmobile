import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/shared/models/app_user.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:nova_paris/shared/services/staff_directory.dart';
import 'package:nova_paris/guest_services/models/room_service.dart';
import 'package:nova_paris/guest_services/services/guest_service_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Staff implements StaffDirectory {
  @override
  Future<List<AppUser>> users({Set<String>? roles}) async => [
    const AppUser(id: 'guest', fullName: 'Client', role: AppRole.guest),
    const AppUser(id: 'sarah', fullName: 'Sarah', role: AppRole.staff),
    const AppUser(id: 'lina', fullName: 'Lina', role: AppRole.staff),
  ];
}

void main() {
  late AppSession session;
  late GuestServiceStore store;
  const kitchen = AppUser(
    id: 'kitchen',
    fullName: 'Cuisine',
    role: AppRole.kitchen,
  );
  const first = AppUser(id: 'guest', fullName: 'Alice', role: AppRole.guest);
  const second = AppUser(id: 'guest-b', fullName: 'Bob', role: AppRole.guest);
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    final database = await AppDatabase.open(
      schemas: [GuestServiceStore.schema],
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    for (final item in roomServiceMenu) {
      await database.database.insert('guest_services_menu', {
        ...item.toRow(),
        'portions': 20,
      });
    }
    for (final category in roomServiceMenu.map((i) => i.category).toSet()) {
      await database.database.insert('guest_services_categories', {
        'name': category,
      });
    }
    await database.database.insert('guest_services_stays', {
      'id': 'test-stay',
      'guest_id': 'guest',
      'guest_name': 'Client',
      'room_number': '305',
      'active': 0,
    });
    await database.database.update(
      'guest_services_stays',
      {
        'active': 1,
        'valid_until': DateTime.now()
            .add(const Duration(days: 2))
            .toUtc()
            .toIso8601String(),
        'verified_by': 'test-reception',
      },
      where: 'guest_id = ?',
      whereArgs: ['guest'],
    );
    session = AppSession(database: database, staff: _Staff())..signIn(first);
    store = GuestServiceStore(session);
  });
  tearDown(() async {
    await session.events.dispose();
    session.dispose();
    await session.database.close();
  });

  test('drafts and order history are isolated per guest', () async {
    await store.saveCart([const CartLine('burger', 2, 'Sauce à part')]);
    session.signIn(second);
    expect(await store.loadCart(), isEmpty);
    session.signIn(first);
    expect((await store.loadCart()).single.quantity, 2);
    await store.submit();
    expect((await store.orders()).single['total_cents'], 4800);
    expect(await store.loadCart(), isEmpty);
    session.signIn(second);
    expect(await store.orders(), isEmpty);
  });
  test(
    'submission consumes draft once and cancellation enforces ownership',
    () async {
      await store.saveCart([const CartLine('coffee', 1, '')]);
      final id = await store.submit();
      await expectLater(store.submit(), throwsStateError);
      session.signIn(second);
      await expectLater(store.cancel(id), throwsStateError);
      session.signIn(first);
      await store.cancel(id);
      expect((await store.orders()).single['status'], 'cancelled');
    },
  );
  test('unavailable items and staff cannot place guest orders', () async {
    await store.saveCart([const CartLine('tart', 1, '')]);
    await expectLater(store.submit(), throwsStateError);
    session.signIn(
      const AppUser(id: 'manager', fullName: 'Manager', role: AppRole.manager),
    );
    await expectLater(store.loadCart(), throwsStateError);
  });
  test(
    'reception progresses orders, rejects stale updates and prevents late cancellation',
    () async {
      await store.saveCart([const CartLine('coffee', 1, '')]);
      final id = await store.submit();
      await expectLater(store.receptionOrders(), throwsStateError);
      session.signIn(
        const AppUser(
          id: 'reception',
          fullName: 'Reception',
          role: AppRole.receptionist,
        ),
      );
      expect((await store.receptionOrders()).single['room_number'], '305');
      await expectLater(
        store.transition(id, 'placed', 'delivered'),
        throwsStateError,
      );
      await expectLater(
        store.transition(id, 'placed', 'preparing'),
        throwsStateError,
      );
      await expectLater(
        store.transition(id, 'placed', 'preparing', agentId: first.id),
        throwsStateError,
      );
      await store.transition(id, 'placed', 'preparing', agentId: 'sarah');
      await expectLater(
        store.transition(id, 'placed', 'cancelled', reason: 'Indisponible'),
        throwsStateError,
      );
      session.signIn(first);
      await expectLater(store.cancel(id), throwsStateError);
      expect((await store.orders()).single['status'], 'preparing');
      session.signIn(
        const AppUser(
          id: 'reception',
          fullName: 'Reception',
          role: AppRole.receptionist,
        ),
      );
      await expectLater(
        store.transition(id, 'preparing', 'delivered'),
        throwsStateError,
      );
      await expectLater(store.confirmDelivery(id), throwsStateError);
      expect(
        (await store.receptionOrders()).single['delivery_agent_name'],
        'Sarah',
      );
      await store.assignDelivery(id, 'preparing', 'sarah', 'lina');
      await expectLater(
        store.assignDelivery(id, 'preparing', 'sarah', 'lina'),
        throwsStateError,
      );
      session.signIn(
        const AppUser(id: 'sarah', fullName: 'Sarah', role: AppRole.staff),
      );
      expect(await store.assignedDeliveries(), isEmpty);
      await expectLater(store.confirmDelivery(id), throwsStateError);
      session.signIn(
        const AppUser(id: 'lina', fullName: 'Lina', role: AppRole.staff),
      );
      expect((await store.assignedDeliveries()).single['id'], id);
      await expectLater(store.markOrderReady(id), throwsStateError);
      await expectLater(store.confirmDelivery(id), throwsStateError);
      session.signIn(kitchen);
      expect((await store.kitchenOrders()).single['id'], id);
      await store.markOrderReady(id);
      await expectLater(store.markOrderReady(id), throwsStateError);
      await expectLater(store.confirmDelivery(id), throwsStateError);
      session.signIn(first);
      expect((await store.orders()).single['status'], 'ready');
      session.signIn(
        const AppUser(id: 'lina', fullName: 'Lina', role: AppRole.staff),
      );
      await store.confirmDelivery(id);
      await expectLater(store.confirmDelivery(id), throwsStateError);
      session.signIn(
        const AppUser(
          id: 'reception',
          fullName: 'Reception',
          role: AppRole.receptionist,
        ),
      );
      final delivered = (await store.receptionOrders()).single;
      expect(delivered['delivered_by_name'], 'Lina');
      expect(DateTime.tryParse(delivered['delivered_at'] as String), isNotNull);
      expect((await store.history(id)).last['actor_id'], 'lina');

      expect((await store.history(id)).map((e) => e['status']), [
        'placed',
        'preparing',
        'assigned',
        'ready',
        'delivered',
      ]);
    },
  );
  test(
    'exceptional cancellation requires a reason and is visible to the guest',
    () async {
      await store.saveCart([const CartLine('coffee', 1, '')]);
      final id = await store.submit();
      session.signIn(
        const AppUser(
          id: 'reception',
          fullName: 'Reception',
          role: AppRole.receptionist,
        ),
      );
      await expectLater(
        store.transition(id, 'placed', 'cancelled', reason: ' '),
        throwsStateError,
      );
      await store.transition(
        id,
        'placed',
        'cancelled',
        reason: 'Cuisine fermée',
      );
      session.signIn(first);
      expect((await store.orders()).single['reason'], 'Cuisine fermée');
      session.signIn(second);
      await expectLater(store.history(id), throwsStateError);
      await expectLater(store.submit(), throwsStateError);
    },
  );
  test(
    'v2 migration preserves legacy orders without inventing a room',
    () async {
      final legacy = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
      );
      try {
        await legacy.execute("""CREATE TABLE guest_services_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT, guest_id TEXT NOT NULL,
        created_at TEXT NOT NULL, lines TEXT NOT NULL, total_cents INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'placed')""");
        await legacy.insert('guest_services_orders', {
          'guest_id': 'guest',
          'created_at': '2026-10-25',
          'lines': '[]',
          'total_cents': 500,
          'status': 'placed',
        });
        await legacy.transaction(
          (tx) => GuestServiceStore.schema.migrate(tx, 1, 2),
        );
        final order = (await legacy.query('guest_services_orders')).single;
        expect(order['total_cents'], 500);
        expect(order['stay_id'], isNull);
        expect(order['room_number'], isNull);
        expect(
          (await legacy.query('guest_services_stays')).single['room_number'],
          '305',
        );
      } finally {
        await legacy.close();
      }
    },
  );
  test(
    'manager CRUD persists menu changes, archiving and restoration',
    () async {
      session.signIn(
        const AppUser(
          id: 'manager',
          fullName: 'Manager',
          role: AppRole.manager,
        ),
      );
      const item = MenuItem(
        'new-dish',
        'Soupe maison',
        'Légumes de saison',
        'Plats',
        '🍲',
        1250,
        15,
        'Céleri',
        vegetarian: true,
      );
      await store.saveMenuItem(item, create: true);
      expect((await store.menu()).any((e) => e.id == 'new-dish'), isTrue);
      const updated = MenuItem(
        'new-dish',
        'Soupe du jour',
        'Légumes frais',
        'Plats',
        '🍲',
        1400,
        20,
        'Céleri',
      );
      await store.saveMenuItem(updated);
      await store.archiveMenuItem('new-dish', true);
      expect((await store.menu()).any((e) => e.id == 'new-dish'), isFalse);
      expect((await store.menu(archived: true)).single.name, 'Soupe du jour');
      await store.archiveMenuItem('new-dish', false);
      session.signIn(kitchen);
      final stock = (await store.kitchenStock()).singleWhere(
        (e) => e['id'] == 'new-dish',
      );
      await store.updateStock(
        'new-dish',
        version: stock['version'] as int,
        portions: 2,
        enabled: true,
      );
      session.signIn(first);
      final current = (await store.menu()).firstWhere(
        (e) => e.id == 'new-dish',
      );
      await store.saveCart([CartLine(current.id, 2, '', current)]);
      expect((await store.loadCart()).single.total, 2800);
      await store.submit();
      expect((await store.orders()).single['total_cents'], 2800);
      session.signIn(
        const AppUser(
          id: 'manager',
          fullName: 'Manager',
          role: AppRole.manager,
        ),
      );
      await store.archiveMenuItem('new-dish', true);
      session.signIn(first);
      expect((await store.orders()).single['total_cents'], 2800);
      await expectLater(store.saveMenuItem(item), throwsStateError);
      session.signIn(
        const AppUser(
          id: 'reception',
          fullName: 'Reception',
          role: AppRole.receptionist,
        ),
      );
      await expectLater(
        store.archiveMenuItem('coffee', true),
        throwsStateError,
      );
    },
  );
  test('changed prices and archived items block stale checkout', () async {
    await store.saveCart([const CartLine('coffee', 1, '')]);
    session.signIn(
      const AppUser(id: 'manager', fullName: 'Manager', role: AppRole.manager),
    );
    const changed = MenuItem(
      'coffee',
      'Café',
      'Café',
      'Boissons',
      '☕',
      600,
      10,
      'Lait',
    );
    await store.saveMenuItem(changed);
    session.signIn(first);
    await expectLater(store.submit(), throwsStateError);
    expect((await store.loadCart()).single.total, 600);
    session.signIn(
      const AppUser(id: 'manager', fullName: 'Manager', role: AppRole.manager),
    );
    await store.archiveMenuItem('coffee', true);
    session.signIn(first);
    await expectLater(store.submit(), throwsStateError);
    expect((await store.loadCart()).single.item.available, isFalse);
  });
  test(
    'category CRUD propagates rename and protects populated categories',
    () async {
      session.signIn(
        const AppUser(
          id: 'manager',
          fullName: 'Direction',
          role: AppRole.manager,
        ),
      );
      await store.saveCategory('Entrées');
      await store.saveCategory('Entrées fraîches', previous: 'Entrées');
      expect(
        (await store.categories()).any((c) => c['name'] == 'Entrées fraîches'),
        isTrue,
      );
      await store.archiveCategory('Entrées fraîches', true);
      expect(
        (await store.categories(archived: true)).single['name'],
        'Entrées fraîches',
      );
      await store.archiveCategory('Entrées fraîches', false);
      await expectLater(store.archiveCategory('Plats', true), throwsStateError);
      await store.saveCategory('Assiettes', previous: 'Plats');
      expect((await store.menu()).where((i) => i.category == 'Plats'), isEmpty);
      expect(
        (await store.menu()).any((i) => i.category == 'Assiettes'),
        isTrue,
      );
      session.signIn(first);
      await expectLater(store.saveCategory('Interdit'), throwsStateError);
    },
  );
  test(
    'verified room association is required, expires and can be deactivated',
    () async {
      await session.database.database.update('guest_services_stays', {
        'active': 0,
      });
      await store.saveCart([const CartLine('coffee', 1, '')]);
      expect(await store.currentStay(), isNull);
      await expectLater(store.submit(), throwsStateError);
      session.signIn(
        const AppUser(
          id: 'reception',
          fullName: 'Accueil',
          role: AppRole.receptionist,
        ),
      );
      await store.saveStay(
        guest: 'guest',
        reference: 'STAY-100',
        room: '412',
        validUntil: DateTime.now().add(const Duration(days: 1)),
      );
      session.signIn(first);
      expect((await store.currentStay())!['room_number'], '412');
      await store.submit();
      expect((await store.orders()).single['room_number'], '412');
      session.signIn(
        const AppUser(
          id: 'reception',
          fullName: 'Accueil',
          role: AppRole.receptionist,
        ),
      );
      await store.deactivateStay('guest');
      session.signIn(first);
      expect(await store.currentStay(), isNull);
      await expectLater(
        store.saveStay(
          guest: 'guest',
          reference: 'FORGED',
          room: '1',
          validUntil: DateTime.now().add(const Duration(days: 1)),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'fresh installations contain no sample menu or automatic active room',
    () async {
      final fresh = await AppDatabase.open(
        schemas: [GuestServiceStore.schema],
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      try {
        expect(await fresh.database.query('guest_services_menu'), isEmpty);
        expect(await fresh.database.query('guest_services_stays'), isEmpty);
        expect(await fresh.database.query('guest_services_slots'), isEmpty);
      } finally {
        await fresh.close();
      }
    },
  );
  test('stale menu edits cannot overwrite a newer manager change', () async {
    session.signIn(
      const AppUser(
        id: 'manager',
        fullName: 'Direction',
        role: AppRole.manager,
      ),
    );
    final item = (await store.menu()).first;
    await store.saveMenuItem(item);
    await expectLater(store.saveMenuItem(item), throwsStateError);
  });
  test('last portion is reserved by only one concurrent checkout', () async {
    final otherSession = AppSession(database: session.database, staff: _Staff())
      ..signIn(second);
    addTearDown(() async {
      await otherSession.events.dispose();
      otherSession.dispose();
    });
    final other = GuestServiceStore(otherSession);
    final db = session.database.database;
    await db.insert('guest_services_stays', {
      'id': 'test-stay-b',
      'guest_id': second.id,
      'guest_name': second.fullName,
      'room_number': '306',
      'active': 1,
      'valid_until': DateTime.now()
          .add(const Duration(days: 1))
          .toUtc()
          .toIso8601String(),
    });
    await db.update(
      'guest_services_menu',
      {'portions': 1},
      where: 'id = ?',
      whereArgs: ['coffee'],
    );
    await store.saveCart([const CartLine('coffee', 1, '')]);
    await other.saveCart([const CartLine('coffee', 1, '')]);
    Future<int?> checkout(GuestServiceStore target) async {
      try {
        return await target.submit();
      } on StateError {
        return null;
      }
    }

    final results = await Future.wait([checkout(store), checkout(other)]);
    expect(results.whereType<int>(), hasLength(1));
    expect(
      (await store.menu()).singleWhere((e) => e.id == 'coffee').available,
      isFalse,
    );
    final loser = results[0] == null ? store : other;
    expect(await loser.loadCart(), hasLength(1));
    await (results[0] == null ? other : store).cancel(
      results.whereType<int>().single,
    );
    expect(
      (await store.menu()).singleWhere((e) => e.id == 'coffee').portions,
      1,
    );
  });

  test(
    'stock changes are kitchen-only and stale counts cannot undo a reservation',
    () async {
      await expectLater(store.kitchenStock(), throwsStateError);
      await expectLater(
        store.updateStock('coffee', version: 1, portions: 1, enabled: true),
        throwsStateError,
      );
      session.signIn(kitchen);
      final coffee = (await store.kitchenStock()).singleWhere(
        (row) => row['id'] == 'coffee',
      );
      await expectLater(store.receptionOrders(), throwsStateError);
      session.signIn(first);
      await store.saveCart([const CartLine('coffee', 1, '')]);
      final id = await store.submit();
      session.signIn(kitchen);
      await expectLater(
        store.updateStock(
          'coffee',
          version: coffee['version'] as int,
          portions: 30,
          enabled: true,
        ),
        throwsStateError,
      );
      session.signIn(
        const AppUser(
          id: 'reception',
          fullName: 'Accueil',
          role: AppRole.receptionist,
        ),
      );
      await store.transition(id, 'placed', 'preparing', agentId: 'sarah');
      await store.transition(
        id,
        'preparing',
        'cancelled',
        reason: 'Incident en cuisine',
      );
      expect(
        (await store.menu()).singleWhere((e) => e.id == 'coffee').portions,
        19,
      );
    },
  );

  test(
    'checkout aggregates matching dishes and rolls back partial reservations',
    () async {
      final db = session.database.database;
      await db.update(
        'guest_services_menu',
        {'portions': 1},
        where: 'id = ?',
        whereArgs: ['coffee'],
      );
      await store.saveCart([
        const CartLine('burger', 1, ''),
        const CartLine('coffee', 1, 'Sans sucre'),
        const CartLine('coffee', 1, 'Avec sucre'),
      ]);
      await expectLater(store.submit(), throwsStateError);
      expect(await store.orders(), isEmpty);
      expect(
        (await store.menu()).singleWhere((e) => e.id == 'burger').portions,
        20,
      );
      expect(
        (await store.menu()).singleWhere((e) => e.id == 'coffee').portions,
        1,
      );
      expect(await store.loadCart(), hasLength(3));
    },
  );
}
