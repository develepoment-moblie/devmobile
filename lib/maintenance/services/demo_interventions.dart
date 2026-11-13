import 'package:flutter/services.dart';

import '../../shared/models/app_user.dart';
import '../../shared/services/app_session.dart';
import '../models/intervention.dart';
import 'maintenance_store.dart';

// Demo interventions for the presentation, made through MaintenanceStore
// (create, take charge, assign, resolve) by the test accounts. They match the
// problems the housekeeping demo reports: air conditioning in 305, the
// bathroom light in 302, the broken bed in 106 (already repaired).
// Build with --dart-define=NOVA_DEMO_DATA=true (and WEATHER_DEMO=true for
// the weather alerts); filled once, only while there are no interventions.

/// Build option: demo data in every module.
const novaDemoData = bool.fromEnvironment('NOVA_DEMO_DATA');

/// A photo of the shared demo pictures, or none when it cannot be read.
typedef DemoPhoto = Future<Uint8List?> Function(String name);

Future<Uint8List?> _assetPhoto(String name) async {
  try {
    final data = await rootBundle.load('assets/images/demo_hotel/$name');
    return data.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

/// Returns the number of interventions made (0 when there were some already).
Future<int> fillDemoInterventions(
  AppSession session, {
  DemoPhoto photo = _assetPhoto,
}) async {
  final db = session.database.database;
  final count =
      (await db.rawQuery(
            'SELECT COUNT(*) AS n FROM maintenance_interventions',
          )).single['n']
          as int;
  if (count > 0) return 0;

  final people = {for (final u in await session.staff.users()) u.id: u};
  AppUser person(String id, String name, String role) =>
      people[id] ?? AppUser(id: id, fullName: name, role: role);
  final amina = person('amina', 'Amina', AppRole.supervisor);
  final lina = person('lina', 'Lina', AppRole.staff);
  final sarah = person('sarah', 'Sarah', AppRole.staff);
  final reception = person('reception', 'Inès Réception', AppRole.receptionist);
  final karim = person('karim', 'Karim Technicien', AppRole.maintenance);

  final store = MaintenanceStore(db);
  final drain = await photo('issue_drain.jpg');
  var made = 0;
  Future<int> report(
    String room,
    String title,
    InterventionCategory category,
    InterventionPriority priority,
    AppUser reporter, {
    String description = '',
    Uint8List? picture,
  }) {
    made++;
    return store.create(
      title: title,
      room: room,
      category: category,
      priority: priority,
      description: description,
      reporter: reporter,
      photos: [?picture],
    );
  }

  // Already repaired (history).
  final shower = await report(
    '203',
    'Douche bouchée',
    InterventionCategory.plomberie,
    InterventionPriority.high,
    sarah,
    description: 'L’eau ne s’écoule plus dans la douche.',
    picture: drain,
  );
  await store.takeCharge(shower, karim);
  await store.markResolved(shower);
  final socket = await report(
    '108',
    'Prise électrique hors service',
    InterventionCategory.electricite,
    InterventionPriority.normal,
    reception,
    description: 'La prise près du bureau ne fonctionne plus.',
  );
  await store.takeCharge(socket, karim);
  await store.markResolved(socket);
  final bed = await report(
    '106',
    'Pied de lit cassé',
    InterventionCategory.autre,
    InterventionPriority.normal,
    amina,
    description: 'Chambre hors service jusqu’à la réparation.',
  );
  await store.takeCharge(bed, karim);
  await store.markResolved(bed);

  // In progress, waiting, assigned.
  final cooling = await report(
    '305',
    'Climatisation en panne',
    InterventionCategory.climatisation,
    InterventionPriority.urgent,
    amina,
    description:
        'La chambre reste à 28 °C, chambre hors service. Client à reloger.',
  );
  await store.takeCharge(cooling, karim);
  final leak = await report(
    '207',
    'Fuite sous le lavabo',
    InterventionCategory.plomberie,
    InterventionPriority.high,
    sarah,
    description: 'Une flaque se forme sous le meuble du lavabo.',
    picture: drain,
  );
  await store.assign(leak, karim);
  await report(
    '302',
    'Ampoule de la salle de bain',
    InterventionCategory.electricite,
    InterventionPriority.normal,
    lina,
    description: 'La lampe de la salle de bain ne s’allume plus.',
  );
  await report(
    '404',
    'Télévision qui ne s’allume plus',
    InterventionCategory.television,
    InterventionPriority.normal,
    reception,
    description: 'Signalé par le client de la suite à son arrivée.',
  );
  return made;
}
