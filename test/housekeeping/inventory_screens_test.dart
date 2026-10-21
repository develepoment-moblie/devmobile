import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/housekeeping/models/catalog_data.dart';
import 'package:nova_paris/housekeeping/screens/laundry_screen.dart';
import 'package:nova_paris/housekeeping/screens/minibar_catalog_screen.dart';
import 'package:nova_paris/housekeeping/screens/minibar_screen.dart';
import 'package:nova_paris/housekeeping/screens/stock_log_screen.dart';
import 'package:nova_paris/housekeeping/screens/supplies_screen.dart';
import 'package:nova_paris/housekeeping/screens/supply_requests_screen.dart';
import 'package:nova_paris/housekeeping/services/sqlite_room_catalog.dart';
import 'package:nova_paris/shared/custom/app_theme.dart';

import 'memory_store.dart';

// Laundry, supply requests, minibar, the usage log and the Manager's
// minibar catalog, on the in-memory store running the real rules.
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

  Future<void> type(WidgetTester tester, String key, String text) async {
    await tester.enterText(find.byKey(ValueKey(key)), text);
    await tester.pump();
  }

  int stock(MemoryStore store, String id) =>
      (store.state['supplies'] as List).firstWhere(
            (x) => x['id'] == id,
          )['quantity']
          as int;

  testWidgets('laundry: send, then return with damaged and lost linen', (
    tester,
  ) async {
    final store = MemoryStore();
    final data = await loadAs(store, 'amina');
    await show(tester, LaundryScreen(data: data));
    expect(find.text('Aucun linge en blanchisserie.'), findsOneWidget);
    await tapText(tester, 'Envoyer du linge');
    expect(find.text('Draps propres'), findsOneWidget);
    expect(find.text('Nettoyant multi-surfaces'), findsNothing);
    await type(tester, 'qty-sheets', '10');
    await tapText(tester, 'Envoyer');
    expect(find.text('Linge envoyé en blanchisserie'), findsOneWidget);
    expect(stock(store, 'sheets'), 32);
    expect(find.text('En blanchisserie'), findsOneWidget);

    await tapText(tester, 'Enregistrer le retour');
    await type(tester, 'Reçu-sheets', '8');
    await type(tester, 'Abîmé-sheets', '1');
    expect(find.text('Total : 9 / 10 · doit faire 10'), findsOneWidget);
    await type(tester, 'Perdu-sheets', '1');
    expect(find.text('Total : 10 / 10'), findsOneWidget);
    await tapText(tester, 'Enregistrer le retour');
    expect(find.text('Retour enregistré'), findsOneWidget);
    expect(stock(store, 'sheets'), 40);
    expect(
      find.text('Draps propres : 10 envoyés · 8 reçus · 1 abîmés · 1 perdus'),
      findsOneWidget,
    );
    data.dispose();
  });

  testWidgets('supply request: the agent asks, the supervisor delivers', (
    tester,
  ) async {
    final store = MemoryStore();
    final agent = await loadAs(store, 'sarah');
    await show(tester, SupplyRequestsScreen(data: agent));
    expect(find.text('Mes demandes'), findsOneWidget);
    await tapText(tester, 'Nouvelle demande');
    expect(find.text('Soda 33 cl'), findsNothing, reason: 'not the minibar');
    await type(tester, 'qty-soap', '5');
    await tapText(tester, 'Envoyer la demande');
    expect(find.text('Demande envoyée à la gouvernante'), findsOneWidget);
    expect(find.text('Demandée'), findsOneWidget);
    agent.dispose();

    await tester.pumpWidget(const SizedBox());
    final supervisor = await loadAs(store, 'amina');
    await show(tester, SupplyRequestsScreen(data: supervisor));
    expect(find.text('Sarah'), findsOneWidget);
    await tapText(tester, 'Approuver');
    await tapText(tester, 'Approuver');
    expect(
      find.text('Demande approuvée · l’agent est prévenu'),
      findsOneWidget,
    );
    await tapText(tester, 'Marquer préparée');
    expect(find.text('Préparée'), findsOneWidget);
    expect(stock(store, 'soap'), 84);
    await tapText(tester, 'Marquer livrée');
    expect(find.text('Demande livrée · stock mis à jour'), findsOneWidget);
    expect(stock(store, 'soap'), 79);
    await tapText(tester, 'Terminées · 1');
    expect(find.text('Livrée'), findsOneWidget);
    supervisor.dispose();

    await tester.pumpWidget(const SizedBox());
    store.signIn('sarah');
    final titles = [
      for (final n in await loadAs(store, 'sarah').then((d) => d.notifications))
        n.title,
    ];
    expect(titles.take(3), [
      'Fournitures livrées',
      'Demande préparée',
      'Demande approuvée',
    ]);
  });

  testWidgets('minibar: record, correct, post, then compensate', (
    tester,
  ) async {
    final store = MemoryStore();
    final agent = await loadAs(store, 'sarah');
    await show(
      tester,
      MinibarRoomScreen(data: agent, room: agent.roomByNumber('214')),
    );
    await tapText(tester, 'Ajouter une consommation');
    expect(find.text('4,50 €'), findsOneWidget);
    await type(tester, 'qty-minibar-soda', '2');
    await tapText(tester, 'Enregistrer');
    expect(find.text('Soda 33 cl × 2'), findsOneWidget);
    expect(find.text('9,00 €'), findsOneWidget);
    expect(find.text('En attente'), findsOneWidget);
    expect(find.textContaining('Valider et facturer'), findsNothing);
    await tapText(tester, 'Corriger');
    final id = (store.state['minibar'] as List).single['id'];
    await type(tester, 'qty-$id', '3');
    await tapText(tester, 'Corriger');
    expect(find.text('Soda 33 cl × 3'), findsOneWidget);
    agent.dispose();

    await tester.pumpWidget(const SizedBox());
    final data = await loadAs(store, 'amina');
    await show(
      tester,
      MinibarRoomScreen(data: data, room: data.roomByNumber('214')),
    );
    await tapText(tester, 'Valider et facturer · 13,50 €');
    expect(find.text('Envoyé à la facturation'), findsOneWidget);
    expect(find.text('Facturé'), findsOneWidget);
    expect(find.text('Corriger'), findsNothing);
    await tapText(tester, 'Corriger la facture');
    await type(tester, 'qty-$id', '1');
    await tapText(tester, 'Enregistrer la correction');
    expect(find.text('Correction · Soda 33 cl -2'), findsOneWidget);
    expect(find.text('Valider et facturer · −9,00 €'), findsOneWidget);
    expect(
      (store.state['minibar'] as List).map(
        (e) => (e['status'], e['amount_cents']),
      ),
      [('pending', -900), ('billed', 1350)],
    );
    data.dispose();
  });

  testWidgets('stock tab filters by type; the log shows usage per room', (
    tester,
  ) async {
    final store = MemoryStore();
    final agent = await loadAs(store, 'sarah');
    await agent.useSupply(
      agent.supplies.firstWhere((s) => s.id == 'towels'),
      agent.roomByNumber('214'),
      3,
    );
    agent.dispose();
    final other = await loadAs(store, 'youssef');
    await other.useSupply(
      other.supplies.firstWhere((s) => s.id == 'soap'),
      other.roomByNumber('311'),
      2,
    );
    other.dispose();
    final data = await loadAs(store, 'amina');
    await show(tester, Scaffold(body: SuppliesScreen(data: data)));
    await tapText(tester, 'Minibar');
    expect(find.text('Soda 33 cl'), findsOneWidget);
    expect(find.text('Serviettes'), findsNothing);
    expect(find.textContaining('4,50 €'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 600));
    await tester.pumpAndSettle();
    await tapText(tester, 'Journal');
    expect(find.text('Journal du stock'), findsOneWidget);
    expect(find.text('Serviettes · Utilisation'), findsOneWidget);
    expect(find.text('Serviettes : 3'), findsOneWidget);
    expect(find.text('−3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await show(tester, StockLogScreen(data: data));
    expect(find.text('Savon et gel douche · Utilisation'), findsOneWidget);
    await tapText(tester, 'Tous');
    await tapText(tester, 'Étage 3');
    expect(find.text('Serviettes · Utilisation'), findsNothing);
    expect(find.text('Savon et gel douche · Utilisation'), findsOneWidget);
    expect(find.text('Savon et gel douche : 2'), findsOneWidget);
    data.dispose();
  });

  testWidgets('the Manager adds a minibar item with its price', (tester) async {
    final store = MemoryStore()..signIn('manager');
    final catalog = CatalogData(SqliteRoomCatalog(store));
    await catalog.load();
    await show(tester, MinibarCatalogScreen(catalog: catalog));
    expect(find.text('Soda 33 cl'), findsOneWidget);
    await tapText(tester, 'Nouvel article');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Article'),
      'Bière',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Prix de vente'),
      '6,5',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'En réserve'),
      '12',
    );
    await tapText(tester, 'Ajouter');
    expect(find.text('Article ajouté au minibar'), findsOneWidget);
    expect(find.text('Bière'), findsOneWidget);
    expect(find.text('6,50 € · 12 unités en réserve'), findsOneWidget);
    catalog.dispose();
  });
}
