import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/hotel_data.dart';
import '../models/inspection.dart';
import '../models/issue.dart';
import '../models/lost_item.dart';
import '../models/room.dart';
import 'auto_assignment.dart';
import '../models/supply.dart';
import 'housekeeping_store.dart';
import 'inspection_scoring.dart';
import 'mutation_meta.dart';
import 'room_catalog_backend.dart';
import 'sqlite_housekeeping.dart';
import 'sqlite_room_catalog.dart';
import '../../shared/services/app_events.dart';
import '../../shared/services/app_session.dart';
import 'hotel_event_handlers.dart';

// A demo hotel for the presentation, built only through the module's own
// actions (same rules, versions and checks as the screens), so every screen
// shows coherent data: 26 rooms on 4 floors, five days of cleanings with
// photos and inspections, and today's work in every state.
// The demo team: Manager Démo, Amina (gouvernante), Sarah, Lina, Youssef.
//
// [fillDemoHotel] expects the housekeeping tables to be empty (see
// [clearHousekeeping]) and the hotel event listeners to be attached.
// In the app: build with --dart-define=HOUSEKEEPING_DEMO_DATA=true (and
// HOUSEKEEPING_SAMPLE_DATA=false); on start, an empty hotel is filled once
// (see [fillDemoHotelIfEmpty]).

/// Build option: fill an empty hotel with the demo data on start.
const housekeepingDemoData = bool.fromEnvironment('HOUSEKEEPING_DEMO_DATA');

/// Fills the hotel when it has no room yet, on its own session (the user
/// signed in on the phone is not touched; other modules hear nothing).
Future<void> fillDemoHotelIfEmpty(AppSession app) async {
  final session = AppSession(database: app.database, staff: app.staff);
  final store = HousekeepingStore(session);
  if ((await store.readState())['rooms'] case final List rooms
      when rooms.isNotEmpty) {
    return;
  }
  listenToHotelEvents(session.events, store);
  final watch = Stopwatch()..start();
  final summary = await fillDemoHotel(session, store);
  debugPrint(
    'housekeeping: hôtel de démonstration prêt en '
    '${watch.elapsed.inSeconds} s ($summary)',
  );
}

const _agents = ['sarah', 'lina', 'youssef'];

/// Deletes every housekeeping row (the phone's sync settings are kept).
Future<void> clearHousekeeping(HousekeepingStore store) =>
    store.replaceAll((tx) async {
      final tables = [
        for (final t in await tx.query(
          'sqlite_master',
          columns: ['name'],
          where: "type = 'table' AND name LIKE 'housekeeping\\_%' ESCAPE '\\'",
        ))
          t['name'] as String,
      ];
      // Children first (their parents cascade anyway).
      tables.sort((a, b) {
        int rank(String t) =>
            t.endsWith('_lines') ||
                t.endsWith('_items') ||
                t.endsWith('_events') ||
                t.endsWith('_reads') ||
                t.endsWith('_photos') && t != 'housekeeping_photos'
            ? 0
            : 1;
        return rank(a) - rank(b);
      });
      for (final t in tables) {
        if (t == 'housekeeping_sync_state') {
          await tx.delete(t, where: "key IN ('last_seq', 'last_sync_at')");
        } else {
          await tx.delete(t);
        }
      }
    });

Uint8List _photo(int n) => Uint8List.fromList(
  img.encodeJpg(
    img.fill(
      img.Image(width: 64, height: 48),
      color: img.ColorRgb8(40 + n * 23 % 180, 110 + n * 11 % 120, 90),
    ),
    quality: 70,
  ),
);

/// Fills the hotel; returns a short summary. [today] is the real day.
Future<String> fillDemoHotel(
  AppSession session,
  HousekeepingStore store, {
  DateTime? today,
}) async {
  final staff = {for (final u in await session.staff.users()) u.id: u};
  final day0 = today ?? DateTime.now();
  final midnight = DateTime(day0.year, day0.month, day0.day);
  var now = midnight.subtract(const Duration(days: 5));
  final rules = SqliteHousekeeping(
    store,
    events: session.events,
    clock: () => now,
  );
  final catalog = SqliteRoomCatalog(store, clock: () => now);
  // No automatic refresh: each step re-reads when it needs to.
  final data = HotelData(api: rules, changes: const Stream.empty());
  var photos = 0;

  Future<HotelData> as(String id) async {
    session.signIn(staff[id]!);
    await data.refresh();
    return data;
  }

  Future<void> manager(RoomCatalogAction action, Map<String, dynamic> body) {
    session.signIn(staff['manager']!);
    return catalog.mutate(action, {...mutationMeta(), ...body});
  }

  Room room(String n) => data.roomByNumber(n);
  Supply supply(String name) => data.supplies.firstWhere((s) => s.name == name);
  void at(DateTime day, int hour, [int minute = 0]) =>
      now = DateTime(day.year, day.month, day.day, hour, minute);
  void later(int minutes) => now = now.add(Duration(minutes: minutes));

  // ---------------------------------------------------------- the hotel
  at(now, 7);
  const floors = {
    1: 'Rez-de-jardin',
    2: 'Étage Saint-Germain',
    3: 'Étage Montmartre',
    4: 'Étage des suites',
  };
  for (final e in floors.entries) {
    await manager(RoomCatalogAction.renameFloor, {
      'floor': e.key,
      'name': e.value,
    });
  }
  const categories = {
    'Chambre Classique': (
      25,
      [
        'Changer le linge de lit',
        'Nettoyer la salle de bain',
        'Aspirer et laver le sol',
        'Réassortir les produits d’accueil',
      ],
    ),
    'Chambre Supérieure': (
      30,
      [
        'Changer le linge de lit',
        'Nettoyer la salle de bain',
        'Dépoussiérer le mobilier',
        'Aspirer et laver le sol',
        'Réassortir les produits d’accueil',
      ],
    ),
    'Chambre Deluxe': (
      40,
      [
        'Changer le linge de lit',
        'Nettoyer la salle de bain et la baignoire',
        'Dépoussiérer le mobilier',
        'Vérifier le minibar',
        'Aspirer et laver le sol',
        'Réassortir les produits d’accueil',
      ],
    ),
    'Suite': (
      60,
      [
        'Changer le linge des deux lits',
        'Nettoyer les salles de bain',
        'Nettoyer le salon et la terrasse',
        'Vérifier le minibar',
        'Aspirer et laver les sols',
        'Préparer la couverture du soir',
      ],
    ),
  };
  for (final e in categories.entries) {
    await manager(RoomCatalogAction.setCategoryTasks, {
      'category': e.key,
      'labels': e.value.$2,
    });
    await manager(RoomCatalogAction.setCategoryEstimate, {
      'category': e.key,
      'minutes': e.value.$1,
    });
  }
  for (final (floor, from, to, category) in [
    (1, 1, 8, 'Chambre Classique'),
    (2, 1, 8, 'Chambre Supérieure'),
    (3, 1, 6, 'Chambre Deluxe'),
    (4, 1, 4, 'Suite'),
  ]) {
    await manager(RoomCatalogAction.createRange, {
      'floor': floor,
      'from': from,
      'to': to,
      'category': category,
    });
  }
  for (final (name, cents, quantity) in [
    ('Eau minérale 50 cl', 350, 48),
    ('Coca-Cola 33 cl', 450, 36),
    ('Jus d’orange 25 cl', 400, 24),
    ('Bière blonde 33 cl', 650, 24),
    ('Champagne 20 cl', 1800, 12),
    ('Chips salées', 300, 30),
    ('Chocolat noir', 350, 30),
  ]) {
    await manager(RoomCatalogAction.saveMinibarItem, {
      'name': name,
      'unit': 'unités',
      'priceCents': cents,
      'minimum': (quantity / 4).ceil(),
      'quantity': quantity,
    });
  }

  // ---------------------------------------------------------- the stock
  final d = await as('amina');
  for (final (name, unit, quantity, minimum, category) in [
    ('Draps', 'pièces', 120, 40, 'linge'),
    ('Housses de couette', 'pièces', 80, 25, 'linge'),
    ('Taies d’oreiller', 'pièces', 160, 50, 'linge'),
    ('Serviettes de bain', 'pièces', 150, 50, 'linge'),
    ('Peignoirs', 'pièces', 40, 15, 'linge'),
    ('Tapis de bain', 'pièces', 60, 20, 'linge'),
    ('Gel douche 30 ml', 'flacons', 300, 80, 'accueil'),
    ('Shampooing 30 ml', 'flacons', 280, 80, 'accueil'),
    ('Savon 20 g', 'pièces', 220, 60, 'accueil'),
    ('Kit dentaire', 'pièces', 34, 30, 'accueil'),
    ('Bonnet de douche', 'pièces', 100, 30, 'accueil'),
    ('Nettoyant multi-surfaces', 'litres', 18, 6, 'entretien'),
    ('Désinfectant sanitaires', 'litres', 9, 6, 'entretien'),
    ('Papier toilette', 'rouleaux', 400, 120, 'entretien'),
    ('Sacs poubelle', 'rouleaux', 30, 10, 'entretien'),
    ('Gants nitrile', 'boîtes', 12, 4, 'entretien'),
  ]) {
    await d.createSupply(
      name: name,
      unit: unit,
      quantity: quantity,
      minimum: minimum,
      category: category,
    );
  }

  // ------------------------------------------- five days of cleanings
  // Each past day: rooms cleaned with a photo per task, then inspected.
  // Durations and scores vary per agent, for the dashboard and the stats.
  final history = [
    ['101', '102', '201', '202', '301'],
    ['103', '104', '203', '204', '302'],
    ['105', '106', '205', '206', '401'],
    ['107', '108', '207', '303'],
    ['305', '306', '402', '403'],
  ];
  const pace = {'sarah': 0, 'lina': 6, 'youssef': 12};
  for (final (i, rooms) in history.indexed) {
    final day = midnight.subtract(Duration(days: 5 - i));
    at(day, 8, 30);
    var supervisor = await as('amina');
    for (final (k, n) in rooms.indexed) {
      await supervisor.assign(room(n), _agents[k % 3], '', false);
    }
    for (final (k, n) in rooms.indexed) {
      final agentId = _agents[k % 3];
      at(day, 9 + k, (i * 7 + k * 13) % 50);
      var agent = await as(agentId);
      await agent.startCleaning(room(n));
      // Linen and amenities taken from the stock for this room.
      agent = await as(agentId);
      await agent.useSupply(supply('Draps'), room(n), 2);
      agent = await as(agentId);
      await agent.useSupply(supply('Gel douche 30 ml'), room(n), 2);
      final estimate = categories[room(n).category]!.$1;
      final minutes = estimate - 4 + pace[agentId]! + (i * 3 + k) % 9;
      for (var t = 0; t < room(n).tasks.length; t++) {
        later(minutes ~/ room(n).tasks.length);
        agent = await as(agentId);
        await agent.setCheck(room(n), t, true, photo: _photo(photos++));
      }
      agent = await as(agentId);
      await agent.submitCleaning(room(n));
      later(12);
      supervisor = await as('amina');
      final r = room(n);
      // One cleaning in five has a partial point; one is sent back once.
      if (i == 2 && k == 4) {
        await supervisor.sendBack(r, [
          for (final (t, task) in r.tasks.indexed)
            ItemRating(
              task.id,
              rating: t == 2 ? InspectionRating.failed : InspectionRating.ok,
              comment: t == 2 ? 'Traces sur la terrasse' : '',
            ),
        ], 'Terrasse à reprendre');
        later(20);
        agent = await as(agentId);
        final back = room(n);
        for (var t = 0; t < back.tasks.length; t++) {
          if (back.checklist[t]) continue;
          agent = await as(agentId);
          await agent.setCheck(room(n), t, true, photo: _photo(photos++));
        }
        agent = await as(agentId);
        await agent.submitCleaning(room(n));
        later(10);
        supervisor = await as('amina');
      }
      final again = room(n);
      await supervisor.approveInspected(again, [
        for (final (t, task) in again.tasks.indexed)
          ItemRating(
            task.id,
            rating: (i + k + t) % 7 == 0
                ? InspectionRating.partial
                : InspectionRating.ok,
          ),
      ]);
    }
  }

  // Yesterday: laundry sent in the morning, back in the evening.
  final yesterday = midnight.subtract(const Duration(days: 1));
  at(yesterday, 10);
  var s = await as('amina');
  await s.sendLaundry({
    supply('Draps'): 30,
    supply('Serviettes de bain'): 40,
  }, note: 'Lot du matin');
  at(yesterday, 18);
  s = await as('amina');
  await s.returnLaundry(s.laundry.first, {
    supply('Draps').id: (received: 29, damaged: 1, lost: 0),
    supply('Serviettes de bain').id: (received: 38, damaged: 1, lost: 1),
  });

  // --------------------------------------------------------------- today
  // Guests: arrivals and departures as told by the reservations module.
  at(midnight, 7, 30);
  const guests = {
    '101': 'M. Martin',
    '201': 'Mme Bernard',
    '202': 'M. et Mme Dubois',
    '301': 'Mme Laurent',
    '302': 'M. Garcia',
    '401': 'M. Rossi',
    '204': 'Mme Petit',
    '303': 'M. Moreau',
  };
  for (final e in guests.entries) {
    session.events.emit(GuestCheckedIn(e.key, guestName: e.value));
  }
  await _settle(store);
  // Three guests leave this morning: their rooms need a cleaning.
  for (final n in ['202', '302', '204']) {
    session.events.emit(GuestCheckedOut(n));
  }
  await _settle(store);

  at(midnight, 8, 15);
  s = await as('amina');
  await s.setStayover(room('101'), true, note: 'Recouche · client présent');
  s = await as('amina');
  await s.setStayover(room('401'), true, note: 'Couverture du soir à 19 h');
  s = await as('amina');
  // Today's plan: one per state, so every screen has something to show.
  await s.assign(room('202'), 'sarah', 'Départ · arrivée VIP à 14 h', true);
  s = await as('amina');
  await s.assign(room('302'), 'lina', 'Départ du client', false);
  s = await as('amina');
  await s.assign(room('204'), 'youssef', '', false);
  s = await as('amina');
  await s.assign(room('101'), 'sarah', 'Recouche', false);
  s = await as('amina');
  await s.assign(room('304'), 'lina', '', false);
  s = await as('amina');
  await s.assign(room('404'), 'youssef', 'Suite à préparer pour ce soir', true);
  s = await as('amina');
  await s.setPriority(room('404'), CleaningPriority.vip);

  // Sarah: 202 done and waiting for inspection.
  at(midnight, 9);
  var a = await as('sarah');
  await a.startCleaning(room('202'));
  for (var t = 0; t < room('202').tasks.length; t++) {
    later(6);
    a = await as('sarah');
    await a.setCheck(room('202'), t, true, photo: _photo(photos++));
  }
  a = await as('sarah');
  await a.submitCleaning(room('202'));
  // Lina: 302 in progress (timer running); 304 not started.
  at(midnight, 9, 20);
  a = await as('lina');
  await a.startCleaning(room('302'));
  later(15);
  a = await as('lina');
  await a.setCheck(room('302'), 0, true, photo: _photo(photos++));
  a = await as('lina');
  await a.setCheck(room('302'), 1, true, photo: _photo(photos++));
  // Youssef: 204 in progress, paused for a call.
  at(midnight, 9, 40);
  a = await as('youssef');
  await a.startCleaning(room('204'));
  later(10);
  a = await as('youssef');
  await a.setCheck(room('204'), 0, true, photo: _photo(photos++));
  a = await as('youssef');
  await a.pauseTimer(room('204'));

  // Problem reports: one out of service, two in other languages (to show
  // the translation), one already repaired by maintenance.
  at(midnight, 10);
  a = await as('youssef');
  await a.reportIssue(
    room('204'),
    category: IssueCategory.plomberie,
    description: 'The shower drain is blocked, water stays in the tray',
    priority: IssuePriority.high,
    outOfService: false,
    photos: [_photo(photos++)],
  );
  a = await as('lina');
  await a.reportIssue(
    room('302'),
    category: IssueCategory.eclairage,
    description: 'المصباح في الحمام لا يعمل',
    priority: IssuePriority.normal,
    outOfService: false,
  );
  s = await as('amina');
  await s.reportIssue(
    room('305'),
    category: IssueCategory.climatisation,
    description: 'Climatisation en panne, la chambre reste à 28 °C',
    priority: IssuePriority.urgent,
    outOfService: true,
  );
  s = await as('amina');
  await s.reportIssue(
    room('106'),
    category: IssueCategory.mobilier,
    description: 'Pied de lit cassé',
    priority: IssuePriority.normal,
    outOfService: true,
  );
  session.events.emit(const MaintenanceResolved('106'));
  await _settle(store);

  // Lost and found.
  at(midnight, 11);
  a = await as('sarah');
  await a.recordLostItem(
    room('202'),
    'Montre en argent sur la table de nuit',
    photo: _photo(photos++),
  );
  a = await as('lina');
  await a.recordLostItem(room('302'), 'Chargeur de téléphone noir');
  s = await as('amina');
  await s.notifyOwner(
    s.lostItems.firstWhere((i) => i.description.startsWith('Montre')),
    ContactChannel.phone,
    'Message laissé au client : montre retrouvée, à récupérer à la réception.',
  );
  at(yesterday, 16);
  s = await as('amina');
  await s.recordLostItem(room('206'), 'Lunettes de soleil');
  at(midnight, 11, 30);
  s = await as('amina');
  await s.returnLostItem(
    s.lostItems.firstWhere((i) => i.description == 'Lunettes de soleil'),
    'Mme Leroy, à la réception',
  );

  // Supply requests from the floors.
  at(midnight, 12);
  a = await as('sarah');
  await a.requestSupplies({
    supply('Serviettes de bain'): 10,
    supply('Gel douche 30 ml'): 12,
  }, note: 'Chariot du 2e étage');
  a = await as('lina');
  await a.requestSupplies({supply('Taies d’oreiller'): 8});
  a = await as('youssef');
  await a.requestSupplies({supply('Peignoirs'): 30}, note: 'Pour les suites');
  s = await as('amina');
  final lina = s.requests.firstWhere((r) => r.agentId == 'lina');
  await s.approveRequest(lina);
  s = await as('amina');
  await s.prepareRequest(s.requests.firstWhere((r) => r.id == lina.id));
  s = await as('amina');
  await s.deliverRequest(s.requests.firstWhere((r) => r.id == lina.id));
  s = await as('amina');
  await s.refuseRequest(
    s.requests.firstWhere((r) => r.agentId == 'youssef'),
    'Stock de peignoirs réservé aux suites occupées',
  );

  // Minibar of occupied rooms.
  at(midnight, 12, 30);
  a = await as('sarah');
  await a.recordMinibar(room('101'), supply('Eau minérale 50 cl'), 2);
  a = await as('sarah');
  await a.recordMinibar(room('101'), supply('Chocolat noir'), 1);
  s = await as('amina');
  await s.recordMinibar(room('401'), supply('Champagne 20 cl'), 1);
  s = await as('amina');
  await s.recordMinibar(room('401'), supply('Coca-Cola 33 cl'), 2);
  s = await as('amina');
  await s.postMinibar('101', [
    for (final e in s.minibar)
      if (e.roomNumber == '101') e,
  ]);

  // Laundry sent this morning, not back yet; a delivery of paper.
  at(midnight, 13);
  s = await as('amina');
  await s.sendLaundry({
    supply('Housses de couette'): 20,
    supply('Taies d’oreiller'): 40,
  }, note: 'Lot du jour');
  s = await as('amina');
  await s.moveStock(supply('Papier toilette'), 96);
  // Tomorrow: Youssef is off.
  s = await as('amina');
  await s.setAvailability(
    'youssef',
    midnight.add(const Duration(days: 1)),
    available: false,
    minutes: 0,
  );

  await data.refresh();
  final summary =
      '${data.rooms.length} chambres, ${data.cleanings.length} nettoyages, '
      '${data.issues.length} signalements, ${data.lostItems.length} objets, '
      '${data.supplies.length} articles, ${data.requests.length} demandes';
  data.dispose();
  session.signOut();
  return summary;
}

// The event listeners save in the background: wait until they are done.
Future<void> _settle(HousekeepingStore store) async {
  await Future<void>.delayed(const Duration(milliseconds: 50));
  await store.readState();
}
