import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../../shared/models/app_user.dart';
import '../../shared/services/app_events.dart';
import '../models/hotel_data.dart';
import '../models/inspection.dart';
import '../models/issue.dart';
import '../models/lost_item.dart';
import '../models/room.dart';
import '../models/supply.dart';
import 'auto_assignment.dart';
import 'hotel_event_handlers.dart';
import 'housekeeping_backup.dart';
import 'housekeeping_store.dart';
import 'inspection_scoring.dart';
import 'local_session_store.dart';
import 'mutation_meta.dart';
import 'room_catalog_backend.dart';
import 'sqlite_housekeeping.dart';
import 'sqlite_room_catalog.dart';

// A demo hotel for the presentation, built only through the module's own
// rules (same versions and checks as the screens), so every screen shows
// coherent data: 26 rooms on 4 floors, five days of cleanings with photos
// and inspections, and today's work in every state.
// The demo team: Manager Démo, Amina (gouvernante), Sarah, Lina, Youssef.
//
// In the app: build with --dart-define=HOUSEKEEPING_DEMO_DATA=true (and
// HOUSEKEEPING_SAMPLE_DATA=false); on start, [fillDemoHotelIfEmpty] fills an
// empty hotel once. It writes through the module's store (the screens
// update as it goes), acting as each demo person without touching who is
// signed in on the phone, and nothing is queued for the sync server.

/// Build option: fill an empty hotel with the demo data on start.
const housekeepingDemoData = bool.fromEnvironment('HOUSEKEEPING_DEMO_DATA');

// In housekeeping_sync_state (this phone's own table): "started" while the
// fill runs, "done" once finished. A fill cut off (app closed) is redone.
const _marker = 'demo_hotel';

/// Fills the hotel once: when it is empty, or when an earlier fill did not
/// finish. Never on a phone set to sync with a server (its hotel comes from
/// the server), never over the hotel's own data.
Future<String?> fillDemoHotelIfEmpty(
  HousekeepingStore store, {
  DateTime? now,
}) async {
  final (:marker, :server, :rooms) = await store.syncLedger((tx) async {
    final settings = {
      for (final row in await tx.query('housekeeping_sync_state'))
        row['key'] as String: row['value'] as String,
    };
    final count =
        (await tx.rawQuery('SELECT COUNT(*) AS n FROM housekeeping_rooms'))
                .single['n']
            as int;
    return (
      marker: settings[_marker],
      server: settings['server_url'],
      rooms: count,
    );
  });
  if (server != null || marker == 'done') return null;
  if (marker == null && rooms > 0) return null;
  // An unfinished fill: start again from an empty hotel.
  if (marker == 'started') await clearHousekeeping(store);
  await _setMarker(store, 'started');
  final watch = Stopwatch()..start();
  final summary = await fillDemoHotel(store, now: now);
  await _setMarker(store, 'done');
  debugPrint(
    'housekeeping: hôtel de démonstration prêt en '
    '${watch.elapsed.inSeconds} s ($summary)',
  );
  return summary;
}

Future<void> _setMarker(HousekeepingStore store, String value) =>
    store.syncLedger(
      (tx) => tx.rawInsert(
        'INSERT OR REPLACE INTO housekeeping_sync_state (key, value) '
        'VALUES (?, ?)',
        [_marker, value],
      ),
    );

/// Empties the module's tables, like a backup restore replaces them: same
/// tables (the phone's sync settings stay), same sync reset.
Future<void> clearHousekeeping(HousekeepingStore store) =>
    store.replaceAll((tx) async {
      final tables =
          [
            for (final t in await tx.query(
              'sqlite_master',
              columns: ['name'],
              where: HousekeepingBackup.moduleTables,
            ))
              t['name'] as String,
          ]..sort(
            (a, b) =>
                (HousekeepingBackup.childTables.contains(a) ? 0 : 1) -
                (HousekeepingBackup.childTables.contains(b) ? 0 : 1),
          );
      for (final table in tables) {
        await tx.delete(table);
      }
      await HousekeepingStore.resetSync(tx);
    });

/// The store, seen as one demo person after another: the rules check their
/// role and rooms as usual, whoever is signed in on the phone.
class _ActingAs implements LocalSessionStore {
  final HousekeepingStore inner;
  Map<String, dynamic> person = const {};
  _ActingAs(this.inner);

  @override
  Map<String, dynamic> actor(Map<String, dynamic> state) => person;

  @override
  Future<void> change(void Function(Map<String, dynamic>) action) =>
      inner.change(action, checkSession: false);

  @override
  Never fail(String message, [int status = 400]) => inner.fail(message, status);

  @override
  Future<Map<String, dynamic>> readState() => inner.readState();
}

const _agents = ['sarah', 'lina', 'youssef'];

/// Real photos for the demo (assets/images/demo_hotel/, sources and
/// licences in CREDITS.md there). A task photo matches its task: bed,
/// bathroom, surfaces, amenities. A plain colour stands in when the assets
/// can't be read (unit tests without a binding).
class _DemoPhotos {
  static const _taskKinds = [
    ('bed', 4),
    ('bathroom', 4),
    ('room', 3),
    ('amenities', 4),
  ];
  final Map<String, Uint8List> _bytes;
  _DemoPhotos(this._bytes);

  static Future<_DemoPhotos> load() async {
    final bytes = <String, Uint8List>{};
    final names = [
      for (final (kind, count) in _taskKinds)
        for (var i = 1; i <= count; i++) '${kind}_$i',
      'issue_drain',
      'lost_watch',
    ];
    for (final name in names) {
      try {
        final data = await rootBundle.load(
          'assets/images/demo_hotel/$name.jpg',
        );
        bytes[name] = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
      } catch (_) {
        // Missing asset or no binding: the plain colour is used.
      }
    }
    return _DemoPhotos(bytes);
  }

  /// Photo for task [task] of a room; [n] varies the picture.
  Uint8List task(int task, int n) {
    final (kind, count) = _taskKinds[task % _taskKinds.length];
    return _bytes['${kind}_${n % count + 1}'] ?? _photo(n);
  }

  Uint8List named(String name, int n) => _bytes[name] ?? _photo(n);
}

Uint8List _photo(int n) => Uint8List.fromList(
  img.encodeJpg(
    img.fill(
      img.Image(width: 64, height: 48),
      color: img.ColorRgb8(40 + n * 23 % 180, 110 + n * 11 % 120, 90),
    ),
    quality: 70,
  ),
);

const _floors = {
  1: 'Rez-de-jardin',
  2: 'Étage Saint-Germain',
  3: 'Étage Montmartre',
  4: 'Étage des suites',
};

// Category: (estimated minutes, tasks).
const _categories = {
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

/// Builds the hotel; returns a short summary. [now] is the real time of the
/// fill: today's work happens in the hours before it, never after.
Future<String> fillDemoHotel(HousekeepingStore store, {DateTime? now}) async {
  final staff = {for (final u in await store.session.staff.users()) u.id: u};
  final realNow = now ?? DateTime.now();
  // Calendar days (a 24 h step would slip on a daylight saving change).
  DateTime day(int offset) =>
      DateTime(realNow.year, realNow.month, realNow.day + offset);
  final today0 = day(0);

  var clock = day(-5).add(const Duration(hours: 7));
  final acting = _ActingAs(store);
  final rules = SqliteHousekeeping(
    acting,
    clock: () => clock,
    queueForSync: false,
  );
  final catalog = SqliteRoomCatalog(
    acting,
    clock: () => clock,
    queueForSync: false,
  );
  // No automatic refresh: [as] re-reads when the person changes, and each
  // action re-reads after saving.
  final data = HotelData(api: rules, changes: const Stream.empty());
  var photos = 0;
  final pictures = await _DemoPhotos.load();
  String? who;

  void actAs(String id) {
    final AppUser user = staff[id]!;
    acting.person = {
      'id': user.id,
      'full_name': user.fullName,
      'role': user.role,
    };
  }

  Future<void> as(String id) async {
    if (who == id) return;
    actAs(id);
    who = id;
    await data.refresh();
  }

  Future<void> manager(RoomCatalogAction action, Map<String, dynamic> body) {
    actAs('manager');
    who = null;
    return catalog.mutate(action, {...mutationMeta(), ...body});
  }

  // Another module's event, at the demo's time.
  Future<void> event(AppEvent e) async {
    await store.systemChange((s) => applyHotelEvent(s, e), at: clock);
    who = null;
  }

  Room room(String n) => data.roomByNumber(n);
  Supply supply(String name) => data.supplies.firstWhere((s) => s.name == name);
  void at(DateTime d, int hour, [int minute = 0]) =>
      clock = DateTime(d.year, d.month, d.day, hour, minute);
  void later(int minutes) => clock = clock.add(Duration(minutes: minutes));

  // Today's work is spread over the hours before [realNow] (at most six):
  // minute 0 to 330 of the demo day map onto that window.
  final dayStart = realNow.subtract(const Duration(hours: 6)).isBefore(today0)
      ? today0
      : realNow.subtract(const Duration(hours: 6));
  final dayEnd = realNow.subtract(const Duration(minutes: 5)).isBefore(dayStart)
      ? dayStart
      : realNow.subtract(const Duration(minutes: 5));
  void today(int minute) => clock = dayStart.add(
    Duration(
      microseconds: (dayEnd.difference(dayStart).inMicroseconds * minute / 330)
          .round(),
    ),
  );

  // ---------------------------------------------------------- the hotel
  for (final e in _floors.entries) {
    await manager(RoomCatalogAction.renameFloor, {
      'floor': e.key,
      'name': e.value,
    });
  }
  for (final e in _categories.entries) {
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
  await as('amina');
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
    await data.createSupply(
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
  // 304 and 208 are kept dirty for today.
  final history = [
    ['101', '102', '201', '202', '301'],
    ['103', '104', '203', '204', '302'],
    ['105', '106', '205', '206', '401'],
    ['107', '108', '207', '303'],
    ['305', '306', '402', '403'],
  ];
  const pace = {'sarah': 0, 'lina': 6, 'youssef': 12};

  Future<void> photographRemaining(String agentId, String n, int every) async {
    await as(agentId);
    for (var t = 0; t < room(n).tasks.length; t++) {
      if (room(n).checklist[t]) continue;
      later(every);
      await data.setCheck(room(n), t, true, photo: pictures.task(t, photos++));
    }
  }

  for (final (i, rooms) in history.indexed) {
    final d = day(i - 5);
    at(d, 8, 30);
    await as('amina');
    for (final (k, n) in rooms.indexed) {
      await data.assign(room(n), _agents[k % 3], '', false);
    }
    for (final (k, n) in rooms.indexed) {
      final agentId = _agents[k % 3];
      at(d, 9 + k, (i * 7 + k * 13) % 50);
      await as(agentId);
      await data.startCleaning(room(n));
      // Linen and amenities taken from the stock for this room.
      await data.useSupply(supply('Draps'), room(n), 2);
      await data.useSupply(supply('Gel douche 30 ml'), room(n), 2);
      final minutes =
          _categories[room(n).category]!.$1 -
          4 +
          pace[agentId]! +
          (i * 3 + k) % 9;
      await photographRemaining(agentId, n, minutes ~/ room(n).tasks.length);
      await data.submitCleaning(room(n));
      later(12);
      await as('amina');
      // One suite is sent back once: the terrace is redone.
      if (i == 2 && k == 4) {
        await data.sendBack(room(n), [
          for (final (t, task) in room(n).tasks.indexed)
            ItemRating(
              task.id,
              rating: t == 2 ? InspectionRating.failed : InspectionRating.ok,
              comment: t == 2 ? 'Traces sur la terrasse' : '',
            ),
        ], 'Terrasse à reprendre');
        later(20);
        await photographRemaining(agentId, n, 5);
        await data.submitCleaning(room(n));
        later(10);
        await as('amina');
      }
      // About one point in seven is "partial".
      await data.approveInspected(room(n), [
        for (final (t, task) in room(n).tasks.indexed)
          ItemRating(
            task.id,
            rating: (i + k + t) % 7 == 0
                ? InspectionRating.partial
                : InspectionRating.ok,
          ),
      ]);
    }
  }

  // Yesterday afternoon: laundry out and back, sunglasses found.
  final yesterday = day(-1);
  at(yesterday, 14);
  await as('amina');
  await data.sendLaundry({
    supply('Draps'): 30,
    supply('Serviettes de bain'): 40,
  }, note: 'Lot de l’après-midi');
  at(yesterday, 16);
  await data.recordLostItem(room('206'), 'Lunettes de soleil');
  at(yesterday, 18);
  await data.returnLaundry(data.laundry.first, {
    supply('Draps').id: (received: 29, damaged: 1, lost: 0),
    supply('Serviettes de bain').id: (received: 38, damaged: 1, lost: 1),
  });

  // --------------------------------------------------------------- today
  // Guests, as the reservations module tells them.
  today(0);
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
    await event(GuestCheckedIn(e.key, guestName: e.value));
  }
  // Three guests leave this morning: their rooms need a cleaning.
  today(20);
  for (final n in ['202', '302', '204']) {
    await event(GuestCheckedOut(n));
  }

  // The plan of the day: one room per state, so every screen has
  // something to show; 208 stays unassigned for the automatic plan.
  today(40);
  await as('amina');
  await data.setStayover(room('101'), true, note: 'Recouche · client présent');
  await data.setStayover(room('401'), true, note: 'Couverture du soir à 19 h');
  await data.assign(room('202'), 'sarah', 'Départ · arrivée VIP à 14 h', true);
  await data.assign(room('302'), 'lina', 'Départ du client', false);
  await data.assign(room('204'), 'youssef', '', false);
  await data.assign(room('101'), 'sarah', 'Recouche', false);
  await data.assign(room('304'), 'lina', '', false);
  await data.assign(
    room('404'),
    'youssef',
    'Suite à préparer pour ce soir',
    true,
  );
  await data.setPriority(room('404'), CleaningPriority.vip);

  // Sarah: 202 done, waiting for the inspection.
  today(60);
  await as('sarah');
  await data.startCleaning(room('202'));
  for (var t = 0; t < room('202').tasks.length; t++) {
    today(64 + t * 6);
    await data.setCheck(
      room('202'),
      t,
      true,
      photo: pictures.task(t, photos++),
    );
  }
  today(95);
  await data.submitCleaning(room('202'));
  // Lina: 302 in progress, timer running; 304 not started.
  today(100);
  await as('lina');
  await data.startCleaning(room('302'));
  today(108);
  await data.setCheck(room('302'), 0, true, photo: pictures.task(0, photos++));
  today(114);
  await data.setCheck(room('302'), 1, true, photo: pictures.task(1, photos++));
  // Youssef: 204 in progress, paused for a call.
  today(118);
  await as('youssef');
  await data.startCleaning(room('204'));
  today(126);
  await data.setCheck(room('204'), 0, true, photo: pictures.task(0, photos++));
  today(132);
  await data.pauseTimer(room('204'));

  // Problem reports: two in other languages (the translation demo), one
  // out of service, one already repaired by maintenance.
  today(140);
  await data.reportIssue(
    room('204'),
    category: IssueCategory.plomberie,
    description: 'The shower drain is blocked, water stays in the tray',
    priority: IssuePriority.high,
    outOfService: false,
    photos: [pictures.named('issue_drain', photos++)],
  );
  today(145);
  await as('lina');
  await data.reportIssue(
    room('302'),
    category: IssueCategory.eclairage,
    description:
        'المصباح في '
        'الحمام لا يعمل',
    priority: IssuePriority.normal,
    outOfService: false,
  );
  today(150);
  await as('amina');
  await data.reportIssue(
    room('305'),
    category: IssueCategory.climatisation,
    description: 'Climatisation en panne, la chambre reste à 28 °C',
    priority: IssuePriority.urgent,
    outOfService: true,
  );
  await data.reportIssue(
    room('106'),
    category: IssueCategory.mobilier,
    description: 'Pied de lit cassé',
    priority: IssuePriority.normal,
    outOfService: true,
  );
  today(160);
  await event(const MaintenanceResolved('106'));

  // Lost and found.
  today(180);
  await as('sarah');
  await data.recordLostItem(
    room('202'),
    'Montre en argent sur la table de nuit',
    photo: pictures.named('lost_watch', photos++),
  );
  await as('lina');
  await data.recordLostItem(room('302'), 'Chargeur de téléphone noir');
  today(190);
  await as('amina');
  await data.notifyOwner(
    data.lostItems.firstWhere((i) => i.description.startsWith('Montre')),
    ContactChannel.phone,
    'Message laissé au client : montre retrouvée, à récupérer à la réception.',
  );
  today(200);
  await data.returnLostItem(
    data.lostItems.firstWhere((i) => i.description == 'Lunettes de soleil'),
    'Mme Leroy, à la réception',
  );

  // Supply requests from the floors.
  today(210);
  await as('sarah');
  await data.requestSupplies({
    supply('Serviettes de bain'): 10,
    supply('Gel douche 30 ml'): 12,
  }, note: 'Chariot du 2e étage');
  await as('lina');
  await data.requestSupplies({supply('Taies d’oreiller'): 8});
  await as('youssef');
  await data.requestSupplies({
    supply('Peignoirs'): 30,
  }, note: 'Pour les suites');
  today(220);
  await as('amina');
  String linaRequest() =>
      data.requests.firstWhere((r) => r.agentId == 'lina').id;
  final linaId = linaRequest();
  await data.approveRequest(data.requests.firstWhere((r) => r.id == linaId));
  today(228);
  await data.prepareRequest(data.requests.firstWhere((r) => r.id == linaId));
  today(235);
  await data.deliverRequest(data.requests.firstWhere((r) => r.id == linaId));
  await data.refuseRequest(
    data.requests.firstWhere((r) => r.agentId == 'youssef'),
    'Stock de peignoirs réservé aux suites occupées',
  );

  // Minibar of the occupied rooms; 101 billed, 401 waiting.
  today(250);
  await as('sarah');
  await data.recordMinibar(room('101'), supply('Eau minérale 50 cl'), 2);
  await data.recordMinibar(room('101'), supply('Chocolat noir'), 1);
  await as('amina');
  await data.recordMinibar(room('401'), supply('Champagne 20 cl'), 1);
  await data.recordMinibar(room('401'), supply('Coca-Cola 33 cl'), 2);
  today(260);
  await data.postMinibar('101', [
    for (final e in data.minibar)
      if (e.roomNumber == '101') e,
  ]);

  // Laundry out this afternoon, a delivery of paper, Youssef off tomorrow.
  today(290);
  await data.sendLaundry({
    supply('Housses de couette'): 20,
    supply('Taies d’oreiller'): 40,
  }, note: 'Lot du jour');
  today(300);
  await data.moveStock(supply('Papier toilette'), 96);
  today(310);
  await data.setAvailability('youssef', day(1), available: false, minutes: 0);

  await data.refresh();
  final summary =
      '${data.rooms.length} chambres, ${data.cleanings.length} nettoyages, '
      '${data.issues.length} signalements, ${data.lostItems.length} objets, '
      '${data.supplies.length} articles, ${data.requests.length} demandes';
  data.dispose();
  return summary;
}
