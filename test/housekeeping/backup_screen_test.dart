import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/housekeeping/screens/backup_screen.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_backup.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_store.dart';
import 'package:nova_paris/shared/custom/app_theme.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'housekeeping_store_test.dart' show TestStaff;

// The backup screen on a real database and folder: back up, share, restore.
void main() {
  late Directory directory;
  late AppSession session;
  late HousekeepingBackup backup;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nova_backup_screen_');
    final database = await AppDatabase.open(
      schemas: [housekeepingSchema],
      factory: databaseFactoryFfi,
      path: p.join(directory.path, 'test.db'),
    );
    session = AppSession(database: database, staff: TestStaff());
    final app = await Directory(p.join(directory.path, 'app')).create();
    backup = HousekeepingBackup(
      HousekeepingStore(session),
      appFolder: () async => app,
    );
  });
  tearDown(() async {
    await session.database.close();
    await directory.delete(recursive: true);
  });

  // Files and SQLite run outside the widget test clock: wait for [finder].
  Future<void> settleUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> open(
    WidgetTester tester, {
    ShareBackup? share,
    PickBackup? pick,
  }) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: novaTheme(),
        home: BackupScreen(
          backup: backup,
          share: share ?? (_) async {},
          pick: pick ?? () async => null,
        ),
      ),
    );
    await settleUntil(tester, find.text('Aucune sauvegarde'));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  testWidgets('the Manager backs up, shares and restores', (tester) async {
    session.signIn(TestStaff.people.firstWhere((u) => u.id == 'manager'));
    final shared = <String>[];
    Uint8List? file;
    await open(
      tester,
      share: (b) async => shared.add(b.name),
      pick: () async => file,
    );
    expect(find.text('Aucune sauvegarde'), findsOneWidget);
    await tester.tap(find.text('Sauvegarder maintenant'));
    await settleUntil(tester, find.text('Sauvegarde enregistrée'));
    expect(find.text('Sauvegarde enregistrée'), findsOneWidget);
    expect(find.textContaining('Manuelle ·'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.share_outlined));
    await settleUntil(tester, find.text('Sauvegarde prête à partager'));
    expect(shared.single, startsWith('nova-paris-menage-'));

    final saved = (await tester.runAsync(backup.list))!.single;
    file = await tester.runAsync(() => backup.readFile(saved.path));
    await tester.tap(find.text('Restaurer depuis un fichier'));
    await tester.pumpAndSettle();
    expect(find.text('Restaurer cette sauvegarde ?'), findsOneWidget);
    await tester.tap(find.text('Restaurer'));
    await settleUntil(tester, find.text('Sauvegarde restaurée'));
    expect(find.text('Sauvegarde restaurée'), findsOneWidget);
    await settleUntil(tester, find.textContaining('Automatique ·'));
    expect(
      find.textContaining('Automatique ·'),
      findsOneWidget,
      reason: 'the safety backup made before restoring',
    );
  });

  testWidgets('the supervisor cannot restore', (tester) async {
    session.signIn(TestStaff.people.firstWhere((u) => u.id == 'amina'));
    await open(tester);
    expect(find.text('Sauvegarder maintenant'), findsOneWidget);
    expect(find.text('Restaurer depuis un fichier'), findsNothing);
  });
}
