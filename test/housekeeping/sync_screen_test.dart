import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/housekeeping/screens/sync_screen.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_store.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_sync.dart';
import 'package:nova_paris/housekeeping/services/server_discovery.dart';
import 'package:nova_paris/shared/custom/app_theme.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'housekeeping_store_test.dart' show TestStaff;
import 'sync_test.dart' show FakeDiscovery, FakeHotelServer;
import 'test_backends.dart';

// The Synchronisation screen on a real database, with an in-memory server.
void main() {
  late Directory directory;
  late AppSession session;
  late HousekeepingStore store;
  late HousekeepingSync sync;
  late FakeHotelServer server;
  late FakeDiscovery wifi;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nova_sync_screen_');
    final database = await AppDatabase.open(
      schemas: [housekeepingSchema],
      factory: databaseFactoryFfi,
      path: p.join(directory.path, 'test.db'),
    );
    session = AppSession(database: database, staff: TestStaff())
      ..signIn(TestStaff.people.firstWhere((u) => u.id == 'amina'));
    store = HousekeepingStore(session);
    server = FakeHotelServer();
    wifi = FakeDiscovery();
    sync = HousekeepingSync(
      store,
      client: server.client,
      background: false,
      timeout: const Duration(milliseconds: 200),
      discovery: wifi,
    );
  });
  tearDown(() async {
    sync.dispose();
    await session.database.close();
    await directory.delete(recursive: true);
  });

  // SQLite runs outside the widget test clock: wait for [finder].
  Future<void> settleUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 80 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(finder, findsWidgets);
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: novaTheme(),
        home: SyncScreen(sync: sync),
      ),
    );
    await settleUntil(tester, find.text('Adresse du serveur'));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  testWidgets('set the server, test it, sync: conflicts resolve themselves', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('État'), findsNothing, reason: 'no server yet');

    await tester.enterText(find.byType(TextField), '8.8.8.8');
    await tester.tap(find.text('Enregistrer'));
    await settleUntil(tester, find.textContaining('réseau local'));

    await tester.enterText(find.byType(TextField), '192.168.1.20');
    await tester.tap(find.text('Tester la connexion'));
    await settleUntil(
      tester,
      find.text('Serveur joignable · 0 action enregistrée.'),
    );

    await tester.tap(find.text('Enregistrer'));
    // Saved once the confirmed version of the sync exists.
    await settleUntil(tester, find.text('Serveur enregistré'));
    expect(find.text('État'), findsOneWidget);
    expect(find.text('Aucune action en attente'), findsOneWidget);
    expect(find.text('Jamais synchronisé'), findsOneWidget);
    expect(find.text('Aucun conflit'), findsOneWidget);
    expect(find.text('Résolu automatiquement'), findsOneWidget);

    // Another phone's agent tried to create stock: refused here.
    server.inject('/v1/supplies/new/create', 'sarah', {
      'name': 'Faux article',
      'unit': 'u',
      'quantity': 1,
      'minimum': 0,
      'category': 'linge',
    });
    await tester.tap(find.text('Synchroniser'));
    await settleUntil(tester, find.text('Stock · création'));
    // Cancelled by itself, on every phone: nothing to click.
    expect(find.textContaining('Annulée · Sarah · '), findsOneWidget);
    expect(
      find.textContaining('Stock réservé à la gouvernante.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.text('Aucun conflit'), findsNothing);
    expect(find.textContaining('Dernière synchronisation'), findsOneWidget);
    expect(find.text('Synchronisé'), findsOneWidget, reason: 'badge');
  });

  testWidgets('a server found on the Wi-Fi is used with one tap', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    expect(find.text('Serveurs trouvés sur le Wi-Fi'), findsOneWidget);
    expect(find.text('Recherche d’un serveur sur le Wi-Fi…'), findsOneWidget);

    server.host = '192.168.1.11';
    wifi.announce(
      FoundServer(
        id: server.serverId,
        name: 'PC-ACCUEIL',
        address: Uri.parse('http://192.168.1.11:8080'),
      ),
    );
    await settleUntil(tester, find.text('PC-ACCUEIL'));
    expect(find.text('192.168.1.11:8080'), findsOneWidget);
    expect(find.text('Recherche d’un serveur sur le Wi-Fi…'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('Utiliser le serveur PC-ACCUEIL')),
      findsOneWidget,
    );

    await tester.tap(find.text('Utiliser'));
    await settleUntil(tester, find.text('Rejoindre ce serveur ?'));
    await tester.tap(find.text('Rejoindre'));
    await settleUntil(tester, find.text('Serveur enregistré'));
    await settleUntil(tester, find.text('Utilisé'));
    expect(find.text('État'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '192.168.1.11:8080');
    expect(sync.overview!.server, Uri.parse('http://192.168.1.11:8080'));
    semantics.dispose();
  });

  testWidgets('broadcasts dropped: the scan finds the server', (tester) async {
    server.host = '192.168.1.11';
    wifi.open.add('192.168.1.11:8080');
    await open(tester);
    await settleUntil(tester, find.text('PC-ACCUEIL'));
    expect(find.text('192.168.1.11:8080'), findsOneWidget);
    await tester.tap(find.text('Utiliser'));
    await settleUntil(tester, find.text('Rejoindre ce serveur ?'));
    await tester.tap(find.text('Rejoindre'));
    await settleUntil(tester, find.text('Serveur enregistré'));
    await settleUntil(tester, find.text('Utilisé'));
  });

  testWidgets('nothing found: typing the address is offered', (tester) async {
    await open(tester);
    // Let the first read of the database finish (real time), then jump
    // past the 10 seconds of listening.
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));
    expect(
      find.text('Aucun serveur trouvé. Saisissez l’adresse ci-dessous.'),
      findsOneWidget,
    );
    expect(find.text('Utiliser'), findsNothing);

    // The server is started afterwards: searching again finds it.
    server.host = '192.168.1.11';
    wifi.open.add('192.168.1.11:8080');
    await tester.tap(find.text('Rechercher de nouveau'));
    await settleUntil(tester, find.text('PC-ACCUEIL'));
    expect(find.text('Rechercher de nouveau'), findsNothing);
  });

  testWidgets('offline: the badge counts the actions waiting', (tester) async {
    await tester.runAsync(() async {
      await sync.setServer('192.168.1.20');
      server.online = false;
      final rules = TestHousekeeping(store);
      final room = ((await store.readState())['rooms'] as List).firstWhere(
        (r) => r['number'] == '305',
      );
      await rules.mutate('/v1/rooms/305/assign', {
        'version': room['version'],
        'employeeId': 'sarah',
        'note': '',
        'urgent': false,
      });
    });
    await open(tester);
    await tester.tap(find.text('Synchroniser'));
    await settleUntil(tester, find.text('Hors ligne · 1 action en attente'));
    expect(find.textContaining('Serveur injoignable'), findsWidgets);
  });
}
