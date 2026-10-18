import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_paris/demo/offline_store.dart';
import 'package:nova_paris/shared/custom/app_theme.dart';
import 'package:nova_paris/shared/services/app_exception.dart';
import 'package:nova_paris/housekeeping/services/room_catalog_backend.dart';
import 'package:nova_paris/housekeeping/screens/manage_rooms_screen.dart';
import 'package:nova_paris/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<OfflineStore> manager() async {
    final store = await OfflineStore.open();
    await store.login('manager@nova.test', OfflineStore.demoPassword);
    return store;
  }

  testWidgets('room catalog visual at phone width', (tester) async {
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    final font = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await manager();
    await store.roomCatalog().mutate(RoomCatalogAction.create, {
      'number': '501',
      'category': 'Chambre familiale',
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: novaTheme(),
        debugShowCheckedModeBanner: false,
        home: ManageRoomsScreen(backend: store.roomCatalog()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '501');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/manager_rooms.png'),
    );
    await tester.pumpWidget(const SizedBox());
    await store.dispose();
    debugDisableShadows = true;
  });
  testWidgets('room creation fits a small phone with 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = await manager();
    await tester.pumpWidget(
      MaterialApp(
        theme: novaTheme(),
        home: ManageRoomsScreen(backend: store.roomCatalog()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '501');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Chambre familiale',
    );
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Créer la chambre');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(
      (await store.roomCatalog().snapshot()).rooms.any(
        (r) => r.number == '501',
      ),
      true,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await store.dispose();
  });

  test('rooms persist, enter housekeeping, update category and archive/restore without losing history', () async {
    final store = await manager();
    addTearDown(store.dispose);
    final catalog = store.roomCatalog();
    await catalog.mutate(RoomCatalogAction.create, {
      'number': '901',
      'category': 'Suite',
    });
    await store.login('amina@nova.test', OfflineStore.demoPassword);
    var hk = await store.housekeeping().snapshot();
    expect(
      (hk['rooms'] as List).firstWhere((r) => r['number'] == '901')['status'],
      'dirty',
    );
    await expectLater(catalog.snapshot(), throwsA(isA<AppServiceException>()));
    await store.login('manager@nova.test', OfflineStore.demoPassword);
    await catalog.mutate(RoomCatalogAction.update, {
      'number': '901',
      'category': 'Suite Prestige',
      'version': 1,
    });
    await expectLater(
      catalog.mutate(RoomCatalogAction.update, {
        'number': '901',
        'category': 'Stale',
        'version': 1,
      }),
      throwsA(isA<AppServiceException>()),
    );
    await catalog.mutate(RoomCatalogAction.archive, {
      'number': '901',
      'version': 2,
    });
    expect((await catalog.snapshot()).archivedRooms.single.number, '901');
    await store.login('sarah@nova.test', OfflineStore.demoPassword);
    hk = await store.housekeeping().snapshot();
    expect((hk['rooms'] as List).any((r) => r['number'] == '901'), false);
    expect(hk.containsKey('roomArchives'), false);
    await expectLater(
      catalog.mutate(RoomCatalogAction.create, {
        'number': '902',
        'category': 'Suite',
      }),
      throwsA(isA<AppServiceException>()),
    );
    final fresh = await OfflineStore.open();
    addTearDown(fresh.dispose);
    await fresh.login('manager@nova.test', OfflineStore.demoPassword);
    final reopened = fresh.roomCatalog();
    expect(
      (await reopened.snapshot()).archivedRooms.single.category,
      'Suite Prestige',
    );
    await reopened.mutate(RoomCatalogAction.restore, {
      'number': '901',
      'version': 3,
    });
    final restored = (await reopened.snapshot()).rooms.firstWhere(
      (r) => r.number == '901',
    );
    expect(restored.version, 4);
    expect(restored.needsCleaning, true);
    expect(restored.history.length, 4);
  });
  test(
    'duplicate numbers and unsafe archive actions are refused locally',
    () async {
      final store = await manager();
      addTearDown(store.dispose);
      final catalog = store.roomCatalog();
      for (final number in ['112', '224', '214', '109']) {
        await expectLater(
          catalog.mutate(RoomCatalogAction.archive, {
            'number': number,
            'version': 1,
          }),
          throwsA(isA<AppServiceException>()),
        );
      }
      await expectLater(
        catalog.mutate(RoomCatalogAction.create, {
          'number': '305',
          'category': 'Suite',
        }),
        throwsA(isA<AppServiceException>()),
      );
      await catalog.mutate(RoomCatalogAction.archive, {
        'number': '402',
        'version': 1,
      });
      await expectLater(
        catalog.mutate(RoomCatalogAction.create, {
          'number': '402',
          'category': 'Reuse',
        }),
        throwsA(isA<AppServiceException>()),
      );
    },
  );

  testWidgets(
    'Manager home exposes rooms; create validates fields and shows the new room',
    (tester) async {
      final store = await manager();
      await tester.pumpWidget(
        NovaParisApp(
          auth: store,
          housekeepingFactory: store.housekeeping,
          roomCatalogFactory: store.roomCatalog,
          offline: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Gérer les chambres'));
      await tester.tap(find.text('Gérer les chambres'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Créer une chambre'));
      await tester.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, 'Créer la chambre');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Saisissez un numéro de 100 à 999.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(0), '901');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Suite Prestige',
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '901');
      await tester.pumpAndSettle();
      expect(find.text('Chambre 901'), findsOneWidget);
      expect(
        (await store.roomCatalog().snapshot()).rooms
            .firstWhere((r) => r.number == '901')
            .category,
        'Suite Prestige',
      );
      await tester.pumpWidget(const SizedBox());
      await store.dispose();
    },
  );
  testWidgets(
    'duplicate create keeps room form draft with an actionable error',
    (tester) async {
      final store = await manager();
      await tester.pumpWidget(
        MaterialApp(
          theme: novaTheme(),
          home: ManageRoomsScreen(backend: store.roomCatalog()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Créer une chambre'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), '305');
      await tester.enterText(find.byType(TextFormField).at(1), 'Suite');
      final save = find.widgetWithText(FilledButton, 'Créer la chambre');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        find.text('Ce numéro existe déjà, y compris dans les archives.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextFormField, '305'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await store.dispose();
    },
  );
}
