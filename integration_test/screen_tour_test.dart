import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nova_paris/app/modules.dart';
import 'package:nova_paris/app/nova_app.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_session.dart';

// Visits the main screens on a real phone and saves a screenshot of each.
// Navigation only: no data is changed.
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/screen_tour_test.dart -d <device>
// Screenshots: build/screen_tour/*.png
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('screen tour', (tester) async {
    final database = await AppDatabase.open(
      schemas: [for (final module in novaModules) ?module.schema],
    );
    final session = AppSession(
      database: database,
      staff: userManagement.staffDirectory,
    );
    attachModules(session);
    await binding.convertFlutterSurfaceToImage();
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
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> signIn(String name) async {
      await tap(find.text(name));
      await tap(find.text('Entrer · $name'));
      await shot('home_$name');
    }

    Future<void> signOut() async {
      await tap(find.byTooltip('Mon profil'));
      await shot('profile');
      await tap(find.text('Se déconnecter'));
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> back() async {
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 600));
    }

    await shot('login');
    await tap(find.text('Entrer (mode test)'));
    await shot('login_error');

    // Supervisor: every workspace tab and one room.
    await signIn('Amina');
    await tap(find.text('Chambres et ménage'));
    await shot('supervisor_home');
    for (final tab in ['Départs', 'Chambres', 'Stock', 'Ménage']) {
      await tap(find.text(tab).last);
      await shot('supervisor_${tab.toLowerCase()}');
    }
    await tap(find.text('Chambres').last);
    await tap(find.text('Chambre 101'));
    await shot('room_101');
    await back();
    await tap(find.byTooltip('Notifications'));
    await shot('notifications');
    await back();
    await tap(find.byTooltip('Retour à l’accueil'));
    await tester.pump(const Duration(milliseconds: 600));
    await signOut();

    // Agent.
    await signIn('Sarah');
    await tap(find.text('Chambres et ménage'));
    await shot('agent_dashboard');
    await tap(find.text('Mes chambres').last);
    await shot('agent_rooms');
    await tap(find.text('Chambre 214'));
    await shot('agent_room_214');
    await back();
    await tap(find.byTooltip('Retour à l’accueil'));
    await tester.pump(const Duration(milliseconds: 600));
    await signOut();

    // Manager: room catalog, then a module still under construction.
    await signIn('Manager');
    await tap(find.text('Chambres et ménage'));
    await shot('manager_catalog');
    await back();
    await tap(find.text('Réservations'));
    await shot('placeholder');
    await back();
    await signOut();
    await database.close();
  });
}
