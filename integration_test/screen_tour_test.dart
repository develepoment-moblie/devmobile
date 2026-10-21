import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:nova_paris/app/modules.dart';
import 'package:nova_paris/app/nova_app.dart';
import 'package:nova_paris/housekeeping/housekeeping_module.dart';
import 'package:nova_paris/housekeeping/services/mutation_meta.dart';
import 'package:nova_paris/housekeeping/services/sqlite_housekeeping.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

// Visits the main screens on a real phone and saves a screenshot of each.
// It uses its own database file (nova_paris_tour.db, recreated each run),
// so the phone's real data is never read or changed.
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/screen_tour_test.dart -d <device>
// Screenshots: build/screen_tour/*.png
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('screen tour', (tester) async {
    final path = p.join(await getDatabasesPath(), 'nova_paris_tour.db');
    await deleteDatabase(path);
    final database = await AppDatabase.open(
      schemas: [for (final module in novaModules) ?module.schema],
      path: path,
    );
    final session = AppSession(
      database: database,
      staff: userManagement.staffDirectory,
    );
    attachModules(session);
    await binding.convertFlutterSurfaceToImage();
    // A cleaning awaiting inspection in the tour database: Amina assigns
    // room 101 to Sarah, who does every task with a photo and submits.
    final staff = await session.staff.users();
    final rules = SqliteHousekeeping(housekeepingStoreFor(session));
    final photo = base64Encode(
      img.encodeJpg(img.Image(width: 16, height: 12), quality: 70),
    );
    Future<Map> room101() async =>
        ((await rules.snapshot())['rooms'] as List).firstWhere(
          (r) => r['number'] == '101',
        ) as Map;
    Future<void> as(
      String id,
      String action, [
      Map<String, dynamic>? extra,
    ]) async {
      session.signIn(staff.firstWhere((u) => u.id == id));
      await rules.mutate('/v1/rooms/101/$action', {
        ...mutationMeta(),
        'version': (await room101())['version'],
        ...?extra,
      });
    }

    await as('amina', 'assign', {
      'employeeId': 'sarah',
      'note': '',
      'urgent': false,
    });
    await as('sarah', 'start');
    for (var i = 0; i < ((await room101())['tasks'] as List).length; i++) {
      await as('sarah', 'checklist', {
        'index': i,
        'value': true,
        'photo': photo,
      });
    }
    await as('sarah', 'submit');
    session.signOut();

    await tester.pumpWidget(NovaApp(session: session));

    var step = 0;
    Future<void> shot(String name) async {
      // Let animations and SQLite reads finish on the device.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await binding.takeScreenshot(
        '${(++step).toString().padLeft(2, '0')}_$name',
      );
    }

    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder.first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(finder.first);
      await tester.pump(const Duration(milliseconds: 600));
    }

    Future<void> back() async {
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 700));
    }

    Future<void> signIn(String name) async {
      await tap(find.text(name));
      await tap(find.text('Entrer · $name'));
      await shot('home_$name');
    }

    Future<void> signOut() async {
      await tap(find.byTooltip('Mon profil'));
      await tap(find.text('Se déconnecter'));
      await tester.pump(const Duration(seconds: 1));
    }

    await shot('login');

    // Supervisor.
    await signIn('Amina');
    await tap(find.text('Chambres et ménage'));
    await shot('supervisor_home');
    for (final tab in ['Chambres', 'Stock', 'Ménage']) {
      await tap(find.text(tab).last);
      await shot('supervisor_${tab.toLowerCase()}');
    }
    await tap(find.text('Stock').last);
    await tap(find.textContaining('Blanchisserie'));
    await shot('laundry');
    await back();
    await tap(find.textContaining('Minibar ·'));
    await shot('minibar_billing');
    await back();
    await tap(find.text('Chambres').last);
    await tap(find.text('Chambre 101'));
    await shot('room_101_review');
    await tap(find.text('Inspecter le nettoyage'));
    await shot('inspection');
    await back();
    await back();
    await tap(find.text('Chambre 112'));
    await shot('room_112_occupied');
    await tap(find.text('Signaler un problème'));
    await shot('report_issue');
    await back();
    await back();
    await tap(find.text('Accueil').last);
    await tap(find.text('Signalements'));
    await shot('issues');
    await tap(find.text('Chambre 224 · Autre'));
    await shot('issue_detail');
    await back();
    await back();
    await tap(find.text('Objets trouvés'));
    await shot('lost_items');
    await back();
    await tap(find.text('Statistiques'));
    await shot('statistics');
    await back();
    await tap(find.byTooltip('Retour à l’accueil'));
    await tester.pump(const Duration(milliseconds: 600));
    await signOut();

    // Agent.
    await signIn('Sarah');
    await tap(find.text('Chambres et ménage'));
    await shot('agent_dashboard');
    await tap(find.text('Chambre 214'));
    await shot('agent_room_214');
    await tap(find.textContaining('Minibar'));
    await shot('agent_minibar_214');
    await back();
    await back();
    await tap(find.textContaining('Mes demandes de fournitures'));
    await shot('agent_supply_requests');
    await back();
    await tap(find.byTooltip('Retour à l’accueil'));
    await tester.pump(const Duration(milliseconds: 600));
    await signOut();

    // Manager: floors, a floor's rooms, a room, adding rooms, task lists.
    await signIn('Manager');
    await tap(find.text('Chambres et ménage'));
    await shot('manager_floors');
    await tap(find.text('Étage 3'));
    await shot('manager_floor_3');
    await tap(find.text('305'));
    await shot('manager_room_sheet');
    await back();
    await tap(find.text('Ajouter des chambres'));
    await shot('manager_add_rooms');
    await back();
    await back();
    await tap(find.text('Tâches'));
    await shot('manager_category_tasks');
    await back();
    await tap(find.textContaining('Carte du minibar'));
    await shot('manager_minibar');
    await back();
    await back();
    await signOut();
    await database.close();
    await deleteDatabase(path);
  });
}
