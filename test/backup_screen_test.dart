import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/app/backup_files.dart';
import 'package:nova_paris/app/backup_screen.dart';
import 'package:nova_paris/app/backup_service.dart';
import 'package:nova_paris/shared/services/backup_codec.dart';

class TestFiles implements BackupFiles {
  bool saved = false;
  @override
  Future<bool> save(String name, Uint8List bytes) async => saved;
  @override
  Future<BackupFile?> pick() async =>
      BackupFile('test.nova-backup', Uint8List(1));
}

class TestBackups implements BackupService {
  final BackupContents contents;
  int restores = 0, creates = 0;
  Completer<Uint8List>? pending;
  TestBackups(this.contents);
  @override
  Future<Uint8List> create(String password) async {
    creates++;
    return pending == null ? Uint8List(1) : pending!.future;
  }

  @override
  Future<BackupContents> inspect(Uint8List bytes, String password) async =>
      contents;
  @override
  Future<void> restore(BackupContents contents) async {
    restores++;
  }
}

void main() {
  late BackupContents contents;
  setUpAll(() async {
    final state = <String, dynamic>{
      'users': [
        {
          'id': 'manager',
          'full_name': 'Manager',
          'email': 'manager@nova.test',
          'role': 'manager',
          'deleted': false,
          'revision': 1,
          'points': 0,
          'salt': base64Encode(List.filled(16, 0)),
          'hash': base64Encode(List.filled(32, 0)),
        },
      ],
      'rooms': [],
      'roomArchives': [],
      'supplies': [],
      'notifications': [],
      'reads': <String, dynamic>{},
    };
    contents = await BackupCodec.decode(
      await BackupCodec.encode(state, 'password'),
      'password',
    );
  });
  Future<void> open(
    WidgetTester tester,
    TestBackups service,
    TestFiles files,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BackupScreen(service: service, files: files),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final target = find.text(text);
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        target,
        250,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'export validates passwords and cancellation never reports success',
    (tester) async {
      final service = TestBackups(contents);
      await open(tester, service, TestFiles());
      await tap(tester, 'Exporter la sauvegarde');
      expect(service.creates, 0);
      expect(find.text('Choisissez au moins 8 caractères.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(0), 'password');
      await tester.enterText(find.byType(TextFormField).at(1), 'password');
      await tap(tester, 'Exporter la sauvegarde');
      expect(service.creates, 1);
      expect(find.text('Enregistrement annulé.'), findsOneWidget);
      expect(
        find.text('Sauvegarde enregistrée à l’emplacement choisi.'),
        findsNothing,
      );
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'password',
      );
    },
  );
  testWidgets(
    'restore requires verification and explicit replacement confirmation',
    (tester) async {
      final service = TestBackups(contents);
      await open(tester, service, TestFiles());
      expect(find.text('Restaurer cette sauvegarde'), findsNothing);
      await tap(tester, 'Choisir un fichier');
      final password = find.widgetWithText(
        TextFormField,
        'Mot de passe du fichier',
      );
      await tester.scrollUntilVisible(
        password,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(password, 'password');
      await tap(tester, 'Vérifier la sauvegarde');
      await tap(tester, 'Restaurer cette sauvegarde');
      expect(service.restores, 0);
      await tap(tester, 'Annuler');
      expect(service.restores, 0);
      await tap(tester, 'Restaurer cette sauvegarde');
      await tap(tester, 'Remplacer les données');
      expect(service.restores, 1);
    },
  );
  testWidgets(
    'busy export disables duplicate submissions and preserves route',
    (tester) async {
      final service = TestBackups(contents)..pending = Completer<Uint8List>();
      await open(tester, service, TestFiles());
      await tester.enterText(find.byType(TextFormField).at(0), 'password');
      await tester.enterText(find.byType(TextFormField).at(1), 'password');
      await tester.ensureVisible(find.text('Exporter la sauvegarde'));
      await tester.tap(find.text('Exporter la sauvegarde'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Exporter la sauvegarde'),
      );
      expect(button.onPressed, isNull);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(BackupScreen), findsOneWidget);
      service.pending!.complete(Uint8List(1));
      await tester.pumpAndSettle();
      expect(service.creates, 1);
    },
  );
  testWidgets(
    'small screen and large text remain scrollable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader(
        'Manrope',
      )..addFont(rootBundle.load('assets/fonts/Manrope.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Manrope'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: BackupScreen(
            service: TestBackups(contents),
            files: TestFiles(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/backup_large_text.png'),
      );
      await tap(tester, 'Choisir un fichier');
      expect(find.text('Fichier : test.nova-backup'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
