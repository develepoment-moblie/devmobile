import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/housekeeping/custom/catalog_widgets.dart';
import 'package:nova_paris/housekeeping/models/hotel_data.dart';
import 'package:nova_paris/housekeeping/screens/details_screen.dart';
import 'package:nova_paris/housekeeping/screens/housekeeping_workspace.dart';
import 'package:nova_paris/housekeeping/screens/lost_items_screen.dart';
import 'package:nova_paris/housekeeping/screens/manage_rooms_screen.dart';
import 'package:nova_paris/housekeeping/screens/stats_screen.dart';
import 'package:nova_paris/housekeeping/services/sqlite_room_catalog.dart';
import 'package:nova_paris/shared/custom/app_theme.dart';

import 'memory_store.dart';
import 'photo_fixture.dart';

// The new screens, on the in-memory store running the real rules.
void main() {
  Future<void> show(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: novaTheme(), home: home));
    await tester.pumpAndSettle();
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    if (find.text(text).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.text(text),
        250,
        scrollable: find.byType(Scrollable).first,
      );
    }
    final target = find.text(text).last;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('the manager browses floors, opens a room and adds a floor', (
    tester,
  ) async {
    final store = MemoryStore()..signIn('manager');
    await show(tester, ManageRoomsScreen(backend: SqliteRoomCatalog(store)));
    expect(find.text('Étages et chambres'), findsOneWidget);
    for (final floor in ['Étage 1', 'Étage 2', 'Étage 3', 'Étage 4']) {
      expect(find.text(floor), findsOneWidget);
    }
    await tapText(tester, 'Étage 1');
    expect(find.byType(RoomTile), findsWidgets);
    await tester.tap(find.text('101'));
    await tester.pumpAndSettle();
    expect(find.text('Chambre 101'), findsOneWidget);
    expect(find.text('Modifier la catégorie'), findsOneWidget);
    expect(find.text('QR code de la porte'), findsOneWidget);
    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tapText(tester, 'Ajouter des chambres');
    // The first floor without rooms is proposed: 5.
    expect(find.text('Étage 5'), findsWidgets);
    await tester.enterText(find.widgetWithText(TextFormField, 'De'), '01');
    await tester.enterText(find.widgetWithText(TextFormField, 'À'), '06');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Catégorie'),
      'Suite',
    );
    await tester.pumpAndSettle();
    expect(find.text('Chambres 501 à 506 · 6 chambres'), findsOneWidget);
    await tapText(tester, 'Créer');
    expect(find.text('6 chambres créées · nettoyage requis'), findsOneWidget);
    expect(find.text('Étage 5'), findsOneWidget);
    expect(
      (store.state['rooms'] as List).where(
        (r) => '${r['number']}'.startsWith('5'),
      ),
      hasLength(6),
    );
  });

  testWidgets('the supervisor adds a stock item from the Stock tab', (
    tester,
  ) async {
    final data = await loadAs(MemoryStore(), 'amina');
    await show(tester, HousekeepingWorkspace(data: data, agent: false));
    await tapText(tester, 'Stock');
    await tapText(tester, 'Nouvel article');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Article'),
      'Gants',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Unité'),
      'paires',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Quantité en stock'),
      '3',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Seuil d’alerte'),
      '5',
    );
    await tapText(tester, 'Ajouter');
    expect(find.text('Article ajouté au stock'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Gants'), 200);
    expect(find.text('Gants'), findsOneWidget);
    expect(find.text('Stock bas'), findsWidgets);
    data.dispose();
  });

  testWidgets(
    'inspection: a failed item sends the room back; the agent sees why',
    (tester) async {
      final store = MemoryStore()..submitted('109', 'sarah');
      final data = await loadAs(store, 'amina');
      await show(
        tester,
        DetailsScreen(data: data, room: data.roomByNumber('109')),
      );
      await tapText(tester, 'Inspecter le nettoyage');
      expect(find.text('Inspection · 109'), findsOneWidget);
      expect(find.text('Conforme'), findsOneWidget);
      // The bed linen is not compliant: 3 of 4 items OK = 75 < 80.
      await tester.tap(find.text('Non conforme').first);
      await tester.pumpAndSettle();
      expect(find.text('Insuffisant'), findsOneWidget);
      final approve = find.widgetWithText(FilledButton, 'Valider le nettoyage');
      await tester.scrollUntilVisible(
        approve,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.widget<FilledButton>(approve).onPressed, isNull);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ce qui ne va pas'),
        'Traces sur le miroir',
      );
      await tapText(tester, 'Renvoyer en nettoyage');
      expect(
        find.textContaining('À refaire : Changer le linge de lit'),
        findsOneWidget,
      );
      await tapText(tester, 'Renvoyer');
      expect(find.text('Chambre renvoyée en nettoyage'), findsOneWidget);
      final room = store.room('109');
      expect(
        (room['cleaning'], room['employeeId'], room['urgent']),
        ('inProgress', 'sarah', true),
      );
      expect((store.state['inspections'] as List).single['score'], 75);
      data.dispose();

      // Sarah reopens the room: what failed and why.
      await tester.pumpWidget(const SizedBox());
      final agent = await loadAs(store, 'sarah');
      await show(
        tester,
        DetailsScreen(data: agent, room: agent.roomByNumber('109')),
      );
      expect(find.text('À reprendre'), findsOneWidget);
      expect(find.text('Non conforme'), findsOneWidget);
      expect(find.text('Traces sur le miroir'), findsOneWidget);
      expect(find.text('Changer le linge de lit'), findsWidgets);
      agent.dispose();
    },
  );

  testWidgets('inspection: everything OK approves the cleaning', (
    tester,
  ) async {
    final store = MemoryStore()..submitted('109', 'sarah');
    final data = await loadAs(store, 'amina');
    await show(
      tester,
      DetailsScreen(data: data, room: data.roomByNumber('109')),
    );
    await tapText(tester, 'Inspecter le nettoyage');
    await tapText(tester, 'Valider le nettoyage');
    expect(find.text('Nettoyage validé · chambre libre'), findsOneWidget);
    expect(store.room('109')['status'], 'ready');
    final round = (store.state['inspections'] as List).single;
    expect((round['score'], round['outcome']), (100, 'approved'));
    data.dispose();
  });

  testWidgets('statistics and lost and found screens show the log', (
    tester,
  ) async {
    final store = MemoryStore();
    final supervisor = await loadAs(store, 'amina');
    await supervisor.assign(supervisor.roomByNumber('305'), 'sarah', '', false);
    final agent = await loadAs(store, 'sarah');
    final room = agent.roomByNumber('305');
    await agent.startCleaning(room);
    for (final task in agent.roomByNumber('305').tasks) {
      final r = agent.roomByNumber('305');
      await agent.completeTask(r, task.id, photoBytes(), r.version);
    }
    await agent.submitCleaning(agent.roomByNumber('305'));
    await agent.recordLostItem(agent.roomByNumber('214'), 'Montre');
    store.signIn('amina');
    await supervisor.refresh();
    await supervisor.approve(supervisor.roomByNumber('305'));

    await show(tester, StatsScreen(data: supervisor));
    expect(find.text('Statistiques du ménage'), findsOneWidget);
    expect(find.text('Sarah'), findsOneWidget);
    expect(find.text('1 validé'), findsOneWidget);

    await show(tester, LostItemsScreen(data: supervisor));
    expect(find.text('Montre'), findsOneWidget);
    await tapText(tester, 'Rendre');
    await tester.enterText(find.byType(TextFormField), 'Mme Durand');
    await tapText(tester, 'Confirmer la restitution');
    expect(find.text('Objet restitué'), findsOneWidget);
    await tapText(tester, 'Rendus · 1');
    expect(find.textContaining('Rendu à Mme Durand'), findsOneWidget);
    for (final d in <HotelData>[supervisor, agent]) {
      d.dispose();
    }
  });
}
