import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/housekeeping/models/hotel_data.dart';
import 'package:nova_paris/housekeeping/models/issue.dart';
import 'package:nova_paris/housekeeping/screens/issues_screen.dart';
import 'package:nova_paris/housekeeping/screens/lost_item_screen.dart';
import 'package:nova_paris/housekeeping/screens/lost_items_screen.dart';
import 'package:nova_paris/housekeeping/screens/report_issue_screen.dart';
import 'package:nova_paris/housekeeping/services/issue_rules.dart';
import 'package:nova_paris/shared/custom/app_theme.dart';

import 'fake_devices.dart';
import 'memory_store.dart';

// The report screen (photos, voice note), Signalements and the lost and
// found screens, on the in-memory store running the real rules.
void main() {
  late FakeVoiceNotes voice;
  late FakePhotoPicker picker;
  setUp(() {
    voice = FakeVoiceNotes();
    picker = FakePhotoPicker();
  });

  Future<HotelData> signIn(MemoryStore store, String id) async =>
      (await loadAs(store, id))
        ..createVoiceNotes = (() => voice)
        ..createPhotoPicker = (() => picker);

  // Opens [screen] from a launcher page, like the app does.
  Future<void> open(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: novaTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => screen),
              ),
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ouvrir'));
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

  // While recording a timer ticks every second: no pumpAndSettle.
  Future<void> record(WidgetTester tester, int seconds) async {
    final button = find.text('Note vocale (1:00 maximum)');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();
    for (var i = 0; i < seconds; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  }

  group('report screen', () {
    testWidgets('an agent reports with photo and voice note, out of service', (
      tester,
    ) async {
      final store = MemoryStore();
      final data = await signIn(store, 'sarah');
      await open(
        tester,
        ReportIssueScreen(data: data, room: data.roomByNumber('214')),
      );
      expect(find.text('Signaler un problème · 214'), findsOneWidget);
      await tapText(tester, 'Envoyer le signalement');
      expect(find.text('Choisissez une catégorie.'), findsOneWidget);
      expect(find.text('Décrivez le problème.'), findsOneWidget);

      await tapText(tester, 'Climatisation');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'La climatisation goutte',
      );
      await tapText(tester, 'Haute');
      await tapText(tester, 'Mettre la chambre hors service');
      await tapText(tester, 'Photo');
      expect(find.text('Photos (1/3)'), findsOneWidget);

      await record(tester, 3);
      expect(find.text('Enregistrement · 0:03 / 1:00'), findsOneWidget);
      await tester.tap(find.text('Arrêter'));
      await tester.pumpAndSettle();
      expect(find.text('Note vocale · 0:03'), findsOneWidget);
      await tester.tap(find.byTooltip('Écouter'));
      await tester.pump();
      expect(voice.played, voice.started);
      expect(find.byTooltip('Arrêter la lecture'), findsOneWidget);
      voice.finish();
      await tester.pump();
      expect(find.byTooltip('Écouter'), findsOneWidget);

      await tapText(tester, 'Envoyer le signalement');
      expect(find.text('Ouvrir'), findsOneWidget, reason: 'back on the room');
      final issue = (store.state['issues'] as List).first as Map;
      expect(
        (
          issue['category'],
          issue['priority'],
          issue['out_of_service'],
          issue['voice_path'],
          issue['voice_seconds'],
        ),
        ('climatisation', 'high', true, voice.started.single, 3),
      );
      expect(issue['photos'], hasLength(1));
      expect(store.room('214')['status'], 'maintenance');
      expect(voice.deleted, isEmpty, reason: 'a sent note is kept');
      data.dispose();
    });

    testWidgets('without voice note; an occupied room stays in service', (
      tester,
    ) async {
      final store = MemoryStore();
      final data = await signIn(store, 'amina');
      await open(
        tester,
        ReportIssueScreen(data: data, room: data.roomByNumber('112')),
      );
      expect(
        find.text('Chambre occupée : elle reste au client pendant le séjour.'),
        findsOneWidget,
      );
      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.onChanged, isNull);
      await tapText(tester, 'Télévision');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Pas de signal',
      );
      await tapText(tester, 'Envoyer le signalement');
      final issue = (store.state['issues'] as List).first as Map;
      expect(
        (issue['category'], issue['voice_path'], issue['out_of_service']),
        ('television', null, false),
      );
      expect(store.room('112')['status'], 'occupied');
      data.dispose();
    });

    testWidgets('the recording stops by itself at one minute', (tester) async {
      final data = await signIn(MemoryStore(), 'sarah');
      await open(
        tester,
        ReportIssueScreen(data: data, room: data.roomByNumber('214')),
      );
      await record(tester, 59);
      expect(find.text('Enregistrement · 0:59 / 1:00'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(voice.stops, 1);
      expect(find.text('Note vocale · 1:00'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Note vocale · 1:00'), findsOneWidget);
      data.dispose();
    });

    testWidgets('a deleted or unsent note is removed from the phone', (
      tester,
    ) async {
      final data = await signIn(MemoryStore(), 'sarah');
      await open(
        tester,
        ReportIssueScreen(data: data, room: data.roomByNumber('214')),
      );
      await record(tester, 2);
      await tester.tap(find.text('Arrêter'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Supprimer la note vocale'));
      await tester.pumpAndSettle();
      expect(voice.deleted, [voice.started[0]]);
      expect(find.text('Note vocale (1:00 maximum)'), findsOneWidget);
      await record(tester, 2);
      await tester.tap(find.text('Arrêter'));
      await tester.pumpAndSettle();
      // Leaving without sending.
      await tester.pumpWidget(const SizedBox());
      expect(voice.deleted, voice.started);
      data.dispose();
    });

    testWidgets('a refused microphone is explained', (tester) async {
      voice.denied = true;
      final data = await signIn(MemoryStore(), 'sarah');
      await open(
        tester,
        ReportIssueScreen(data: data, room: data.roomByNumber('214')),
      );
      await tapText(tester, 'Note vocale (1:00 maximum)');
      expect(find.text('Bad state: Micro refusé.'), findsOneWidget);
      data.dispose();
    });
  });

  testWidgets('Signalements: the supervisor brings a repaired room back', (
    tester,
  ) async {
    final store = MemoryStore();
    final data = await signIn(store, 'amina');
    await data.reportIssue(
      data.roomByNumber('305'),
      category: IssueCategory.plomberie,
      description: 'Fuite',
      priority: IssuePriority.urgent,
      outOfService: true,
      voicePath: 'housekeeping/voice/00000000-0000-4000-8000-000000000009.m4a',
      voiceSeconds: 8,
    );
    // What the MaintenanceResolved listener does on the SQLite store.
    resolveIssues(store.state, '305', DateTime.now());
    await data.refresh();
    await open(tester, IssuesScreen(data: data));
    expect(find.text('Signalements'), findsOneWidget);
    expect(find.text('Signalés · 1'), findsOneWidget, reason: 'room 224');
    await tapText(tester, 'Résolus · 1');
    await tapText(tester, 'Chambre 305 · Plomberie');
    expect(
      find.text('Intervention terminée par la maintenance'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Écouter'));
    await tester.pump();
    expect(voice.played, [
      'housekeeping/voice/00000000-0000-4000-8000-000000000009.m4a',
    ]);
    await tapText(tester, 'Remettre à nettoyer');
    expect(find.text('Chambre 305 remise à nettoyer'), findsOneWidget);
    expect(store.room('305')['status'], 'dirty');
    expect(find.text('Clôturé par Amina'), findsOneWidget);
    expect(find.text('Remettre à nettoyer'), findsNothing);
    data.dispose();
  });

  testWidgets('Mes signalements: an agent sees their own reports only', (
    tester,
  ) async {
    final store = MemoryStore();
    final agent = await signIn(store, 'sarah');
    await agent.reportIssue(
      agent.roomByNumber('214'),
      category: IssueCategory.mobilier,
      description: 'Chaise cassée',
      priority: IssuePriority.low,
      outOfService: false,
    );
    await open(tester, IssuesScreen(data: agent));
    expect(find.text('Mes signalements'), findsOneWidget);
    expect(find.text('Chambre 214 · Mobilier'), findsOneWidget);
    expect(find.text('Chambre 224 · Autre'), findsNothing);
    await tapText(tester, 'Chambre 214 · Mobilier');
    expect(find.text('Clôturer le signalement'), findsNothing);
    agent.dispose();
  });

  group('lost and found', () {
    testWidgets(
      'prévenir le client, then archive: the history shows each step',
      (tester) async {
        final store = MemoryStore();
        final agent = await signIn(store, 'sarah');
        await agent.recordLostItem(agent.roomByNumber('214'), 'Montre dorée');
        final data = await signIn(store, 'amina');
        await open(
          tester,
          LostItemScreen(data: data, itemId: data.lostItems.single.id),
        );
        expect(find.text('Trouvé par Sarah'), findsOneWidget);
        await tapText(tester, 'Prévenir le client');
        expect(
          find.textContaining('Bonjour, nous avons retrouvé « Montre dorée »'),
          findsOneWidget,
        );
        await tapText(tester, 'Enregistrer la tentative');
        expect(
          find.text('Choisissez comment le client a été prévenu.'),
          findsOneWidget,
        );
        await tapText(tester, 'Téléphone');
        await tapText(tester, 'Enregistrer la tentative');
        expect(find.text('Tentative de contact enregistrée'), findsOneWidget);
        expect(find.text('Client prévenu · Téléphone · Amina'), findsOneWidget);
        expect(find.text('Nouvelle tentative de contact'), findsOneWidget);
        await tapText(tester, 'Archiver');
        await tapText(tester, 'Archiver');
        expect(find.text('Objet archivé'), findsOneWidget);
        expect(find.text('Archivé · Amina'), findsOneWidget);
        expect(find.text('Rendre'), findsNothing);
        expect((store.state['lostItems'] as List).single['status'], 'archived');

        // The agent who found it sees the history, without the actions.
        await tester.pumpWidget(const SizedBox());
        final mine = await signIn(store, 'sarah');
        await open(
          tester,
          LostItemScreen(data: mine, itemId: mine.lostItems.single.id),
        );
        expect(find.text('Client prévenu · Téléphone · Amina'), findsOneWidget);
        expect(find.text('Prévenir le client'), findsNothing);
        for (final d in [agent, data, mine]) {
          d.dispose();
        }
      },
    );

    testWidgets('search and filter by status and room; archive delay', (
      tester,
    ) async {
      final store = MemoryStore();
      final data = await signIn(store, 'amina');
      await data.recordLostItem(data.roomByNumber('214'), 'Montre');
      await data.recordLostItem(data.roomByNumber('305'), 'Parapluie noir');
      await data.returnLostItem(
        data.lostItems.firstWhere((i) => i.description == 'Montre'),
        'M. Martin',
      );
      await open(tester, LostItemsScreen(data: data));
      expect(find.text('Tous · 2'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'para');
      await tester.pumpAndSettle();
      expect(find.text('Parapluie noir'), findsOneWidget);
      expect(find.text('Montre'), findsNothing);
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();
      await tapText(tester, 'Remis · 1');
      expect(find.text('Montre'), findsOneWidget);
      expect(find.text('Parapluie noir'), findsNothing);
      await tapText(tester, 'Tous · 2');
      await tapText(tester, 'Toutes');
      await tapText(tester, '305');
      expect(find.text('Parapluie noir'), findsOneWidget);
      expect(find.text('Montre'), findsNothing);

      await tester.tap(find.byTooltip('Archivage automatique'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Délai'), '3');
      await tapText(tester, 'Enregistrer');
      expect(find.text('De 7 à 365 jours.'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'Délai'), '14');
      await tapText(tester, 'Enregistrer');
      expect(find.text('Archivage après 14 jours'), findsOneWidget);
      expect(data.lostArchiveDays, 14);
      data.dispose();
    });
  });
}
