import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/housekeeping/custom/agent_room_card.dart';
import 'package:nova_paris/housekeeping/models/agent_workload.dart';
import 'package:nova_paris/housekeeping/models/hotel_data.dart';
import 'package:nova_paris/housekeeping/models/room.dart';
import 'package:nova_paris/housekeeping/screens/agent_dashboard_screen.dart';
import 'package:nova_paris/housekeeping/screens/details_screen.dart';
import 'package:nova_paris/housekeeping/screens/housekeeping_workspace.dart';
import 'package:nova_paris/housekeeping/screens/notifications_screen.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_backend.dart';
import 'package:nova_paris/shared/custom/app_theme.dart';

import 'memory_store.dart';
import 'photo_fixture.dart';

class IdentityBackend implements HousekeepingBackend {
  @override
  Future<void> mutate(String path, Map<String, dynamic> body) async {}
  @override
  Future<Map<String, dynamic>> snapshot() async => throw UnimplementedError();
  @override
  void close() {}
}

// Sarah's sample planning: 214 in progress; 109 and 404 submitted.
MemoryStore sarahsPlanning() => MemoryStore()
  ..submitted('109', 'sarah')
  ..submitted('404', 'sarah')
  ..submitted('208', 'lina');

void main() {
  test('account IDs isolate assignments even when two agents share a name', () {
    final data = HotelData(api: IdentityBackend());
    addTearDown(data.dispose);
    data.rooms.addAll([
      Room('101', employee: 'Sarah')..employeeId = 'sarah',
      Room('102', employee: 'Sarah')..employeeId = 'other',
      Room('103'),
      Room('104', status: RoomStatus.occupied)..employeeId = 'sarah',
      Room('105', status: RoomStatus.maintenance)..employeeId = 'sarah',
    ]);
    data.currentUserId = 'sarah';
    expect(AgentWorkload(data).rooms.map((r) => r.number), ['101']);
    data.currentUserId = 'other';
    expect(AgentWorkload(data).rooms.map((r) => r.number), ['102']);
  });

  test(
    'resume active work before urgent assignments and keep approval separate',
    () async {
      final store = sarahsPlanning();
      store.room('305')['employeeId'] = 'sarah';
      final data = await loadAs(store, 'sarah');
      addTearDown(data.dispose);
      final work = AgentWorkload(data);
      expect(work.next!.number, '214');
      expect(work.pending.map((r) => r.number), ['214', '305']);
      expect(work.urgent, 1);
      expect(work.withStatus(CleaningStatus.review).length, 2);
      expect(work.withStatus(CleaningStatus.completed), isEmpty);
      data.roomByNumber('214').cleaning = CleaningStatus.review;
      expect(AgentWorkload(data).next!.number, '305');
      data.roomByNumber('305').employeeId = 'lina';
      expect(AgentWorkload(data).next, isNull);
    },
  );

  late MemoryStore store;
  late HotelData data;
  Future<void> open(
    WidgetTester tester, {
    double width = 402,
    double scale = 1,
    MemoryStore? using,
  }) async {
    store = using ?? sarahsPlanning();
    data = await loadAs(store, 'sarah');
    tester.view.physicalSize = Size(width, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      data.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: novaTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: HousekeepingWorkspace(data: data, agent: true),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final target = find.text(label);
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        target,
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await Scrollable.ensureVisible(tester.element(target), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'agent starts on personal dashboard and sees no global work controls',
    (tester) async {
      await open(tester);
      expect(find.byType(AgentDashboardScreen), findsOneWidget);
      expect(find.text('Chambres'), findsNothing);
      expect(find.text('Stock'), findsNothing);
      expect(find.text('Attribuer une tâche'), findsNothing);
      expect(find.text('1 chambre à prendre en charge'), findsOneWidget);
      await tap(tester, 'Mes chambres');
      expect(find.byType(AgentRoomCard), findsNWidgets(3));
      expect(find.text('Chambre 207'), findsNothing);
      expect(find.text('Chambre 208'), findsNothing);
      await tap(tester, 'À valider · 2');
      expect(find.byType(AgentRoomCard), findsNWidgets(2));
    },
  );

  testWidgets('photo checklist, submission and approval update the dashboard', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, 'Chambre 214');
    expect(find.byType(DetailsScreen), findsOneWidget);
    expect(find.text('Modifier l’attribution'), findsNothing);
    expect(find.text('Valider le nettoyage'), findsNothing);
    // The photo screen has its own tests; complete the tasks directly.
    for (final task in data.roomByNumber('214').tasks) {
      final room = data.roomByNumber('214');
      await data.completeTask(room, task.id, photoBytes(), room.version);
    }
    await tester.pumpAndSettle();
    await tap(tester, 'Terminer le nettoyage');
    expect(data.roomByNumber('214').cleaning, CleaningStatus.review);
    Navigator.of(tester.element(find.byType(DetailsScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Aucun nettoyage à démarrer'), findsOneWidget);

    final supervisor = await loadAs(store, 'amina');
    await supervisor.approve(supervisor.roomByNumber('214'));
    supervisor.dispose();
    store.signIn('sarah');
    await data.refresh();
    await tester.pumpAndSettle();
    await tap(tester, 'Validées');
    expect(find.text('Validée par Amina · Voir le détail →'), findsOneWidget);
  });

  testWidgets(
    'reassignment removes a room immediately and empty filters explain recovery',
    (tester) async {
      await open(tester);
      store.room('214')['employeeId'] = 'lina';
      await data.refresh();
      await tester.pumpAndSettle();
      expect(find.text('1 chambre à prendre en charge'), findsNothing);
      await tap(tester, 'Mes chambres');
      await tap(tester, 'En cours · 0');
      expect(find.text('Aucune chambre dans ce statut'), findsOneWidget);
      expect(find.text('Chambre 214'), findsNothing);
      for (final r in store.state['rooms'] as List) {
        r['employeeId'] = null;
      }
      await data.refresh();
      await tester.pumpAndSettle();
      expect(find.text('Aucune chambre attribuée'), findsOneWidget);
    },
  );

  testWidgets(
    'agents see only notifications about their own rooms, never the supervisor’s',
    (tester) async {
      final planning = sarahsPlanning();
      planning.room('305')['employeeId'] = 'sarah';
      await open(tester, using: planning);
      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(find.text('Départ VIP'), findsOneWidget);
      expect(find.text('Chambre 109 prête pour inspection.'), findsNothing);
      await tester.tap(find.byTooltip('Tout marquer comme lu'));
      await tester.pumpAndSettle();
      expect((store.state['reads'] as Map)['sarah'], contains('vip305'));
      expect((store.state['reads'] as Map)['amina'], isNull);
    },
  );

  testWidgets(
    'dashboard and filtered queue support 200 percent text at narrow width',
    (tester) async {
      await open(tester, width: 320, scale: 2);
      expect(tester.takeException(), isNull);
      await tap(tester, 'Mes chambres');
      await tap(tester, 'En cours · 1');
      await tap(tester, 'Chambre 214');
      expect(find.byType(DetailsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('personal dashboard visual reference', (tester) async {
    await (FontLoader(
      'Manrope',
    )..addFont(rootBundle.load('assets/fonts/Manrope.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await open(tester);
    // Decode the logo first so every run captures the same frame.
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/nova_paris_logo.png'),
        tester.element(find.byType(HousekeepingWorkspace)),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/agent_dashboard.png'),
    );
    await tap(tester, 'Mes chambres');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/agent_rooms.png'),
    );
  });
}
