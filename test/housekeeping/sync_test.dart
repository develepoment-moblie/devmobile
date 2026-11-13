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
import 'package:nova_paris/housekeeping/services/server_discovery.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'housekeeping_store_test.dart' show TestStaff;
import 'schema_downgrade.dart';
import 'test_backends.dart';

/// The hotel server's contract (server/lib/sync_api.dart), in memory.
class FakeHotelServer {
  final log = <Map<String, dynamic>>[];
  bool online = true;
  int? failWith;
  bool hang = false;
  int requests = 0;

  /// Its id, as GET /v1/health gives it.
  String serverId = '9d3c1a2b-5e4f-4a6b-8c7d-1e2f3a4b5c6d';

  /// Reachable only at this address when set (the computer got another one
  /// from the Wi-Fi).
  String? host;

  // Answers in UTF-8, like the real server.
  http.Response reply(Object body, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  late final client = MockClient((request) async {
    requests++;
    if (hang) await Completer<void>().future;
    if (!online || (host != null && request.url.host != host)) {
      throw const SocketException('Network is unreachable');
    }
    if (failWith != null) return http.Response('{}', failWith!);
    final path = request.url.path;
    if (path == '/v1/health') {
      return reply({
        'status': 'ok',
        'serverId': serverId,
        'mutations': log.length,
      });
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
        // Every action in order, the asking phone's own included.
        'mutations': page,
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

/// The Wi-Fi as a phone hears it: [announcing] is heard by every listener.
class FakeDiscovery extends ServerDiscovery {
  final announcing = <FoundServer>[];
  late final StreamController<FoundServer> _heard = StreamController.broadcast(
    onListen: () => announcing.forEach(_heard.add),
  );
  int listens = 0;

  @override
  Stream<FoundServer> watch() {
    listens++;
    return _heard.stream;
  }

  void announce(FoundServer server) {
    announcing.add(server);
    if (_heard.hasListener) _heard.add(server);
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

  /// The same starting data for every phone of a test (in the hotel: the
  /// same install, or the same backup restored).
  static String? template;

  static Future<Phone> open(
    String path,
    FakeHotelServer server, {
    ServerDiscovery? discovery,
  }) async {
    if (template != null && !File(path).existsSync()) {
      File(template!).copySync(path);
    }
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
      discovery: discovery,
      followWithin: const Duration(milliseconds: 300),
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

  /// The housekeeping data as the screens read it (staff list aside), to
  /// compare phones.
  Future<String> data() async =>
      jsonEncode((await store.readState())..remove('users'));
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
    Phone.template = p.join(directory.path, 'template.db');
    final made = await AppDatabase.open(
      schemas: [housekeepingSchema],
      factory: databaseFactoryFfi,
      path: Phone.template,
    );
    await made.close();
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

    test('two changes of the same room: the server\'s order decides, '
        'every phone ends up with the same data', () async {
      final manager =
          await Phone.open(p.join(directory.path, 'manager.db'), server)
            ..login('manager');
      addTearDown(() async {
        manager.sync.dispose();
        await manager.session.database.close();
      });
      final version = (await supervisor.room('305'))['version'];
      // The supervisor assigns 305 offline; meanwhile the Manager changes
      // its category, from the same version.
      server.online = false;
      await supervisor.act('305', 'assign', {
        'employeeId': 'lina',
        'note': 'Hors ligne',
        'urgent': false,
      });
      expect((await supervisor.room('305'))['employeeId'], 'lina');
      expect(await supervisor.sync.syncNow(), isFalse);
      server.online = true;
      await manager.catalog.mutate(RoomCatalogAction.update, {
        'number': '305',
        'category': 'Suite',
        'version': version,
      });
      await manager.sync.syncNow(); // #1 the Manager
      await supervisor.sync.syncNow(); // #2 the supervisor, refused
      await manager.sync.syncNow();
      await agent.sync.syncNow();

      // The supervisor's assignment is undone on her phone and explained.
      final room = await supervisor.room('305');
      expect(room['category'], 'Suite');
      expect(room['employeeId'], isNull);
      final mine = (await supervisor.sync.refresh()).conflicts.single;
      expect(mine.own, isTrue);
      expect(mine.label, 'Chambre 305 · attribution');
      expect(mine.message, contains('changé'));
      expect((await supervisor.sync.refresh()).pending, 0);
      // The other phones list the same refusal, as another phone's.
      for (final other in [manager, agent]) {
        final c = (await other.sync.refresh()).conflicts.single;
        expect(c.mutationId, mine.mutationId);
        expect(c.own, isFalse);
        expect(c.actorName, 'Amina');
      }
      // The three phones hold exactly the same data.
      final reference = await manager.data();
      expect(await supervisor.data(), reference);
      expect(await agent.data(), reference);
    });

    test('phones that sync in different orders end up identical', () async {
      final third = await Phone.open(p.join(directory.path, 'third.db'), server)
        ..login('amina');
      addTearDown(() async {
        third.sync.dispose();
        await third.session.database.close();
      });
      // Offline work on two supervisor phones, then each syncs in turn,
      // several times, in a different order.
      server.online = false;
      await supervisor.act('305', 'assign', {
        'employeeId': 'sarah',
        'note': 'A',
        'urgent': false,
      });
      await supervisor.rules.mutate('/v1/supplies/towels/movement', {
        'version': 1,
        'delta': -3,
      });
      await third.act('305', 'assign', {
        'employeeId': 'lina',
        'note': 'B',
        'urgent': true,
      });
      await third.act('306', 'assign', {
        'employeeId': 'lina',
        'note': '',
        'urgent': false,
      });
      await third.rules.mutate('/v1/supplies/towels/movement', {
        'version': 1,
        'delta': 10,
      });
      server.online = true;
      for (final order in [
        [third, supervisor, agent],
        [agent, supervisor, third],
        [supervisor, third, agent],
      ]) {
        for (final phone in order) {
          expect(await phone.sync.syncNow(), isTrue);
        }
      }
      final reference = await third.data();
      expect(await supervisor.data(), reference);
      expect(await agent.data(), reference);
      // The third phone's work reached the server first: it stands.
      expect((await agent.room('305'))['employeeId'], 'lina');
      expect((await agent.room('306'))['employeeId'], 'lina');
      final towels = (await agent.supplies()).firstWhere(
        (s) => s['id'] == 'towels',
      );
      expect(towels['quantity'], 78, reason: '68 + 10; the -3 was refused');
      expect(
        [
          for (final c in (await supervisor.sync.refresh()).conflicts)
            if (c.own) c.label,
        ],
        unorderedEquals([
          'Chambre 305 · attribution',
          'Stock · mouvement de stock',
        ]),
      );
    });

    test('an action still waiting is applied again on top', () async {
      // The agent works offline while the supervisor's actions reach the
      // server: after the sync, both show.
      await supervisor.act('305', 'assign', {
        'employeeId': 'sarah',
        'note': '',
        'urgent': false,
      });
      await supervisor.sync.syncNow();
      await agent.sync.syncNow();
      server.online = false;
      await agent.act('305', 'start');
      expect(await agent.sync.syncNow(), isFalse);
      server.online = true;
      await supervisor.act('306', 'assign', {
        'employeeId': 'lina',
        'note': '',
        'urgent': false,
      });
      await supervisor.sync.syncNow();
      await agent.sync.syncNow();
      expect((await agent.room('305'))['cleaning'], 'inProgress');
      expect((await agent.room('306'))['employeeId'], 'lina');
      expect((await agent.sync.refresh()).pending, 0);
      expect((await agent.sync.refresh()).conflicts, isEmpty);
      await supervisor.sync.syncNow();
      expect(await supervisor.data(), await agent.data());
    });

    test(
      'a change made by this phone\'s own rules survives a rebuild',
      () async {
        await supervisor.sync.syncNow(); // the confirmed version exists
        // Like a check-out told by the reservations module.
        await supervisor.store.systemChange((s) {
          for (final r in s['rooms'] as List) {
            if (r['number'] == '306') r['note'] = 'Départ client';
          }
        });
        await agent.rules.mutate('/v1/notifications/read', {
          'ids': ['vip305'],
        });
        await agent.sync.syncNow();
        await supervisor.sync.syncNow(); // rebuilds with the agent's action
        expect((await supervisor.room('306'))['note'], 'Départ client');
        expect(
          ((await supervisor.store.readState())['reads'] as Map)['sarah'],
          ['vip305'],
        );
      },
    );

    test('a restore starts the confirmed version again', () async {
      await supervisor.act('305', 'assign', {
        'employeeId': 'sarah',
        'note': '',
        'urgent': false,
      });
      await supervisor.sync.syncNow();
      final db = supervisor.session.database.database;
      expect(await db.query('housekeeping_sync_base'), hasLength(1));
      // What a restore does to the sync tables (housekeeping_backup.dart).
      await db.delete('housekeeping_sync_base');
      await db.update('housekeeping_sync_state', {
        'value': '0',
      }, where: "key = 'last_seq'");
      expect(await supervisor.sync.syncNow(), isTrue);
      expect(await db.query('housekeeping_sync_base'), hasLength(1));
      expect((await supervisor.sync.refresh()).lastSeq, 1);
      expect((await supervisor.room('305'))['employeeId'], 'sarah');
      expect((await supervisor.sync.refresh()).conflicts, isEmpty);
    });
  });

  test('a version 8 database upgrades in place, its queue kept', () async {
    final path = p.join(directory.path, 'old.db');
    var phone = await Phone.open(path, server)
      ..login('amina');
    await phone.act('305', 'assign', {
      'employeeId': 'sarah',
      'note': '',
      'urgent': false,
    });
    final db = phone.session.database.database;
    final queued = await phone.outbox();
    await dropVersion9(db);
    await db.insert('housekeeping_sync_outbox', queued.single);
    await db.update('module_versions', {
      'version': 8,
    }, where: "module = 'housekeeping'");
    phone.sync.dispose();
    await phone.session.database.close();

    phone = await Phone.open(path, server)
      ..login('amina');
    addTearDown(() async {
      phone.sync.dispose();
      await phone.session.database.close();
    });
    expect(await phone.session.database.versionOf('housekeeping'), 9);
    expect(await phone.outbox(), hasLength(1));
    expect((await phone.sync.refresh()).pending, 1);
    expect(await phone.sync.syncNow(), isTrue);
    expect(await phone.outbox(), isEmpty, reason: 'sent and confirmed');
    expect((await phone.room('305'))['employeeId'], 'sarah');
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

  group('server found on the Wi-Fi', () {
    late FakeDiscovery wifi;
    late Phone phone;
    FoundServer at(String host, {String? id}) => FoundServer(
      id: id ?? server.serverId,
      name: 'PC-ACCUEIL',
      address: Uri(scheme: 'http', host: host, port: 8080),
    );
    setUp(() async {
      wifi = FakeDiscovery();
      phone =
          await Phone.open(
              p.join(directory.path, 'wifi.db'),
              server,
              discovery: wifi,
            )
            ..login('amina');
    });
    tearDown(() async {
      phone.sync.dispose();
      await phone.session.database.close();
    });

    test('the server id is kept when the server is set', () async {
      expect((await phone.sync.refresh()).serverId, server.serverId);
    });

    test('a typed address of a server that is off: its id comes with the '
        'first sync', () async {
      server.online = false;
      await phone.sync.setServer('192.168.1.30');
      expect((await phone.sync.refresh()).serverId, isNull);
      server.online = true;
      expect(await phone.sync.syncNow(), isTrue);
      expect((await phone.sync.refresh()).serverId, server.serverId);
    });

    test('the server moved: the phone follows it and carries on', () async {
      await phone.act('305', 'assign', {
        'employeeId': 'sarah',
        'note': '',
        'urgent': false,
      });
      expect(await phone.sync.syncNow(), isTrue);
      expect((await phone.sync.refresh()).lastSeq, 1);

      // The computer restarted with another address.
      server.host = '192.168.1.42';
      wifi.announce(at('192.168.1.42'));
      await phone.act('306', 'assign', {
        'employeeId': 'sarah',
        'note': '',
        'urgent': false,
      });
      expect(await phone.sync.syncNow(), isTrue);
      final after = await phone.sync.refresh();
      expect(after.server, Uri.parse('http://192.168.1.42:8080'));
      expect(after.lastError, isNull);
      expect(after.pending, 0);
      expect(after.lastSeq, 2, reason: 'not read again from the start');
      expect(phone.sync.phase, SyncPhase.idle);
    });

    test('another server announcing itself is not followed', () async {
      server.host = '192.168.1.42';
      wifi.announce(at('192.168.1.42', id: 'someone-else'));
      expect(await phone.sync.syncNow(), isFalse);
      final view = await phone.sync.refresh();
      expect(view.server, Uri.parse('http://192.168.1.20:8080'));
      expect(view.lastError, contains('Serveur injoignable'));
      expect(phone.sync.phase, SyncPhase.offline);
    });

    test(
      'an announcement the address does not confirm is not followed',
      () async {
        // Announced with the right id, but that address answers with another.
        final id = server.serverId;
        server.host = '192.168.1.42';
        server.serverId = 'replaced';
        wifi.announce(at('192.168.1.42', id: id));
        expect(await phone.sync.syncNow(), isFalse);
        expect(
          (await phone.sync.refresh()).server,
          Uri.parse('http://192.168.1.20:8080'),
        );
      },
    );

    test('a server error is no reason to look elsewhere', () async {
      server.failWith = 500;
      expect(await phone.sync.syncNow(), isFalse);
      expect(wifi.listens, 0);
    });

    test('using a found server checks its id first', () async {
      await expectLater(
        phone.sync.useFoundServer(at('192.168.1.20', id: 'someone-else')),
        throwsA(
          isA<AppServiceException>().having(
            (e) => e.message,
            'message',
            contains('ne correspond pas'),
          ),
        ),
      );
      server.online = false;
      await expectLater(
        phone.sync.useFoundServer(at('192.168.1.50')),
        throwsA(isA<AppServiceException>()),
      );
      server.online = true;
      server.host = '192.168.1.50';
      await phone.sync.useFoundServer(at('192.168.1.50'));
      final view = await phone.sync.refresh();
      expect(view.server, Uri.parse('http://192.168.1.50:8080'));
      expect(view.serverId, server.serverId);
    });

    test('another server typed by hand starts from its first action', () async {
      server.inject('/v1/notifications/read', 'amina', {'ids': []});
      expect(await phone.sync.syncNow(), isTrue);
      expect((await phone.sync.refresh()).lastSeq, 1);
      server.serverId = 'a-new-server';
      await phone.sync.setServer('192.168.1.60');
      final view = await phone.sync.refresh();
      expect(view.lastSeq, 0);
      expect(view.serverId, 'a-new-server');
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
