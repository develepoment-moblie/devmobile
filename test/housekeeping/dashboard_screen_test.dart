import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/housekeeping/models/dashboard_data.dart';
import 'package:nova_paris/housekeeping/screens/dashboard_screen.dart';
import 'package:nova_paris/housekeeping/services/hotel_event_handlers.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_store.dart';
import 'package:nova_paris/shared/custom/app_theme.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_events.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'housekeeping_store_test.dart' show TestStaff;

// The dashboard on a real database: figures shown, and an update without
// polling when another module's event changes a room.
void main() {
  late Directory directory;
  late AppSession session;
  late HousekeepingStore store;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nova_dashboard_');
    final database = await AppDatabase.open(
      schemas: [housekeepingSchema],
      factory: databaseFactoryFfi,
      path: p.join(directory.path, 'test.db'),
    );
    session = AppSession(database: database, staff: TestStaff());
    store = HousekeepingStore(session);
    listenToHotelEvents(session.events, store);
  });
  tearDown(() async {
    await session.database.close();
    await directory.delete(recursive: true);
  });

  // SQLite runs outside the widget test clock: wait for [finder].
  Future<void> settleUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Finder tile(String label, String value) => find.ancestor(
    of: find.text(value),
    matching: find.ancestor(
      of: find.text(label),
      matching: find.byType(Column),
    ),
  );

  testWidgets('the Manager sees the figures, updated by an event', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    session.signIn(TestStaff.people.firstWhere((u) => u.id == 'manager'));
    final dashboard = DashboardData(store);
    await tester.pumpWidget(
      MaterialApp(
        theme: novaTheme(),
        home: DashboardScreen(dashboard: dashboard),
      ),
    );
    await settleUntil(tester, find.text('Chambres · 16'));
    expect(find.text('Tableau de bord'), findsOneWidget);
    expect(find.text('Chambres · 16'), findsOneWidget);
    expect(tile('Chambres à nettoyer', '12'), findsWidgets);
    expect(find.text('Signalements ouverts'), findsWidgets);
    expect(find.text('Aucun nettoyage validé sur la période.'), findsOneWidget);
    expect(find.textContaining('Chambre 224'), findsOneWidget);

    // Reservations checks a guest out: no refresh call, no timer.
    session.events.emit(const GuestCheckedOut('402'));
    await settleUntil(tester, tile('Chambres à nettoyer', '13'));
    expect(tile('Chambres à nettoyer', '13'), findsWidgets);

    await tester.tap(find.text('7 jours'));
    await settleUntil(tester, find.text('Chambres · 16'));
    expect(dashboard.days, 7);
    await tester.pumpWidget(const SizedBox());
    dashboard.dispose();
  });

  testWidgets('an agent is refused', (tester) async {
    session.signIn(TestStaff.people.firstWhere((u) => u.id == 'sarah'));
    final dashboard = DashboardData(store);
    await tester.pumpWidget(
      MaterialApp(
        theme: novaTheme(),
        home: DashboardScreen(dashboard: dashboard),
      ),
    );
    await settleUntil(tester, find.textContaining('réservé'));
    expect(
      find.text('Tableau de bord réservé à la gouvernante et au manager.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    dashboard.dispose();
  });
}
