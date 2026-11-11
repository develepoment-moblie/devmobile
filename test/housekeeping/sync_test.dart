import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nova_paris/housekeeping/services/app_exception.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_store.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_sync.dart';
import 'package:nova_paris/housekeeping/services/mutation_meta.dart';
import 'package:nova_paris/housekeeping/services/room_catalog_backend.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'housekeeping_store_test.dart' show TestStaff;
import 'test_backends.dart';

/// The hotel server's contract (server/lib/sync_api.dart), in memory.
class FakeHotelServer {
  final log = <Map<String, dynamic>>[];
  bool online = true;
  int? failWith;
  bool hang = false;
  int requests = 0;

  // Answers in UTF-8, like the real server.
  http.Response reply(Object body, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  late final client = MockClient((request) async {
    requests++;
    if (hang) await Completer<void>().future;
    if (!online) throw const SocketException('Network is unreachable');
    if (failWith != null) return http.Response('{}', failWith!);
    final path = request.url.path;
    if (path == '/v1/health') {
      return reply({'status': 'ok', 'mutations': log.length});
    }
    if (path == '/v1/sync/push') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final results = [];
      for (final m in body['mutations'] as List) {
        if (log.any((e) => e['mutationId'] == m['mutationId'])) {
          results.add({'mutationId': m['mutationId'], 'status': 'duplicate'});
        } else {
          log.add({
            ...m as Map<String, dynamic>,
            'seq': log.length + 1,
            'device': body['deviceId'],
          });
          results.add({'mutationId': m['mutationId'], 'status': 'applied'});
        }
      }
      return reply({'results': results});
    }
    if (path == '/v1/sync/pull') {
      final q = request.url.queryParameters;
      final since = int.parse(q['since']!);
      final limit = int.parse(q['limit']!);
      final page = log.where((m) => m['seq'] > since).take(limit).toList();
      return reply({
        'mutations': [
          for (final m in page)
            if (m['device'] != q['device']) m,
        ],
        'until': page.isEmpty ? since : page.last['seq'],
        'more': page.length == limit,
      });
    }
    return http.Response('{}', 404);
  });

  /// An action as another (possibly forged) phone would send it.
  void inject(String path, String actorId, Map<String, dynamic> body) {
    final meta = mutationMeta();
    log.add({
      'mutationId': meta['mutationId'],
      'path': path,
      'body': {...meta, ...body},
      'actorId': actorId,
      'appliedAt': '2026-11-11T09:00:00.000',
      'seq': log.length + 1,
      'device': 'forged',
    });
  }
}

/// One phone: its own database, session, rules and sync.
class Phone {
  final AppSession session;
  final HousekeepingStore store;
  final TestHousekeeping rules;
  final TestCatalog catalog;
  final HousekeepingSync sync;
  Phone._(this.session, this.store, this.sync)
    : rules = TestHousekeeping(store),
      catalog = TestCatalog(store);

  static Future<Phone> open(String path, FakeHotelServer server) async {
    final database = await AppDatabase.open(
      schemas: [housekeepingSchema],
      factory: databaseFactoryFfi,
      path: path,
    );
    final session = AppSession(database: database, staff: TestStaff());
    final store = HousekeepingStore(session);
    final sync = HousekeepingSync(
      store,
      client: server.client,
      background: false,
      timeout: const Duration(milliseconds: 200),
    );
    await sync.setServer('192.168.1.20');
    return Phone._(session, store, sync);
  }

  void login(String id) =>
      session.signIn(TestStaff.people.firstWhere((u) => u.id == id));

  Future<Map<String, dynamic>> room(String number) async =>
      ((await store.readState())['rooms'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((r) => r['number'] == number);

  Future<List<Map<String, dynamic>>> supplies() async =>
      ((await store.readState())['supplies'] as List)
          .cast<Map<String, dynamic>>();

  Future<void> act(
    String number,
    String action, [
    Map<String, dynamic> extra = const {},
  ]) async => rules.mutate('/v1/rooms/$number/$action', {
    'version': (await room(number))['version'],
    ...extra,
  });

  Future<List<Map<String, Object?>>> outbox() =>
      session.database.database.query('housekeeping_sync_outbox');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late FakeHotelServer server;
  late Phone agent, supervisor;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nova_sync_');
    server = FakeHotelServer();
    agent = await Phone.open(p.join(directory.path, 'agent.db'), server)
      ..login('sarah');
    supervisor =
        await Phone.open(p.join(directory.path, 'supervisor.db'), server)
          ..login('amina');
  });
  tearDown(() async {
    agent.sync.dispose();
    supervisor.sync.dispose();
    await agent.session.database.close();
    await supervisor.session.database.close();
    await directory.delete(recursive: true);
  });

  group('outbox', () {
    test('an action is queued in its own transaction, once', () async {
      final body = {
        ...mutationMeta(),
        'version': (await supervisor.room('305'))['version'],
        'employeeId': 'sarah',
        'note': 'Avant midi',
        'urgent': true,
      };
      await supervisor.rules.mutate('/v1/rooms/305/assign', body);
      // The same mutationId again (a retry): nothing changes, nothing queued.
      await supervisor.rules.mutate('/v1/rooms/305/assign', body);
      final rows = await supervisor.outbox();
      expect(rows, hasLength(1));
      expect(rows.single['path'], '/v1/rooms/305/assign');
      expect(rows.single['actor_id'], 'amina');
      expect(jsonDecode(rows.single['body'] as String)['note'], 'Avant midi');
      expect((await supervisor.sync.refresh()).pending, 1);
    });

    test('a refused action leaves no row', () async {
      // An agent cannot assign rooms.
      await expectLater(
        agent.act('305', 'assign', {
          'employeeId': 'sarah',
          'note': '',
          'urgent': false,
        }),
        throwsA(isA<AppServiceException>()),
      );
      expect(await agent.outbox(), isEmpty);
    });
  });

  group('two phones', () {
    test('the supervisor\'s assignment reaches the agent\'s phone', () async {
      await supervisor.act('305', 'assign', {
        'employeeId': 'sarah',
        'note': 'Avant midi',
        'urgent': true,
      });
      expect(await supervisor.sync.syncNow(), isTrue);
      expect(await supervisor.outbox(), isEmpty, reason: 'sent');
      expect(server.log, hasLength(1));

      expect((await agent.room('305'))['employeeId'], isNull);
      expect(await agent.sync.syncNow(), isTrue);
      final room = await agent.room('305');
      expect(room['employeeId'], 'sarah');
      expect(room['note'], 'Avant midi');
      expect(room['version'], (await supervisor.room('305'))['version']);
      expect((await agent.sync.refresh()).lastSeq, 1);
      expect(await agent.outbox(), isEmpty, reason: 'a replay is not resent');

      // Syncing again changes nothing (the action is not applied twice).
      final before = await agent.room('305');
      await agent.sync.syncNow();
      expect(await agent.room('305'), before);
    });

    test('a new item gets the same id on every phone', () async {
      await supervisor.rules.mutate('/v1/supplies/new/create', {
        'name': 'Peignoirs',
        'unit': 'pièces',
        'quantity': 10,
        'minimum': 2,
        'category': 'linge',
      });
      await supervisor.sync.syncNow();
      await agent.sync.syncNow();
      final created = (await supervisor.supplies()).firstWhere(
        (s) => s['name'] == 'Peignoirs',
      );
      final copy = (await agent.supplies()).firstWhere(
        (s) => s['name'] == 'Peignoirs',
      );
      expect(copy['id'], created['id']);
      expect(copy, created);

      // A later action on that item, made on the other phone, applies here.
      supervisor.login('amina');
      final second =
          await Phone.open(p.join(directory.path, 'second.db'), server)
            ..login('amina');
      addTearDown(() async {
        second.sync.dispose();
        await second.session.database.close();
      });
      await second.sync.syncNow();
      await second.rules.mutate('/v1/supplies/${created['id']}/movement', {
        'version': copy['version'],
        'delta': 5,
      });
      await second.sync.syncNow();
      await supervisor.sync.syncNow();
      expect(
        (await supervisor.supplies()).firstWhere(
          (s) => s['id'] == created['id'],
        )['quantity'],
        15,
      );
    });

    test('a replayed action keeps its author\'s rights', () async {
      // Sarah is an agent: the stock is the supervisor's.
      server.inject('/v1/supplies/new/create', 'sarah', {
        'name': 'Faux article',
        'unit': 'u',
        'quantity': 1,
        'minimum': 0,
        'category': 'linge',
      });
      server.inject('/v1/rooms/305/start', 'ghost', {'version': 1});
      expect(await supervisor.sync.syncNow(), isTrue);
      expect(
        (await supervisor.supplies()).where((s) => s['name'] == 'Faux article'),
        isEmpty,
      );
      final view = await supervisor.sync.refresh();
      expect(
        [for (final c in view.conflicts) c.message],
        ['Auteur inconnu sur ce téléphone.', 'Stock réservé à la gouvernante.'],
      );
      expect(view.conflicts.last.label, 'Stock · création');
      expect(view.lastSeq, 2, reason: 'a refused action does not block');

      await supervisor.sync.dismissConflict(view.conflicts.first.mutationId);
      expect((await supervisor.sync.refresh()).conflicts, hasLength(1));
    });

    test('the Manager\'s catalog changes are synced too', () async {
      final manager =
          await Phone.open(p.join(directory.path, 'manager.db'), server)
            ..login('manager');
      addTearDown(() async {
        manager.sync.dispose();
        await manager.session.database.close();
      });
      await manager.catalog.mutate(RoomCatalogAction.create, {
        'number': '901',
        'category': 'Suite',
      });
      await manager.sync.syncNow();
      expect(server.log.single['path'], 'catalog/create');
      await supervisor.sync.syncNow();
      expect((await supervisor.room('901'))['category'], 'Suite');
    });

    test(
      'changes to the same room made offline end in a visible conflict',
      () async {
        final version = (await supervisor.room('305'))['version'];
        // Both phones act on room 305 at the same version, without network.
        server.online = false;
        await supervisor.act('305', 'assign', {
          'employeeId': 'lina',
          'note': '',
          'urgent': false,
        });
        final manager =
            await Phone.open(p.join(directory.path, 'manager.db'), server)
              ..login('manager');
        addTearDown(() async {
          manager.sync.dispose();
          await manager.session.database.close();
        });
        await manager.catalog.mutate(RoomCatalogAction.update, {
          'number': '305',
          'category': 'Suite',
          'version': version,
        });
        expect(await supervisor.sync.syncNow(), isFalse);
        expect(supervisor.sync.phase, SyncPhase.offline);

        server.online = true;
        await manager.sync.syncNow();
        await supervisor.sync.syncNow();
        final view = await supervisor.sync.refresh();
        expect(
          view.conflicts.single.message,
          'Cette chambre a changé. Actualisez.',
        );
        expect(view.conflicts.single.actorName, 'Manager Test');
        expect(view.conflicts.single.label, 'Catalogue · chambre modifiée');
        expect(view.pending, 0, reason: 'its own action was still sent');
      },
    );
  });

  group('network', () {
    test(
      'offline: the queue waits, then drains when the Wi-Fi is back',
      () async {
        server.online = false;
        for (final n in ['305', '306']) {
          await supervisor.act(n, 'assign', {
            'employeeId': 'sarah',
            'note': '',
            'urgent': false,
          });
        }
        expect(await supervisor.sync.syncNow(), isFalse);
        var view = await supervisor.sync.refresh();
        expect(supervisor.sync.phase, SyncPhase.offline);
        expect(view.pending, 2);
        expect(view.lastError, contains('Serveur injoignable'));

        server.online = true;
        expect(await supervisor.sync.syncNow(), isTrue);
        view = await supervisor.sync.refresh();
        expect(supervisor.sync.phase, SyncPhase.idle);
        expect(view.pending, 0);
        expect(view.lastError, isNull);
        expect(view.lastSyncAt, isNotNull);
        expect(
          [for (final m in server.log) m['path']],
          ['/v1/rooms/305/assign', '/v1/rooms/306/assign'],
        );
      },
    );

    test('a server error or a timeout keeps the queue', () async {
      await supervisor.act('305', 'assign', {
        'employeeId': 'sarah',
        'note': '',
        'urgent': false,
      });
      server.failWith = 500;
      expect(await supervisor.sync.syncNow(), isFalse);
      expect(
        (await supervisor.sync.refresh()).lastError,
        'Erreur du serveur (500).',
      );
      server.failWith = null;
      server.hang = true;
      expect(await supervisor.sync.syncNow(), isFalse);
      expect(
        (await supervisor.sync.refresh()).lastError,
        'Le serveur ne répond pas (délai dépassé).',
      );
      expect((await supervisor.sync.refresh()).pending, 1);
    });

    test('a test of the connection reports the server\'s actions', () async {
      expect(
        await supervisor.sync.testConnection('192.168.1.20:8080'),
        'Serveur joignable · 0 action enregistrée.',
      );
      server.online = false;
      await expectLater(
        supervisor.sync.testConnection('192.168.1.20:8080'),
        throwsA(isA<AppServiceException>()),
      );
    });

    test('no server set: no request at all', () async {
      await supervisor.sync.clearServer();
      server.requests = 0;
      expect(await supervisor.sync.syncNow(), isFalse);
      expect(server.requests, 0);
      expect(supervisor.sync.phase, SyncPhase.off);
    });
  });

  group('server address', () {
    test('plain HTTP only on the local network', () {
      expect(
        parseServerAddress('192.168.1.20').toString(),
        'http://192.168.1.20:8080',
      );
      expect(
        parseServerAddress(' http://10.0.2.2:9000/x ').toString(),
        'http://10.0.2.2:9000',
      );
      expect(parseServerAddress('172.20.0.5:8080').port, 8080);
      expect(
        parseServerAddress('https://sync.example.com').toString(),
        'https://sync.example.com',
      );
      for (final bad in [
        '',
        'example.com',
        'http://8.8.8.8',
        '172.40.0.1',
        'ftp://192.168.1.2',
        '300.1.1.1',
      ]) {
        expect(
          () => parseServerAddress(bad),
          throwsA(isA<AppServiceException>()),
          reason: bad,
        );
      }
    });

    test('labels are in French', () {
      expect(
        describeSyncPath('/v1/rooms/204/approve'),
        'Chambre 204 · validation',
      );
      expect(
        describeSyncPath('/v1/requests/new/create'),
        'Demande de produits · création',
      );
      expect(
        describeSyncPath('catalog/archive'),
        'Catalogue · chambre archivée',
      );
      expect(pendingText(1), '1 action en attente');
      expect(pendingText(3), '3 actions en attente');
      expect(conflictText(2), '2 conflits');
    });
  });
}
