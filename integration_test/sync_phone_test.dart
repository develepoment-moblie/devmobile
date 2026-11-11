import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:nova_paris/app/modules.dart';
import 'package:nova_paris/housekeeping/screens/sync_screen.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_store.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_sync.dart';
import 'package:nova_paris/housekeeping/services/mutation_meta.dart';
import 'package:nova_paris/housekeeping/services/room_catalog_backend.dart';
import 'package:nova_paris/housekeeping/services/sqlite_housekeeping.dart';
import 'package:nova_paris/housekeeping/services/sqlite_room_catalog.dart';
import 'package:nova_paris/shared/custom/app_theme.dart';
import 'package:nova_paris/shared/models/app_user.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

// The sync with the hotel server, on a real phone, over the real Wi-Fi, with
// the server running on the computer (server/). Three "phones" (agent,
// supervisor, Manager) are three databases on this phone, each with its own
// sync, so one device shows the whole exchange. Their files
// (nova_paris_sync_*.db) are recreated each run: the phone's real data is
// never read or changed.
//   dart run server/bin/server.dart --db server/data/phone_test.db
//   flutter drive --driver=test_driver/sync_phone_driver.dart \
//     --target=integration_test/sync_phone_test.dart \
//     --dart-define=SYNC_SERVER=<computer IP>:8080 -d <device>
// Results: build/sync_phone_test/ (steps.json and screenshots).
const server = String.fromEnvironment('SYNC_SERVER');

class _Phone {
  final AppSession session;
  final HousekeepingStore store;
  final HousekeepingSync sync;
  final List<AppUser> staff;
  _Phone(this.session, this.store, this.sync, this.staff);

  void login(String id) => session.signIn(staff.firstWhere((u) => u.id == id));

  Future<Map<String, dynamic>> room(String number) async =>
      ((await store.readState())['rooms'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((r) => r['number'] == number);

  Future<void> act(
    String number,
    String action, [
    Map<String, dynamic> extra = const {},
  ]) async => SqliteHousekeeping(store).mutate('/v1/rooms/$number/$action', {
    ...mutationMeta(),
    'version': (await room(number))['version'],
    ...extra,
  });
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sync with the hotel server', (tester) async {
    final steps = <Map<String, Object?>>[];
    final phones = <_Phone>[];
    // A unique note per run: the server's log may hold earlier runs.
    final run = DateTime.now().toIso8601String().substring(11, 19);

    Future<_Phone> phone(String name, String user) async {
      final path = p.join(await getDatabasesPath(), 'nova_paris_sync_$name.db');
      await deleteDatabase(path);
      final database = await AppDatabase.open(
        schemas: [for (final module in novaModules) ?module.schema],
        path: path,
      );
      final session = AppSession(
        database: database,
        staff: userManagement.staffDirectory,
      );
      final store = HousekeepingStore(session);
      final sync = HousekeepingSync(
        store,
        background: false,
        timeout: const Duration(seconds: 6),
      );
      final staff = await session.staff.users();
      final made = _Phone(session, store, sync, staff)..login(user);
      phones.add(made);
      return made;
    }

    void check(bool ok, String message) {
      if (!ok) throw StateError(message);
    }

    Future<void> synced(_Phone phone) async {
      final ok = await phone.sync.syncNow();
      check(ok, 'Synchronisation échouée : ${phone.sync.overview?.lastError}');
    }

    var number = 0;
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
      steps.add({
        'n': ++number,
        'id': id,
        'title': title,
        'status': status,
        'detail': detail,
        'ms': watch.elapsedMilliseconds,
      });
    }

    Future<void> screenshot(String name, HousekeepingSync sync) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: novaTheme(),
          home: SyncScreen(key: UniqueKey(), sync: sync),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      try {
        await binding.convertFlutterSurfaceToImage();
      } catch (_) {}
      await tester.pump();
      await binding.takeScreenshot(name);
    }

    final agent = await phone('agent', 'sarah');
    final supervisor = await phone('supervisor', 'amina');
    final manager = await phone('manager', 'manager');
    final photo = base64Encode(
      img.encodeJpg(
        img.fill(
          img.Image(width: 64, height: 48),
          color: img.ColorRgb8(30, 100, 80),
        ),
        quality: 70,
      ),
    );

    await step('wifi', 'Le téléphone joint le serveur par le Wi-Fi', () async {
      check(server.isNotEmpty, 'SYNC_SERVER manquant (--dart-define).');
      final message = await supervisor.sync.testConnection(server);
      for (final p in phones) {
        await p.sync.setServer(server);
      }
      return '$server · $message';
    });

    await step('assign', 'La gouvernante attribue la 101 ; le téléphone de l’agent la reçoit', () async {
      await supervisor.act('101', 'assign', {
        'employeeId': 'sarah',
        'note': 'Test $run',
        'urgent': true,
      });
      check(
        (await supervisor.sync.refresh()).pending == 1,
        'Action non mise en file',
      );
      final watch = Stopwatch()..start();
      await synced(supervisor);
      check((await supervisor.sync.refresh()).pending == 0, 'File non vidée');
      await synced(agent);
      final room = await agent.room('101');
      check(room['employeeId'] == 'sarah', 'Non attribuée chez l’agent');
      check(room['note'] == 'Test $run', 'Note : ${room['note']}');
      return 'Reçue chez l’agent en ${watch.elapsedMilliseconds} ms (envoi + réception)';
    });

    await step('photos', 'L’agent nettoie avec photos ; la gouvernante voit « à valider » et les photos', () async {
      await agent.act('101', 'start');
      final tasks = ((await agent.room('101'))['tasks'] as List).length;
      for (var i = 0; i < tasks; i++) {
        await agent.act('101', 'checklist', {
          'index': i,
          'value': true,
          'photo': photo,
        });
      }
      await agent.act('101', 'submit');
      await synced(agent);
      await synced(supervisor);
      final room = await supervisor.room('101');
      check(room['cleaning'] == 'review', 'État : ${room['cleaning']}');
      final ids = [
        for (final t in room['tasks'] as List) t['photoId'] as String?,
      ];
      check(ids.every((id) => id != null), 'Photo manquante');
      for (final id in ids) {
        await supervisor.store.readAttachment(id!);
      }
      return '$tasks tâches, $tasks photos reçues (${tasks + 2} actions)';
    });

    await step(
      'approve',
      'La gouvernante valide ; la chambre est prête chez l’agent',
      () async {
        await supervisor.act('101', 'approve');
        await synced(supervisor);
        await synced(agent);
        final room = await agent.room('101');
        check(room['cleaning'] == 'completed', 'État : ${room['cleaning']}');
        return 'Chez l’agent : ${room['status']} / ${room['cleaning']}';
      },
    );

    await step('offline', 'Serveur injoignable : les actions attendent, puis partent au retour', () async {
      // Same computer, a port where nothing listens: like the Wi-Fi off.
      final down = '${Uri.parse('http://$server').host}:9';
      await supervisor.sync.setServer(down);
      for (final n in ['203', '306']) {
        await supervisor.act(n, 'assign', {
          'employeeId': 'sarah',
          'note': 'Hors ligne $run',
          'urgent': false,
        });
      }
      final ok = await supervisor.sync.syncNow();
      final view = await supervisor.sync.refresh();
      check(
        !ok && supervisor.sync.phase == SyncPhase.offline,
        'Pas hors ligne',
      );
      check(view.pending == 2, 'En attente : ${view.pending}');
      await screenshot('01_hors_ligne', supervisor.sync);
      await supervisor.sync.setServer(server);
      await synced(supervisor);
      check((await supervisor.sync.refresh()).pending == 0, 'File non vidée');
      await synced(agent);
      for (final n in ['203', '306']) {
        check((await agent.room(n))['employeeId'] == 'sarah', '$n non reçue');
      }
      return 'Hors ligne · ${view.pending} en attente (« ${view.lastError} »), puis envoyées et reçues';
    });

    await step(
      'conflict',
      'Deux changements de la même chambre : l’ordre du serveur décide, '
          'les trois téléphones finissent identiques',
      () async {
        await synced(manager);
        final version = (await manager.room('118'))['version'];
        // The supervisor assigns 118 offline while the Manager changes it.
        await supervisor.sync.setServer(
          '${Uri.parse('http://$server').host}:9',
        );
        await supervisor.act('118', 'assign', {
          'employeeId': 'lina',
          'note': '',
          'urgent': false,
        });
        await SqliteRoomCatalog(manager.store)
            .mutate(RoomCatalogAction.update, {
              ...mutationMeta(),
              'number': '118',
              'category': 'Suite $run',
              'version': version,
            });
        check(
          (await supervisor.room('118'))['employeeId'] == 'lina',
          'Attribution non affichée hors ligne',
        );
        await synced(manager); // reaches the server first
        await supervisor.sync.setServer(server);
        await synced(supervisor); // second: refused by the rules
        await synced(manager);
        await synced(agent);
        // The supervisor's phone undid her assignment and says why.
        final view = await supervisor.sync.refresh();
        final mine = view.conflicts
            .where((c) => c.own && c.label == 'Chambre 118 · attribution')
            .firstOrNull;
        check(mine != null, 'Refus non signalé à la gouvernante');
        for (final other in [manager, agent]) {
          check(
            (await other.sync.refresh()).conflicts.any(
              (c) => c.mutationId == mine!.mutationId && !c.own,
            ),
            'Refus absent sur un autre téléphone',
          );
        }
        // The three phones hold the same room 118.
        final rooms = [
          for (final p in [supervisor, manager, agent])
            jsonEncode(await p.room('118')),
        ];
        check(rooms.toSet().length == 1, 'Chambre 118 différente : $rooms');
        final room = await supervisor.room('118');
        check(
          room['category'] == 'Suite $run',
          'Catégorie : ${room['category']}',
        );
        check(room['employeeId'] == null, 'Attribution restée');
        await screenshot('02_conflit', supervisor.sync);
        return 'Identique sur les 3 téléphones (${room['category']}, non '
            'attribuée) · chez la gouvernante : « ${mine!.message} »';
      },
    );

    await step('idempotent', 'Synchroniser encore ne change rien', () async {
      final before = await agent.room('101');
      await synced(agent);
      await synced(agent);
      final after = await agent.room('101');
      check(jsonEncode(before) == jsonEncode(after), 'La chambre a changé');
      await screenshot('03_synchronise', agent.sync);
      return 'Chambre 101 identique, version ${after['version']}';
    });

    // The test passes so that the driver saves everything; each step's
    // result is in the report.
    binding.reportData = {...?binding.reportData, 'steps': steps};
    for (final p in phones) {
      p.sync.dispose();
      await p.session.database.close();
    }
  });
}
