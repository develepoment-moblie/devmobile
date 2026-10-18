import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/main.dart';
import 'package:nova_paris/shared/custom/app_theme.dart';
import 'package:nova_paris/housekeeping/models/hotel_data.dart';
import 'package:nova_paris/housekeeping/models/room.dart';
import 'package:nova_paris/housekeeping/screens/assign_task_screen.dart';
import 'package:nova_paris/housekeeping/screens/details_screen.dart';
import 'package:nova_paris/housekeeping/screens/rooms_screen.dart';
import 'package:nova_paris/housekeeping/screens/supplies_screen.dart';

void main() {
  test('Cleaning requires assignment, checklist and supervisor approval', () {
    final data = HotelData();
    final room = data.roomByNumber('305');
    expect(data.remaining, 12);
    expect(() => data.startCleaning(room), throwsStateError);
    expect(() => data.assign(room, 'Sarah', '', false), throwsStateError);
    data.isSupervisor = true;
    data.assign(room, 'Sarah', 'Avant midi', true);
    data.isSupervisor = false;
    data.startCleaning(room);
    expect(() => data.submitCleaning(room), throwsStateError);
    room.checklist.fillRange(0, 4, true);
    data.submitCleaning(room);
    expect(room.status, RoomStatus.dirty);
    expect(room.cleaning, CleaningStatus.review);
    expect(data.notifications.first.roomNumber, '305');
    expect(() => data.approve(room), throwsStateError);
    data.isSupervisor = true;
    data.currentUser = 'Amina';
    data.approve(room);
    expect(room.status, RoomStatus.ready);
    expect(data.remaining, 11);
    expect(() => data.assign(room, 'Sarah', '', false), throwsStateError);
  });

  test('Checkout creates one cleaning task and one notification', () {
    final data = HotelData();
    final before = data.notifications.length;
    final room = data.roomByNumber('112');
    data.checkout(room);
    expect(data.remaining, 13);
    expect(data.notifications.length, before + 1);
    expect(room.cleaning, CleaningStatus.waiting);
    expect(room.employee, isNull);
    expect(() => data.checkout(room), throwsStateError);
    expect(data.notifications.length, before + 1);
  });

  Future<void> phone(
    WidgetTester tester,
    Widget child, {
    double width = 402,
  }) async {
    tester.view.physicalSize = Size(width, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: novaTheme(), home: child));
    await tester.pumpAndSettle();
  }

  testWidgets('Figma overview and task filters work', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const NovaParisApp());
    await tester.pumpAndSettle();
    expect(find.text('12 chambres restantes'), findsOneWidget);
    expect(find.text('Chambre 402'), findsOneWidget);
    await tester.tap(find.text('À faire · 6'));
    await tester.pumpAndSettle();
    expect(find.text('Chambre 402'), findsNothing);
    expect(find.text('Chambre 305'), findsOneWidget);
    await tester.tap(find.text('Terminées'));
    await tester.pumpAndSettle();
    expect(find.text('Chambre 402'), findsOneWidget);
    expect(find.text('Chambre 305'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Assignment form validates then saves selected room and agent', (
    tester,
  ) async {
    final data = HotelData()..isSupervisor = true;
    await phone(tester, AssignTaskScreen(data: data));
    await tester.ensureVisible(find.text('Attribuer la tâche'));
    await tester.tap(find.text('Attribuer la tâche'));
    await tester.pumpAndSettle();
    expect(find.text('Choisissez une chambre.'), findsOneWidget);
    expect(find.text('Choisissez un agent.'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<Room>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chambre 305 · Urgent').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sarah').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Contrôler le minibar');
    await tester.ensureVisible(find.text('Attribuer la tâche'));
    await tester.tap(find.text('Attribuer la tâche'));
    await tester.pumpAndSettle();
    expect(data.roomByNumber('305').employee, 'Sarah');
    expect(data.roomByNumber('305').note, 'Contrôler le minibar');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Room search no-results can be cleared', (tester) async {
    final data = HotelData();
    await phone(tester, Scaffold(body: RoomsScreen(data: data)), width: 320);
    await tester.enterText(find.byType(TextField), '999');
    await tester.pumpAndSettle();
    expect(find.text('Aucune chambre trouvée'), findsOneWidget);
    await tester.tap(find.byTooltip('Effacer la recherche'));
    await tester.pumpAndSettle();
    expect(find.text('16 chambres'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Checklist submission keeps room dirty until approved', (
    tester,
  ) async {
    final data = HotelData();
    final room = data.roomByNumber('214');
    await phone(tester, DetailsScreen(data: data, room: room));
    for (var i = 0; i < 4; i++) {
      await tester.ensureVisible(find.byType(CheckboxListTile).at(i));
      await tester.tap(find.byType(CheckboxListTile).at(i));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text('Terminer le nettoyage'));
    await tester.tap(find.text('Terminer le nettoyage'));
    await tester.pumpAndSettle();
    expect(room.cleaning, CleaningStatus.review);
    expect(room.status, RoomStatus.dirty);
    expect(find.text('Valider le nettoyage'), findsNothing);
    expect(
      find.text('Le nettoyage attend la validation de la gouvernante.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Stock rejects excess use and cancellation preserves quantity', (
    tester,
  ) async {
    final data = HotelData()..isSupervisor = true;
    await phone(tester, Scaffold(body: SuppliesScreen(data: data)));
    await tester.tap(find.text('Utiliser').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '100');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(
      find.text('Quantité supérieure au stock disponible.'),
      findsOneWidget,
    );
    expect(data.supplies.first.quantity, 42);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abandonner'));
    await tester.pumpAndSettle();
    expect(data.supplies.first.quantity, 42);
    await tester.tap(find.text('Utiliser').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '2');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(data.supplies.first.quantity, 40);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Small phone supports enlarged text without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      NovaParisApp(data: HotelData()..isSupervisor = true),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Attribuer une tâche'), 180);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Attribuer une tâche'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attribuer une tâche'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Attribuer la tâche'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
