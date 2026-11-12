import 'package:nova_paris/guest_services/screens/agent_deliveries_screen.dart';
import 'package:nova_paris/guest_services/screens/kitchen_orders_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/shared/custom/app_theme.dart';
import 'package:nova_paris/shared/models/app_user.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:nova_paris/shared/services/staff_directory.dart';
import 'package:nova_paris/guest_services/models/room_service.dart';
import 'package:nova_paris/guest_services/services/guest_service_store.dart';
import 'package:nova_paris/guest_services/screens/guest_services_home_screen.dart';
import 'package:nova_paris/guest_services/screens/reception_orders_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Staff implements StaffDirectory {
  @override
  Future<List<AppUser>> users({Set<String>? roles}) async => [
    const AppUser(id: 'sarah', fullName: 'Sarah', role: AppRole.staff),
  ];
}

void main() {
  setUpAll(sqfliteFfiInit);
  testWidgets(
    'client can confirm a saved cart and view its order on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final database = (await tester.runAsync(
        () => AppDatabase.open(
          schemas: [GuestServiceStore.schema],
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        ),
      ))!;
      await tester.runAsync(() async {
        for (final item in roomServiceMenu) {
          await database.database.insert('guest_services_menu', {
            ...item.toRow(),
            'portions': 20,
          });
        }
        for (final category in roomServiceMenu.map((i) => i.category).toSet()) {
          await database.database.insert('guest_services_categories', {
            'name': category,
          });
        }
        await database.database.insert('guest_services_stays', {
          'id': 'test-stay',
          'guest_id': 'guest',
          'guest_name': 'Client',
          'room_number': '305',
          'active': 0,
        });
        await database.database.update(
          'guest_services_stays',
          {
            'active': 1,
            'valid_until': DateTime.now()
                .add(const Duration(days: 2))
                .toUtc()
                .toIso8601String(),
            'verified_by': 'test-reception',
          },
          where: 'guest_id = ?',
          whereArgs: ['guest'],
        );
      });
      final session = AppSession(database: database, staff: _Staff())
        ..signIn(
          const AppUser(
            id: 'guest',
            fullName: 'Client Démo',
            role: AppRole.guest,
          ),
        );
      addTearDown(() async {
        await session.events.dispose();
        session.dispose();
        await database.close();
      });
      await tester.runAsync(
        () => GuestServiceStore(
          session,
        ).saveCart([const CartLine('coffee', 2, 'Sans sucre')]),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: novaTheme(),
          home: GuestServicesHomeScreen(session: session),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mon panier'));
      await tester.pumpAndSettle();
      expect(find.text('Sans sucre'), findsOneWidget);
      await tester.tap(find.text('Confirmer · 10,00 €'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Commande #1'), findsOneWidget);
      expect(find.text('Enregistrée · en attente'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.signIn(
        const AppUser(
          id: 'reception',
          fullName: 'Inès',
          role: AppRole.receptionist,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: novaTheme(),
          home: ReceptionOrdersScreen(session: session),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('Chambre 305'), findsOneWidget);
      await tester.ensureVisible(find.text('Accepter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accepter'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sarah'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.text('En préparation'), findsOneWidget);
      expect(find.text('Agent : Sarah'), findsOneWidget);
      expect(find.text('Marquer comme livrée'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      session.signIn(
        const AppUser(id: 'sarah', fullName: 'Sarah', role: AppRole.staff),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: novaTheme(),
          home: AgentDeliveriesScreen(store: GuestServiceStore(session)),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('Chambre 305'), findsOneWidget);
      expect(find.textContaining('Attendez la confirmation'), findsOneWidget);
      expect(find.text('Marquer comme livrée'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      session.signIn(
        const AppUser(
          id: 'kitchen',
          fullName: 'Cuisine',
          role: AppRole.kitchen,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: novaTheme(),
          home: KitchenOrdersScreen(store: GuestServiceStore(session)),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('Sans sucre'), findsOneWidget);
      await tester.tap(find.text('Marquer prête à livrer'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.text('Prête à livrer'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      session.signIn(
        const AppUser(id: 'sarah', fullName: 'Sarah', role: AppRole.staff),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: novaTheme(),
          home: AgentDeliveriesScreen(store: GuestServiceStore(session)),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.text('Prête à livrer'), findsOneWidget);
      await tester.tap(find.text('Marquer comme livrée'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('Livrée le'), findsOneWidget);
      expect(find.text('Livraison enregistrée.'), findsOneWidget);
      expect(find.text('Impossible d’enregistrer la livraison.'), findsNothing);
      await tester.runAsync(
        () => database.database.insert('guest_services_orders', {
          'id': 99,
          'guest_id': 'guest',
          'created_at': '2000-01-01T12:00:00',
          'lines': '[]',
          'total_cents': 500,
          'status': 'delivered',
        }),
      );
      await tester.pumpWidget(const SizedBox());
      session.signIn(
        const AppUser(
          id: 'reception',
          fullName: 'Reception',
          role: AppRole.receptionist,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: novaTheme(),
          home: ReceptionOrdersScreen(session: session),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('Terminées'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.textContaining(RegExp(r'^Commande #')).first)
            .data,
        startsWith('Commande #1 ·'),
      );
      expect(find.textContaining('Livrée par Sarah'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
