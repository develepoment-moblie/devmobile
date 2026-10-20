import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/housekeeping/custom/cleaning_timer_card.dart';
import 'package:nova_paris/housekeeping/screens/auto_assign_screen.dart';
import 'package:nova_paris/housekeeping/screens/details_screen.dart';
import 'package:nova_paris/shared/custom/app_theme.dart';

import 'memory_store.dart';

// Timer card and automatic assignment screen, on the in-memory store.
void main() {
  Future<void> show(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: novaTheme(), home: home));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  // A running timer ticks every second: advance time explicitly.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  test('elapsed times read naturally', () {
    expect(formatElapsed(const Duration(minutes: 4, seconds: 7)), '04:07');
    expect(
      formatElapsed(const Duration(hours: 1, minutes: 5, seconds: 9)),
      '1:05:09',
    );
  });

  testWidgets('the agent pauses and resumes the timer from the room', (
    tester,
  ) async {
    final store = MemoryStore();
    final supervisor = await loadAs(store, 'amina');
    await supervisor.assign(supervisor.roomByNumber('305'), 'sarah', '', false);
    final agent = await loadAs(store, 'sarah');
    await agent.startCleaning(agent.roomByNumber('305'));
    await show(
      tester,
      DetailsScreen(data: agent, room: agent.roomByNumber('305')),
    );
    await settle(tester);
    expect(find.text('Minuteur · En cours'), findsOneWidget);
    await tester.ensureVisible(find.text('Pause'));
    await tester.tap(find.text('Pause'));
    await settle(tester);
    expect(find.text('Minuteur · En pause'), findsOneWidget);
    expect(agent.roomByNumber('305').timerState, 'paused');
    await tester.tap(find.text('Reprendre'));
    await settle(tester);
    expect(find.text('Minuteur · En cours'), findsOneWidget);
    await tester.tap(find.text('Arrêter'));
    await settle(tester);
    expect(find.text('Minuteur · Arrêté'), findsOneWidget);
    expect(
      find.text('Temps réel de nettoyage, pauses exclues.'),
      findsOneWidget,
    );
    supervisor.dispose();
    agent.dispose();
  });

  testWidgets('the supervisor sees the timer but cannot control it', (
    tester,
  ) async {
    final store = MemoryStore();
    final supervisor = await loadAs(store, 'amina');
    await supervisor.assign(supervisor.roomByNumber('305'), 'sarah', '', false);
    final agent = await loadAs(store, 'sarah');
    await agent.startCleaning(agent.roomByNumber('305'));
    store.signIn('amina');
    await supervisor.refresh();
    await show(
      tester,
      DetailsScreen(data: supervisor, room: supervisor.roomByNumber('305')),
    );
    await settle(tester);
    expect(find.text('Minuteur · En cours'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);
    expect(find.text('Priorité du nettoyage'), findsOneWidget);
    supervisor.dispose();
    agent.dispose();
  });

  testWidgets('the supervisor reviews, adjusts and applies the plan', (
    tester,
  ) async {
    final store = MemoryStore();
    final supervisor = await loadAs(store, 'amina');
    final waiting = [for (final r in supervisor.unassignedRooms) r.number];
    expect(waiting, isNotEmpty);
    await show(
      tester,
      AutoAssignScreen(data: supervisor, day: DateTime(2026, 10, 20)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Disponibilités du jour'), findsOneWidget);
    for (final name in ['Lina', 'Sarah', 'Youssef']) {
      expect(find.text(name), findsWidgets);
    }
    // Lina is off today: her rooms go to the others.
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(
      supervisor.availabilityOf('lina', DateTime(2026, 10, 20)).available,
      isFalse,
    );
    final apply = find.textContaining('Appliquer l’attribution');
    expect(apply, findsOneWidget);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    final now = {
      for (final r in store.state['rooms'] as List)
        if (waiting.contains(r['number'])) r['number']: r['employeeId'],
    };
    expect(now.values.whereType<String>(), isNotEmpty);
    expect(now.values, isNot(contains('lina')));
    expect(supervisor.unassignedRooms.length, lessThan(waiting.length));
    supervisor.dispose();
  });
}
