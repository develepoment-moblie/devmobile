import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/main.dart';
import 'package:nova_paris/housekeeping/models/hotel_data.dart';
import 'package:nova_paris/app/main_screen.dart';
import 'package:nova_paris/housekeeping/screens/assign_task_screen.dart';

void main() {
  testWidgets('Housekeeping and assignment retain the Figma visual baseline', (
    tester,
  ) async {
    final font = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      NovaParisApp(data: HotelData()..isSupervisor = true),
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/nova_paris_logo.png'),
        tester.element(find.byType(MainScreen)),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MainScreen),
      matchesGoldenFile('goldens/housekeeping.png'),
    );
    await tester.tap(find.text('Attribuer une tâche'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(AssignTaskScreen),
      matchesGoldenFile('goldens/assignment.png'),
    );
    expect(tester.takeException(), isNull);
    debugDisableShadows = true;
  });
}
