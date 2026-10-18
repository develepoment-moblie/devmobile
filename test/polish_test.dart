import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/shared/custom/app_theme.dart';
import 'package:nova_paris/main.dart';
import 'package:nova_paris/housekeeping/models/hotel_data.dart';
import 'package:nova_paris/housekeeping/models/room.dart';
import 'package:nova_paris/housekeeping/screens/assign_task_screen.dart';
import 'package:nova_paris/housekeeping/screens/notifications_screen.dart';
import 'package:nova_paris/housekeeping/screens/supplies_screen.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_backend.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_api.dart';

class ControlledBackend implements HousekeepingBackend {
  final Map<String, dynamic> state = jsonDecode(
    File('test/fixtures/snapshot.json').readAsStringSync(),
  );
  Completer<Map<String, dynamic>>? pendingRead;
  bool conflict = false, readFails = false;
  final writes = <Map<String, dynamic>>[];
  ControlledBackend() {
    state['principal'] = {'id': 'amina', 'name': 'Amina', 'role': 'supervisor'};
  }
  @override
  Future<Map<String, dynamic>> snapshot() async {
    if (readFails) throw const HousekeepingException('Connexion interrompue');
    if (pendingRead != null) return pendingRead!.future;
    return jsonDecode(jsonEncode(state));
  }

  @override
  Future<void> mutate(String path, Map<String, dynamic> body) async {
    writes.add(Map.of(body));
    if (conflict) {
      state['supplies'][0]['version'] = 2;
      state['supplies'][0]['quantity'] = 40;
      throw const HousekeepingException(
        'Stock modifié. Vérifiez puis réessayez.',
        409,
      );
    }
    if (path.contains('supplies')) {
      state['supplies'][0]['quantity'] += body['delta'];
      state['supplies'][0]['version']++;
    }
  }

  @override
  void close() {}
}

void main() {
  testWidgets(
    'stock conflict preserves quantity draft and retries the refreshed version',
    (tester) async {
      final backend = ControlledBackend();
      final data = HotelData(api: backend);
      await data.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: novaTheme(),
          home: Scaffold(body: SuppliesScreen(data: data)),
        ),
      );
      await tester.tap(find.text('Utiliser').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '2');
      backend.conflict = true;
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(
        find.text('Stock modifié. Vérifiez puis réessayez.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextFormField, '2'), findsOneWidget);
      expect(data.supplies.first.quantity, 40);
      backend.conflict = false;
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(backend.writes.map((w) => w['version']), [1, 2]);
      expect(data.supplies.first.quantity, 38);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
      data.dispose();
    },
  );

  testWidgets('changing task room loads its own notes, assignee and urgency', (
    tester,
  ) async {
    final data = HotelData()..isSupervisor = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: novaTheme(),
        home: AssignTaskScreen(data: data, room: data.roomByNumber('305')),
      ),
    );
    await tester.tap(find.byType(DropdownButtonFormField<Room>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chambre 214 · En cours').last);
    await tester.pumpAndSettle();
    expect(find.text('Sarah'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      false,
    );
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '',
    );
    await tester.pumpWidget(const SizedBox());
    data.dispose();
  });

  testWidgets(
    'cancel task asks before discarding and keeps the draft when declined',
    (tester) async {
      final data = HotelData()..isSupervisor = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: novaTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => AssignTaskScreen(data: data),
                  ),
                ),
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Ne pas perdre');
      await tester.scrollUntilVisible(
        find.text('Annuler'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(find.text('Abandonner les modifications ?'), findsOneWidget);
      await tester.tap(find.text('Continuer la saisie'));
      await tester.pumpAndSettle();
      expect(find.text('Ne pas perdre'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abandonner'));
      await tester.pumpAndSettle();
      expect(find.text('Ouvrir'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      data.dispose();
    },
  );

  testWidgets(
    'notifications update live and a missing room never crashes navigation',
    (tester) async {
      final data = HotelData();
      data.notifications.clear();
      await tester.pumpWidget(
        MaterialApp(
          theme: novaTheme(),
          home: NotificationsScreen(data: data),
        ),
      );
      expect(find.text('Tout est à jour'), findsOneWidget);
      data.notifications.add(
        HotelNotification('Nouvelle notification', 'Chambre supprimée', '999'),
      );
      data.changed();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nouvelle notification'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Cette chambre n’est plus disponible. Actualisez le planning.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Tout marquer comme lu',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      data.dispose();
    },
  );

  testWidgets('room search survives switching bottom navigation tabs', (
    tester,
  ) async {
    final data = HotelData();
    await tester.pumpWidget(NovaParisApp(data: data));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chambres'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '305');
    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chambres'));
    await tester.pumpAndSettle();
    expect(find.text('305'), findsWidgets);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '305',
    );
    await tester.pumpWidget(const SizedBox());
    data.dispose();
  });

  test('a mutation waits for a background read instead of rejecting the user action', () async {
    final backend = ControlledBackend();
    final data = HotelData(api: backend);
    await data.refresh();
    backend.pendingRead = Completer<Map<String, dynamic>>();
    final read = data.refresh();
    final write = Future.sync(() => data.moveStock(data.supplies.first, -1));
    expect(backend.writes, isEmpty);
    backend.pendingRead!.complete(jsonDecode(jsonEncode(backend.state)));
    backend.pendingRead = null;
    await read;
    await write;
    expect(backend.writes.single['delta'], -1);
    data.dispose();
  });

  test('acknowledged stock write followed by failed refresh is not reported as a failed write', () async {
    final backend = ControlledBackend();
    final data = HotelData(api: backend);
    await data.refresh();
    backend.readFails = true;
    await Future.sync(() => data.moveStock(data.supplies.first, -1));
    expect(backend.writes.length, 1);
    expect(data.connectionError, contains('Enregistrement confirmé'));
    data.dispose();
  });

  testWidgets('stock dialog stays usable on a small phone with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final data = HotelData()..isSupervisor = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: novaTheme(),
        home: Scaffold(body: SuppliesScreen(data: data)),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Utiliser'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Utiliser').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Utiliser').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '2');
    await tester.ensureVisible(find.text('Enregistrer'));
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(data.supplies.first.quantity, 40);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    data.dispose();
  });
}
