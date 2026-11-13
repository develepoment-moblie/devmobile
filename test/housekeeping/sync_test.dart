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
import 'package:nova_paris/housekeeping/services/sync_rebase.dart';
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

  /// The copy of the data a phone sent (PUT /v1/sync/snapshot).
  ({int seq, List<int> data})? snapshot;
  int snapshotsSent = 0;
  final waits = <String?>[];

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
        'name': 'PC-ACCUEIL',
        'mutations': log.length,
        'snapshotSeq': snapshot?.seq,
      });
    }
    if (path == '/v1/sync/snapshot' && request.method == 'PUT') {
      snapshotsSent++;
      final seq = int.parse(request.url.queryParameters['seq']!);
      final stored =
          seq <= log.length && (snapshot == null || seq > snapshot!.seq);
      if (stored) snapshot = (seq: seq, data: request.bodyBytes);
      return reply({'stored': stored, 'snapshotSeq': snapshot?.seq});
    }
    if (path == '/v1/sync/snapshot') {
      if (snapshot == null) return http.Response('{}', 404);
      return http.Response.bytes(
        snapshot!.data,
        200,
        headers: {
          'content-type': 'application/gzip',
          'x-snapshot-seq': '${snapshot!.seq}',
        },
      );
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
      waits.add(q['wait']);
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

/// The Wi-Fi as a phone sees it: [announcing] is heard by every listener;
/// the scan finds the port open on the [open] addresses of [own]'s network.
class FakeDiscovery extends ServerDiscovery {
  final announcing = <FoundServer>[];
  List<String> own = ['192.168.1.13'];
  final open = <String>{};
  final tried = <String>[];

  @override
  Future<List<String>> ownAddresses() async => own;

  @override
  Future<bool> isOpen(String host, int port) async {
    tried.add('$host:$port');
    return open.contains('$host:$port');
  }

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

  /// Backups made before joining a server, all phones together.
  static int backupsBeforeJoin = 0;

  static Future<Phone> open(
    String path,
    FakeHotelServer server, {
    ServerDiscovery? discovery,
    bool connect = true,
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
      backupBeforeJoin: () async => backupsBeforeJoin++,
    );
    if (connect) await sync.setServer('192.168.1.20');
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
      expect(
        view.conflicts.every((c) => !c.merged),
        isTrue,
        reason: 'not allowed: cancelled, never applied on a newer version',
      );
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
      await supervisor.sync.syncNow(); // #2 the supervisor, a stale version
      await manager.sync.syncNow();
      await agent.sync.syncNow();

      // Resolved by itself: the assignment is applied on the latest version
      // of the room, both changes stay.
      final room = await supervisor.room('305');
      expect(room['category'], 'Suite');
      expect(room['employeeId'], 'lina');
      final mine = (await supervisor.sync.refresh()).conflicts.single;
      expect(mine.own, isTrue);
      expect(mine.merged, isTrue);
      expect(mine.label, 'Chambre 305 · attribution');
      expect(mine.message, 'Appliquée sur la dernière version.');
      expect((await supervisor.sync.refresh()).pending, 0);
      // The other phones log the same resolution, as another phone's.
      for (final other in [manager, agent]) {
        final c = (await other.sync.refresh()).conflicts.single;
        expect(c.mutationId, mine.mutationId);
        expect(c.own, isFalse);
        expect(c.merged, isTrue);
        expect(c.actorName, 'Amina');
        expect((await other.room('305'))['employeeId'], 'lina');
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
      // The third phone's work reached the server first; the supervisor's
      // came after, on stale versions: applied on the latest ones. Same
      // field (who cleans 305): the last one to arrive wins; stock: both.
      expect((await agent.room('305'))['employeeId'], 'sarah');
      expect((await agent.room('306'))['employeeId'], 'lina');
      final towels = (await agent.supplies()).firstWhere(
        (s) => s['id'] == 'towels',
      );
      expect(towels['quantity'], 75, reason: '68 + 10 - 3: both kept');
      final log = (await supervisor.sync.refresh()).conflicts;
      expect(
        [
          for (final c in log)
            if (c.own) c.label,
        ],
        unorderedEquals([
          'Chambre 305 · attribution',
          'Stock · mouvement de stock',
        ]),
      );
      expect(log.every((c) => c.merged), isTrue);
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

  group('conflicts resolve themselves', () {
    test('an action no longer possible is cancelled on every phone', () async {
      await supervisor.act('305', 'assign', {
        'employeeId': 'sarah',
        'note': '',
        'urgent': false,
      });
      await supervisor.sync.syncNow();
      await agent.sync.syncNow();
      // Offline, the agent starts 305; meanwhile the supervisor gives it to
      // Lina: Sarah may no longer start it.
      server.online = false;
      await agent.act('305', 'start');
      expect((await agent.room('305'))['cleaning'], 'inProgress');
      server.online = true;
      await supervisor.act('305', 'assign', {
        'employeeId': 'lina',
        'note': '',
        'urgent': false,
      });
      await supervisor.sync.syncNow();
      await agent.sync.syncNow();
      await supervisor.sync.syncNow();

      for (final phone in [agent, supervisor]) {
        final room = await phone.room('305');
        expect(room['employeeId'], 'lina');
        expect(room['cleaning'], isNot('inProgress'));
        final entry = (await phone.sync.refresh()).conflicts.single;
        expect(entry.merged, isFalse);
        expect(entry.label, 'Chambre 305 · début du nettoyage');
        expect(entry.own, phone == agent);
      }
      expect((await agent.sync.refresh()).pending, 0);
      expect(await agent.data(), await supervisor.data());
    });

    test('the log keeps the last 20 entries', () async {
      for (var i = 0; i < 25; i++) {
        server.inject('/v1/rooms/305/start', 'ghost', {'version': 1});
      }
      expect(await supervisor.sync.syncNow(), isTrue);
      final log = (await supervisor.sync.refresh()).conflicts;
      expect(log, hasLength(HousekeepingSync.logSize));
      expect((await supervisor.sync.refresh()).lastSeq, 25);
    });

    test('a version mismatch on an unknown item is cancelled', () {
      expect(latestVersions({'rooms': []}, '/v1/rooms/999/start', {}), isEmpty);
      final state = {
        'rooms': [
          {'number': '305', 'version': 4},
        ],
        'supplies': [
          {'id': '305', 'version': 9},
          {'id': 'towels', 'version': 2},
        ],
      };
      expect(latestVersions(state, '/v1/rooms/305/assign', {}), [4, 9]);
      expect(latestVersions(state, '/v1/supplies/towels/movement', {}), [2]);
      expect(latestVersions(state, 'catalog/update', {'number': '305'}), [
        4,
        9,
      ]);
      expect(latestVersions(state, '/v1/supplies/new/create', {}), isEmpty);
    });
  });

  group('live', () {
    test(
      'a change on another phone arrives with one waiting request',
      () async {
        await supervisor.act('305', 'assign', {
          'employeeId': 'sarah',
          'note': '',
          'urgent': false,
        });
        await supervisor.sync.syncNow();
        expect(await agent.sync.waitForChanges(), isTrue);
        expect(server.waits, contains('25'));
        expect((await agent.room('305'))['employeeId'], 'sarah');
        // Nothing new: the request just comes back.
        expect(await agent.sync.waitForChanges(), isTrue);
        server.online = false;
        expect(await agent.sync.waitForChanges(), isFalse);
      },
    );
  });

  group('joining a server', () {
    late Phone joiner;
    setUp(() async {
      Phone.backupsBeforeJoin = 0;
      joiner =
          await Phone.open(
              p.join(directory.path, 'joiner.db'),
              server,
              connect: false,
            )
            ..login('amina');
    });
    tearDown(() async {
      joiner.sync.dispose();
      await joiner.session.database.close();
    });

    test(
      'a synced phone shares its data once, then every 100 actions',
      () async {
        await supervisor.act('305', 'assign', {
          'employeeId': 'sarah',
          'note': '',
          'urgent': false,
        });
        expect(await supervisor.sync.syncNow(), isTrue);
        expect(server.snapshot?.seq, 1);
        expect(server.snapshotsSent, 1);
        await supervisor.act('306', 'assign', {
          'employeeId': 'lina',
          'note': '',
          'urgent': false,
        });
        expect(await supervisor.sync.syncNow(), isTrue);
        expect(await agent.sync.syncNow(), isTrue);
        expect(server.snapshotsSent, 1, reason: 'the copy is recent enough');
      },
    );

    test('a new phone takes the hotel\'s data, keeps its own waiting work, '
        'and ends up identical', () async {
      await supervisor.act('305', 'assign', {
        'employeeId': 'sarah',
        'note': 'Copie',
        'urgent': false,
      });
      await supervisor.sync.syncNow(); // shares its data (seq 1)
      await supervisor.act('306', 'assign', {
        'employeeId': 'lina',
        'note': '',
        'urgent': false,
      });
      await supervisor.sync.syncNow(); // seq 2, after the copy

      // The joining phone has other data (not from any action) and some
      // work of its own waiting.
      await joiner.session.database.database.update(
        'housekeeping_rooms',
        {'note': 'Autre hôtel'},
        where: 'number = ?',
        whereArgs: ['305'],
      );
      await joiner.act('410', 'priority', {'value': 'vip'});
      expect((await joiner.sync.refresh()).pending, 1);

      await joiner.sync.setServer('192.168.1.20');
      expect(Phone.backupsBeforeJoin, 1);
      expect((await joiner.room('305'))['note'], 'Copie');
      expect((await joiner.sync.refresh()).pending, 1, reason: 'kept');

      expect(await joiner.sync.syncNow(), isTrue);
      expect((await joiner.room('306'))['employeeId'], 'lina');
      expect((await joiner.sync.refresh()).pending, 0);
      await supervisor.sync.syncNow();
      expect(await joiner.data(), await supervisor.data());
      expect(server.log.last['path'], '/v1/rooms/410/priority');
    });

    test('the same server again: no new copy, no backup', () async {
      await supervisor.act('305', 'assign', {
        'employeeId': 'sarah',
        'note': '',
        'urgent': false,
      });
      await supervisor.sync.syncNow();
      await joiner.sync.setServer('192.168.1.20');
      expect(Phone.backupsBeforeJoin, 1);
      await joiner.sync.setServer('192.168.1.20');
      expect(Phone.backupsBeforeJoin, 1);
      expect(
        joiner.sync.joins(
          FoundServer(
            id: server.serverId,
            name: 'PC',
            address: Uri.parse('http://192.168.1.20:8080'),
          ),
        ),
        isFalse,
      );
    });

    test('a server without a copy yet: the phone keeps its data', () async {
      server.inject('/v1/rooms/305/start', 'ghost', {'version': 1});
      await joiner.sync.setServer('192.168.1.20');
      expect(Phone.backupsBeforeJoin, 0);
      expect(await joiner.sync.syncNow(), isTrue);
    });
  });

  group('connecting by itself', () {
    late FakeDiscovery wifi;
    late Phone phone;
    setUp(() async {
      wifi = FakeDiscovery();
      final made = await AppDatabase.open(
        schemas: [housekeepingSchema],
        factory: databaseFactoryFfi,
        path: p.join(directory.path, 'auto.db'),
      );
      final session = AppSession(database: made, staff: TestStaff())
        ..signIn(TestStaff.people.firstWhere((u) => u.id == 'sarah'));
      final store = HousekeepingStore(session);
      phone = Phone._(
        session,
        store,
        HousekeepingSync(
          store,
          client: server.client,
          background: false,
          timeout: const Duration(milliseconds: 200),
          discovery: wifi,
          backupBeforeJoin: () async {},
        ),
      );
    });
    tearDown(() async {
      phone.sync.dispose();
      await phone.session.database.close();
    });

    test('the only server found is used, whoever is signed in', () async {
      server.host = '192.168.1.42';
      wifi.open.add('192.168.1.42:8080');
      expect(await phone.sync.autoConnect(listen: Duration.zero), isTrue);
      final view = await phone.sync.refresh();
      expect(view.server, Uri.parse('http://192.168.1.42:8080'));
      expect(view.serverId, server.serverId);
    });

    test('several servers: the Manager chooses', () async {
      wifi.open.add('192.168.1.42:8080');
      wifi.announce(
        FoundServer(
          id: 'another-server',
          name: 'PC-2',
          address: Uri.parse('http://192.168.1.43:8080'),
        ),
      );
      expect(await phone.sync.autoConnect(listen: Duration.zero), isFalse);
      expect((await phone.sync.refresh()).server, isNull);
    });

    test('none found, or after "Arrêter": nothing happens', () async {
      expect(await phone.sync.autoConnect(listen: Duration.zero), isFalse);
      wifi.open.add('192.168.1.42:8080');
      await phone.sync.clearServer();
      expect((await phone.sync.refresh()).autoConnect, isFalse);
      expect(await phone.sync.autoConnect(listen: Duration.zero), isFalse);
      await phone.sync.setServer('192.168.1.42');
      expect((await phone.sync.refresh()).autoConnect, isTrue);
    });
  });

  test('a version 9 database upgrades in place: refused actions join the '
      'log', () async {
    final path = p.join(directory.path, 'v9.db');
    var phone = await Phone.open(path, server)
      ..login('amina');
    final db = phone.session.database.database;
    await dropVersion10(db);
    await db.insert('housekeeping_sync_outbox', {
      'mutation_id': 'bad-1',
      'path': '/v1/rooms/305/assign',
      'body': '{}',
      'actor_id': 'amina',
      'applied_at': '2026-11-11T09:00:00.000',
      'created_at': '2026-11-11T09:00:00.000',
      'status': 'rejected',
      'last_error': 'Chemin inconnu.',
    });
    await db.update('module_versions', {
      'version': 9,
    }, where: "module = 'housekeeping'");
    phone.sync.dispose();
    await phone.session.database.close();

    phone = await Phone.open(path, server)
      ..login('amina');
    addTearDown(() async {
      phone.sync.dispose();
      await phone.session.database.close();
    });
    expect(await phone.session.database.versionOf('housekeeping'), 10);
    expect(await phone.outbox(), isEmpty);
    final entry = (await phone.sync.refresh()).conflicts.single;
    expect(entry.mutationId, 'bad-1');
    expect(entry.merged, isFalse);
    expect(entry.own, isTrue);
    expect(entry.message, 'Chemin inconnu.');
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
    expect(await phone.session.database.versionOf('housekeeping'), 10);
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

    test('broadcasts dropped: the scan finds the server that moved', () async {
      expect(await phone.sync.syncNow(), isTrue);
      server.host = '192.168.1.42';
      wifi.open.add('192.168.1.42:8080');
      expect(await phone.sync.syncNow(), isTrue);
      expect(
        (await phone.sync.refresh()).server,
        Uri.parse('http://192.168.1.42:8080'),
      );
    });

    test('the scan lists the Nova Paris servers of the network only', () async {
      server.host = '192.168.1.42';
      // .7 has the port open but is not a Nova Paris server.
      wifi.open.addAll({'192.168.1.42:8080', '192.168.1.7:8080'});
      final found = await phone.sync.scanNetwork().toList();
      expect(found, [
        FoundServer(
          id: server.serverId,
          name: 'PC-ACCUEIL',
          address: Uri.parse('http://192.168.1.42:8080'),
        ),
      ]);
      expect(wifi.tried, hasLength(253), reason: '.1 to .254, not itself');
      expect(wifi.tried, isNot(contains('192.168.1.13:8080')));
    });

    test('the scan tries the saved server\'s port too', () async {
      server.online = false;
      await phone.sync.setServer('192.168.1.20:9000');
      server.online = true;
      await phone.sync.scanNetwork().toList();
      expect(wifi.tried, contains('192.168.1.5:9000'));
      expect(wifi.tried, contains('192.168.1.5:8080'));
    });

    test('a server error is no reason to look elsewhere', () async {
      server.failWith = 500;
      expect(await phone.sync.syncNow(), isFalse);
      expect(wifi.listens, 0);
      expect(wifi.tried, isEmpty);
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
      // Another server, without a copy of the data yet.
      server.serverId = 'a-new-server';
      server.snapshot = null;
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
