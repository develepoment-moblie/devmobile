import '../../shared/models/app_user.dart';
import 'package:sqflite/sqflite.dart';
import '../../shared/services/app_session.dart';
import 'restaurant_confirmation.dart';

const serviceKinds = <String, String>{
  'restaurant': 'Restaurant',
  'spa': 'Spa',
  'request': 'Demande spéciale',
  'complaint': 'Réclamation',
  'conversation': 'Message à la réception',
};
const serviceStatuses = <String, String>{
  'pending': 'En attente',
  'confirmed': 'Confirmée',
  'in_progress': 'En cours',
  'completed': 'Terminée',
  'cancelled': 'Annulée',
  'rejected': 'Refusée',
};

class ServiceDeskStore {
  final AppSession session;
  final DateTime Function() now;
  ServiceDeskStore(this.session, {DateTime Function()? clock})
    : now = clock ?? DateTime.now;
  String get actor {
    final user = session.user;
    if (user == null ||
        !{
          AppRole.guest,
          AppRole.receptionist,
          AppRole.manager,
          AppRole.admin,
        }.contains(user.role)) {
      throw StateError('Accès non autorisé.');
    }
    return user.id;
  }

  bool get isGuest => session.user?.role == AppRole.guest;
  void staff() {
    actor;
    if (isGuest) throw StateError('Accès réservé à la réception.');
  }

  void manager() {
    actor;
    if (!session.user!.hasAnyRole(AppRole.management)) {
      throw StateError('Accès réservé à la direction.');
    }
  }

  static Future<void> migrate(Transaction tx) async {
    await tx.execute(
      '''CREATE TABLE guest_services_slots (
      id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL CHECK(kind IN ('restaurant','spa')),
      name TEXT NOT NULL, starts_at TEXT NOT NULL, ends_at TEXT NOT NULL,
      capacity INTEGER NOT NULL CHECK(capacity > 0), price_cents INTEGER NOT NULL CHECK(price_cents >= 0),
      archived INTEGER NOT NULL DEFAULT 0, version INTEGER NOT NULL DEFAULT 1)''',
    );
    await tx.execute('''CREATE TABLE guest_services_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT, guest_id TEXT NOT NULL, guest_name TEXT NOT NULL,
      kind TEXT NOT NULL CHECK(kind IN ('restaurant','spa','request','complaint','conversation')), title TEXT NOT NULL, details TEXT NOT NULL,
      slot_id INTEGER REFERENCES guest_services_slots(id), slot_name TEXT, starts_at TEXT, ends_at TEXT, units INTEGER NOT NULL DEFAULT 1,
      status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','confirmed','in_progress','completed','cancelled','rejected')), reason TEXT, assigned_to TEXT,
      due_at TEXT, price_cents INTEGER NOT NULL DEFAULT 0,
      version INTEGER NOT NULL DEFAULT 1, archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''');
    await tx.execute(
      'CREATE INDEX guest_services_records_owner ON guest_services_records(guest_id, archived, id)',
    );
    await tx.execute(
      'CREATE INDEX guest_services_records_slot ON guest_services_records(slot_id, status)',
    );
    await tx.execute('''CREATE TABLE guest_services_messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT, record_id INTEGER NOT NULL REFERENCES guest_services_records(id),
      author_id TEXT NOT NULL, author_name TEXT NOT NULL, body TEXT NOT NULL,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0,
      version INTEGER NOT NULL DEFAULT 1)''');
    await tx.execute(
      '''CREATE TABLE guest_services_reviews (
      id INTEGER PRIMARY KEY AUTOINCREMENT, record_id INTEGER NOT NULL UNIQUE REFERENCES guest_services_records(id),
      guest_id TEXT NOT NULL, rating INTEGER NOT NULL CHECK(rating BETWEEN 1 AND 5),
      body TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1)''',
    );
    await tx.execute(
      '''CREATE TABLE guest_services_audit (
      id INTEGER PRIMARY KEY AUTOINCREMENT, entity TEXT NOT NULL, entity_id INTEGER NOT NULL,
      actor_id TEXT NOT NULL, action TEXT NOT NULL, created_at TEXT NOT NULL)''',
    );
  }

  static Future<void> migrateRestaurantFloor(Transaction tx) async {
    await tx.execute(
      'ALTER TABLE guest_services_records ADD COLUMN arrived_at TEXT',
    );
    await tx.execute('''CREATE TABLE guest_services_dining_tables (
      id INTEGER PRIMARY KEY, name TEXT NOT NULL COLLATE NOCASE UNIQUE,
      seats INTEGER NOT NULL CHECK(seats BETWEEN 1 AND 20))''');
    await tx.execute('''CREATE TABLE guest_services_seatings (
      id INTEGER PRIMARY KEY, table_id INTEGER NOT NULL REFERENCES guest_services_dining_tables(id),
      record_id INTEGER NOT NULL REFERENCES guest_services_records(id),
      seated_at TEXT NOT NULL, released_at TEXT)''');
    await tx.execute(
      'CREATE UNIQUE INDEX guest_services_live_table ON guest_services_seatings(table_id) WHERE released_at IS NULL',
    );
    await tx.execute(
      'CREATE UNIQUE INDEX guest_services_live_party ON guest_services_seatings(record_id) WHERE released_at IS NULL',
    );
  }

  static Future<void> migrateDiningReservations(Transaction tx) async {
    await tx.execute(
      'ALTER TABLE guest_services_dining_tables ADD COLUMN position INTEGER',
    );
    await tx.execute(
      'UPDATE guest_services_dining_tables SET position = id - 1',
    );
    await tx.execute(
      'CREATE UNIQUE INDEX guest_services_table_position ON guest_services_dining_tables(position)',
    );
    await tx.execute(
      'ALTER TABLE guest_services_records ADD COLUMN dining_table_id INTEGER REFERENCES guest_services_dining_tables(id)',
    );
    await tx.execute(
      'CREATE INDEX guest_services_booked_table ON guest_services_records(dining_table_id, starts_at, ends_at)',
    );
  }

  static Future<void> migrateFixedDiningRoom(Transaction tx) async {
    await tx.execute(
      'ALTER TABLE guest_services_dining_tables ADD COLUMN shape TEXT',
    );
    await tx.execute('UPDATE guest_services_dining_tables SET position = -id');
    const layout = [
      (2, 'square'),
      (4, 'circle'),
      (2, 'square'),
      (6, 'rectangle'),
      (4, 'square'),
      (8, 'rectangle'),
      (4, 'circle'),
      (6, 'circle'),
      (2, 'circle'),
    ];
    final existingNames = {
      for (final row in await tx.query(
        'guest_services_dining_tables',
        columns: ['name'],
      ))
        (row['name'] as String).toLowerCase(),
    };
    for (final (position, (seats, shape)) in layout.indexed) {
      var name = '${101 + position}';
      while (existingNames.contains(name.toLowerCase())) {
        name = '$name · plan fixe';
      }
      await tx.insert('guest_services_dining_tables', {
        'name': name,
        'seats': seats,
        'shape': shape,
        'position': position,
      });
    }
  }

  Future<List<AppUser>> restaurantGuests() {
    manager();
    return session.staff.users(roles: {AppRole.guest});
  }

  Future<List<Map<String, Object?>>> restaurantTableChoices(
    int slotId, {
    int? recordId,
  }) async {
    actor;
    final slots = await session.database.database.query(
      'guest_services_slots',
      where: "id = ? AND kind = 'restaurant' AND archived = 0",
      whereArgs: [slotId],
    );
    if (slots.isEmpty) return [];
    final slot = slots.single;
    return restaurantTableChoicesAt(
      DateTime.parse(slot['starts_at'] as String),
      end: DateTime.parse(slot['ends_at'] as String),
      recordId: recordId,
    );
  }

  static const restaurantDuration = Duration(hours: 2);

  Future<List<Map<String, Object?>>> restaurantTableChoicesAt(
    DateTime start, {
    DateTime? end,
    int? recordId,
  }) async {
    actor;
    if (recordId != null) {
      await accessible(session.database.database, recordId);
    }
    return session.database.database.rawQuery(
      '''
      SELECT t.id, CAST(101 + t.position AS TEXT) AS name, t.seats, t.position, t.shape,
        EXISTS(SELECT 1 FROM guest_services_records r
          WHERE r.dining_table_id = t.id AND r.id != ?
            AND r.status IN ('pending','confirmed','in_progress')
            AND r.starts_at < ? AND r.ends_at > ?) AS reserved
      FROM guest_services_dining_tables t
      WHERE t.shape IS NOT NULL
      ORDER BY t.position''',
      [
        recordId ?? -1,
        (end ?? start.add(restaurantDuration)).toUtc().toIso8601String(),
        start.toUtc().toIso8601String(),
      ],
    );
  }

  Future<void> checkDiningReservation(
    Transaction tx,
    int tableId,
    int units,
    Object? start,
    Object? end,
    Object? except,
  ) async {
    final tables = await tx.rawQuery(
      '''
      SELECT t.id FROM guest_services_dining_tables t
      WHERE t.id = ? AND t.seats >= ? AND NOT EXISTS (
        SELECT 1 FROM guest_services_records r
        WHERE r.dining_table_id = t.id AND r.id != ?
          AND r.status IN ('pending','confirmed','in_progress')
          AND r.starts_at < ? AND r.ends_at > ?
      )''',
      [tableId, units, except ?? -1, end, start],
    );
    if (tables.isEmpty) {
      throw StateError('Cette table ne convient plus ou est déjà réservée.');
    }
  }

  Future<List<Map<String, Object?>>> diningTables() async {
    staff();
    return session.database.database.rawQuery(
      '''
      SELECT t.id, CASE WHEN t.shape IS NULL THEN t.name ELSE CAST(101 + t.position AS TEXT) END AS name,
        t.seats, t.position, t.shape, s.record_id, r.guest_name, r.units, s.seated_at,
        EXISTS(SELECT 1 FROM guest_services_records b WHERE b.dining_table_id = t.id
          AND b.status IN ('pending','confirmed','in_progress')
          AND b.starts_at <= ? AND b.ends_at > ?) AS reserved
      FROM guest_services_dining_tables t
      LEFT JOIN guest_services_seatings s ON s.table_id = t.id AND s.released_at IS NULL
      LEFT JOIN guest_services_records r ON r.id = s.record_id
      WHERE t.shape IS NOT NULL OR s.record_id IS NOT NULL
      ORDER BY t.seats, t.position''',
      [timestamp(), timestamp()],
    );
  }

  Future<List<Map<String, Object?>>> restaurantArrivals() async {
    staff();
    final today = now().toLocal();
    final start = DateTime(
      today.year,
      today.month,
      today.day,
    ).toUtc().toIso8601String();
    final end = DateTime(
      today.year,
      today.month,
      today.day + 1,
    ).toUtc().toIso8601String();
    return session.database.database.rawQuery(
      '''
      SELECT r.*, CASE WHEN t.shape IS NULL THEN t.name ELSE CAST(101 + t.position AS TEXT) END AS dining_table_name
      FROM guest_services_records r
      LEFT JOIN guest_services_dining_tables t ON t.id = r.dining_table_id
      WHERE r.kind = 'restaurant' AND r.archived = 0 AND r.status = 'confirmed'
        AND (r.arrived_at IS NOT NULL OR (r.starts_at >= ? AND r.starts_at < ?))
      ORDER BY r.arrived_at IS NULL, r.arrived_at, r.starts_at, r.id''',
      [start, end],
    );
  }

  Future<void> registerRestaurantArrival(int id) async {
    staff();
    await session.database.database.transaction((tx) async {
      final stamp = timestamp();
      final changed = await tx.rawUpdate(
        '''
        UPDATE guest_services_records SET arrived_at = ?, updated_at = ?, version = version + 1
        WHERE id = ? AND kind = 'restaurant' AND status = 'confirmed'
          AND archived = 0 AND arrived_at IS NULL''',
        [stamp, stamp, id],
      );
      if (changed != 1) {
        throw StateError(
          'Cette arrivée a déjà été traitée ou n’est pas confirmée.',
        );
      }
      await audit(tx, 'record', id, 'restaurant:arrived');
    });
  }

  Future<void> seatRestaurantParty(int id, int tableId) async {
    staff();
    try {
      await session.database.database.transaction((tx) async {
        final party = await accessible(tx, id);
        await checkDiningReservation(
          tx,
          tableId,
          party['units'] as int,
          party['starts_at'],
          party['ends_at'],
          id,
        );
        final rows = await tx.query(
          'guest_services_dining_tables',
          where: 'id = ?',
          whereArgs: [tableId],
        );
        if (rows.isEmpty) throw StateError('Table introuvable.');
        final stamp = timestamp();
        final changed = await tx.rawUpdate(
          '''
          UPDATE guest_services_records SET status = 'in_progress', dining_table_id = ?, updated_at = ?, version = version + 1
          WHERE id = ? AND kind = 'restaurant' AND status = 'confirmed' AND archived = 0
            AND arrived_at IS NOT NULL AND units <= ?''',
          [tableId, stamp, id, rows.single['seats']],
        );
        if (changed != 1) {
          throw StateError('Ce groupe ne peut pas être placé à cette table.');
        }
        await tx.insert('guest_services_seatings', {
          'record_id': id,
          'table_id': tableId,
          'seated_at': stamp,
        });
        await audit(
          tx,
          'record',
          id,
          'restaurant:seated:${rows.single['name']}',
        );
      });
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw StateError(
          'Cette table est déjà occupée. Choisissez une autre table.',
        );
      }
      rethrow;
    }
  }

  Future<void> finishRestaurantService(int recordId) async {
    staff();
    final record = await accessible(session.database.database, recordId);
    if (record['kind'] != 'restaurant') {
      throw StateError('Réservation de restaurant introuvable.');
    }
    await status(record, 'completed');
  }

  String timestamp() => now().toUtc().toIso8601String();
  Future<void> audit(
    Transaction tx,
    String entity,
    int id,
    String action,
  ) async {
    await tx.insert('guest_services_audit', {
      'entity': entity,
      'entity_id': id,
      'actor_id': actor,
      'action': action,
      'created_at': timestamp(),
    });
  }

  void text(String value, int max, String label, {bool required = true}) {
    if ((required && value.trim().isEmpty) || value.length > max) {
      throw StateError('$label invalide.');
    }
  }

  Future<List<Map<String, Object?>>> slots({
    String? kind,
    bool archived = false,
  }) async {
    actor;
    if (archived) manager();
    return session.database.database.rawQuery(
      '''SELECT s.*, COALESCE((SELECT SUM(r.units)
      FROM guest_services_records r WHERE r.slot_id = s.id AND r.status IN ('pending','confirmed','in_progress')),0) AS reserved
      FROM guest_services_slots s WHERE s.archived = ? ${kind == null ? '' : 'AND s.kind = ?'} ORDER BY s.starts_at''',
      [archived ? 1 : 0, ?kind],
    );
  }

  Future<void> saveSlot({
    Map<String, Object?>? previous,
    required String kind,
    required String name,
    required DateTime start,
    required DateTime end,
    required int capacity,
    required int priceCents,
  }) async {
    manager();
    text(name, 100, 'Nom');
    if (!{'restaurant', 'spa'}.contains(kind) ||
        !start.isAfter(now()) ||
        !end.isAfter(start) ||
        end.difference(start) > const Duration(hours: 24) ||
        capacity < 1 ||
        capacity > 500 ||
        priceCents < 0 ||
        priceCents > 1000000) {
      throw StateError('Vérifiez les horaires, la capacité et le tarif.');
    }
    await session.database.database.transaction((tx) async {
      final conflicts = await tx.rawQuery(
        """SELECT id FROM guest_services_slots WHERE archived = 0
        AND kind = ? AND LOWER(TRIM(name)) = LOWER(TRIM(?)) AND starts_at < ? AND ends_at > ? AND id != ?""",
        [
          kind,
          name,
          end.toUtc().toIso8601String(),
          start.toUtc().toIso8601String(),
          previous?['id'] ?? -1,
        ],
      );
      if (conflicts.isNotEmpty) {
        throw StateError(
          'Cette ressource possède déjà un créneau sur cette période.',
        );
      }
      if (previous != null) {
        final used = await tx.rawQuery(
          "SELECT COUNT(*) AS n FROM guest_services_records WHERE slot_id = ? AND status IN ('pending','confirmed','in_progress')",
          [previous['id']],
        );
        if ((used.single['n'] as int) > 0) {
          throw StateError(
            'Ce créneau a des réservations actives. Annulez-les avant de le modifier.',
          );
        }
      }
      final data = {
        'kind': kind,
        'name': name.trim(),
        'starts_at': start.toUtc().toIso8601String(),
        'ends_at': end.toUtc().toIso8601String(),
        'capacity': capacity,
        'price_cents': priceCents,
      };
      int id;
      if (previous == null) {
        id = await tx.insert('guest_services_slots', data);
      } else {
        id = previous['id'] as int;
        final n = await tx.update(
          'guest_services_slots',
          {...data, 'version': (previous['version'] as int) + 1},
          where: 'id = ? AND version = ? AND archived = 0',
          whereArgs: [id, previous['version']],
        );
        if (n != 1) throw StateError('Le créneau a changé. Actualisez.');
      }
      await audit(tx, 'slot', id, previous == null ? 'created' : 'updated');
    });
  }

  Future<void> archiveSlot(Map<String, Object?> slot, bool archived) async {
    manager();
    await session.database.database.transaction((tx) async {
      if (archived) {
        final rows = await tx.rawQuery(
          "SELECT COUNT(*) AS n FROM guest_services_records WHERE slot_id = ? AND status IN ('pending','confirmed','in_progress')",
          [slot['id']],
        );
        if (rows.single['n'] != 0) {
          throw StateError('Des réservations actives utilisent ce créneau.');
        }
      }

      if (!archived) {
        final conflicts = await tx.rawQuery(
          """SELECT id FROM guest_services_slots WHERE archived = 0
          AND kind = ? AND LOWER(TRIM(name)) = LOWER(TRIM(?)) AND starts_at < ? AND ends_at > ? AND id != ?""",
          [
            slot['kind'],
            slot['name'],
            slot['ends_at'],
            slot['starts_at'],
            slot['id'],
          ],
        );
        if (conflicts.isNotEmpty) {
          throw StateError('Un autre créneau occupe cette ressource.');
        }
      }
      final n = await tx.update(
        'guest_services_slots',
        {'archived': archived ? 1 : 0, 'version': (slot['version'] as int) + 1},
        where: 'id = ? AND version = ?',
        whereArgs: [slot['id'], slot['version']],
      );
      if (n != 1) throw StateError('Le créneau a changé. Actualisez.');
      await audit(
        tx,
        'slot',
        slot['id'] as int,
        archived ? 'archived' : 'restored',
      );
    });
  }

  Future<Map<String, Object?>> accessible(DatabaseExecutor tx, int id) async {
    final uid = actor;
    final rows = await tx.query(
      'guest_services_records',
      where: 'id = ?${isGuest ? ' AND guest_id = ?' : ''}',
      whereArgs: [id, if (isGuest) uid],
    );
    if (rows.isEmpty) throw StateError('Dossier inaccessible.');
    return Map<String, Object?>.from(rows.single);
  }

  Future<List<Map<String, Object?>>> records({bool archived = false}) async {
    final uid = actor;
    return session.database.database.rawQuery(
      '''
      SELECT r.*, CASE WHEN t.shape IS NULL THEN t.name ELSE CAST(101 + t.position AS TEXT) END AS dining_table_name
      FROM guest_services_records r
      LEFT JOIN guest_services_dining_tables t ON t.id = r.dining_table_id
      WHERE r.archived = ?${isGuest ? ' AND r.guest_id = ?' : ''}
      ORDER BY r.id DESC''',
      [archived ? 1 : 0, if (isGuest) uid],
    );
  }

  Future<int> saveRecord({
    Map<String, Object?>? previous,
    required String kind,
    required String title,
    required String details,
    int? slotId,
    DateTime? restaurantStart,
    int? diningTableId,
    int units = 1,
    DateTime? dueAt,
    String? guestId,
    String? visitorName,
    String? confirmationEmail,
  }) async {
    final signedIn = actor;
    final staffBooking = !isGuest;
    AppUser guest = session.user!;
    if (staffBooking) {
      manager();
      if (kind != 'restaurant' ||
          previous != null ||
          (guestId == null) == (visitorName == null)) {
        throw StateError(
          'Choisissez un compte client ou saisissez le nom du visiteur.',
        );
      }
      if (visitorName != null) {
        text(visitorName, 100, 'Nom du visiteur');
      } else {
        guest = (await restaurantGuests()).firstWhere(
          (client) => client.id == guestId,
          orElse: () => throw StateError('Ce compte client est indisponible.'),
        );
      }
      if (session.user?.id != signedIn) {
        throw StateError('La session a changé.');
      }
    } else if (guestId != null || visitorName != null) {
      throw StateError('Réservation pour un tiers réservée à la direction.');
    }
    text(title, 100, 'Objet');
    if (kind != 'restaurant' || details.trim().isNotEmpty) {
      text(details, 2000, 'Description');
    }
    if (!serviceKinds.containsKey(kind) ||
        units < 1 ||
        units > 20 ||
        (dueAt != null && !dueAt.isAfter(now()))) {
      throw StateError('Informations de demande invalides.');
    }
    final email = confirmationEmail?.trim();
    if (email != null &&
        email.isNotEmpty &&
        (kind != 'restaurant' || !RestaurantConfirmation.validEmail(email))) {
      throw StateError('Saisissez une adresse e-mail valide.');
    }
    final recordId = await session.database.database.transaction((tx) async {
      final uid = visitorName == null
          ? guest.id
          : (await tx.rawQuery(
                  "SELECT 'visitor:' || lower(hex(randomblob(16))) AS id",
                )).single['id']
                as String;
      if (previous != null) {
        final old = await accessible(tx, previous['id'] as int);
        if (old['status'] != 'pending' ||
            old['archived'] == 1 ||
            old['version'] != previous['version'] ||
            old['kind'] != kind) {
          throw StateError(
            'Seule une demande en attente et à jour peut être modifiée.',
          );
        }
      }
      var price = 0;
      Map<String, Object?>? booking;
      if (kind == 'restaurant' && slotId == null) {
        if (restaurantStart == null || !restaurantStart.isAfter(now())) {
          throw StateError('Choisissez une date et une heure à venir.');
        }
        booking = {
          'name': 'Restaurant',
          'starts_at': restaurantStart.toUtc().toIso8601String(),
          'ends_at': restaurantStart
              .add(restaurantDuration)
              .toUtc()
              .toIso8601String(),
        };
      } else if ({'restaurant', 'spa'}.contains(kind)) {
        if (restaurantStart != null)
          throw StateError('Choisissez un seul horaire.');
        if (slotId == null) throw StateError('Choisissez un créneau.');
        final slots = await tx.query(
          'guest_services_slots',
          where: 'id = ? AND kind = ? AND archived = 0',
          whereArgs: [slotId, kind],
        );
        if (slots.isEmpty ||
            !DateTime.parse(
              slots.single['starts_at'] as String,
            ).isAfter(now())) {
          throw StateError('Ce créneau n’est plus disponible.');
        }
        final slot = slots.single;
        booking = slot;
        final reserved = await tx.rawQuery(
          "SELECT COALESCE(SUM(units),0) AS n FROM guest_services_records WHERE slot_id = ? AND status IN ('pending','confirmed','in_progress') AND id != ?",
          [slotId, previous?['id'] ?? -1],
        );
        if ((reserved.single['n'] as int) + units > (slot['capacity'] as int)) {
          throw StateError('Capacité insuffisante pour ce créneau.');
        }
        price = (slot['price_cents'] as int) * units;
      } else if (slotId != null || restaurantStart != null) {
        throw StateError('Ce service n’utilise pas de créneau.');
      }
      if (kind == 'restaurant') {
        if (diningTableId != null) {
          final fixed = await tx.query(
            'guest_services_dining_tables',
            columns: ['id'],
            where: 'id = ? AND shape IS NOT NULL',
            whereArgs: [diningTableId],
          );
          if (fixed.isEmpty) {
            throw StateError('Choisissez une table du plan actuel.');
          }
          await checkDiningReservation(
            tx,
            diningTableId,
            units,
            booking!['starts_at'],
            booking['ends_at'],
            previous?['id'],
          );
        } else {
          throw StateError('Choisissez une table sur le plan de salle.');
        }
      }
      if (booking != null) {
        // Prevent the same guest booking overlapping restaurant/spa appointments.
        final overlap = await tx.rawQuery(
          """SELECT r.id FROM guest_services_records r
          WHERE r.guest_id = ? AND r.id != ? AND r.status IN ('pending','confirmed','in_progress')
          AND r.starts_at < ? AND r.ends_at > ?""",
          [
            uid,
            previous?['id'] ?? -1,
            booking['ends_at'],
            booking['starts_at'],
          ],
        );
        if (overlap.isNotEmpty) {
          throw StateError('Vous avez déjà une réservation sur cette période.');
        }
      }
      final data = {
        'guest_id': uid,
        'guest_name': visitorName?.trim() ?? guest.fullName,
        'kind': kind,
        'title': title.trim(),
        'details': details.trim(),
        if (kind == 'restaurant')
          'confirmation_email': email == null || email.isEmpty ? null : email,
        'slot_id': slotId,
        'dining_table_id': kind == 'restaurant' ? diningTableId : null,
        'slot_name': booking?['name'],
        'starts_at': booking?['starts_at'],
        'ends_at': booking?['ends_at'],
        'units': units,
        'price_cents': price,
        'due_at': dueAt?.toUtc().toIso8601String(),
        'updated_at': timestamp(),
      };
      int id;
      if (previous == null) {
        id = await tx.insert('guest_services_records', {
          ...data,
          'created_at': timestamp(),
          if (staffBooking) 'status': 'confirmed',
        });
      } else {
        id = previous['id'] as int;
        final n = await tx.update(
          'guest_services_records',
          {...data, 'version': (previous['version'] as int) + 1},
          where: 'id = ? AND version = ? AND status = ?',
          whereArgs: [id, previous['version'], 'pending'],
        );
        if (n != 1) throw StateError('La demande a changé. Actualisez.');
      }
      await audit(tx, 'record', id, previous == null ? 'created' : 'updated');
      return id;
    });
    if (staffBooking && email != null && email.isNotEmpty) {
      await sendRestaurantConfirmation(recordId);
    }
    return recordId;
  }

  Future<void> status(
    Map<String, Object?> previous,
    String next, {
    String reason = '',
  }) async {
    actor;
    await session.database.database.transaction((tx) async {
      final row = await accessible(tx, previous['id'] as int);
      final current = row['status'] as String;
      if (next == 'confirmed' &&
          row['ends_at'] != null &&
          !DateTime.parse(row['ends_at'] as String).isAfter(now())) {
        throw StateError('Ce créneau est terminé. Annulez cette réservation.');
      }

      if (row['archived'] == 1 || row['version'] != previous['version']) {
        throw StateError('Dossier modifié. Actualisez.');
      }
      final allowed = isGuest
          ? current == 'pending' && next == 'cancelled'
          : ({
                  'pending': {'confirmed', 'rejected'},
                  'confirmed': {'in_progress', 'cancelled'},
                  'in_progress': {'completed', 'cancelled'},
                }[current]?.contains(next) ??
                false);
      if (!allowed) throw StateError('Changement de statut non autorisé.');
      if (row['kind'] == 'restaurant' && next == 'in_progress') {
        throw StateError('Placez le groupe depuis le plan de salle.');
      }
      if (next == 'rejected' || (!isGuest && next == 'cancelled')) {
        text(reason, 500, 'Motif');
      }
      await tx.update(
        'guest_services_records',
        {
          'status': next,
          'reason': reason.trim().isEmpty ? null : reason.trim(),
          'version': (row['version'] as int) + 1,
          'updated_at': timestamp(),
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      if (next == 'completed' || next == 'cancelled') {
        await tx.update(
          'guest_services_seatings',
          {'released_at': timestamp()},
          where: 'record_id = ? AND released_at IS NULL',
          whereArgs: [row['id']],
        );
      }
      await audit(
        tx,
        'record',
        row['id'] as int,
        'status:$next${reason.trim().isEmpty ? '' : ':${reason.trim()}'}',
      );
    });
    if (next == 'confirmed' && previous['kind'] == 'restaurant') {
      await sendRestaurantConfirmation(previous['id'] as int);
    }
  }

  static final _sendingConfirmations = <String>{};

  Future<void> sendRestaurantConfirmation(int id) async {
    if (!(session.user?.hasAnyRole({
          AppRole.receptionist,
          ...AppRole.management,
        }) ??
        false)) {
      throw StateError('Envoi réservé à la réception et à la direction.');
    }
    final db = session.database.database;
    final payload = await db.transaction((tx) async {
      final rows = await tx.rawQuery(
        '''
        SELECT r.*, CASE WHEN t.shape IS NULL THEN t.name
          ELSE CAST(101 + t.position AS TEXT) END AS table_name
        FROM guest_services_records r
        LEFT JOIN guest_services_dining_tables t ON t.id = r.dining_table_id
        WHERE r.id = ? AND r.kind = 'restaurant' AND r.status = 'confirmed'
          AND r.confirmation_email IS NOT NULL
          AND COALESCE(r.confirmation_email_status, '') != 'accepted'
      ''',
        [id],
      );
      if (rows.isEmpty) return null;
      final row = rows.single;
      final key =
          row['confirmation_email_key'] as String? ??
          (await tx.rawQuery("""
            SELECT lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) ||
              '-4' || substr(hex(randomblob(2)), 2) || '-8' ||
              substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6))) AS key
          """)).single['key']
              as String;
      await tx.update(
        'guest_services_records',
        {'confirmation_email_key': key},
        where: 'id = ?',
        whereArgs: [id],
      );
      return <String, Object?>{
        'idempotencyKey': key,
        'reference': 'REST-$id',
        'email': row['confirmation_email'],
        'guest': row['guest_name'],
        'startsAt': row['starts_at'],
        'seats': row['units'],
        'table': row['table_name'],
      };
    });
    if (payload == null) return;
    final key = payload['idempotencyKey'] as String;
    if (!_sendingConfirmations.add(key)) return;
    try {
      var status = 'accepted';
      try {
        await RestaurantConfirmation().send(payload);
      } catch (_) {
        status = 'failed';
      }
      await db.update(
        'guest_services_records',
        {'confirmation_email_status': status},
        where: 'id = ? AND confirmation_email_key = ?',
        whereArgs: [id, key],
      );
    } finally {
      _sendingConfirmations.remove(key);
    }
  }

  Future<void> assign(Map<String, Object?> previous, String? assignee) async {
    staff();
    if (assignee != null) {
      final users = await session.staff.users(
        roles: {
          AppRole.receptionist,
          AppRole.staff,
          AppRole.supervisor,
          AppRole.maintenance,
          AppRole.manager,
          AppRole.admin,
        },
      );
      if (!users.any((u) => u.id == assignee)) {
        throw StateError('Le responsable sélectionné n’est plus disponible.');
      }
    }
    await session.database.database.transaction((tx) async {
      final row = await accessible(tx, previous['id'] as int);
      if (row['version'] != previous['version'] ||
          row['archived'] == 1 ||
          !{'pending', 'confirmed', 'in_progress'}.contains(row['status'])) {
        throw StateError('Dossier modifié ou fermé. Actualisez.');
      }
      await tx.update(
        'guest_services_records',
        {
          'assigned_to': assignee,
          'version': (row['version'] as int) + 1,
          'updated_at': timestamp(),
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      await audit(
        tx,
        'record',
        row['id'] as int,
        'assigned:${assignee ?? "unassigned"}',
      );
    });
  }

  Future<void> archiveRecord(
    Map<String, Object?> previous,
    bool archived,
  ) async {
    staff();
    await session.database.database.transaction((tx) async {
      final row = await accessible(tx, previous['id'] as int);
      if (!{'completed', 'cancelled', 'rejected'}.contains(row['status']) ||
          row['version'] != previous['version']) {
        throw StateError(
          'Seuls les dossiers terminés et à jour peuvent être archivés.',
        );
      }
      await tx.update(
        'guest_services_records',
        {'archived': archived ? 1 : 0, 'version': (row['version'] as int) + 1},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      await audit(
        tx,
        'record',
        row['id'] as int,
        archived ? 'archived' : 'restored',
      );
    });
  }

  Future<List<Map<String, Object?>>> messages(int id) async {
    await accessible(session.database.database, id);
    return session.database.database.query(
      'guest_services_messages',
      where: 'record_id = ?',
      whereArgs: [id],
      orderBy: 'id',
    );
  }

  Future<void> saveMessage(
    int id,
    String body, {
    Map<String, Object?>? previous,
    bool delete = false,
  }) async {
    final uid = actor;
    if (!delete) text(body, 2000, 'Message');
    await session.database.database.transaction((tx) async {
      final row = await accessible(tx, id);
      if (row['archived'] == 1 ||
          {'completed', 'cancelled', 'rejected'}.contains(row['status'])) {
        throw StateError('Ce dossier est fermé.');
      }
      int messageId;
      if (previous == null) {
        if (delete) throw StateError('Message introuvable.');
        messageId = await tx.insert('guest_services_messages', {
          'record_id': id,
          'author_id': uid,
          'author_name': session.user!.fullName,
          'body': body.trim(),
          'created_at': timestamp(),
          'updated_at': timestamp(),
        });
      } else {
        messageId = previous['id'] as int;
        final n = await tx.update(
          'guest_services_messages',
          {
            'body': delete ? '' : body.trim(),
            'deleted': delete ? 1 : 0,
            'version': (previous['version'] as int) + 1,
            'updated_at': timestamp(),
          },
          where:
              'id = ? AND record_id = ? AND author_id = ? AND version = ? AND deleted = 0',
          whereArgs: [messageId, id, uid, previous['version']],
        );
        if (n != 1) throw StateError('Message modifié ou accès non autorisé.');
      }
      await audit(
        tx,
        'message',
        messageId,
        delete
            ? 'deleted'
            : previous == null
            ? 'created'
            : 'updated',
      );
    });
  }

  Future<Map<String, Object?>?> review(int id) async {
    await accessible(session.database.database, id);
    final rows = await session.database.database.query(
      'guest_services_reviews',
      where: 'record_id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<void> saveReview(
    int id,
    int rating,
    String body, {
    Map<String, Object?>? previous,
    bool delete = false,
  }) async {
    final uid = actor;
    if (!isGuest) throw StateError('Seul le client peut gérer son avis.');
    if (!delete) {
      text(body, 1000, 'Avis');
      if (rating < 1 || rating > 5) throw StateError('Note entre 1 et 5.');
    }
    await session.database.database.transaction((tx) async {
      final row = await accessible(tx, id);
      if (row['status'] != 'completed') {
        throw StateError('Le service doit être terminé pour laisser un avis.');
      }
      if (previous == null) {
        if (delete) throw StateError('Avis introuvable.');
        await tx.insert('guest_services_reviews', {
          'record_id': id,
          'guest_id': uid,
          'rating': rating,
          'body': body.trim(),
          'updated_at': timestamp(),
        });
      } else {
        final n = delete
            ? await tx.delete(
                'guest_services_reviews',
                where:
                    'id = ? AND record_id = ? AND guest_id = ? AND version = ?',
                whereArgs: [previous['id'], id, uid, previous['version']],
              )
            : await tx.update(
                'guest_services_reviews',
                {
                  'rating': rating,
                  'body': body.trim(),
                  'updated_at': timestamp(),
                  'version': (previous['version'] as int) + 1,
                },
                where:
                    'id = ? AND record_id = ? AND guest_id = ? AND version = ?',
                whereArgs: [previous['id'], id, uid, previous['version']],
              );
        if (n != 1) throw StateError('Avis modifié. Actualisez.');
      }
      await audit(tx, 'record', id, delete ? 'review_deleted' : 'review_saved');
    });
  }

  Future<List<Map<String, Object?>>> history(int id) async {
    staff();
    await accessible(session.database.database, id);
    return session.database.database.query(
      'guest_services_audit',
      where: 'entity = ? AND entity_id = ?',
      whereArgs: ['record', id],
      orderBy: 'id',
    );
  }
}
