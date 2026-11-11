import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nova_paris/housekeeping/custom/supply_form_dialog.dart';
import 'package:nova_paris/housekeeping/models/catalog_data.dart';
import 'package:nova_paris/housekeeping/screens/issues_screen.dart';
import 'package:nova_paris/housekeeping/screens/minibar_catalog_screen.dart';
import 'package:nova_paris/housekeeping/services/app_exception.dart';
import 'package:nova_paris/housekeeping/services/product_lookup.dart';
import 'package:nova_paris/housekeeping/services/report_translation.dart';
import 'package:nova_paris/housekeeping/services/sqlite_room_catalog.dart';
import 'package:nova_paris/shared/custom/app_theme.dart';

import 'fake_devices.dart';
import 'memory_store.dart';

// The public APIs of the module, without network: Open Food Facts and Open
// Beauty Facts (fill in a stock item from its barcode) and MyMemory
// (translate a report).
http.Response json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> cocaCola = {
  'code': '5449000000996',
  'status': 1,
  'product': {
    'product_name': 'Coca-Cola Original',
    'product_name_fr': 'Coca-Cola',
    'brands': 'Coca-Cola',
    'quantity': '330 ml',
    'image_front_small_url': 'https://images.example/coca.jpg',
  },
};

Map<String, Object?> translated(String text, String from) => {
  'responseData': {'translatedText': text, 'detectedLanguage': from},
  'quotaFinished': false,
  'responseStatus': 200,
  'responseDetails': '',
};

void main() {
  group('Open Food Facts', () {
    test('a known barcode gives the product\'s French name and size', () async {
      Uri? asked;
      String? agent;
      final lookup = ProductLookup(
        client: MockClient((request) async {
          asked = request.url;
          agent = request.headers['user-agent'];
          return json(cocaCola);
        }),
      );
      final product = await lookup.find('5449000000996');
      expect(asked!.host, 'world.openfoodfacts.org');
      expect(asked!.path, '/api/v2/product/5449000000996.json');
      expect(asked!.queryParameters['fields'], contains('product_name_fr'));
      expect(agent, startsWith('NovaParis/'));
      expect(product!.label, 'Coca-Cola 330 ml');
      expect(product.brand, 'Coca-Cola');
      expect(product.imageUrl, 'https://images.example/coca.jpg');
    });

    test('the size is not repeated, the name fits 80 characters', () {
      expect(
        const ProductInfo(
          barcode: '1',
          name: 'Eau 50 cl',
          quantity: '50 cl',
        ).label,
        'Eau 50 cl',
      );
      expect(ProductInfo(barcode: '1', name: 'x' * 90).label, hasLength(80));
    });

    test('an unknown product is null; errors are explained', () async {
      Future<Object?> answer(http.Response Function() reply) async {
        try {
          return await ProductLookup(
            client: MockClient((_) async => reply()),
            timeout: const Duration(milliseconds: 100),
          ).find('3017620422003');
        } on AppServiceException catch (e) {
          return e.message;
        }
      }

      expect(
        await answer(() => json({'status': 0, 'status_verbose': 'not found'})),
        isNull,
      );
      expect(await answer(() => json({}, 404)), isNull);
      expect(
        await answer(() => json({}, 503)),
        'Open Food Facts indisponible (503).',
      );
      expect(
        await answer(() => throw const SocketException('offline')),
        contains('Pas de connexion Internet'),
      );
      expect(
        await ProductLookup(
          client: MockClient((_) async {
            await Future<void>.delayed(const Duration(seconds: 1));
            return json(cocaCola);
          }),
          timeout: const Duration(milliseconds: 50),
        ).find('5449000000996').then<Object?>((v) => v, onError: (e) => '$e'),
        contains('ne répond pas'),
      );
      await expectLater(
        ProductLookup(client: MockClient((_) async => json(cocaCola)))
            .find('abc'),
        throwsA(isA<AppServiceException>()),
      );
    });
  });

  group('Open Beauty Facts', () {
    final showerGel = {
      'code': '4305615834696',
      'status': 1,
      'product': {
        'product_name': 'Duschgel Relax 3in1',
        'brands': 'Isana',
        'quantity': '300 ml',
      },
    };

    test('the stock looks in Open Beauty Facts first', () async {
      final hosts = <String>[];
      final product =
          await ProductLookup(
            client: MockClient((request) async {
              hosts.add(request.url.host);
              return json(showerGel);
            }),
          ).find(
            '4305615834696',
            sources: const [ProductSource.beauty, ProductSource.food],
          );
      expect(hosts, ['world.openbeautyfacts.org']);
      expect(product!.source, ProductSource.beauty);
      expect(product.label, 'Duschgel Relax 3in1 300 ml');
    });

    test('unknown there, Open Food Facts is asked next', () async {
      final hosts = <String>[];
      final lookup = ProductLookup(
        client: MockClient((request) async {
          hosts.add(request.url.host);
          return request.url.host == 'world.openfoodfacts.org'
              ? json(cocaCola)
              : json({'status': 0});
        }),
      );
      final product = await lookup.find(
        '5449000000996',
        sources: const [ProductSource.beauty, ProductSource.food],
      );
      expect(hosts, ['world.openbeautyfacts.org', 'world.openfoodfacts.org']);
      expect(product!.source, ProductSource.food);
      expect(product.source.label, 'Open Food Facts');
      hosts.clear();
      expect(
        await ProductLookup(
          client: MockClient((request) async {
            hosts.add(request.url.host);
            return json({'status': 0});
          }),
        ).find(
          '3017620422003',
          sources: const [ProductSource.beauty, ProductSource.food],
        ),
        isNull,
      );
      expect(hosts, hasLength(2));
    });

    test('an error names the database that failed', () async {
      expect(
        await ProductLookup(client: MockClient((_) async => json({}, 502)))
            .find('4305615834696', sources: const [ProductSource.beauty])
            .then<Object?>((v) => v, onError: (e) => '$e'),
        'Open Beauty Facts indisponible (502).',
      );
    });
  });

  group('MyMemory', () {
    test('a report in Arabic comes back in French', () async {
      Uri? asked;
      final translator = ReportTranslator(
        client: MockClient((request) async {
          asked = request.url;
          return json(translated('Le lavabo fuit.', 'ar'));
        }),
      );
      final t = await translator.toFrench('الحوض يسرب الماء');
      expect(asked!.host, 'api.mymemory.translated.net');
      expect(asked!.queryParameters['langpair'], 'autodetect|fr');
      expect(asked!.queryParameters['q'], 'الحوض يسرب الماء');
      expect(t.text, 'Le lavabo fuit.');
      expect(t.fromLabel, 'arabe');
      expect(t.alreadyFrench, isFalse);
    });

    test('a report already in French is left as it is', () async {
      final t = await ReportTranslator(
        client: MockClient(
          (_) async => json({
            'responseData': {
              'translatedText': 'PLEASE SELECT TWO DISTINCT LANGUAGES',
            },
            'responseStatus': '403',
            'responseDetails': 'PLEASE SELECT TWO DISTINCT LANGUAGES',
          }),
        ),
      ).toFrench('Le lavabo fuit');
      expect(t.alreadyFrench, isTrue);
      expect(t.text, 'Le lavabo fuit');
    });

    test('a long text is sent in pieces of 500 bytes at most', () async {
      final pieces = <String>[];
      final t = await ReportTranslator(
        client: MockClient((request) async {
          pieces.add(request.url.queryParameters['q']!);
          return json(translated('morceau', 'ar'));
        }),
      ).toFrench(List.filled(80, 'الماء').join(' '));
      expect(pieces.length, greaterThan(1));
      for (final piece in pieces) {
        expect(utf8.encode(piece).length, lessThanOrEqualTo(500));
      }
      expect(t.text, List.filled(pieces.length, 'morceau').join(' '));
    });

    test('quota, network and server errors are explained', () async {
      Future<String> error(http.Response Function() reply) =>
          ReportTranslator(client: MockClient((_) async => reply()))
              .toFrench('The sink is leaking')
              .then((t) => t.text, onError: (e) => '$e');

      expect(
        await error(
          () => json({...translated('', 'en'), 'quotaFinished': true}),
        ),
        'Quota de traduction du jour atteint. Réessayez demain.',
      );
      expect(
        await error(() => throw const SocketException('offline')),
        'Pas de connexion Internet : traduction impossible.',
      );
      expect(
        await error(() => http.Response('oops', 500)),
        'Traduction indisponible.',
      );
    });

    test('HTML entities in the answer are decoded', () async {
      final t = await ReportTranslator(
        client: MockClient(
          (_) async => json(translated('L&#39;évier fuit', 'en')),
        ),
      ).toFrench('The sink is leaking');
      expect(t.text, 'L\'évier fuit');
      expect(t.fromLabel, 'anglais');
    });
  });

  group('screens', () {
    Future<void> show(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: novaTheme(), home: home));
      await tester.pumpAndSettle();
      addTearDown(() => tester.pumpWidget(const SizedBox()));
    }

    testWidgets('the Manager scans a can: the minibar item fills itself in', (
      tester,
    ) async {
      final store = MemoryStore()..signIn('manager');
      final catalog = CatalogData(SqliteRoomCatalog(store));
      await catalog.load();
      var lookups = 0;
      await show(
        tester,
        MinibarCatalogScreen(
          catalog: catalog,
          scan: (_) async => '5449000000996',
          lookup: ProductLookup(
            client: MockClient((_) async {
              lookups++;
              return json(cocaCola);
            }),
          ),
        ),
      );
      await tester.tap(find.text('Nouvel article'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scanner le code-barres'));
      await tester.pumpAndSettle();
      expect(lookups, 1);
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Article'),
            )
            .controller!
            .text,
        'Coca-Cola 330 ml',
      );
      expect(
        find.textContaining('Fiche Open Food Facts · 5449000000996'),
        findsOneWidget,
      );
      // The Manager adds the price and the stock, then saves as usual.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Prix de vente'),
        '4,5',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'En réserve'),
        '24',
      );
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      expect(find.text('Article ajouté au minibar'), findsOneWidget);
      expect(find.text('Coca-Cola 330 ml'), findsOneWidget);
      catalog.dispose();
    });

    testWidgets('an unknown product or no network keeps the form manual', (
      tester,
    ) async {
      final store = MemoryStore()..signIn('manager');
      final catalog = CatalogData(SqliteRoomCatalog(store));
      await catalog.load();
      var online = true;
      await show(
        tester,
        MinibarCatalogScreen(
          catalog: catalog,
          scan: (_) async => '3017620422003',
          lookup: ProductLookup(
            client: MockClient((_) async {
              if (!online) throw const SocketException('offline');
              return json({'status': 0});
            }),
          ),
        ),
      );
      await tester.tap(find.text('Nouvel article'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scanner le code-barres'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Code 3017620422003 inconnu d’Open Food Facts : saisissez l’article à la main.',
        ),
        findsOneWidget,
      );
      online = false;
      await tester.tap(find.text('Scanner le code-barres'));
      await tester.pumpAndSettle();
      expect(
        find.text('Pas de connexion Internet. Saisissez l’article à la main.'),
        findsOneWidget,
      );
      expect(find.text('Ajouter'), findsOneWidget, reason: 'still usable');
      catalog.dispose();
    });

    testWidgets(
      'a report is translated under the original; errors stay readable',
      (tester) async {
        final store = MemoryStore();
        final data = (await loadAs(store, 'amina'))
          ..createVoiceNotes = (() => FakeVoiceNotes());
        final issue = data.issues.first; // room 224, "Télévision sans signal"
        var reply = json(translated('The TV has no signal', 'en'));
        await show(
          tester,
          IssueDetailScreen(
            data: data,
            issueId: issue.id,
            translator: ReportTranslator(
              client: MockClient((_) async => reply),
            ),
          ),
        );
        expect(find.text(issue.description), findsOneWidget);
        await tester.tap(find.text('Traduire en français'));
        await tester.pumpAndSettle();
        expect(
          find.text('Traduction automatique (anglais → français)'),
          findsOneWidget,
        );
        expect(find.text('The TV has no signal'), findsOneWidget);
        expect(find.text(issue.description), findsOneWidget, reason: 'kept');
        await tester.pumpWidget(const SizedBox());

        reply = json({...translated('', 'en'), 'quotaFinished': true});
        await show(
          tester,
          IssueDetailScreen(
            data: data,
            issueId: issue.id,
            translator: ReportTranslator(
              client: MockClient((_) async => reply),
            ),
          ),
        );
        await tester.tap(find.text('Traduire en français'));
        await tester.pumpAndSettle();
        expect(
          find.text('Quota de traduction du jour atteint. Réessayez demain.'),
          findsOneWidget,
        );
        expect(find.text('Traduire en français'), findsOneWidget);
        data.dispose();
      },
    );

    testWidgets('a report already in French says so', (tester) async {
      final store = MemoryStore();
      final data = (await loadAs(store, 'amina'))
        ..createVoiceNotes = (() => FakeVoiceNotes());
      final issue = data.issues.first;
      await show(
        tester,
        IssueDetailScreen(
          data: data,
          issueId: issue.id,
          translator: ReportTranslator(
            client: MockClient(
              (_) async => json({
                'responseStatus': '403',
                'responseDetails': 'PLEASE SELECT TWO DISTINCT LANGUAGES',
              }),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Traduire en français'));
      await tester.pumpAndSettle();
      expect(find.text('Déjà en français.'), findsOneWidget);
      data.dispose();
    });

    Future<void> openSupplyForm(
      WidgetTester tester,
      MemoryStore store, {
      required String code,
      required ProductLookup lookup,
    }) async {
      final data = await loadAs(store, 'amina');
      addTearDown(data.dispose);
      await show(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => SupplyFormDialog(
                  data: data,
                  scan: (_) async => code,
                  lookup: lookup,
                ),
              ),
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('the supervisor scans a shower gel: an amenity is filled in', (
      tester,
    ) async {
      final store = MemoryStore();
      await openSupplyForm(
        tester,
        store,
        code: '4305615834696',
        lookup: ProductLookup(
          client: MockClient(
            (request) async => request.url.host == 'world.openbeautyfacts.org'
                ? json({
                    'status': 1,
                    'product': {
                      'product_name': 'Duschgel Relax 3in1',
                      'brands': 'Isana',
                      'quantity': '300 ml',
                    },
                  })
                : json({'status': 0}),
          ),
        ),
      );
      await tester.tap(find.text('Scanner le code-barres'));
      await tester.pumpAndSettle();
      String field(String label) => tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, label))
          .controller!
          .text;
      expect(field('Article'), 'Duschgel Relax 3in1 300 ml');
      expect(field('Unité'), 'flacons');
      expect(find.text('Produits d’accueil'), findsOneWidget);
      expect(
        find.textContaining('Fiche Open Beauty Facts · 4305615834696'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Quantité en stock'),
        '40',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Seuil d’alerte'),
        '10',
      );
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      final saved = (store.state['supplies'] as List).firstWhere(
        (s) => s['name'] == 'Duschgel Relax 3in1 300 ml',
      );
      expect(saved['category'], 'accueil');
      expect(saved['unit'], 'flacons');
      expect(saved['quantity'], 40);
    });

    testWidgets('a drink found in Open Food Facts becomes a minibar item', (
      tester,
    ) async {
      await openSupplyForm(
        tester,
        MemoryStore(),
        code: '5449000000996',
        lookup: ProductLookup(
          client: MockClient(
            (request) async => request.url.host == 'world.openfoodfacts.org'
                ? json(cocaCola)
                : json({'status': 0}),
          ),
        ),
      );
      await tester.tap(find.text('Scanner le code-barres'));
      await tester.pumpAndSettle();
      expect(find.text('Minibar'), findsOneWidget);
      expect(find.text('Prix de vente'), findsOneWidget, reason: 'minibar');
      expect(
        find.textContaining('Fiche Open Food Facts · 5449000000996'),
        findsOneWidget,
      );
    });

    testWidgets('unknown everywhere: the stock form stays manual', (
      tester,
    ) async {
      await openSupplyForm(
        tester,
        MemoryStore(),
        code: '3017620422003',
        lookup: ProductLookup(
          client: MockClient((_) async => json({'status': 0})),
        ),
      );
      await tester.tap(find.text('Scanner le code-barres'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Produit 3017620422003 introuvable : saisissez-le à la main.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Produits d’entretien'),
        findsOneWidget,
        reason: 'type kept',
      );
    });
  });
}
