import 'package:sqflite/sqflite.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'service_desk_store.dart';
import 'dart:convert';
import '../../shared/models/app_user.dart';
import '../../shared/services/app_session.dart';
import '../../shared/services/app_database.dart';
import '../models/room_service.dart';

class GuestServiceStore {
  final AppSession session;
  GuestServiceStore(this.session);
  String get guestId {
    final user = session.user;
    if (user == null || user.role != AppRole.guest) {
      throw StateError('Cet espace est réservé aux clients.');
    }
    return user.id;
  }

  static final schema = ModuleSchema(
    module: 'guest_services',
    version: 11,
    migrate: (tx, from, to) async {
      if (from < 1) {
        await tx.execute(
          'CREATE TABLE guest_services_drafts (guest_id TEXT PRIMARY KEY, lines TEXT NOT NULL)',
        );
        await tx.execute('''CREATE TABLE guest_services_orders (
          id INTEGER PRIMARY KEY AUTOINCREMENT, guest_id TEXT NOT NULL,
          created_at TEXT NOT NULL, lines TEXT NOT NULL, total_cents INTEGER NOT NULL,
          status TEXT NOT NULL DEFAULT 'placed')''');
        await tx.execute(
          'CREATE INDEX guest_services_orders_guest ON guest_services_orders(guest_id, id)',
        );
      }
      if (from < 2) {
        await tx.execute('''CREATE TABLE guest_services_demo_stays (
          id TEXT PRIMARY KEY, guest_id TEXT NOT NULL UNIQUE,
          guest_name TEXT NOT NULL, room_number TEXT NOT NULL,
          active INTEGER NOT NULL DEFAULT 1)''');
        await tx.insert('guest_services_demo_stays', {
          'id': 'demo-stay-305',
          'guest_id': 'guest',
          'guest_name': 'Client Démo',
          'room_number': '305',
          'active': 1,
        });
        for (final column in [
          'stay_id',
          'room_number',
          'guest_name',
          'reason',
        ]) {
          await tx.execute(
            'ALTER TABLE guest_services_orders ADD COLUMN $column TEXT',
          );
        }
        await tx.execute('''CREATE TABLE guest_services_order_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT, order_id INTEGER NOT NULL
          REFERENCES guest_services_orders(id), status TEXT NOT NULL,
          actor_id TEXT NOT NULL, created_at TEXT NOT NULL, reason TEXT)''');
      }
      if (from < 3) {
        await tx.execute('''CREATE TABLE guest_services_menu (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT NOT NULL,
          category TEXT NOT NULL, symbol TEXT NOT NULL, price_cents INTEGER NOT NULL CHECK(price_cents > 0),
          minutes INTEGER NOT NULL, allergens TEXT NOT NULL, vegetarian INTEGER NOT NULL,
          available INTEGER NOT NULL, archived INTEGER NOT NULL DEFAULT 0)''');
        for (final item in roomServiceMenu) {
          await tx.insert('guest_services_menu', item.toRow());
        }
      }
      if (from < 4) {
        await ServiceDeskStore.migrate(tx);
        await tx.execute(
          'ALTER TABLE guest_services_menu ADD COLUMN version INTEGER NOT NULL DEFAULT 1',
        );
        await tx.execute(
          'CREATE TABLE guest_services_categories (name TEXT PRIMARY KEY COLLATE NOCASE, archived INTEGER NOT NULL DEFAULT 0)',
        );
        await tx.execute(
          'INSERT INTO guest_services_categories(name) SELECT DISTINCT category FROM guest_services_menu',
        );
        await tx.execute(
          'ALTER TABLE guest_services_demo_stays RENAME TO guest_services_stays',
        );
        await tx.execute(
          'ALTER TABLE guest_services_stays ADD COLUMN valid_until TEXT',
        );
        await tx.execute(
          'ALTER TABLE guest_services_stays ADD COLUMN verified_by TEXT',
        );
        await tx.execute('UPDATE guest_services_stays SET active = 0');
        if (from == 0) {
          await tx.delete('guest_services_menu');
          await tx.delete('guest_services_categories');
          await tx.delete('guest_services_stays');
        }
      }
      if (from < 5 && to >= 5) {
        await tx.execute(
          'ALTER TABLE guest_services_menu ADD COLUMN portions INTEGER NOT NULL DEFAULT 0 CHECK(portions >= 0)',
        );
        await tx.execute('''CREATE TABLE guest_services_order_stock (
          order_id INTEGER NOT NULL REFERENCES guest_services_orders(id),
          item_id TEXT NOT NULL REFERENCES guest_services_menu(id),
          quantity INTEGER NOT NULL CHECK(quantity > 0),
          PRIMARY KEY(order_id, item_id))''');
      }
      if (from < 6 && to >= 6) {
        for (final column in [
          'delivery_agent_id',
          'delivery_agent_name',
          'delivered_by_name',
        ]) {
          await tx.execute(
            'ALTER TABLE guest_services_orders ADD COLUMN $column TEXT',
          );
        }
        await tx.execute(
          'CREATE INDEX guest_services_orders_delivery ON guest_services_orders(delivery_agent_id, status)',
        );
      }
      if (from < 7 && to >= 7) {
        await ServiceDeskStore.migrateRestaurantFloor(tx);
      }
      if (from < 8 && to >= 8) {
        await ServiceDeskStore.migrateDiningReservations(tx);
      }
      if (from < 9 && to >= 9) {
        await ServiceDeskStore.migrateFixedDiningRoom(tx);
      }
      if (from < 10 && to >= 10) {
        await tx.execute('''CREATE TABLE guest_services_exchange_rates (
          id INTEGER PRIMARY KEY CHECK(id = 1), rate REAL NOT NULL,
          rate_date TEXT NOT NULL, fetched_at TEXT NOT NULL)''');
        await tx.execute(
          'ALTER TABLE guest_services_records ADD COLUMN confirmation_email TEXT',
        );
        await tx.execute(
          'ALTER TABLE guest_services_records ADD COLUMN confirmation_email_key TEXT',
        );
        await tx.execute(
          'ALTER TABLE guest_services_records ADD COLUMN confirmation_email_status TEXT',
        );
      }
      if (from < 11 && to >= 11) {
        await tx.execute('''CREATE TABLE guest_services_currency_rates (
          currency TEXT PRIMARY KEY, rate REAL NOT NULL,
          rate_date TEXT NOT NULL, fetched_at TEXT NOT NULL)''');
        await tx.execute(
          '''INSERT INTO guest_services_currency_rates
          SELECT 'TND', rate, rate_date, fetched_at FROM guest_services_exchange_rates''',
        );
        await tx.execute('DROP TABLE guest_services_exchange_rates');
      }
    },
  );

  Future<List<CartLine>> loadCart() async {
    final rows = await session.database.database.query(
      'guest_services_drafts',
      where: 'guest_id = ?',
      whereArgs: [guestId],
    );
    if (rows.isEmpty) return [];
    final saved = (jsonDecode(rows.single['lines'] as String) as List)
        .map(
          (line) => CartLine.fromJson(Map<String, dynamic>.from(line as Map)),
        )
        .toList();
    final refreshed = <CartLine>[];
    for (final line in saved) {
      final rows = await session.database.database.query(
        'guest_services_menu',
        where: 'id = ?',
        whereArgs: [line.itemId],
      );
      refreshed.add(
        CartLine(
          line.itemId,
          line.quantity,
          line.note,
          rows.isEmpty ? line.item : MenuItem.fromRow(rows.single),
        ),
      );
    }
    await saveCart(refreshed);
    return refreshed;
  }

  Future<void> saveCart(List<CartLine> lines) async {
    final id = guestId;
    await session.database.database.transaction((tx) async {
      await tx.delete(
        'guest_services_drafts',
        where: 'guest_id = ?',
        whereArgs: [id],
      );
      await tx.insert('guest_services_drafts', {
        'guest_id': id,
        'lines': jsonEncode(lines.map((line) => line.toJson()).toList()),
      });
    });
  }

  Future<List<Map<String, Object?>>> orders() =>
      session.database.database.query(
        'guest_services_orders',
        where: 'guest_id = ?',
        whereArgs: [guestId],
        orderBy: 'id DESC',
      );

  // Draft consumption and order insertion are atomic, including repeated submits.
  Future<int> submit() async {
    final id = guestId;
    return session.database.database.transaction((tx) async {
      final stays = await tx.query(
        'guest_services_stays',
        where: 'guest_id = ? AND active = 1 AND valid_until > ?',
        whereArgs: [id, DateTime.now().toUtc().toIso8601String()],
      );
      if (stays.length != 1) {
        throw StateError('Aucun séjour actif associé à ce client.');
      }
      final stay = stays.single;
      final rows = await tx.query(
        'guest_services_drafts',
        where: 'guest_id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) throw StateError('Votre panier est vide.');
      final lines = (jsonDecode(rows.single['lines'] as String) as List)
          .map(
            (line) => CartLine.fromJson(Map<String, dynamic>.from(line as Map)),
          )
          .toList();
      if (lines.isEmpty ||
          lines.any(
            (line) =>
                !line.item.available || line.quantity < 1 || line.quantity > 20,
          )) {
        throw StateError('Veuillez vérifier votre panier.');
      }
      final portionsByItem = <String, int>{};
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final current = await tx.query(
          'guest_services_menu',
          where: 'id = ?',
          whereArgs: [line.itemId],
        );
        if (current.isEmpty ||
            current.single['archived'] == 1 ||
            current.single['available'] != 1 ||
            current.single['price_cents'] != line.item.priceCents) {
          throw StateError(
            'La carte a changé. Actualisez puis vérifiez votre panier.',
          );
        }
        portionsByItem.update(
          line.itemId,
          (n) => n + line.quantity,
          ifAbsent: () => line.quantity,
        );
        lines[i] = CartLine(
          line.itemId,
          line.quantity,
          line.note,
          MenuItem.fromRow(current.single),
        );
      }

      for (final entry in portionsByItem.entries) {
        final changed = await tx.rawUpdate(
          'UPDATE guest_services_menu SET portions = portions - ?, version = version + 1 WHERE id = ? AND archived = 0 AND available = 1 AND portions >= ?',
          [entry.value, entry.key, entry.value],
        );
        if (changed != 1) {
          final item = lines
              .firstWhere((line) => line.itemId == entry.key)
              .item;
          throw StateError(
            'Stock insuffisant : ${item.name}. Actualisez votre panier.',
          );
        }
      }
      final orderId = await tx.insert('guest_services_orders', {
        'guest_id': id,
        'stay_id': stay['id'],
        'room_number': stay['room_number'],
        'guest_name': stay['guest_name'],
        'created_at': DateTime.now().toIso8601String(),
        'lines': jsonEncode(
          lines
              .map(
                (line) => {
                  ...line.toJson(),
                  'name': line.item.name,
                  'priceCents': line.item.priceCents,
                  'minutes': line.item.minutes,
                },
              )
              .toList(),
        ),
        'total_cents': lines.fold<int>(0, (sum, line) => sum + line.total),
        'status': 'placed',
      });

      for (final entry in portionsByItem.entries) {
        await tx.insert('guest_services_order_stock', {
          'order_id': orderId,
          'item_id': entry.key,
          'quantity': entry.value,
        });
      }
      await tx.insert('guest_services_order_history', {
        'order_id': orderId,
        'status': 'placed',
        'actor_id': id,
        'created_at': DateTime.now().toIso8601String(),
      });
      await tx.delete(
        'guest_services_drafts',
        where: 'guest_id = ?',
        whereArgs: [id],
      );
      return orderId;
    });
  }

  Future<void> cancel(int orderId) async {
    final id = guestId;
    await session.database.database.transaction((tx) async {
      final changed = await tx.update(
        'guest_services_orders',
        {'status': 'cancelled'},
        where: 'id = ? AND guest_id = ? AND status = ?',
        whereArgs: [orderId, id, 'placed'],
      );
      if (changed != 1) {
        throw StateError('Cette commande ne peut plus être annulée.');
      }
      await _releaseStock(tx, orderId);
      await tx.insert('guest_services_order_history', {
        'order_id': orderId,
        'status': 'cancelled',
        'actor_id': id,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  void requireStaff() {
    if (session.user == null ||
        !session.user!.hasAnyRole({
          AppRole.receptionist,
          AppRole.manager,
          AppRole.admin,
        })) {
      throw StateError('Accès réservé à la réception et à la direction.');
    }
  }

  Future<List<Map<String, Object?>>> receptionOrders() async {
    requireStaff();
    return session.database.database.rawQuery("""
      SELECT o.*, h.delivered_at FROM guest_services_orders o
      LEFT JOIN (SELECT order_id, MAX(created_at) AS delivered_at
        FROM guest_services_order_history WHERE status = 'delivered' GROUP BY order_id) h
      ON h.order_id = o.id ORDER BY o.id ASC
    """);
  }

  Future<List<Map<String, Object?>>> history(int orderId) async {
    final user = session.user;
    if (user?.role == AppRole.guest) {
      final owned = await session.database.database.query(
        'guest_services_orders',
        where: 'id = ? AND guest_id = ?',
        whereArgs: [orderId, guestId],
      );
      if (owned.isEmpty) throw StateError('Commande inaccessible.');
    } else {
      requireStaff();
    }
    return session.database.database.query(
      'guest_services_order_history',
      where: 'order_id = ?',
      whereArgs: [orderId],
      orderBy: 'id ASC',
    );
  }

  static const deliveryStatuses = {
    'accepted',
    'preparing',
    'ready',
    'out_for_delivery',
  };
  // Orders already marked in transit by an older build can still be delivered.
  static const readyDeliveryStatuses = {'ready', 'out_for_delivery'};

  Future<List<Map<String, Object?>>> kitchenOrders() async {
    _requireKitchen();
    return session.database.database.rawQuery("""
      SELECT o.id, o.room_number, o.lines, o.status, o.created_at,
        (SELECT MAX(h.created_at) FROM guest_services_order_history h
         WHERE h.order_id = o.id AND h.status = 'kitchen_started') AS started_at
      FROM guest_services_orders o
      WHERE o.stay_id IS NOT NULL AND o.status IN ('accepted', 'preparing', 'ready')
      ORDER BY o.id ASC
    """);
  }

  Future<void> startPreparation(int orderId) async {
    _requireKitchen();
    final actor = session.user!.id;
    await session.database.database.transaction((tx) async {
      // One recorded preparation lane. A completed or cancelled order releases it.
      final inserted = await tx.rawInsert(
        """
        INSERT INTO guest_services_order_history (order_id, status, actor_id, created_at)
        SELECT id, 'kitchen_started', ?, ? FROM guest_services_orders
        WHERE id = ? AND stay_id IS NOT NULL AND status IN ('accepted', 'preparing')
        AND NOT EXISTS (
          SELECT 1 FROM guest_services_orders o
          JOIN guest_services_order_history h ON h.order_id = o.id
          WHERE o.status IN ('accepted', 'preparing') AND h.status = 'kitchen_started'
        )
      """,
        [actor, DateTime.now().toUtc().toIso8601String(), orderId],
      );
      // SQLite retains its last insert ID even when INSERT ... SELECT inserts nothing.
      final changed = (await tx.rawQuery(
        'SELECT changes() AS count',
      )).single['count'];
      if (changed != 1 || inserted <= 0) {
        throw StateError(
          'Une préparation est déjà en cours ou la commande a changé.',
        );
      }
    });
  }

  Future<void> markOrderReady(int orderId) async {
    _requireKitchen();
    final actor = session.user!.id;
    await session.database.database.transaction((tx) async {
      final changed = await tx.update(
        'guest_services_orders',
        {'status': 'ready'},
        where:
            "id = ? AND stay_id IS NOT NULL AND status IN ('accepted', 'preparing')",
        whereArgs: [orderId],
      );
      if (changed != 1) {
        throw StateError('Cette commande n’est plus en préparation.');
      }
      await tx.insert('guest_services_order_history', {
        'order_id': orderId,
        'status': 'ready',
        'actor_id': actor,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  Future<List<AppUser>> deliveryAgents() async {
    requireStaff();
    final people = await session.staff.users(roles: {AppRole.staff});
    return people.where((person) => person.role == AppRole.staff).toList();
  }

  Future<List<({AppUser agent, int activeDeliveries})>> deliverySuggestions(
    int orderId,
  ) async {
    final agents = await deliveryAgents();
    final statuses = deliveryStatuses.toList();
    final rows = await session.database.database.rawQuery(
      '''
      SELECT delivery_agent_id, COUNT(*) AS total
      FROM guest_services_orders
      WHERE id != ? AND delivery_agent_id IS NOT NULL
        AND status IN (${List.filled(statuses.length, '?').join(',')})
      GROUP BY delivery_agent_id
    ''',
      [orderId, ...statuses],
    );
    final counts = {
      for (final row in rows)
        row['delivery_agent_id'] as String: row['total'] as int,
    };
    return [
      for (final agent in agents)
        (agent: agent, activeDeliveries: counts[agent.id] ?? 0),
    ]..sort((a, b) {
      final load = a.activeDeliveries.compareTo(b.activeDeliveries);
      if (load != 0) return load;
      final name = a.agent.fullName.toLowerCase().compareTo(
        b.agent.fullName.toLowerCase(),
      );
      return name != 0 ? name : a.agent.id.compareTo(b.agent.id);
    });
  }

  Future<AppUser> _deliveryAgent(String? id) async {
    final matches = (await deliveryAgents()).where((person) => person.id == id);
    if (matches.length != 1) {
      throw StateError('Choisissez un agent d’étage disponible.');
    }
    return matches.single;
  }

  Future<void> assignDelivery(
    int orderId,
    String status,
    String? previousAgentId,
    String agentId,
  ) async {
    requireStaff();
    final actor = session.user!.id;
    if (!deliveryStatuses.contains(status)) {
      throw StateError('Cette commande ne peut pas être attribuée.');
    }
    final agent = await _deliveryAgent(agentId);
    await session.database.database.transaction((tx) async {
      final changed = await tx.update(
        'guest_services_orders',
        {'delivery_agent_id': agent.id, 'delivery_agent_name': agent.fullName},
        where:
            'id = ? AND status = ? AND delivery_agent_id IS ? AND stay_id IS NOT NULL',
        whereArgs: [orderId, status, previousAgentId],
      );
      if (changed != 1) {
        throw StateError('La commande a changé. Actualisez la liste.');
      }
      await tx.insert('guest_services_order_history', {
        'order_id': orderId,
        'status': 'assigned',
        'actor_id': actor,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'reason': agent.fullName,
      });
    });
  }

  AppUser _requireDeliveryAgent() {
    final user = session.user;
    if (user == null || user.role != AppRole.staff) {
      throw StateError('Accès réservé aux agents d’étage.');
    }
    return user;
  }

  Future<List<Map<String, Object?>>> assignedDeliveries() async {
    final agent = _requireDeliveryAgent();
    return session.database.database.rawQuery(
      """
      SELECT o.id, o.room_number, o.lines, o.status, h.delivered_at
      FROM guest_services_orders o
      LEFT JOIN (SELECT order_id, MAX(created_at) AS delivered_at
        FROM guest_services_order_history WHERE status = 'delivered' GROUP BY order_id) h
      ON h.order_id = o.id
      WHERE o.delivery_agent_id = ? AND o.status IN ('accepted','preparing','ready','out_for_delivery','delivered')
      ORDER BY CASE WHEN o.status IN ('ready','out_for_delivery') THEN 0
        WHEN o.status = 'delivered' THEN 2 ELSE 1 END, o.id DESC
    """,
      [agent.id],
    );
  }

  Future<void> confirmDelivery(int orderId) async {
    final agent = _requireDeliveryAgent();
    await session.database.database.transaction((tx) async {
      final changed = await tx.update(
        'guest_services_orders',
        {'status': 'delivered', 'delivered_by_name': agent.fullName},
        where:
            "id = ? AND delivery_agent_id = ? AND status IN ('ready','out_for_delivery')",
        whereArgs: [orderId, agent.id],
      );
      if (changed != 1) {
        throw StateError(
          'Seule une commande prête qui vous est attribuée peut être livrée.',
        );
      }
      await tx.insert('guest_services_order_history', {
        'order_id': orderId,
        'status': 'delivered',
        'actor_id': agent.id,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  Future<void> transition(
    int orderId,
    String expected,
    String next, {
    String? reason,
    String? agentId,
  }) async {
    requireStaff();
    final actor = session.user!.id;
    final cancellation =
        next == 'cancelled' && nextOrderStatus.containsKey(expected);
    final accepting = expected == 'placed' && next == 'preparing';
    if (!cancellation && !accepting) {
      throw StateError('Transition non autorisée.');
    }
    final note = reason?.trim() ?? '';
    if (cancellation && (note.isEmpty || note.length > 250)) {
      throw StateError(
        'Indiquez un motif d’annulation (250 caractères maximum).',
      );
    }
    final agent = accepting ? await _deliveryAgent(agentId) : null;
    await session.database.database.transaction((tx) async {
      if (accepting) {
        final rows = await tx.query(
          'guest_services_orders',
          where: 'id = ?',
          whereArgs: [orderId],
        );
        if (rows.isEmpty || rows.single['stay_id'] == null) {
          throw StateError(
            'Cette ancienne commande n’a pas de séjour associé. Annulez-la et demandez une nouvelle commande.',
          );
        }
      }
      final changed = await tx.update(
        'guest_services_orders',
        {
          'status': next,
          'reason': cancellation ? note : null,
          if (agent != null) 'delivery_agent_id': agent.id,
          if (agent != null) 'delivery_agent_name': agent.fullName,
        },
        where: 'id = ? AND status = ?',
        whereArgs: [orderId, expected],
      );
      if (changed != 1) {
        throw StateError('La commande a changé. Actualisez la liste.');
      }
      if (cancellation && expected == 'placed') {
        await _releaseStock(tx, orderId);
      }
      await tx.insert('guest_services_order_history', {
        'order_id': orderId,
        'status': next,
        'actor_id': actor,
        'created_at': DateTime.now().toIso8601String(),
        'reason': cancellation ? note : agent?.fullName,
      });
    });
  }

  Future<void> _releaseStock(Transaction tx, int orderId) async {
    final reservations = await tx.query(
      'guest_services_order_stock',
      where: 'order_id = ?',
      whereArgs: [orderId],
    );
    for (final row in reservations) {
      await tx.rawUpdate(
        'UPDATE guest_services_menu SET portions = portions + ?, version = version + 1 WHERE id = ?',
        [row['quantity'], row['item_id']],
      );
    }
  }

  void _requireKitchen() {
    if (session.user?.role != AppRole.kitchen) {
      throw StateError('Accès réservé à la cuisine.');
    }
  }

  Future<List<Map<String, Object?>>> kitchenStock() async {
    _requireKitchen();
    return session.database.database.query(
      'guest_services_menu',
      columns: ['id', 'name', 'category', 'portions', 'available', 'version'],
      where: 'archived = 0',
      orderBy: 'category, name',
    );
  }

  Future<void> updateStock(
    String id, {
    required int version,
    required int portions,
    required bool enabled,
  }) async {
    _requireKitchen();
    if (portions < 0 || portions > 1000000) {
      throw StateError('Saisissez un nombre de portions entre 0 et 1 000 000.');
    }
    final changed = await session.database.database.update(
      'guest_services_menu',
      {
        'portions': portions,
        'available': enabled ? 1 : 0,
        'version': version + 1,
      },
      where: 'id = ? AND version = ? AND archived = 0',
      whereArgs: [id, version],
    );
    if (changed != 1) {
      throw StateError('Le stock a changé. Actualisez avant de réessayer.');
    }
  }

  void requireManager() {
    if (session.user == null ||
        !session.user!.hasAnyRole({AppRole.manager, AppRole.admin})) {
      throw StateError('Seule la direction peut modifier la carte.');
    }
  }

  Future<List<MenuItem>> menu({bool archived = false}) async {
    if (session.user == null) throw StateError('Connexion requise.');
    if (archived) requireManager();
    final rows = await session.database.database.query(
      'guest_services_menu',
      where: 'archived = ?',
      whereArgs: [archived ? 1 : 0],
      orderBy: 'category, name',
    );
    return rows.map(MenuItem.fromRow).toList();
  }

  Future<void> saveMenuItem(MenuItem item, {bool create = false}) async {
    requireManager();
    if (item.name.trim().isEmpty ||
        item.name.characters.length > 80 ||
        item.description.characters.length > 500 ||
        item.priceCents < 1 ||
        item.priceCents > 100000 ||
        item.minutes < 1 ||
        item.minutes > 180 ||
        item.allergens.trim().isEmpty ||
        item.allergens.characters.length > 250 ||
        item.symbol.characters.length > 16) {
      throw StateError('Vérifiez les informations du plat.');
    }
    await session.database.database.transaction((tx) async {
      final categoryRows = await tx.query(
        'guest_services_categories',
        where: 'name = ? AND archived = 0',
        whereArgs: [item.category],
      );
      if (categoryRows.isEmpty) {
        throw StateError('Choisissez une catégorie active.');
      }
      if (create) {
        await tx.insert('guest_services_menu', {
          ...item.toRow(),
          'available': 1,
        });
      } else {
        final count = await tx.update(
          'guest_services_menu',
          (item.toRow()..remove('available'))..['version'] = item.version + 1,
          where: 'id = ? AND archived = 0 AND version = ?',
          whereArgs: [item.id, item.version],
        );
        if (count != 1) {
          throw StateError('Article introuvable ou archivé. Actualisez.');
        }
      }
    });
  }

  Future<void> archiveMenuItem(String id, bool archived) async {
    requireManager();

    await session.database.database.transaction((tx) async {
      if (!archived) {
        final rows = await tx.rawQuery(
          'SELECT m.id FROM guest_services_menu m JOIN guest_services_categories c ON c.name = m.category WHERE m.id = ? AND c.archived = 0',
          [id],
        );
        if (rows.isEmpty) {
          throw StateError('Restaurez d’abord la catégorie de cet article.');
        }
      }
      final count = await tx.rawUpdate(
        'UPDATE guest_services_menu SET archived = ?, version = version + 1 WHERE id = ?',
        [archived ? 1 : 0, id],
      );
      if (count != 1) throw StateError('Article introuvable.');
    });
  }

  Future<List<Map<String, Object?>>> categories({bool archived = false}) async {
    if (session.user == null) throw StateError('Connexion requise.');
    if (archived) requireManager();
    return session.database.database.query(
      'guest_services_categories',
      where: 'archived = ?',
      whereArgs: [archived ? 1 : 0],
      orderBy: 'name',
    );
  }

  Future<void> saveCategory(String name, {String? previous}) async {
    requireManager();
    name = name.trim();
    if (name.isEmpty || name.length > 60) {
      throw StateError('Nom de catégorie obligatoire, 60 caractères maximum.');
    }
    await session.database.database.transaction((tx) async {
      if (previous == null) {
        await tx.insert('guest_services_categories', {'name': name});
      } else {
        final n = await tx.update(
          'guest_services_categories',
          {'name': name},
          where: 'name = ? AND archived = 0',
          whereArgs: [previous],
        );
        if (n != 1) {
          throw StateError('Catégorie modifiée ou archivée. Actualisez.');
        }
        await tx.rawUpdate(
          'UPDATE guest_services_menu SET category = ?, version = version + 1 WHERE category = ?',
          [name, previous],
        );
      }
    });
  }

  Future<void> archiveCategory(String name, bool archived) async {
    requireManager();
    await session.database.database.transaction((tx) async {
      if (archived) {
        final used = await tx.query(
          'guest_services_menu',
          where: 'category = ? AND archived = 0',
          whereArgs: [name],
          limit: 1,
        );
        if (used.isNotEmpty) {
          throw StateError(
            'Archivez ou déplacez les articles de cette catégorie avant de l’archiver.',
          );
        }
      }
      final n = await tx.update(
        'guest_services_categories',
        {'archived': archived ? 1 : 0},
        where: 'name = ?',
        whereArgs: [name],
      );
      if (n != 1) throw StateError('Catégorie introuvable.');
    });
  }

  Future<Map<String, Object?>?> currentStay() async {
    final id = guestId;
    final rows = await session.database.database.query(
      'guest_services_stays',
      where: 'guest_id = ? AND active = 1 AND valid_until > ?',
      whereArgs: [id, DateTime.now().toUtc().toIso8601String()],
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<List<Map<String, Object?>>> stays() async {
    requireStaff();
    return session.database.database.query(
      'guest_services_stays',
      orderBy: 'guest_name',
    );
  }

  Future<void> saveStay({
    required String guest,
    required String reference,
    required String room,
    required DateTime validUntil,
  }) async {
    requireStaff();
    if (reference.trim().isEmpty ||
        reference.length > 100 ||
        room.trim().isEmpty ||
        room.length > 20 ||
        !validUntil.isAfter(DateTime.now())) {
      throw StateError(
        'Vérifiez la référence du séjour, la chambre et la date de départ.',
      );
    }
    final users = await session.staff.users(roles: {AppRole.guest});
    final matches = users.where((u) => u.id == guest);
    if (matches.length != 1) {
      throw StateError('Client introuvable dans l’annuaire utilisateurs.');
    }
    final actor = session.user!.id;
    await session.database.database.transaction((tx) async {
      final other = await tx.query(
        'guest_services_stays',
        where: 'id = ? AND guest_id != ?',
        whereArgs: [reference.trim(), guest],
      );
      if (other.isNotEmpty) {
        throw StateError(
          'Cette référence est déjà associée à un autre client.',
        );
      }
      await tx.delete(
        'guest_services_stays',
        where: 'guest_id = ?',
        whereArgs: [guest],
      );
      await tx.insert('guest_services_stays', {
        'id': reference.trim(),
        'guest_id': guest,
        'guest_name': matches.single.fullName,
        'room_number': room.trim(),
        'active': 1,
        'valid_until': validUntil.toUtc().toIso8601String(),
        'verified_by': actor,
      });
    });
  }

  Future<void> deactivateStay(String guest) async {
    requireStaff();
    final count = await session.database.database.update(
      'guest_services_stays',
      {'active': 0, 'verified_by': session.user!.id},
      where: 'guest_id = ?',
      whereArgs: [guest],
    );
    if (count != 1) throw StateError('Association introuvable.');
  }
}
