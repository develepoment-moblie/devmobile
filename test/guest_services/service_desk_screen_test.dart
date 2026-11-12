import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/shared/custom/app_theme.dart';
import 'package:nova_paris/shared/models/app_user.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:nova_paris/shared/services/staff_directory.dart';
import 'package:nova_paris/guest_services/screens/service_desk_screen.dart';
import 'package:nova_paris/guest_services/services/guest_service_store.dart';
import 'package:nova_paris/guest_services/services/service_desk_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Staff implements StaffDirectory {
  @override
  Future<List<AppUser>> users({Set<String>? roles}) async => [];
}

void main() {
  late AppSession session;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    final db = await AppDatabase.open(
      schemas: [GuestServiceStore.schema],
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    session = AppSession(database: db, staff: _Staff())
      ..signIn(
        const AppUser(id: 'alice', fullName: 'Alice', role: AppRole.guest),
      );
  });
  tearDown(() async {
    await session.events.dispose();
    session.dispose();
    await session.database.close();
  });
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'client creates a special request and sends a message at phone size',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: novaTheme(),
          home: ServiceDeskScreen(session: session),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Demande spéciale'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nouvelle demande'));
      await settle(tester);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Transport aéroport',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Une voiture pour deux personnes',
      );
      await tester.ensureVisible(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer'));
      await settle(tester);
      await settle(tester);
      expect(find.byType(TextFormField), findsNothing);
      await tester.scrollUntilVisible(
        find.textContaining('Transport aéroport'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Transport aéroport'), findsOneWidget);
      await tester.tap(find.textContaining('Transport aéroport'));
      await settle(tester);
      await tester.ensureVisible(find.text('Écrire un message'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Écrire un message'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField),
        'Merci de confirmer le prix',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await settle(tester);
      expect(find.text('Merci de confirmer le prix'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('manager can create a restaurant slot from an empty catalogue', (
    tester,
  ) async {
    session.signIn(
      const AppUser(
        id: 'manager',
        fullName: 'Direction',
        role: AppRole.manager,
      ),
    );
    final store = ServiceDeskStore(session);
    await tester.pumpWidget(
      MaterialApp(
        theme: novaTheme(),
        home: SlotManagementScreen(store: store),
      ),
    );
    await settle(tester);
    expect(find.text('Aucun créneau'), findsOneWidget);
    await tester.tap(find.text('Créer un créneau'));
    await tester.pumpAndSettle();
    expect(find.text('Établissement, salle ou cabine'), findsOneWidget);
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Nom obligatoire'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
