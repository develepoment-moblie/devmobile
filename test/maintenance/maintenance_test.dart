import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/maintenance/models/intervention.dart';
import 'package:nova_paris/maintenance/screens/intervention_detail_screen.dart';
import 'package:nova_paris/maintenance/screens/maintenance_home_screen.dart';
import 'package:nova_paris/maintenance/services/maintenance_store.dart';
import 'package:nova_paris/shared/models/app_user.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:nova_paris/user_management/services/demo_staff_directory.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _karim = AppUser(
  id: 'karim',
  fullName: 'Karim Technicien',
  role: AppRole.maintenance,
);
const _sarah = AppUser(id: 'sarah', fullName: 'Sarah', role: AppRole.staff);
const _manager = AppUser(
  id: 'manager',
  fullName: 'Manager Démo',
  role: AppRole.manager,
);

void main() {
  late Directory directory;
  late AppSession session;
  late MaintenanceStore store;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    // The weather check ran just now: the screens never call Open-Meteo here.
    SharedPreferences.setMockInitialValues({
      'maintenance_weather_last_check': DateTime.now().millisecondsSinceEpoch,
    });
    directory = await Directory.systemTemp.createTemp('nova_maintenance_');
    final database = await AppDatabase.open(
      schemas: [maintenanceSchema],
      factory: databaseFactoryFfi,
      path: p.join(directory.path, 'nova.db'),
    );
    session = AppSession(database: database, staff: const DemoStaffDirectory());
    store = MaintenanceStore(database.database);
  });
  tearDown(() async {
    await session.database.close();
    await directory.delete(recursive: true);
  });

  Future<int> report(String title, InterventionPriority priority) =>
      store.create(
        title: title,
        room: '305',
        category: InterventionCategory.climatisation,
        priority: priority,
        reporter: _sarah,
      );

  group('store', () {
    test('active lists urgent first, history lists the resolved', () async {
      final normal = await report('Télévision', InterventionPriority.normal);
      final urgent = await report('Climatisation', InterventionPriority.urgent);
      await report('Fuite', InterventionPriority.high);

      final active = await store.active();
      expect(active.map((i) => i.title), [
        'Climatisation',
        'Fuite',
        'Télévision',
      ]);
      expect(active.first.reporterName, 'Sarah');
      expect(active.first.status, InterventionStatus.pending);

      await store.takeCharge(urgent, _karim);
      await store.markResolved(urgent);
      expect((await store.active()).map((i) => i.id), isNot(contains(urgent)));
      final history = await store.resolved();
      expect(history.single.id, urgent);
      expect(history.single.assigneeName, 'Karim Technicien');
      expect(history.single.resolvedAt, isNotNull);

      expect((await store.byId(normal))!.isResolved, isFalse);
    });

    test('take charge assigns the technician and starts the work', () async {
      final id = await report('Clim', InterventionPriority.urgent);
      await store.takeCharge(id, _karim);
      final item = (await store.byId(id))!;
      expect(item.status, InterventionStatus.inProgress);
      expect(item.assigneeId, 'karim');
      expect(item.assigneeFirstName, 'Karim');
    });

    test('photos are kept with the report and removed with it', () async {
      final id = await store.create(
        title: 'Fuite',
        room: '118',
        category: InterventionCategory.plomberie,
        priority: InterventionPriority.high,
        photos: [
          Uint8List.fromList([1, 2, 3]),
        ],
      );
      await store.addPhoto(id, Uint8List.fromList([4, 5]));
      expect(await store.photos(id), [
        [1, 2, 3],
        [4, 5],
      ]);

      await store.delete(id);
      expect(await store.byId(id), isNull);
      expect(await store.photos(id), isEmpty);
    });
  });

  group('screens', () {
    // The screens read SQLite for real, so let that I/O run between frames.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
      }
    }

    Future<void> pump(WidgetTester tester, Widget screen) async {
      await tester.pumpWidget(MaterialApp(home: screen));
      await settle(tester);
    }

    testWidgets('a staff member reports a problem from the home screen', (
      tester,
    ) async {
      session.signIn(_sarah);
      await pump(tester, MaintenanceHomeScreen(session: session));
      expect(find.text('Aucune intervention en cours.'), findsOneWidget);

      await tester.tap(find.text('Signaler un problème'));
      await settle(tester);
      await tester.enterText(find.byType(TextFormField).at(0), '412');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Ampoule grillée',
      );
      await tester.tap(find.text('Électricité'));
      await tester.ensureVisible(find.text('Envoyer le signalement'));
      await tester.tap(find.text('Envoyer le signalement'));
      await settle(tester);

      expect(find.text('Ampoule grillée'), findsOneWidget);
      expect(find.text('1 intervention active'), findsOneWidget);
      final saved = (await tester.runAsync(store.active))!.single;
      expect(saved.room, '412');
      expect(saved.category, InterventionCategory.electricite);
      expect(saved.reporterId, 'sarah');
    });

    testWidgets('the technician takes charge then resolves', (tester) async {
      final id = (await tester.runAsync(
        () => report('Clim', InterventionPriority.urgent),
      ))!;
      session.signIn(_karim);
      await pump(
        tester,
        InterventionDetailScreen(session: session, interventionId: id),
      );
      expect(find.text('Supprimer'), findsNothing);

      await tester.ensureVisible(find.text('Prendre en charge'));
      await tester.tap(find.text('Prendre en charge'));
      await settle(tester);
      expect(find.text('Karim Technicien'), findsOneWidget);

      await tester.ensureVisible(find.text('Marquer comme résolu'));
      await tester.tap(find.text('Marquer comme résolu'));
      await settle(tester);
      final item = (await tester.runAsync(() => store.byId(id)))!;
      expect(item.status, InterventionStatus.resolved);
    });

    testWidgets('the manager assigns a technician from the staff list', (
      tester,
    ) async {
      final id = (await tester.runAsync(
        () => report('Fuite', InterventionPriority.high),
      ))!;
      session.signIn(_manager);
      await pump(
        tester,
        InterventionDetailScreen(session: session, interventionId: id),
      );

      await tester.ensureVisible(find.text('Attribuer à un technicien'));
      await tester.tap(find.text('Attribuer à un technicien'));
      await settle(tester);
      await tester.tap(find.text('Karim Technicien').last);
      await settle(tester);

      final item = (await tester.runAsync(() => store.byId(id)))!;
      expect(item.assigneeId, 'karim');
      expect(item.status, InterventionStatus.pending);
    });
  });
}
