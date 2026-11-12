import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/app/modules.dart';
import 'package:nova_paris/app/nova_app.dart';
import 'package:nova_paris/shared/models/app_user.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory directory;
  late AppSession session;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nova_shell_test_');
    final database = await AppDatabase.open(
      schemas: [for (final module in novaModules) ?module.schema],
      factory: databaseFactoryFfi,
      path: p.join(directory.path, 'nova.db'),
    );
    session = AppSession(
      database: database,
      staff: userManagement.staffDirectory,
    );
    attachModules(session);
  });
  tearDown(() async {
    await session.database.close();
    await directory.delete(recursive: true);
  });

  test('every module has a unique id, a title and at least one role', () {
    final ids = novaModules.map((m) => m.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final module in novaModules) {
      expect(
        Directory('lib/${module.id}').existsSync(),
        isTrue,
        reason: module.id,
      );
      expect(module.title, isNotEmpty);
      expect(module.roles, isNotEmpty);
      expect(AppRole.all.containsAll(module.roles), isTrue, reason: module.id);
      expect(module.schema?.module ?? module.id, module.id);
    }
  });

  test('modules never import another module folder', () {
    final ids = novaModules.map((m) => m.id).toSet();
    for (final id in ids) {
      for (final file in Directory('lib/$id').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final source = file.readAsStringSync();
        for (final other in ids.difference({id})) {
          expect(
            RegExp("import '(package:nova_paris/|(\\.\\./)+)$other/")
                .hasMatch(source),
            isFalse,
            reason:
                '${file.path} imports lib/$other. Use shared/ or AppEvents.',
          );
        }
        expect(
          RegExp(r"import '(package:nova_paris/|(\.\./)+)app/")
              .hasMatch(source),
          isFalse,
          reason:
              '${file.path} imports lib/app. Modules receive AppSession instead.',
        );
      }
    }
  });

  testWidgets('test login opens the modules of the chosen role', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NovaApp(session: session));
    expect(find.text('Qui êtes-vous ?'), findsOneWidget);

    await tester.tap(find.text('Entrer (mode test)'));
    await tester.pump();
    expect(find.text('Choisissez une personne.'), findsOneWidget);

    await tester.tap(find.text('Amina'));
    await tester.pumpAndSettle();
    expect(find.text('Entrer · Amina'), findsOneWidget);
    await tester.tap(find.text('Entrer · Amina'));
    await tester.pumpAndSettle();

    expect(find.text('Bonjour Amina.'), findsOneWidget);
    expect(find.text('Chambres et ménage'), findsOneWidget);
    expect(find.text('Maintenance'), findsOneWidget);
    expect(find.text('Facturation et rapports'), findsNothing);
    expect(find.text('Utilisateurs'), findsNothing);

    await tester.tap(find.text('Maintenance'));
    await tester.pumpAndSettle();
    expect(find.text('Module en construction'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Mon profil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Se déconnecter'));
    await tester.pumpAndSettle();
    expect(find.text('Qui êtes-vous ?'), findsOneWidget);
  });

  testWidgets('each role sees exactly the modules that declare it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final role in AppRole.all) {
      session.signIn(AppUser(id: role, fullName: 'Test', role: role));
      await tester.pumpWidget(NovaApp(session: session));
      await tester.pumpAndSettle();
      for (final module in novaModules) {
        expect(
          find.text(module.title),
          module.roles.contains(role) ? findsOneWidget : findsNothing,
          reason: '$role / ${module.id}',
        );
      }
      session.signOut();
      await tester.pumpAndSettle();
    }
  });
}
