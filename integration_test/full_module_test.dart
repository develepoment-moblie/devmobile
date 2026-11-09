import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:nova_paris/app/modules.dart';
import 'package:nova_paris/app/nova_app.dart';
import 'package:nova_paris/housekeeping/housekeeping_module.dart';
import 'package:nova_paris/housekeeping/services/mutation_meta.dart';
import 'package:nova_paris/housekeeping/services/room_catalog_backend.dart';
import 'package:nova_paris/housekeeping/services/sqlite_housekeeping.dart';
import 'package:nova_paris/housekeeping/services/sqlite_room_catalog.dart';
import 'package:nova_paris/shared/models/app_user.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_events.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

// End-to-end test of the whole housekeeping module on a real phone, through
// the real screens. Every step is checked, then photographed; the steps and
// their results go to the driver for the report.
// It uses its own database (nova_paris_e2e.db, recreated each run): the
// phone's real data is never read or changed.
//   flutter drive --driver=test_driver/full_module_driver.dart \
//     --target=integration_test/full_module_test.dart -d <device>
// Android's own screens (camera, gallery, share sheet, file picker) cannot
// be driven by a test: the photos are injected through the module's rules.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('full housekeeping module', (tester) async {
    final path = p.join(await getDatabasesPath(), 'nova_paris_e2e.db');
    await deleteDatabase(path);
    final database = await AppDatabase.open(
      schemas: [for (final module in novaModules) ?module.schema],
      path: path,
    );
    final session = AppSession(
      database: database,
      staff: userManagement.staffDirectory,
    );
    attachModules(session);
    final store = housekeepingStoreFor(session);
    final rules = SqliteHousekeeping(store, events: session.events);
    final staff = await session.staff.users();
    AppUser user(String id) => staff.firstWhere((u) => u.id == id);
    final charges = <ExtraCharged>[];
    session.events.on<ExtraCharged>().listen(charges.add);
    final photo = base64Encode(
      img.encodeJpg(
        img.fill(
          img.Image(width: 64, height: 48),
          color: img.ColorRgb8(30, 100, 80),
        ),
        quality: 70,
      ),
    );

    Future<Map<String, dynamic>> state() => store.readState();
    Future<Map> room(String n) async =>
        ((await state())['rooms'] as List).firstWhere((r) => r['number'] == n)
            as Map;
    Future<void> mutate(String path, [Map<String, dynamic>? body]) =>
        rules.mutate(path, {...mutationMeta(), ...?body});
    Future<void> roomAction(
      String n,
      String action, [
      Map<String, dynamic>? b,
    ]) async => mutate('/v1/rooms/$n/$action', {
      'version': (await room(n))['version'],
      ...?b,
    });

    // Setup through the rules, before the screens: the Manager sets a
    // 5-minute estimate (late alert after 6 min 15 s), and room 101 is
    // cleaned by Lina and awaits inspection.
    session.signIn(user('manager'));
    await SqliteRoomCatalog(store).mutate(
      RoomCatalogAction.setCategoryEstimate,
      {...mutationMeta(), 'category': 'Chambre Deluxe', 'minutes': 5},
    );
    session.signIn(user('amina'));
    await roomAction('101', 'assign', {
      'employeeId': 'lina',
      'note': '',
      'urgent': false,
    });
    session.signIn(user('lina'));
    await roomAction('101', 'start');
    for (var i = 0; i < ((await room('101'))['tasks'] as List).length; i++) {
      await roomAction('101', 'checklist', {
        'index': i,
        'value': true,
        'photo': photo,
      });
    }
    await roomAction('101', 'submit');
    session.signOut();

    await binding.convertFlutterSurfaceToImage();
    await tester.pumpWidget(NovaApp(session: session));

    // ------------------------------------------------------------ helpers
    final steps = <Map<String, dynamic>>[];
    var number = 0;
    var phase = '';

    Future<void> wait([int ms = 900]) async {
      for (var i = 0; i < ms ~/ 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    final vertical = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    );

    // Waits for [finder], scrolling the page down then up if needed.
    Future<Finder> reveal(Finder finder, {int seconds = 8}) async {
      for (var i = 0; i < seconds * 10; i++) {
        if (finder.evaluate().isNotEmpty) return finder;
        await tester.pump(const Duration(milliseconds: 100));
        if (i == 15 || i == 40) {
          for (final dy in [-350.0, -350, -350, -350, -350, 1400]) {
            if (finder.evaluate().isNotEmpty || vertical.evaluate().isEmpty) {
              break;
            }
            await tester.drag(vertical.last, Offset(0, dy.toDouble()));
            await tester.pump(const Duration(milliseconds: 300));
          }
        }
      }
      throw StateError(
        'Élément introuvable : ${finder.describeMatch(Plurality.zero)}',
      );
    }

    // [finder] is waited for first; [last] picks the top-most match (a
    // dialog's button rather than the page's).
    Future<void> tap(Finder finder, {bool last = false}) async {
      final found = await reveal(finder);
      final target = last ? found.last : found.first;
      await tester.ensureVisible(target);
      await wait(300);
      await tester.tap(target);
      await wait(700);
    }

    Future<void> tapText(String text) => tap(find.text(text), last: true);

    Future<void> type(Finder field, String text) async {
      await tester.enterText((await reveal(field)).first, text);
      await wait(300);
    }

    Future<void> back() async {
      await tester.binding.handlePopRoute();
      await wait(800);
    }

    void check(bool value, String message) {
      if (!value) throw StateError(message);
    }

    Future<void> step(
      String id,
      String title,
      String how,
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
      await wait(1200);
      final shot =
          '${(++number).toString().padLeft(2, '0')}_${status == 'passed' ? '' : 'ECHEC_'}$id';
      try {
        await binding.takeScreenshot(shot);
      } catch (_) {}
      steps.add({
        'n': number,
        'phase': phase,
        'id': id,
        'title': title,
        'how': how,
        'status': status,
        'detail': detail,
        'ms': watch.elapsedMilliseconds,
        'screenshot': '$shot.png',
      });
    }

    // Each role starts from a fresh app on the login screen.
    Future<void> signIn(String name) async {
      session.signOut();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(NovaApp(session: session, key: UniqueKey()));
      await wait(1200);
      await tapText(name);
      await tapText('Entrer · $name');
      await tapText('Chambres et ménage');
      await wait(2500);
    }

    Future<List<String>> phoneNotifications() async {
      final android = FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return [
        for (final n in await android?.getActiveNotifications() ?? const [])
          if (n.title != null) n.title!,
      ];
    }

    Future<List<String>> scheduledAlerts() async => [
      for (final n
          in await FlutterLocalNotificationsPlugin()
              .pendingNotificationRequests())
        '${n.title} · ${n.payload}',
    ];

    // ======================================================== supervisor
    phase = 'Gouvernante (Amina)';
    await step(
      'connexion',
      'Écran de connexion',
      'Lancement de l’application',
      () async {
        await wait(1500);
        check(
          find.text('Amina').evaluate().isNotEmpty,
          'Amina absente de la liste',
        );
        return 'Les comptes de test sont proposés';
      },
    );
    await step(
      'accueil_gouvernante',
      'Accueil de la gouvernante',
      'Connexion d’Amina, ouverture de « Chambres et ménage »',
      () async {
        await signIn('Amina');
        await reveal(find.text('Bonjour Amina.'));
        return 'Accueil et raccourcis affichés';
      },
    );
    await step(
      'chambres_statuts',
      'Chambres par statut',
      'Onglet « Chambres »',
      () async {
        await tap(find.text('Chambres'), last: true);
        await reveal(find.text('Chambre 112'));
        return '16 chambres : libres, occupée, à nettoyer, maintenance';
      },
    );
    await step('attribution_urgente', 'Attribution urgente en direct', 'Chambre 305 ouverte ; attribution à Sarah (urgente) par les règles ; la fiche se met à jour seule', () async {
      await tapText('Chambre 305');
      await roomAction('305', 'assign', {
        'employeeId': 'sarah',
        'note': 'Client VIP à 11 h',
        'urgent': true,
      });
      await reveal(find.textContaining('Sarah'));
      check((await room('305'))['employeeId'] == 'sarah', 'Non attribuée');
      return 'Fiche mise à jour sans actualiser : « Agent d’étage · Sarah »';
    });
    await step(
      'attribution_auto',
      'Attribution automatique',
      'Onglet « Ménage » → « Attribution automatique » → appliquer',
      () async {
        await back();
        await tap(find.text('Ménage'), last: true);
        await tap(find.textContaining('Attribution automatique'));
        await reveal(find.textContaining('Appliquer l’attribution'));
        final before = ((await state())['rooms'] as List)
            .where((r) => r['employeeId'] != null)
            .length;
        await tap(find.textContaining('Appliquer l’attribution'));
        await wait(2000);
        final after = ((await state())['rooms'] as List)
            .where((r) => r['employeeId'] != null)
            .length;
        check(after > before, 'Aucune chambre attribuée');
        return '${after - before} chambres réparties entre les agents';
      },
    );
    await step('depart_client', 'Départ d’un client (événement Réservations)', 'Événement GuestCheckedOut(112) émis ; notification et chambre à nettoyer', () async {
      await back();
      session.events.emit(const GuestCheckedOut('112'));
      await wait(2500);
      check(
        (await room('112'))['status'] == 'dirty',
        'Chambre 112 pas à nettoyer',
      );
      await tester.tap(find.byTooltip('Notifications').first);
      await wait(1200);
      await reveal(find.text('Départ client'));
      return 'Chambre 112 à nettoyer, notification « Départ client »';
    });
    await step(
      'stock_bas',
      'Stock et alerte de stock bas',
      'Onglet « Stock » ; sortie de 27 draps par les règles (seuil 15)',
      () async {
        await back();
        await tap(find.text('Stock'), last: true);
        final sheets = ((await state())['supplies'] as List).firstWhere(
          (x) => x['id'] == 'sheets',
        );
        await mutate('/v1/supplies/sheets/movement', {
          'version': sheets['version'],
          'delta': -27,
        });
        await wait(2000);
        await reveal(find.text('Stock bas'));
        return 'Draps : 15, badge « Stock bas », alerte envoyée';
      },
    );
    await step(
      'stock_types',
      'Filtre par type d’article',
      'Puce « Minibar »',
      () async {
        await tapText('Minibar');
        await reveal(find.text('Soda 33 cl'));
        check(find.text('Serviettes').evaluate().isEmpty, 'Filtre inactif');
        return 'Seuls les articles du minibar, avec leur prix';
      },
    );
    await step(
      'blanchisserie_envoi',
      'Blanchisserie : envoi',
      '« Blanchisserie » → « Envoyer du linge » → 10 serviettes',
      () async {
        await tapText('Tous');
        await tap(find.textContaining('Blanchisserie'));
        await tapText('Envoyer du linge');
        await type(find.byKey(const ValueKey('qty-towels')), '10');
        await tapText('Envoyer');
        await reveal(find.text('En blanchisserie'));
        final towels = ((await state())['supplies'] as List).firstWhere(
          (x) => x['id'] == 'towels',
        );
        check(
          towels['quantity'] == 58,
          'Stock serviettes ${towels['quantity']}',
        );
        return 'Serviettes 68 → 58';
      },
    );
    await step(
      'blanchisserie_retour',
      'Blanchisserie : retour avec perte',
      '« Enregistrer le retour » : 8 reçues, 1 abîmée, 1 perdue',
      () async {
        await tapText('Enregistrer le retour');
        await type(find.byKey(const ValueKey('Reçu-towels')), '8');
        await type(find.byKey(const ValueKey('Abîmé-towels')), '1');
        await type(find.byKey(const ValueKey('Perdu-towels')), '1');
        await tap(find.text('Enregistrer le retour'), last: true);
        await reveal(find.textContaining('8 reçus'));
        final towels = ((await state())['supplies'] as List).firstWhere(
          (x) => x['id'] == 'towels',
        );
        check(
          towels['quantity'] == 66,
          'Stock serviettes ${towels['quantity']}',
        );
        return 'Serviettes 58 → 66 ; abîmé et perdu notés au journal';
      },
    );
    await step(
      'journal_stock',
      'Journal du stock',
      'Stock → « Journal »',
      () async {
        await back();
        await tap(find.text('Journal'));
        await reveal(find.textContaining('Envoi en blanchisserie'));
        return 'Chaque mouvement avec personne, chambre et heure';
      },
    );
    await step(
      'reglages_notifications',
      'Réglages des notifications',
      'Cloche → réglages → couper puis remettre « Stock bas »',
      () async {
        await back();
        await tester.tap(find.byTooltip('Notifications').first);
        await wait(1000);
        await tester.tap(find.byTooltip('Réglages des notifications'));
        await wait(1000);
        await tapText('Stock bas');
        await reveal(find.text('Notifications désactivées'));
        await tapText('Stock bas');
        await reveal(find.text('Notifications activées'));
        return 'Réglage enregistré pour Amina seulement';
      },
    );
    await step(
      'notifications_telephone',
      'Notifications du téléphone',
      'Lecture des notifications Android affichées par l’application',
      () async {
        await back();
        await back();
        final shown = await phoneNotifications();
        check(
          shown.contains('Départ client') || shown.contains('Stock bas'),
          'Aucune notification Android (autorisation refusée ?) : $shown',
        );
        return 'Affichées : ${shown.toSet().join(', ')}';
      },
    );
    await step(
      'tableau_de_bord',
      'Tableau de bord',
      'Accueil → « Tableau de bord »',
      () async {
        await tap(find.text('Accueil'), last: true);
        await tap(find.text('Tableau de bord'));
        await reveal(find.text('Chambres à nettoyer'));
        return 'Chambres par statut, agents, signalements';
      },
    );
    await step(
      'sauvegarde',
      'Sauvegarde manuelle',
      'Accueil → « Sauvegardes » → « Sauvegarder maintenant »',
      () async {
        await back();
        await tap(find.text('Sauvegardes'));
        await tapText('Sauvegarder maintenant');
        await reveal(find.text('Sauvegarde enregistrée'));
        return 'Fichier .json.gz créé dans le dossier de l’application';
      },
    );
    await step('objet_trouve', 'Objet trouvé : prévenir le client', 'Montre enregistrée en 305 ; « Objets trouvés » → l’objet → « Prévenir le client » par téléphone', () async {
      await back();
      await mutate('/v1/lost/new/create', {
        'roomNumber': '305',
        'description': 'Montre dorée',
      });
      await tap(find.text('Objets trouvés'));
      await tapText('Montre dorée');
      await tapText('Prévenir le client');
      await tapText('Téléphone');
      await tapText('Enregistrer la tentative');
      await reveal(find.text('Client prévenu · Téléphone · Amina'));
      return 'Statut « Client prévenu », tentative dans l’historique';
    });
    await step(
      'objet_rendu',
      'Objet trouvé : remis',
      '« Rendre » → « M. Martin »',
      () async {
        await tapText('Rendre');
        await type(find.byType(TextFormField), 'M. Martin');
        await tapText('Confirmer la restitution');
        await reveal(find.text('Remis · Amina'));
        return 'Statut « Remis », rendu à M. Martin';
      },
    );

    // ============================================================= agent
    phase = 'Agent d’étage (Sarah)';
    await step(
      'accueil_agent',
      'Accueil de l’agent',
      'Connexion de Sarah',
      () async {
        await signIn('Sarah');
        await reveal(find.text('Bonjour Sarah.'));
        return 'Ses chambres et sa progression';
      },
    );
    await step(
      'tache_urgente',
      'Notification « Tâche urgente »',
      'Cloche de Sarah',
      () async {
        await tester.tap(find.byTooltip('Notifications').first);
        await wait(1200);
        await reveal(find.text('Tâche urgente'));
        return '« Chambre 305 à traiter en priorité · Client VIP à 11 h »';
      },
    );
    await step(
      'nettoyage_demarre',
      'Démarrer le nettoyage et le minuteur',
      '« Mes chambres » → Chambre 305 → « Commencer le nettoyage »',
      () async {
        await back();
        await tap(find.text('Mes chambres'), last: true);
        await tapText('Chambre 305');
        await tapText('Commencer le nettoyage');
        await reveal(find.text('Pause'));
        return 'Nettoyage en cours, minuteur lancé';
      },
    );
    await step(
      'alerte_programmee',
      'Alerte de retard confiée à Android',
      'Lecture des alertes programmées',
      () async {
        await wait(2000);
        final planned = await scheduledAlerts();
        check(
          planned.any((a) => a.contains('late:305')),
          'Rien de programmé : $planned',
        );
        return 'Programmée : ${planned.join(' ; ')}';
      },
    );
    await step('minuteur_pause', 'Pause du minuteur', '« Pause »', () async {
      await tapText('Pause');
      await reveal(find.text('Reprendre'));
      await wait(1500);
      final planned = await scheduledAlerts();
      check(
        !planned.any((a) => a.contains('late:305')),
        'Alerte encore programmée',
      );
      return 'Minuteur en pause, alerte de retard retirée';
    });
    await step(
      'minuteur_reprise',
      'Reprise du minuteur',
      '« Reprendre »',
      () async {
        await tapText('Reprendre');
        await reveal(find.text('Pause'));
        return 'Minuteur relancé';
      },
    );
    await step('controles_photos', 'Contrôles avec photo', 'Les photos (appareil photo) sont injectées par les règles ; la fiche se met à jour', () async {
      for (var i = 0; i < ((await room('305'))['tasks'] as List).length; i++) {
        await roomAction('305', 'checklist', {
          'index': i,
          'value': true,
          'photo': photo,
        });
      }
      await wait(2000);
      await reveal(find.text('Photo enregistrée'));
      return '4 tâches cochées, une photo chacune';
    });
    await step(
      'nettoyage_termine',
      'Terminer le nettoyage',
      '« Terminer le nettoyage »',
      () async {
        await tapText('Terminer le nettoyage');
        await reveal(find.text('Nettoyage envoyé pour validation'));
        check(
          (await room('305'))['cleaning'] == 'review',
          'Pas en attente de validation',
        );
        return 'Envoyé à la gouvernante ; minuteur arrêté';
      },
    );
    await step('signalement', 'Signaler un problème avec note vocale', 'Chambre 214 → « Signaler un problème » → Plomberie, Haute, note vocale de 3 s (micro réel)', () async {
      await back();
      await tapText('Chambre 214');
      await tapText('Signaler un problème');
      await tapText('Plomberie');
      await type(
        find.widgetWithText(TextFormField, 'Description'),
        'Fuite sous le lavabo',
      );
      await tapText('Haute');
      await tapText('Note vocale (1:00 maximum)');
      await reveal(find.text('Arrêter'), seconds: 25);
      await wait(3000);
      await tapText('Arrêter');
      await reveal(find.textContaining('Note vocale · 0:0'));
      await tester.tap(find.byTooltip('Écouter'));
      await wait(3500);
      await tapText('Envoyer le signalement');
      await reveal(find.text('Problème signalé à la maintenance'));
      final issue = ((await state())['issues'] as List).firstWhere(
        (i) => i['room_number'] == '214',
      );
      check(issue['voice_path'] != null, 'Sans note vocale');
      return 'Signalement Plomberie / Haute, note vocale de ${issue['voice_seconds']} s';
    });
    await step(
      'minibar_consommation',
      'Minibar : consommation',
      'Chambre 214 → « Minibar » → 2 sodas',
      () async {
        await tap(find.textContaining('Minibar'));
        await tapText('Ajouter une consommation');
        await type(find.byKey(const ValueKey('qty-minibar-soda')), '2');
        await tapText('Enregistrer');
        await reveal(find.text('Soda 33 cl × 2'));
        return '2 sodas, 9,00 €, en attente';
      },
    );
    await step(
      'demande_fournitures',
      'Demande de fournitures',
      'Accueil → « Mes demandes de fournitures » → 5 savons',
      () async {
        await back();
        await back();
        await tap(find.text('Mon service'), last: true);
        await tap(find.textContaining('Mes demandes de fournitures'));
        await tapText('Nouvelle demande');
        await type(find.byKey(const ValueKey('qty-soap')), '5');
        await tapText('Envoyer la demande');
        await reveal(find.text('Demandée'));
        return 'Demande envoyée à la gouvernante';
      },
    );

    // ======================================================== supervisor
    phase = 'Gouvernante (Amina), suite';
    await step('inspection_renvoi', 'Inspection notée : renvoi', 'Chambre 101 (Lina) → « Inspecter » → un point non conforme → « Renvoyer en nettoyage »', () async {
      await signIn('Amina');
      await tap(find.text('Chambres'), last: true);
      await tapText('Chambre 101');
      await tapText('Inspecter le nettoyage');
      await tap(find.text('Non conforme').first);
      await type(
        find.widgetWithText(TextFormField, 'Ce qui ne va pas'),
        'Traces sur le miroir',
      );
      await tapText('Renvoyer en nettoyage');
      await tapText('Renvoyer');
      await reveal(find.text('Chambre renvoyée en nettoyage'));
      final r = await room('101');
      check(
        r['cleaning'] == 'inProgress' && r['employeeId'] == 'lina',
        'Renvoi non fait',
      );
      return 'Score 75/100 < 80 ; renvoyée à Lina en priorité';
    });
    await step(
      'inspection_validee',
      'Inspection notée : validation',
      'Chambre 305 (Sarah) → « Inspecter » → tout conforme → « Valider »',
      () async {
        await back();
        await tapText('Chambre 305');
        await tapText('Inspecter le nettoyage');
        await tapText('Valider le nettoyage');
        await reveal(find.text('Nettoyage validé · chambre libre'));
        check((await room('305'))['status'] == 'ready', 'Chambre pas libre');
        return 'Score 100/100, chambre 305 libre (RoomReady envoyé)';
      },
    );
    await step('maintenance_terminee', 'Maintenance terminée → remettre à nettoyer', 'Événement MaintenanceResolved(224) ; « Signalements » → Résolus → « Remettre à nettoyer »', () async {
      await back();
      session.events.emit(const MaintenanceResolved('224'));
      await wait(2000);
      await tap(find.text('Accueil'), last: true);
      await tap(find.text('Signalements'));
      await tap(find.textContaining('Résolus'));
      await tapText('Chambre 224 · Autre');
      await tapText('Remettre à nettoyer');
      await reveal(find.text('Chambre 224 remise à nettoyer'));
      check(
        (await room('224'))['status'] == 'dirty',
        'Toujours en maintenance',
      );
      return 'Signalement clôturé, chambre 224 à nettoyer';
    });
    await step(
      'signalement_sarah',
      'Signalement de Sarah reçu',
      'Signalements → Signalés',
      () async {
        await back();
        await tap(find.textContaining('Signalés'));
        await reveal(find.text('Chambre 214 · Plomberie'));
        return 'Visible avec priorité, photo et note vocale';
      },
    );
    await step(
      'demande_traitee',
      'Demande de fournitures : livrée',
      'Stock → « Demandes » → Approuver → Préparée → Livrée',
      () async {
        await back();
        await tap(find.text('Stock'), last: true);
        await tap(find.textContaining('Demandes ·'));
        await tapText('Approuver');
        await tap(find.text('Approuver'), last: true);
        await tapText('Marquer préparée');
        await tapText('Marquer livrée');
        await reveal(find.text('Demande livrée · stock mis à jour'));
        final soap = ((await state())['supplies'] as List).firstWhere(
          (x) => x['id'] == 'soap',
        );
        check(soap['quantity'] == 79, 'Savon ${soap['quantity']}');
        return 'Savon 84 → 79 ; Sarah prévenue à chaque étape';
      },
    );
    await step('minibar_facture', 'Minibar : valider et facturer', 'Stock → « Minibar » → chambre 214 → « Valider et facturer »', () async {
      await back();
      await tap(find.textContaining('Minibar ·'));
      await tapText('Chambre 214');
      await tapText('Valider et facturer · 9,00 €');
      await reveal(find.text('Facturé'));
      check(
        charges.length == 1 && charges.single.amountCents == 900,
        'Charges : $charges',
      );
      return 'ExtraCharged envoyé une fois : « ${charges.single.label} », 9,00 €';
    });
    await step(
      'minibar_correction',
      'Minibar : correction après facturation',
      '« Corriger la facture » → 1 soda → « Valider et facturer »',
      () async {
        await tapText('Corriger la facture');
        final entry = ((await state())['minibar'] as List).first;
        await type(find.byKey(ValueKey('qty-${entry['id']}')), '1');
        await tapText('Enregistrer la correction');
        await tapText('Valider et facturer · −4,50 €');
        await reveal(find.text('Envoyé à la facturation'));
        check(
          charges.length == 2 && charges.last.amountCents == -450,
          'Charges : $charges',
        );
        return 'Écriture compensatoire −4,50 € ; jamais deux fois la même';
      },
    );
    await step(
      'statistiques',
      'Statistiques',
      'Accueil → « Statistiques »',
      () async {
        await back();
        await back();
        await tap(find.text('Accueil'), last: true);
        await tap(find.text('Statistiques'));
        await reveal(find.text('Statistiques du ménage'));
        return 'Validés, temps moyen, réussite au premier passage';
      },
    );
    await step(
      'tableau_de_bord_maj',
      'Tableau de bord mis à jour',
      'Accueil → « Tableau de bord »',
      () async {
        await back();
        await tap(find.text('Tableau de bord'));
        await reveal(find.text('Productivité des agents'));
        await reveal(find.text('Sarah'));
        return 'Sarah : 1 validé, score 100/100';
      },
    );

    // =========================================================== manager
    phase = 'Manager';
    await step(
      'manager_etages',
      'Étages et chambres',
      'Connexion du Manager',
      () async {
        await signIn('Manager');
        await reveal(find.text('Étage 3'));
        return 'Étages avec la couleur des statuts';
      },
    );
    await step('manager_etage', 'Chambres d’un étage', '« Étage 3 »', () async {
      await tapText('Étage 3');
      await reveal(find.text('305'));
      return 'Grille des chambres de l’étage';
    });
    await step(
      'manager_minibar',
      'Carte du minibar : nouvel article',
      '« Carte du minibar » → « Nouvel article » → Bière, 6,50 €',
      () async {
        await back();
        await tap(find.textContaining('Carte du minibar'));
        await tapText('Nouvel article');
        await type(find.widgetWithText(TextFormField, 'Article'), 'Bière');
        await type(find.widgetWithText(TextFormField, 'Prix de vente'), '6,5');
        await type(find.widgetWithText(TextFormField, 'En réserve'), '12');
        await tapText('Ajouter');
        await reveal(find.text('Bière'));
        return 'Bière ajoutée à 6,50 €';
      },
    );
    await step(
      'manager_tableau',
      'Tableau de bord du Manager',
      '« Tableau de bord »',
      () async {
        await back();
        await tap(find.text('Tableau de bord'));
        await reveal(find.text('Chambres à nettoyer'));
        return 'Mêmes chiffres que la gouvernante';
      },
    );
    await step('restauration', 'Restauration d’une sauvegarde', '« Sauvegardes » → restaurer la sauvegarde manuelle → confirmer', () async {
      await back();
      await tap(find.text('Sauvegardes'));
      await tap(find.byIcon(Icons.settings_backup_restore));
      await tapText('Restaurer');
      await reveal(find.text('Sauvegarde restaurée'), seconds: 15);
      final lost = ((await state())['lostItems'] as List);
      check(lost.isEmpty, 'L’objet trouvé après la sauvegarde est encore là');
      return 'Données revenues à l’état de la sauvegarde ; sauvegarde de sécurité faite avant';
    });

    // ============================== closing: a timer left running for the
    // late alert delivered by Android once the app is closed.
    phase = 'Fin';
    await step('minuteur_laisse', 'Minuteur laissé en marche', 'Sarah lance le minuteur de la chambre 214 ; l’alerte doit arriver app fermée', () async {
      await signIn('Sarah');
      await tap(find.text('Mes chambres'), last: true);
      await tapText('Chambre 214');
      await tapText('Lancer le minuteur');
      await reveal(find.text('Pause'));
      await wait(2500);
      final planned = await scheduledAlerts();
      check(
        planned.any((a) => a.contains('late:214')),
        'Rien de programmé : $planned',
      );
      return 'Alerte programmée vers ${DateTime.now().add(const Duration(minutes: 6, seconds: 15)).toString().substring(11, 16)}';
    });

    // The test itself passes so that the driver saves every screenshot;
    // each step's own result is in the report.
    // Added next to the screenshots the binding already keeps there.
    binding.reportData = {...?binding.reportData, 'steps': steps};
    await database.close();
  });
}
