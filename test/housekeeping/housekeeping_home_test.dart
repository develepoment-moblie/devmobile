import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/housekeeping/housekeeping_module.dart';
import 'package:nova_paris/housekeeping/screens/manage_rooms_screen.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_store.dart';
import 'package:nova_paris/shared/custom/app_theme.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'housekeeping_store_test.dart' show TestStaff;

void main() {
  late Directory directory;
  late AppSession session;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nova_hk_home_');
    final database = await AppDatabase.open(
      schemas: [housekeepingSchema],
      factory: databaseFactoryFfi,
      path: p.join(directory.path, 'test.db'),
    );
    session = AppSession(database: database, staff: TestStaff());
    const HousekeepingModule().attach(session);
  });
  tearDown(() async {
    await session.database.close();
    await directory.delete(recursive: true);
  });

  // SQLite runs outside the widget test clock.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  // Real SQLite takes longer when the whole suite runs in parallel: wait for
  // [finder] rather than a fixed time.
  Future<void> settleUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
      await settle(tester);
    }
  }

  Future<void> open(WidgetTester tester, String id, {Finder? until}) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    session.signIn(TestStaff.people.firstWhere((u) => u.id == id));
    await tester.pumpWidget(
      MaterialApp(
        theme: novaTheme(),
        home: Builder(
          builder: (context) =>
              const HousekeepingModule().buildHome(context, session),
        ),
      ),
    );
    await settleUntil(tester, until ?? find.byType(NavigationBar));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  testWidgets('the supervisor opens the workspace tabs and reports a problem', (
    tester,
  ) async {
    await open(tester, 'amina');
    for (final tab in ['Accueil', 'Départs', 'Chambres', 'Stock', 'Ménage']) {
      expect(find.text(tab), findsWidgets, reason: tab);
    }
    expect(find.text('Bonjour Amina.'), findsOneWidget);
    await tester.tap(find.text('Chambres').last);
    await tester.pump();
    await tester.tap(find.text('Chambre 101').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Signaler un problème'), 200);
    await tester.ensureVisible(find.text('Signaler un problème'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Signaler un problème'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plomberie'));
    await tester.enterText(find.byType(TextFormField), 'Fuite sous le lavabo');
    await tester.tap(find.text('Mettre la chambre hors service'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Envoyer le signalement'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Envoyer le signalement'));
    await settleUntil(tester, find.text('Problème signalé à la maintenance'));
    expect(find.text('Problème signalé à la maintenance'), findsOneWidget);
    final state = await tester.runAsync(
      () => housekeepingStoreFor(session).readState(),
    );
    final room = (state!['rooms'] as List).firstWhere(
      (r) => r['number'] == '101',
    );
    expect(room['status'], 'maintenance');
  });

  testWidgets('the header arrow leaves the module even after visiting tabs', (
    tester,
  ) async {
    session.signIn(TestStaff.people.firstWhere((u) => u.id == 'amina'));
    await tester.pumpWidget(
      MaterialApp(
        theme: novaTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (context) =>
                      const HousekeepingModule().buildHome(context, session),
                ),
              ),
              child: const Text('Accueil de l’app'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Accueil de l’app'));
    await settleUntil(tester, find.text('Stock'));
    await tester.tap(find.text('Stock').last);
    await tester.pump();
    await tester.tap(find.text('Ménage').last);
    await tester.pump();
    await tester.tap(find.byTooltip('Retour à l’accueil'));
    await tester.pumpAndSettle();
    expect(find.text('Accueil de l’app'), findsOneWidget);
    expect(find.text('Stock'), findsNothing);
  });

  testWidgets('the manager gets the room catalog', (tester) async {
    await open(tester, 'manager', until: find.byType(ManageRoomsScreen));
    expect(find.byType(ManageRoomsScreen), findsOneWidget);
  });

  testWidgets('an agent gets the personal workspace only', (tester) async {
    await open(tester, 'sarah');
    expect(find.text('Mon service'), findsWidgets);
    expect(find.text('Mes chambres'), findsWidgets);
    expect(find.text('Stock'), findsNothing);
  });
}
