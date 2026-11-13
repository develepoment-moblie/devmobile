import '../../shared/models/app_user.dart';
import '../../shared/services/app_session.dart';
import '../models/room_service.dart';
import 'guest_service_store.dart';
import 'service_desk_store.dart';

// Demo data for the presentation, made only through the module's own stores
// and rules, each step by the test account allowed to do it (Manager Démo,
// Inès Réception, Cuisine Démo, the floor agents, Client Démo). A separate
// session is used, so whoever is signed in on the phone is not touched.
//
// Client Démo stays in room 101 (reservation NP-248190, as in reservations
// and housekeeping): room-service orders at every step, restaurant and spa
// bookings past and to come, requests with messages, reviews. Visitors fill
// the restaurant floor. Build with --dart-define=NOVA_DEMO_DATA=true; filled
// once, only while the module has no menu, orders or requests.

/// Build option: demo data in every module.
const novaDemoData = bool.fromEnvironment('NOVA_DEMO_DATA');

/// The stay of the test account « Client Démo » (same id as in reservations).
const demoStayReference = 'NP-248190';
const demoStayRoom = '101';

/// Returns false when the module already had data (nothing is changed).
Future<bool> fillDemoGuestServices(AppSession app, {DateTime? now}) async {
  final db = app.database.database;
  Future<int> count(String table) async =>
      (await db.rawQuery('SELECT COUNT(*) AS n FROM $table')).single['n']
          as int;
  for (final table in [
    'guest_services_menu',
    'guest_services_orders',
    'guest_services_records',
    'guest_services_stays',
  ]) {
    if (await count(table) > 0) return false;
  }

  final start = now ?? DateTime.now();
  final today = DateTime(start.year, start.month, start.day);
  DateTime at(int day, int hour, [int minute = 0]) =>
      today.add(Duration(days: day, hours: hour, minutes: minute));

  final people = {for (final u in await app.staff.users()) u.id: u};
  AppUser person(String id, String name, String role) =>
      people[id] ?? AppUser(id: id, fullName: name, role: role);
  final manager = person('manager', 'Manager Démo', AppRole.manager);
  final reception = person('reception', 'Inès Réception', AppRole.receptionist);
  final kitchen = person('kitchen', 'Cuisine Démo', AppRole.kitchen);
  final guest = person('guest', 'Client Démo', AppRole.guest);
  final sarah = person('sarah', 'Sarah', AppRole.staff);
  final lina = person('lina', 'Lina', AppRole.staff);

  final session = AppSession(database: app.database, staff: app.staff);
  void as(AppUser user) => session.signIn(user);
  final orders = GuestServiceStore(session);
  var clock = start;
  final desk = ServiceDeskStore(session, clock: () => clock);

  try {
    // ------------------------------------------------ menu, stock, stay
    as(manager);
    for (final category in {
      for (final item in roomServiceMenu) item.category,
    }) {
      await orders.saveCategory(category);
    }
    for (final item in roomServiceMenu) {
      await orders.saveMenuItem(item, create: true);
    }
    as(kitchen);
    for (final row in await orders.kitchenStock()) {
      final id = row['id'] as String;
      await orders.updateStock(
        id,
        version: row['version'] as int,
        portions: switch (id) {
          'tart' => 0, // sold out today
          'pancakes' => 3,
          _ => 40,
        },
        enabled: true,
      );
    }
    as(reception);
    await orders.saveStay(
      guest: guest.id,
      reference: demoStayReference,
      room: demoStayRoom,
      validUntil: at(3, 11),
    );

    // ------------------------------------------------ room service
    Future<int> order(List<(String, int)> lines, [String note = '']) async {
      as(guest);
      await orders.saveCart([
        for (final (i, (item, quantity)) in lines.indexed)
          CartLine(item, quantity, i == 0 ? note : ''),
      ]);
      return orders.submit();
    }

    Future<void> accept(int id, AppUser agent) async {
      as(reception);
      await orders.transition(id, 'placed', 'preparing', agentId: agent.id);
    }

    Future<void> cook(int id) async {
      as(kitchen);
      await orders.startPreparation(id);
      await orders.markOrderReady(id);
    }

    Future<void> deliver(int id, AppUser agent) async {
      as(agent);
      await orders.confirmDelivery(id);
    }

    final breakfast = await order([
      ('breakfast', 2),
      ('juice', 2),
    ], 'Café très chaud, s’il vous plaît');
    await accept(breakfast, sarah);
    await cook(breakfast);
    await deliver(breakfast, sarah);

    final lunch = await order([('burger', 1), ('cake', 1)]);
    await accept(lunch, lina);
    await cook(lunch);
    await deliver(lunch, lina);

    final ready = await order([('salad', 1), ('coffee', 1)], 'Sans avocat');
    await accept(ready, person('youssef', 'Youssef', AppRole.staff));
    await cook(ready);

    final cooking = await order([('pasta', 2)]);
    await accept(cooking, sarah);
    as(kitchen);
    await orders.startPreparation(cooking);

    final queued = await order([('fruit', 1), ('coffee', 2)]);
    await accept(queued, lina);

    await order([('pancakes', 2), ('juice', 1)], 'Sirop à part');

    final changedMind = await order([('cake', 1)]);
    as(guest);
    await orders.cancel(changedMind);

    final late = await order([('burger', 2)]);
    as(reception);
    await orders.transition(
      late,
      'placed',
      'cancelled',
      reason: 'Le burger n’est plus servi après 23 h, nous vous avons appelé.',
    );

    // ------------------------------------------------ service desk
    Future<Map<String, Object?>> record(int id) async => Map.of(
      (await db.query(
        'guest_services_records',
        where: 'id = ?',
        whereArgs: [id],
      )).single,
    );
    Future<void> move(int id, String next, {String reason = ''}) async =>
        desk.status(await record(id), next, reason: reason);
    Future<void> say(AppUser who, int id, String body) async {
      as(who);
      await desk.saveMessage(id, body);
    }

    final tables = [
      for (final row in await db.query(
        'guest_services_dining_tables',
        where: 'shape IS NOT NULL',
        orderBy: 'position',
      ))
        row['id'] as int,
    ];

    // Two days ago, Client Démo booked yesterday's dinner and a facial.
    clock = at(-2, 10);
    as(manager);
    await desk.saveSlot(
      kind: 'spa',
      name: 'Soin du visage',
      start: at(-1, 15),
      end: at(-1, 16),
      capacity: 2,
      priceCents: 8500,
    );
    final pastSlot = (await desk.slots(kind: 'spa')).single['id'] as int;
    as(guest);
    final dinner = await desk.saveRecord(
      kind: 'restaurant',
      title: 'Dîner',
      details: 'Anniversaire de mariage',
      restaurantStart: at(-1, 20),
      diningTableId: tables[0],
      units: 2,
    );
    final facial = await desk.saveRecord(
      kind: 'spa',
      title: 'Soin du visage',
      details: 'Peau sensible',
      slotId: pastSlot,
    );
    as(reception);
    await move(dinner, 'confirmed');
    await move(facial, 'confirmed');
    clock = at(-1, 15);
    await move(facial, 'in_progress');
    clock = at(-1, 16);
    await move(facial, 'completed');
    clock = at(-1, 20, 5);
    await desk.registerRestaurantArrival(dinner);
    await desk.seatRestaurantParty(dinner, tables[0]);
    clock = at(-1, 22);
    await desk.finishRestaurantService(dinner);

    // An iron yesterday, a late check-out refused.
    clock = at(-1, 9);
    as(guest);
    final iron = await desk.saveRecord(
      kind: 'request',
      title: 'Fer et planche à repasser',
      details: 'Pour une chemise avant une réunion.',
    );
    final lateCheckout = await desk.saveRecord(
      kind: 'request',
      title: 'Départ tardif à 16 h',
      details: 'Notre train part en fin d’après-midi.',
    );
    as(reception);
    await move(iron, 'confirmed');
    await move(iron, 'in_progress');
    clock = at(-1, 9, 30);
    await move(iron, 'completed');
    await move(
      lateCheckout,
      'rejected',
      reason:
          'L’hôtel est complet ce jour-là. Départ possible jusqu’à 13 h, '
          'la bagagerie reste à votre disposition.',
    );

    as(guest);
    await desk.saveReview(
      dinner,
      5,
      'Une table parfaite et un service attentionné. Merci pour le dessert !',
    );
    await desk.saveReview(
      facial,
      4,
      'Très relaxant, la cabine était un peu froide.',
    );
    await desk.saveReview(iron, 5, 'Apporté en dix minutes.');

    // Today: lunch service in progress (visitors seated at table 104).
    clock = start.subtract(const Duration(minutes: 40));
    as(manager);
    final lunchParty = await desk.saveRecord(
      kind: 'restaurant',
      title: 'Déjeuner',
      details: 'Une chaise haute pour un enfant',
      restaurantStart: start.subtract(const Duration(minutes: 30)),
      diningTableId: tables[3],
      units: 4,
      visitorName: 'M. et Mme Lefèvre',
    );
    clock = start.subtract(const Duration(minutes: 25));
    as(reception);
    await desk.registerRestaurantArrival(lunchParty);
    await desk.seatRestaurantParty(lunchParty, tables[3]);

    // Coming up: spa slots, bookings to confirm.
    clock = start;
    as(manager);
    await desk.saveSlot(
      kind: 'spa',
      name: 'Massage relaxant · 60 min',
      start: at(1, 10),
      end: at(1, 11),
      capacity: 2,
      priceCents: 9500,
    );
    await desk.saveSlot(
      kind: 'spa',
      name: 'Hammam privatif',
      start: at(1, 16),
      end: at(1, 17, 30),
      capacity: 4,
      priceCents: 4500,
    );
    await desk.saveRecord(
      kind: 'restaurant',
      title: 'Déjeuner d’affaires',
      details: '',
      restaurantStart: at(1, 13),
      diningTableId: tables[4],
      units: 3,
      visitorName: 'Mme Fontaine',
    );
    final massageSlot =
        (await desk.slots(kind: 'spa')).firstWhere(
              (s) => (s['name'] as String).startsWith('Massage'),
            )['id']
            as int;
    final dinnerAt = DateTime(
      start.year,
      start.month,
      start.day,
      start.hour,
    ).add(const Duration(hours: 6));
    as(guest);
    final massage = await desk.saveRecord(
      kind: 'spa',
      title: 'Massage relaxant',
      details: 'Pression douce',
      slotId: massageSlot,
    );
    await desk.saveRecord(
      kind: 'restaurant',
      title: 'Dîner',
      details: 'Table près de la fenêtre si possible',
      restaurantStart: dinnerAt,
      diningTableId: tables[1],
      units: 2,
    );
    as(reception);
    await move(massage, 'confirmed');

    // Requests and messages with the reception.
    as(guest);
    final pillows = await desk.saveRecord(
      kind: 'request',
      title: 'Oreillers supplémentaires',
      details: 'Deux oreillers fermes, s’il vous plaît.',
      dueAt: start.add(const Duration(hours: 3)),
    );
    final noise = await desk.saveRecord(
      kind: 'complaint',
      title: 'Bruit dans le couloir',
      details: 'Des portes claquent vers 23 h au premier étage.',
    );
    final taxi = await desk.saveRecord(
      kind: 'conversation',
      title: 'Taxi pour l’aéroport',
      details: 'Pour notre départ, vers Roissy.',
    );
    as(reception);
    await move(pillows, 'confirmed');
    await desk.assign(await record(pillows), sarah.id);
    await move(pillows, 'in_progress');
    await say(
      reception,
      pillows,
      'C’est noté, Sarah vous les apporte d’ici une heure.',
    );
    as(reception);
    await move(noise, 'confirmed');
    await desk.assign(await record(noise), 'amina');
    await say(
      reception,
      noise,
      'Toutes nos excuses. La gouvernante passe ce soir vérifier les ferme-portes.',
    );
    await say(guest, noise, 'Merci beaucoup !');
    await say(
      guest,
      taxi,
      'Pouvez-vous réserver un taxi à 9 h le jour du départ ?',
    );
    await say(
      reception,
      taxi,
      'Bien sûr : un taxi vous attendra à 9 h devant l’hôtel (environ 55 €).',
    );
    as(reception);
    await move(taxi, 'confirmed');
  } finally {
    session.dispose();
  }
  return true;
}
