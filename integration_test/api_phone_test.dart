import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nova_paris/app/modules.dart';
import 'package:nova_paris/housekeeping/custom/supply_form_dialog.dart';
import 'package:nova_paris/housekeeping/housekeeping_module.dart';
import 'package:nova_paris/housekeeping/models/catalog_data.dart';
import 'package:nova_paris/housekeeping/models/hotel_data.dart';
import 'package:nova_paris/housekeeping/models/issue.dart';
import 'package:nova_paris/housekeeping/screens/issues_screen.dart';
import 'package:nova_paris/housekeeping/screens/minibar_catalog_screen.dart';
import 'package:nova_paris/housekeeping/services/sqlite_housekeeping.dart';
import 'package:nova_paris/housekeeping/services/sqlite_room_catalog.dart';
import 'package:nova_paris/shared/custom/app_theme.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

// The module's three public APIs on a real phone, over its real network:
// Open Food Facts, Open Beauty Facts (barcode → stock item) and MyMemory
// (report translation). The camera is replaced by the barcode it would
// read; everything else is the real screens and the real services.
// Own database (nova_paris_api.db, recreated each run).
//   flutter drive --driver=test_driver/api_phone_driver.dart \
//     --target=integration_test/api_phone_test.dart -d <device>
// Results: build/api_phone_test/ (steps.json and screenshots).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('public APIs on the phone', (tester) async {
    final path = p.join(await getDatabasesPath(), 'nova_paris_api.db');
    await deleteDatabase(path);
    final database = await AppDatabase.open(
      schemas: [for (final module in novaModules) ?module.schema],
      path: path,
    );
    final session = AppSession(
      database: database,
      staff: userManagement.staffDirectory,
    );
    final store = housekeepingStoreFor(session);
    final staff = await session.staff.users();
    void signIn(String id) =>
        session.signIn(staff.firstWhere((u) => u.id == id));
    await binding.convertFlutterSurfaceToImage();

    final steps = <Map<String, Object?>>[];
    var number = 0;

    // Real network: pump until [finder] shows, up to 20 s.
    Future<void> waitFor(Finder finder) async {
      for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      if (finder.evaluate().isEmpty) {
        throw StateError('Introuvable à l’écran : $finder');
      }
    }

    Future<void> show(Widget home) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(theme: novaTheme(), home: home, key: UniqueKey()),
      );
      await tester.pumpAndSettle();
    }

    String field(String label) => tester
        .widget<TextFormField>(find.widgetWithText(TextFormField, label))
        .controller!
        .text;

    Future<void> step(
      String id,
      String title,
      Future<String?> Function() body,
    ) async {
      final watch = Stopwatch()..start();
      var status = 'passed';
      String? detail;
      try {
        detail = await body();
      } catch (e) {
        status = 'failed';
        detail = '$e'.split('\n').first;
      }
      await tester.pump(const Duration(milliseconds: 600));
      final shot =
          '${(++number).toString().padLeft(2, '0')}_${status == 'passed' ? '' : 'ECHEC_'}$id';
      try {
        await binding.takeScreenshot(shot);
      } catch (_) {}
      steps.add({
        'n': number,
        'id': id,
        'title': title,
        'status': status,
        'detail': detail,
        'ms': watch.elapsedMilliseconds,
        'screenshot': '$shot.png',
      });
    }

    // ------------------------------------------------ Open Food Facts
    signIn('manager');
    final catalog = CatalogData(SqliteRoomCatalog(store));
    await catalog.load();
    await step(
      'off_minibar',
      'Open Food Facts : une canette scannée remplit l’article du minibar',
      () async {
        await show(
          MinibarCatalogScreen(
            catalog: catalog,
            scan: (_) async => '5449000000996',
          ),
        );
        await tester.tap(find.text('Nouvel article'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Scanner le code-barres'));
        await waitFor(find.textContaining('Fiche Open Food Facts'));
        final name = field('Article');
        if (!name.startsWith('Coca-Cola')) throw StateError('Nom : $name');
        return 'Article : « $name »';
      },
    );
    await step('off_enregistre', 'L’article scanné est enregistré', () async {
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Prix de vente'),
        '4,5',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'En réserve'),
        '24',
      );
      await tester.tap(find.text('Ajouter'));
      await waitFor(find.text('Article ajouté au minibar'));
      return 'Ajouté à la carte du minibar';
    });

    // ------------------------------------------------ Open Beauty Facts
    signIn('amina');
    final data = HotelData(api: SqliteHousekeeping(store));
    await data.refresh();
    Future<void> openStockForm(String code) async {
      await show(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) =>
                      SupplyFormDialog(data: data, scan: (_) async => code),
                ),
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scanner le code-barres'));
    }

    await step(
      'obf_accueil',
      'Open Beauty Facts : un gel douche devient un produit d’accueil',
      () async {
        await openStockForm('4305615834696');
        await waitFor(find.textContaining('Fiche Open Beauty Facts'));
        if (find.text('Produits d’accueil').evaluate().isEmpty) {
          throw StateError('Type non choisi');
        }
        return '« ${field('Article')} » · ${field('Unité')}';
      },
    );
    await step(
      'obf_enregistre',
      'Le produit d’accueil est enregistré',
      () async {
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Quantité en stock'),
          '40',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Seuil d’alerte'),
          '10',
        );
        await tester.tap(find.text('Ajouter'));
        for (var i = 0; i < 50; i++) {
          await tester.pump(const Duration(milliseconds: 200));
          if (find.byType(SupplyFormDialog).evaluate().isEmpty) break;
        }
        await data.refresh();
        final saved = data.supplies.where((s) => s.name.contains('Duschgel'));
        if (saved.isEmpty) throw StateError('Non enregistré');
        return '${saved.first.name} · ${saved.first.category}';
      },
    );
    await step(
      'obf_vers_off',
      'Inconnu d’Open Beauty Facts : une boisson passe par Open Food Facts',
      () async {
        await openStockForm('5449000000996');
        await waitFor(find.textContaining('Fiche Open Food Facts'));
        if (find.text('Minibar').evaluate().isEmpty) {
          throw StateError('Type non minibar');
        }
        return '« ${field('Article')} » · Minibar';
      },
    );
    await step(
      'code_inconnu',
      'Code inconnu partout : saisie à la main',
      () async {
        await openStockForm('20000000000017');
        await waitFor(find.textContaining('introuvable'));
        return 'Message affiché, formulaire utilisable';
      },
    );

    // ------------------------------------------------ MyMemory
    signIn('sarah');
    final agent = HotelData(api: SqliteHousekeeping(store));
    await agent.refresh();
    Future<String> report(String text) async {
      await agent.refresh();
      await agent.reportIssue(
        agent.roomByNumber('214'),
        category: IssueCategory.autre,
        description: text,
        priority: IssuePriority.normal,
        outOfService: false,
      );
      await data.refresh();
      return data.issues.firstWhere((i) => i.description == text).id;
    }

    // Setup as a step: a problem here shows in the report, not as a crash.
    late final String english, arabic, french;
    await step('signalements', 'Trois signalements écrits par Sarah', () async {
      english = await report('The bathroom light is broken');
      arabic = await report('الحوض يسرب الماء');
      french = await report('La télévision ne s’allume plus');
      return 'En anglais, en arabe et en français';
    });
    signIn('amina');
    await data.refresh();
    Future<void> translate(String issueId, Finder expected) async {
      await show(IssueDetailScreen(data: data, issueId: issueId));
      await tester.tap(find.text('Traduire en français'));
      await waitFor(expected);
    }

    await step(
      'mymemory_anglais',
      'MyMemory : un signalement en anglais',
      () async {
        await translate(
          english,
          find.text('Traduction automatique (anglais → français)'),
        );
        return 'Traduit depuis l’anglais';
      },
    );
    await step(
      'mymemory_arabe',
      'MyMemory : un signalement en arabe',
      () async {
        await translate(
          arabic,
          find.text('Traduction automatique (arabe → français)'),
        );
        return 'Traduit depuis l’arabe';
      },
    );
    await step('mymemory_francais', 'MyMemory : déjà en français', () async {
      await translate(french, find.text('Déjà en français.'));
      return 'Rien à traduire';
    });

    binding.reportData = {...?binding.reportData, 'steps': steps};
    catalog.dispose();
    data.dispose();
    agent.dispose();
    await tester.pumpWidget(const SizedBox());
    await database.close();
  });
}
