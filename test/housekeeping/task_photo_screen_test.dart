import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/housekeeping/models/hotel_data.dart';
import 'package:nova_paris/housekeeping/screens/details_screen.dart';
import 'package:nova_paris/housekeeping/screens/task_photo_screen.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_backend.dart';
import 'package:nova_paris/housekeeping/services/task_photo_picker.dart';
import 'package:nova_paris/shared/custom/app_theme.dart';
import 'package:nova_paris/housekeeping/services/app_exception.dart';
import 'package:nova_paris/housekeeping/models/task_schema.dart';

import 'photo_fixture.dart';

class PhotoBackend implements HousekeepingBackend, TaskPhotoBackend {
  late final Map<String, dynamic> state = jsonDecode(
    File('test/housekeeping/fixtures/snapshot.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  bool conflict = false, duplicate = false;
  Completer<void>? pending;
  final writes = <Map<String, dynamic>>[];
  PhotoBackend({bool supervisor = false}) {
    state['principal'] = {
      'id': supervisor ? 'amina' : 'sarah',
      'name': supervisor ? 'Amina' : 'Sarah',
      'role': supervisor ? 'supervisor' : 'agent',
    };
    for (final r in state['rooms'] as List) {
      r['tasks'] = TaskSchema.defaults();
    }
  }
  Map get current =>
      (state['rooms'] as List).firstWhere((r) => r['number'] == '214') as Map;
  @override
  Future<Map<String, dynamic>> snapshot() async =>
      jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
  @override
  Future<void> mutate(String path, Map<String, dynamic> body) async {
    if (pending != null) await pending!.future;
    if (conflict) {
      conflict = false;
      current['version'] = (current['version'] as int) + 1;
      throw const AppServiceException(
        'Cette chambre a changé. Actualisez.',
        409,
      );
    }
    if (duplicate) {
      throw const AppServiceException(
        'Cette tâche existe déjà dans cette chambre.',
      );
    }
    writes.add(body);
    if (path.endsWith('/add-task')) {
      (current['tasks'] as List).add({
        'id': 'new',
        'label': body['label'],
        'photoId': null,
      });
      (current['checklist'] as List).add(false);
    } else {
      current['checklist'][0] = true;
      current['tasks'][0]['photoId'] = 'saved-photo';
    }
    current['version'] = (current['version'] as int) + 1;
  }

  @override
  Future<String> taskPhoto(String roomNumber, String taskId) async =>
      photoBase64();
  @override
  void close() {}
}

class PhotoPicker implements TaskPhotoPicker {
  Uint8List? selected, recovered;
  bool? camera;
  Object? error;
  @override
  Future<Uint8List?> pick({required bool camera}) async {
    this.camera = camera;
    if (error != null) throw error!;
    return selected;
  }

  @override
  Future<Uint8List?> recover() async => recovered;
}

void main() {
  late HotelData data;
  late PhotoBackend backend;
  late PhotoPicker picker;
  Future<void> open(
    WidgetTester tester, {
    bool supervisor = false,
    double width = 402,
    double scale = 1,
    Uint8List? recovered,
  }) async {
    backend = PhotoBackend(supervisor: supervisor);
    data = HotelData(api: backend);
    await data.refresh();
    picker = PhotoPicker()..recovered = recovered;
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
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => supervisor
                        ? DetailsScreen(
                            data: data,
                            room: data.roomByNumber('214'),
                          )
                        : TaskPhotoScreen(
                            data: data,
                            room: data.roomByNumber('214'),
                            task: data.roomByNumber('214').tasks.first,
                            picker: picker,
                          ),
                  ),
                ),
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final target = find.text(label);
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        target,
        180,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await Scrollable.ensureVisible(tester.element(target), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'cancelled capture does not check task; chosen image needs explicit confirmation',
    (tester) async {
      await open(tester);
      final save = find.widgetWithText(
        FilledButton,
        'Enregistrer la photo et terminer la tâche',
      );
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tap(tester, 'Prendre une photo');
      expect(picker.camera, true);
      expect(data.roomByNumber('214').checklist.first, false);
      expect(backend.writes, isEmpty);
      picker.selected = photoBytes();
      await tap(tester, 'Choisir dans la galerie');
      expect(picker.camera, false);
      expect(backend.writes, isEmpty);
      await tap(tester, 'Enregistrer la photo et terminer la tâche');
      expect(backend.writes.single['taskId'], 'standard-0');
      expect(backend.writes.single['photo'], photoBase64());
      expect(data.roomByNumber('214').checklist.first, true);
      expect(find.byType(TaskPhotoScreen), findsNothing);
    },
  );
  testWidgets(
    'photo draft survives conflict and refresh before explicit retry',
    (tester) async {
      await open(tester);
      picker.selected = photoBytes();
      await tap(tester, 'Choisir dans la galerie');
      backend.conflict = true;
      await tap(tester, 'Enregistrer la photo et terminer la tâche');
      expect(find.text('Cette chambre a changé. Actualisez.'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(backend.writes, isEmpty);
      await tap(tester, 'Actualiser la chambre');
      await tap(tester, 'Enregistrer la photo et terminer la tâche');
      expect(backend.writes.single['version'], 2);
    },
  );
  testWidgets(
    'Back asks before discarding photo and errors leave task unchecked',
    (tester) async {
      await open(tester);
      picker.error = const AppServiceException('Accès aux photos refusé.');
      await tap(tester, 'Choisir dans la galerie');
      expect(find.text('Accès aux photos refusé.'), findsOneWidget);
      expect(data.roomByNumber('214').checklist.first, false);
      picker.error = null;
      picker.selected = photoBytes();
      await tap(tester, 'Choisir dans la galerie');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Abandonner les modifications ?'), findsOneWidget);
      await tap(tester, 'Continuer la saisie');
      expect(find.byType(TaskPhotoScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tap(tester, 'Abandonner');
      expect(backend.writes, isEmpty);
    },
  );
  testWidgets(
    'gouvernante validates custom task and preserves label after error',
    (tester) async {
      await open(tester, supervisor: true);
      await tap(tester, 'Ajouter une tâche à cette chambre');
      await tap(tester, 'Ajouter la tâche');
      expect(find.text('Décrivez la tâche à effectuer.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Nettoyer le balcon');
      backend.duplicate = true;
      await tap(tester, 'Ajouter la tâche');
      expect(
        find.text('Cette tâche existe déjà dans cette chambre.'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextFormField, 'Nettoyer le balcon'),
        findsOneWidget,
      );
      backend.duplicate = false;
      await tap(tester, 'Ajouter la tâche');
      expect(data.roomByNumber('214').tasks.length, 5);
      expect(data.roomByNumber('214').tasks.last.label, 'Nettoyer le balcon');
    },
  );
  testWidgets('narrow photo and custom-task flows fit large text', (
    tester,
  ) async {
    await open(tester, width: 320, scale: 2, supervisor: true);
    await tap(tester, 'Ajouter une tâche à cette chambre');
    await tester.enterText(
      find.byType(TextFormField),
      'Vérifier tous les produits d’accueil du balcon',
    );
    await tap(tester, 'Ajouter la tâche');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'recovered camera result is previewed and never applied automatically',
    (tester) async {
      await open(tester, recovered: photoBytes());
      expect(
        find.text(
          'Photo récupérée après interruption. Vérifiez qu’elle correspond à cette tâche avant de confirmer.',
        ),
        findsOneWidget,
      );
      expect(backend.writes, isEmpty);
      expect(data.roomByNumber('214').checklist.first, false);
      await tap(tester, 'Enregistrer la photo et terminer la tâche');
      expect(backend.writes.length, 1);
    },
  );
  testWidgets('photo confirmation remains usable at 200 percent text', (
    tester,
  ) async {
    await open(tester, width: 320, scale: 2);
    picker.selected = photoBytes();
    await tap(tester, 'Choisir dans la galerie');
    await tap(tester, 'Enregistrer la photo et terminer la tâche');
    expect(backend.writes.length, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'saving disables duplicate confirmation and blocks Back until commit',
    (tester) async {
      await open(tester);
      picker.selected = photoBytes();
      await tap(tester, 'Choisir dans la galerie');
      backend.pending = Completer<void>();
      final save = find.text('Enregistrer la photo et terminer la tâche');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(
                FilledButton,
                'Enregistrer la photo et terminer la tâche',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(TaskPhotoScreen), findsOneWidget);
      expect(find.text('Abandonner les modifications ?'), findsNothing);
      backend.pending!.complete();
      await tester.pumpAndSettle();
      expect(backend.writes.length, 1);
    },
  );
  testWidgets('photo completion visual reference', (tester) async {
    await (FontLoader(
      'Manrope',
    )..addFont(rootBundle.load('assets/fonts/Manrope.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await open(tester);
    picker.selected = photoBytes();
    await tap(tester, 'Choisir dans la galerie');
    await tester.runAsync(
      () => precacheImage(
        MemoryImage(picker.selected!),
        tester.element(find.byType(TaskPhotoScreen)),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/task_photo.png'),
    );
  });
}
