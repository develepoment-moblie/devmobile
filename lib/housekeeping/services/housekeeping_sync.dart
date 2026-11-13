import 'dart:async';
import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'app_exception.dart';
import 'housekeeping_backup.dart';
import 'http_guard.dart';
import 'housekeeping_store.dart';
import 'mutation_meta.dart';
import 'server_discovery.dart';
import 'sync_outbox.dart';
import 'sync_rebase.dart';

// Offline-first sync with the hotel server (server/ at the repo root).
//
// Every action is saved on the phone first and queued in
// housekeeping_sync_outbox in the same transaction. A sync then:
//  1. pushes the queue (POST /v1/sync/push); sent actions stay queued, as
//     "sent", until the server's list confirms them;
//  2. pulls the numbered actions (GET /v1/sync/pull), this phone's own
//     included, and rebuilds the data in the server's order (sync_rebase.dart):
//     the confirmed version moves forward, the actions still waiting are
//     applied again on top. A refused action is refused on every phone alike.
// Live: while the app runs, one request waits at the server
// (GET /v1/sync/pull?wait=25), which answers as soon as another phone pushes
// something: their work shows up here within a second. A change made here
// is sent 0.5 s later. Conflicts resolve themselves (sync_rebase.dart).
// Joining: a phone connecting to a server for the first time takes the
// hotel's data from the server's copy (GET /v1/sync/snapshot, a backup is
// made first), then the actions after it; the phones keep that copy up to
// date (PUT, every [HousekeepingSync.snapshotEvery] actions).
// Without a server set, the phone connects by itself to the only Nova Paris
// server it finds on the Wi-Fi ([HousekeepingSync.autoConnect]).
// Without network nothing is lost: the queue waits and the sync retries
// with a growing delay. When the server cannot be reached, the phone also
// looks for it on the Wi-Fi (server_discovery.dart: its announcements, and a
// scan of the network): if the same server (same id) answers at another
// address, it follows it. A repeated mutationId changes nothing, on the
// phone as on the server, so retrying is always safe.

/// How the sync is doing, for the badge and the Synchronisation screen.
enum SyncPhase { off, idle, syncing, offline }

/// A conflict the sync resolved by itself, the same way on every phone
/// ("Résolu automatiquement"): [merged] applied on the item's latest
/// version, else cancelled (not possible any more). [own]: made here.
class SyncConflict {
  final String mutationId, path, message;
  final String? actorName;
  final DateTime appliedAt;
  final bool own, merged;
  const SyncConflict({
    required this.mutationId,
    required this.path,
    required this.message,
    required this.actorName,
    required this.appliedAt,
    this.own = false,
    this.merged = false,
  });
  String get label => describeSyncPath(path);
}

class SyncOverview {
  final Uri? server;

  /// The server's id (from GET /v1/health), once it answered.
  final String? serverId;
  final String deviceId;
  final int pending, lastSeq;
  final DateTime? lastSyncAt;
  final String? lastError;

  /// The "Résolu automatiquement" log, newest first.
  final List<SyncConflict> conflicts;

  /// False after "Arrêter": the phone no longer connects by itself.
  final bool autoConnect;
  const SyncOverview({
    required this.server,
    this.serverId,
    required this.deviceId,
    required this.pending,
    required this.lastSeq,
    required this.lastSyncAt,
    required this.lastError,
    required this.conflicts,
    this.autoConnect = true,
  });
}

/// The server's address as typed by the user, checked: plain HTTP only for
/// an address of the local network (the hotel's Wi-Fi), else HTTPS.
Uri parseServerAddress(String input) {
  var text = input.trim();
  if (text.isEmpty) {
    throw const AppServiceException('Saisissez l’adresse du serveur.');
  }
  if (!text.contains('://')) text = 'http://$text';
  final uri = Uri.tryParse(text);
  if (uri == null ||
      uri.host.isEmpty ||
      !{'http', 'https'}.contains(uri.scheme)) {
    throw const AppServiceException(
      'Adresse invalide. Exemple : 192.168.1.20:8080',
    );
  }
  if (uri.scheme == 'http' && !isLocalNetworkHost(uri.host)) {
    throw const AppServiceException(
      'En HTTP, seule une adresse du réseau local est acceptée '
      '(ex. 192.168.1.20:8080). Sinon, utilisez https://.',
    );
  }
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    // The server listens on 8080 unless another port is given.
    port: uri.hasPort ? uri.port : (uri.scheme == 'http' ? 8080 : 443),
  );
}

/// localhost, 127.x, 10.x (10.0.2.2 is the PC seen from the emulator),
/// 192.168.x and 172.16.x to 172.31.x.
bool isLocalNetworkHost(String host) {
  if (host == 'localhost') return true;
  final parts = host.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null || p < 0 || p > 255)) {
    return false;
  }
  final a = parts[0]!, b = parts[1]!;
  return a == 127 ||
      a == 10 ||
      (a == 192 && b == 168) ||
      (a == 172 && b >= 16 && b <= 31);
}

const _families = {
  'supplies': 'Stock',
  'lost': 'Objet trouvé',
  'issues': 'Signalement',
  'availability': 'Disponibilité',
  'plans': 'Planning',
  'inspection-rules': 'Règles d’inspection',
  'settings': 'Réglages',
  'notification-prefs': 'Préférences de notification',
  'notifications': 'Notifications',
  'laundry': 'Linge',
  'requests': 'Demande de produits',
  'minibar': 'Minibar',
};

const _actions = {
  'add-task': 'tâche ajoutée',
  'apply': 'planning appliqué',
  'approve': 'validation',
  'assign': 'attribution',
  'bring-back': 'remise en service',
  'checklist': 'liste de contrôle',
  'close': 'clôture',
  'compensate': 'compensation',
  'correct': 'correction',
  'create': 'création',
  'delete': 'suppression',
  'deliver': 'livraison',
  'movement': 'mouvement de stock',
  'notify': 'notification',
  'pause': 'pause',
  'post': 'facturation',
  'prepare': 'préparation',
  'priority': 'priorité',
  'read': 'lecture',
  'record': 'saisie',
  'refuse': 'refus',
  'report': 'signalement',
  'restock': 'réassort',
  'resume': 'reprise',
  'return': 'retour',
  'send': 'envoi',
  'set': 'réglage',
  'start': 'début du nettoyage',
  'stayover': 'recouche',
  'stop': 'fin du nettoyage',
  'submit': 'envoi pour validation',
  'update': 'modification',
  'use': 'utilisation',
};

const _catalogActions = {
  'create': 'chambre créée',
  'createRange': 'chambres créées',
  'update': 'chambre modifiée',
  'archive': 'chambre archivée',
  'restore': 'chambre restaurée',
  'renameFloor': 'étage renommé',
  'setCategoryTasks': 'tâches d’une catégorie',
  'setCategoryEstimate': 'temps estimé',
  'setInspectionRules': 'règles d’inspection',
  'saveMinibarItem': 'article du minibar',
  'deleteMinibarItem': 'article du minibar supprimé',
};

/// "Chambre 204 · validation", for the conflict lists.
String describeSyncPath(String path) {
  if (path.startsWith(catalogPathPrefix)) {
    final action = path.substring(catalogPathPrefix.length);
    return 'Catalogue · ${_catalogActions[action] ?? 'modification'}';
  }
  final parts = path.split('/');
  if (parts.length < 4) return 'Modification';
  final family = parts[2];
  final action = parts.last;
  final what = family == 'rooms'
      ? 'Chambre ${parts[3]}'
      : _families[family] ?? 'Modification';
  return parts.length == 5 && _actions.containsKey(action)
      ? '$what · ${_actions[action]}'
      : what;
}

/// "1 action en attente", "3 actions en attente".
String pendingText(int count) =>
    '$count action${count > 1 ? 's' : ''} en attente';

/// "1 conflit", "2 conflits".
String conflictText(int count) => '$count conflit${count > 1 ? 's' : ''}';

/// The server could not be reached, or answered with an error.
class _Unreachable implements Exception {
  final String message;

  /// No answer at all (Wi-Fi, address, timeout), not an error answer.
  final bool network;
  const _Unreachable(this.message, {this.network = false});
}

// One sync service per store (per session), shared by the screens.
final _services = Expando<HousekeepingSync>('housekeeping sync');
HousekeepingSync housekeepingSyncFor(HousekeepingStore store) =>
    _services[store] ??= HousekeepingSync(
      store,
      // Only the hotel's own database connects by itself: never the screen
      // tour's or a test's (their actions must not reach the hotel).
      autoConnectOnStart:
          p.basename(store.session.database.database.path) ==
          'nova_paris_hotel.db',
    );

class HousekeepingSync extends ChangeNotifier {
  final HousekeepingStore store;
  final http.Client _client;
  final Duration timeout;

  /// Pull interval while the app runs, so other phones' work shows up.
  final Duration pollEvery;
  final DateTime Function() clock;

  /// False in tests: no timers, syncs only when [syncNow] is called.
  final bool background;

  /// Listens for the server on the Wi-Fi; null: typing the address only.
  final ServerDiscovery? discovery;

  /// Without a server set, looks for one at start and every 30 s
  /// ([autoConnect]).
  final bool autoConnectOnStart;

  /// How long a failed sync listens for its server's announcements (the
  /// scan of the network runs meanwhile, to its end).
  final Duration followWithin;

  /// How long a scanned address has to answer GET /v1/health.
  final Duration probeTimeout;

  /// How long the live request waits at the server for something new.
  final Duration liveWait;

  /// Made before a phone takes the server's copy of the data.
  final Future<void> Function() _backupBeforeJoin;

  /// Actions sent or received per request.
  static const pageSize = 50;

  /// The server's copy of the data is renewed every this many actions.
  static const snapshotEvery = 100;

  /// The log keeps this many entries, for this long.
  static const logSize = 20;
  static const logDays = 7;

  HousekeepingSync(
    this.store, {
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
    this.pollEvery = const Duration(seconds: 20),
    DateTime Function()? clock,
    this.background = true,
    ServerDiscovery? discovery,
    this.autoConnectOnStart = false,
    this.followWithin = const Duration(seconds: 3),
    this.probeTimeout = const Duration(seconds: 2),
    this.liveWait = const Duration(seconds: 25),
    Future<void> Function()? backupBeforeJoin,
  }) : _client = client ?? http.Client(),
       clock = clock ?? DateTime.now,
       discovery = discovery ?? (background ? ServerDiscovery() : null),
       _backupBeforeJoin =
           backupBeforeJoin ??
           (() => HousekeepingBackup(store).backupBeforeJoin());

  SyncPhase phase = SyncPhase.off;
  SyncOverview? overview;
  int _failures = 0;
  bool _running = false, _again = false, _disposed = false;
  bool _live = false, _connecting = false;
  Timer? _retry, _poll, _debounce, _search;
  StreamSubscription<void>? _changes;

  // ------------------------------------------------------------- lifecycle

  /// Reads the settings; when a server is set, syncs now and keeps syncing;
  /// otherwise looks for one on the Wi-Fi ([autoConnect]).
  Future<void> start() async {
    await refresh();
    if (overview?.server != null) {
      _arm();
    } else {
      _armSearch();
    }
  }

  /// The app came back to the screen: sync at once.
  Future<void> resumed() async {
    if (_disposed) return;
    final view = await refresh();
    if (view.server != null) {
      await syncNow();
    } else {
      _armSearch();
    }
  }

  void _arm() {
    if (_disposed || !background) return;
    _search?.cancel();
    _search = null;
    // After a change on this phone (debounced), live while the app runs,
    // and every [pollEvery] in case the live request is not answered.
    _changes ??= store.changes.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(
        const Duration(milliseconds: 500),
        () => unawaited(syncNow()),
      );
    });
    _poll ??= Timer.periodic(pollEvery, (_) => unawaited(syncNow()));
    unawaited(syncNow());
  }

  void _armSearch() {
    if (_disposed || !background || !autoConnectOnStart || discovery == null) {
      return;
    }
    unawaited(autoConnect());
    _search ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(autoConnect()),
    );
  }

  void _disarm() {
    _changes?.cancel();
    _changes = null;
    for (final t in [_poll, _retry, _debounce, _search]) {
      t?.cancel();
    }
    _poll = _retry = _debounce = _search = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _disarm();
    _client.close();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // -------------------------------------------------------------- settings

  Future<Map<String, String>> _settings(DatabaseExecutor db) async => {
    for (final row in await db.query('housekeeping_sync_state'))
      row['key'] as String: row['value'] as String,
  };

  Future<void> _set(DatabaseExecutor db, String key, String? value) =>
      value == null
      ? db.delete('housekeeping_sync_state', where: 'key = ?', whereArgs: [key])
      : db.insert('housekeeping_sync_state', {
          'key': key,
          'value': value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

  /// This phone's id, made once: the server does not send a phone its own
  /// actions back.
  Future<String> _deviceId(DatabaseExecutor db) async {
    final current = (await _settings(db))['device_id'];
    if (current != null) return current;
    final id = uuidV4();
    await _set(db, 'device_id', id);
    return id;
  }

  /// Re-reads the queue, the conflicts and the last sync.
  Future<SyncOverview> refresh() async {
    final view = await store.syncLedger((tx) async {
      final device = await _deviceId(tx);
      final settings = await _settings(tx);
      final pending = Sqflite.firstIntValue(
        await tx.rawQuery(
          "SELECT COUNT(*) FROM housekeeping_sync_outbox "
          "WHERE status IN ('pending','sent')",
        ),
      )!;
      final conflicts = await tx.query(
        'housekeeping_sync_conflicts',
        orderBy: 'received_at DESC, seq DESC',
      );
      return SyncOverview(
        server: settings['server_url'] == null
            ? null
            : Uri.parse(settings['server_url']!),
        serverId: settings['server_id'],
        deviceId: device,
        pending: pending,
        lastSeq: int.tryParse(settings['last_seq'] ?? '') ?? 0,
        lastSyncAt: DateTime.tryParse(settings['last_sync_at'] ?? ''),
        lastError: settings['last_error'],
        autoConnect: settings['auto_connect'] != 'off',
        conflicts: [
          for (final c in conflicts)
            SyncConflict(
              mutationId: c['mutation_id'] as String,
              path: c['path'] as String,
              message: c['message'] as String,
              actorName: c['actor_name'] as String?,
              appliedAt: DateTime.parse(c['applied_at'] as String),
              own: c['own'] == 1,
              merged: c['resolution'] == 'merged',
            ),
        ],
      );
    });
    overview = view;
    if (view.server == null) {
      phase = SyncPhase.off;
    } else if (phase == SyncPhase.off) {
      phase = SyncPhase.idle;
    }
    _notify();
    return view;
  }

  /// Checks the server answers; returns a short French summary.
  Future<String> testConnection(String address) async {
    final server = parseServerAddress(address);
    try {
      final health = await _getJson(server.replace(path: '/v1/health'));
      final count = health['mutations'] as int? ?? 0;
      return 'Serveur joignable · $count action${count > 1 ? 's' : ''} enregistrée${count > 1 ? 's' : ''}.';
    } on _Unreachable catch (e) {
      throw AppServiceException(e.message);
    }
  }

  /// The id GET /v1/health gives, or null when the server has none.
  Future<String?> _serverIdAt(Uri server) async {
    final id = (await _getJson(server.replace(path: '/v1/health')))['serverId'];
    return id is String && id.isNotEmpty ? id : null;
  }

  /// Saves the server's address and starts syncing. Another server starts
  /// again from its first action (replays already applied change nothing);
  /// the same server at a new address carries on where it was.
  /// [expectedId]: the id a found server announced; it must answer with it.
  Future<void> setServer(String address, {String? expectedId}) async {
    final server = parseServerAddress(address);
    String? id;
    ({int seq, List<int> data})? copy;
    try {
      id = await _serverIdAt(server);
      // A server this phone never synced with: take the hotel's data.
      final known = (await store.syncLedger(_settings))['server_id'];
      if (id != null && id != known) copy = await _snapshotAt(server);
    } on _Unreachable catch (e) {
      // Saved anyway when typed: the server may simply be off for now.
      if (expectedId != null) throw AppServiceException(e.message);
    }
    if (expectedId != null && id != expectedId) {
      throw const AppServiceException(
        'Ce serveur ne correspond pas à l’annonce reçue. Réessayez.',
      );
    }
    await store.syncLedger((tx) async {
      final settings = await _settings(tx);
      final sameServer = id != null && id == settings['server_id'];
      if (settings['server_url'] != server.toString() && !sameServer) {
        // Another server: its list is read from the start, on top of the
        // confirmed version (actions already in it change nothing).
        await _set(tx, 'last_seq', '0');
        await _set(tx, 'last_error', null);
        await tx.update('housekeeping_sync_base', {'seq': 0});
        await _set(tx, 'server_id', null);
      }
      if (id != null) await _set(tx, 'server_id', id);
      await _set(tx, 'server_url', server.toString());
      await _set(tx, 'auto_connect', null);
    });
    if (copy != null) await _join(copy);
    // From now on, actions made here wait to be confirmed: the confirmed
    // version starts as the data before them.
    await store.ensureSyncBase((await refresh()).lastSeq);
    _failures = 0;
    phase = SyncPhase.idle;
    await refresh();
    _arm();
  }

  /// The Nova Paris servers of this phone's network, as they answer: every
  /// address where the server's port is open is asked GET /v1/health. The
  /// port of the server already set is tried too.
  Stream<FoundServer> scanNetwork() async* {
    final finder = discovery;
    if (finder == null) return;
    final current = overview?.server;
    final ports = {
      defaultServerPort,
      if (current != null && current.scheme == 'http') current.port,
    };
    await for (final candidate in finder.scan(ports: ports)) {
      final server = await _probe(candidate);
      if (server != null) yield server;
    }
  }

  /// The server at [base] (GET /v1/health with its id), or null when nothing
  /// or something else answers there.
  Future<FoundServer?> _probe(Uri base) async {
    try {
      final response = await _client
          .get(
            base.replace(path: '/v1/health'),
            headers: {'accept': 'application/json'},
          )
          .timeout(probeTimeout);
      if (response.statusCode != 200) return null;
      final health = jsonObject(response);
      final id = health?['serverId'];
      if (id is! String || id.isEmpty || id.length > 64) return null;
      return FoundServer(
        id: id,
        name: serverLabel(health!['name']),
        address: base,
      );
    } on Exception {
      // Another program on that port, or it stopped answering.
      return null;
    }
  }

  /// Whether using [found] replaces this phone's data with the hotel's
  /// (a server it never synced with), for the confirmation.
  bool joins(FoundServer found) => found.id != overview?.serverId;

  /// No server set: connects by itself to the Nova Paris server found on
  /// the Wi-Fi, when there is exactly one (announcements heard during
  /// [listen], and the scan). True once connected. Not after "Arrêter".
  Future<bool> autoConnect({
    Duration listen = const Duration(seconds: 4),
  }) async {
    final finder = discovery;
    if (finder == null || _connecting || _disposed) return false;
    final view = await refresh();
    if (view.server != null || !view.autoConnect) {
      _search?.cancel();
      _search = null;
      return false;
    }
    _connecting = true;
    final found = <String, FoundServer>{};
    final heard = finder.watch().listen((s) => found[s.id] = s);
    try {
      final watch = Stopwatch()..start();
      await for (final server in scanNetwork()) {
        found[server.id] = server;
      }
      final left = listen - watch.elapsed;
      if (left > Duration.zero) await Future<void>.delayed(left);
      await heard.cancel();
      if (found.length != 1 || _disposed) return false;
      await useFoundServer(found.values.single);
      return true;
    } on AppServiceException {
      return false;
    } finally {
      await heard.cancel();
      _connecting = false;
    }
  }

  /// Saves a server found on the Wi-Fi, once it answered with its id.
  Future<void> useFoundServer(FoundServer found) =>
      setServer(found.hostPort, expectedId: found.id);

  /// Stops syncing. The queue is kept and sent once a server is set again.
  /// Stops syncing, and connecting by itself. The queue is kept and sent
  /// once a server is set again.
  Future<void> clearServer() async {
    _disarm();
    await store.syncLedger((tx) async {
      await _set(tx, 'server_url', null);
      await _set(tx, 'auto_connect', 'off');
    });
    phase = SyncPhase.off;
    await refresh();
  }

  // ------------------------------------------------------- copy of the data

  /// The server's copy of the hotel's data, or null when it has none.
  Future<({int seq, List<int> data})?> _snapshotAt(Uri server) async {
    final response = await guardedRequest(
      () => _client.get(server.replace(path: '/v1/sync/snapshot')),
      timeout: const Duration(seconds: 60),
      fail: (_) => throw const _Unreachable(
        'Serveur injoignable. Vérifiez le Wi-Fi et l’adresse.',
        network: true,
      ),
    );
    if (response.statusCode != 200) return null;
    final seq = int.tryParse(response.headers['x-snapshot-seq'] ?? '');
    return seq == null ? null : (seq: seq, data: response.bodyBytes);
  }

  /// Takes the server's copy as this phone's data (after a backup): the
  /// confirmed version at its number, then this phone's waiting actions on
  /// top, sent again to this server. False when the copy is unreadable.
  Future<bool> _join(({int seq, List<int> data}) copy) async {
    final Map<String, dynamic> state;
    final Map photos;
    try {
      final json = jsonDecode(utf8.decode(gzip.decode(copy.data)));
      if (json is! Map || json['format'] != 1 || json['state'] is! Map) {
        return false;
      }
      state = (json['state'] as Map).cast<String, dynamic>();
      photos = json['photos'] is Map ? json['photos'] as Map : const {};
    } on FormatException {
      return false;
    }
    await _backupBeforeJoin();
    await store.rebuild((tx, current) async {
      await HousekeepingStore.saveSyncBase(tx, {
        ...state,
        '_photoWrites': photos,
      }, copy.seq);
      await HousekeepingStore.writeState(tx, {
        ...(jsonDecode(jsonEncode(state)) as Map).cast<String, dynamic>(),
        'users': current['users'],
      });
      await tx.update('housekeeping_sync_outbox', {
        'status': 'pending',
      }, where: "status = 'sent'");
      await tx.delete('housekeeping_sync_conflicts');
      await _set(tx, 'last_seq', '${copy.seq}');
      await _set(tx, 'snapshot_seq', '${copy.seq}');
      await _set(tx, 'last_error', null);
    });
    await _rebuild(const [], copy.seq);
    return true;
  }

  /// Sends this phone's confirmed version as the server's copy when the
  /// server's is missing or [snapshotEvery] actions old. Not essential: a
  /// failure waits for the next sync.
  Future<void> _shareSnapshot(Uri server, String device) async {
    final (base, known) = await store.syncLedger(
      (tx) async => (
        await HousekeepingStore.loadSyncBase(tx),
        int.tryParse((await _settings(tx))['snapshot_seq'] ?? ''),
      ),
    );
    if (base == null || base.seq < 1) return;
    if (known != null && base.seq - known < snapshotEvery) return;
    try {
      final held = (await _getJson(
        server.replace(path: '/v1/health'),
      ))['snapshotSeq'];
      if (held is int && base.seq - held < snapshotEvery) {
        await store.syncLedger((tx) => _set(tx, 'snapshot_seq', '$held'));
        return;
      }
      final ids = HousekeepingStore.photoIds(base.state);
      final photos = await store.syncLedger(
        (tx) async => {
          for (final row in await tx.query('housekeeping_photos'))
            if (ids.contains(row['id'])) row['id'] as String: row['data'],
        },
      );
      final bytes = gzip.encode(
        utf8.encode(
          jsonEncode({
            'format': 1,
            'seq': base.seq,
            'state': base.state,
            'photos': photos,
          }),
        ),
      );
      final answer = await _send(
        () => _client.put(
          server.replace(
            path: '/v1/sync/snapshot',
            queryParameters: {'seq': '${base.seq}', 'device': device},
          ),
          headers: {
            'accept': 'application/json',
            'content-type': 'application/gzip',
          },
          body: bytes,
        ),
        timeout: const Duration(seconds: 60),
      );
      final kept = answer['snapshotSeq'];
      await store.syncLedger(
        (tx) => _set(tx, 'snapshot_seq', '${kept is int ? kept : base.seq}'),
      );
    } on _Unreachable {
      // Next sync.
    }
  }

  // ------------------------------------------------------------------ live

  /// One request waiting at the server ([liveWait]); syncs when something
  /// new came. False when the server could not be reached.
  Future<bool> waitForChanges() async {
    final view = overview ?? await refresh();
    final server = view.server;
    if (server == null) return false;
    try {
      final page = await _getJson(
        server.replace(
          path: '/v1/sync/pull',
          queryParameters: {
            'since': '${view.lastSeq}',
            'device': view.deviceId,
            'limit': '1',
            'wait': '${liveWait.inSeconds}',
          },
        ),
        timeout: liveWait + const Duration(seconds: 10),
      );
      final until = page['until'];
      if ((page['mutations'] as List?)?.isNotEmpty == true ||
          (until is int && until > view.lastSeq)) {
        await syncNow();
      }
      return true;
    } on _Unreachable {
      return false;
    }
  }

  // While the app runs: always one request waiting at the server. Stops
  // when the server cannot be reached (the retries take over).
  Future<void> _liveLoop() async {
    if (_live || !background || _disposed) return;
    _live = true;
    try {
      while (!_disposed && _poll != null && overview?.server != null) {
        if (!await waitForChanges()) break;
      }
    } finally {
      _live = false;
    }
  }

  // ------------------------------------------------------------------ sync

  /// Pushes then pulls. Returns false when the server could not be reached.
  /// A call while a sync runs makes it run once more afterwards.
  Future<bool> syncNow() async {
    if (_disposed) return false;
    if (_running) {
      _again = true;
      return true;
    }
    _running = true;
    var ok = true;
    try {
      do {
        _again = false;
        ok = await _syncOnce();
      } while (_again && ok && !_disposed);
    } finally {
      _running = false;
    }
    return ok;
  }

  /// [followed]: already moved to the server's new address this time.
  Future<bool> _syncOnce({bool followed = false}) async {
    final view = await refresh();
    final server = view.server;
    if (server == null) return false;
    phase = SyncPhase.syncing;
    _notify();
    try {
      await store.ensureSyncBase(view.lastSeq);
      if (await _push(server, view.deviceId)) {
        // An action the server refused leaves this phone's data too.
        await _rebuild(const [], view.lastSeq);
      }
      await _pull(server, view.deviceId);
      if (view.serverId == null) await _learnServerId(server);
      await _shareSnapshot(server, view.deviceId);
      _failures = 0;
      _retry?.cancel();
      _retry = null;
      await store.syncLedger((tx) async {
        await _set(tx, 'last_sync_at', clock().toIso8601String());
        await _set(tx, 'last_error', null);
      });
      phase = SyncPhase.idle;
      await refresh();
      unawaited(_liveLoop());
      return true;
    } on _Unreachable catch (e) {
      if (e.network && !followed && await _followServer(view)) {
        return _syncOnce(followed: true);
      }
      await store.syncLedger((tx) => _set(tx, 'last_error', e.message));
      phase = SyncPhase.offline;
      _scheduleRetry();
      await refresh();
      return false;
    }
  }

  /// Remembers the server's id (saved while it was off, or an older
  /// server without one). Not having it only stops [_followServer].
  Future<void> _learnServerId(Uri server) async {
    try {
      final id = await _serverIdAt(server);
      if (id != null) {
        await store.syncLedger((tx) => _set(tx, 'server_id', id));
      }
    } on _Unreachable {
      // Next sync.
    }
  }

  /// The server did not answer: is it announcing itself at another address
  /// (the computer got a new one from the Wi-Fi)? Only the same server, by
  /// its id, checked with GET /v1/health. True when the address was moved.
  Future<bool> _followServer(SyncOverview view) async {
    final id = view.serverId, current = view.server, finder = discovery;
    if (finder == null || id == null || current == null) return false;
    final found = await _locate(id, finder);
    if (found == null || found.address == current || _disposed) return false;
    try {
      if (await _serverIdAt(found.address) != id) return false;
    } on _Unreachable {
      return false;
    }
    await store.syncLedger(
      (tx) => _set(tx, 'server_url', found.address.toString()),
    );
    return true;
  }

  /// Server [id], by its announcements or the scan, whichever finds it
  /// first; null when neither does.
  Future<FoundServer?> _locate(String id, ServerDiscovery finder) {
    final done = Completer<FoundServer?>();
    var searching = 2;
    void finish(FoundServer? server) {
      if (done.isCompleted) return;
      if (server != null) {
        done.complete(server);
      } else if (--searching == 0) {
        done.complete(null);
      }
    }

    finder.find(id, followWithin).then(finish, onError: (_) => finish(null));
    scanNetwork()
        .where((s) => s.id == id)
        .cast<FoundServer?>()
        .firstWhere((_) => true, orElse: () => null)
        .then(finish, onError: (_) => finish(null));
    return done.future;
  }

  /// 5 s, 10 s, 20 s… up to 5 minutes between attempts.
  void _scheduleRetry() {
    if (_disposed || !background) return;
    final seconds = 5 * (1 << _failures.clamp(0, 6));
    _failures++;
    _retry?.cancel();
    _retry = Timer(
      Duration(seconds: seconds.clamp(5, 300)),
      () => unawaited(syncNow()),
    );
  }

  Future<void> _pull(Uri server, String device) async {
    while (true) {
      final since = (await refresh()).lastSeq;
      final page = await _getJson(
        server.replace(
          path: '/v1/sync/pull',
          queryParameters: {
            'since': '$since',
            'device': device,
            'limit': '$pageSize',
          },
        ),
      );
      final List<SyncAction> numbered;
      try {
        numbered = [
          for (final m in page['mutations'] as List? ?? const [])
            SyncAction.fromJson((m as Map).cast<String, dynamic>()),
        ];
      } on TypeError {
        throw const _Unreachable('Réponse illisible du serveur.');
      }
      final until = page['until'] is int ? page['until'] as int : since;
      if (numbered.isNotEmpty || until > since) {
        await _rebuild(numbered, until);
      }
      if (page['more'] != true) return;
    }
  }

  /// Moves the confirmed version forward with [numbered] and rebuilds the
  /// data on this phone, all in one transaction (see sync_rebase.dart).
  Future<void> _rebuild(List<SyncAction> numbered, int until) async {
    final authors = {
      for (final u in await store.session.staff.users())
        u.id: <String, dynamic>{
          'id': u.id,
          'full_name': u.fullName,
          'role': u.role,
        },
    };
    await store.rebuild((tx, current) async {
      final base =
          await HousekeepingStore.loadSyncBase(tx) ?? SyncBase(current, until);
      final rows = await tx.query(
        'housekeeping_sync_outbox',
        where: "status IN ('pending','sent')",
        orderBy: 'created_at, rowid',
      );
      final own = {
        for (final r in await tx.query(
          'housekeeping_sync_outbox',
          columns: ['mutation_id'],
        ))
          r['mutation_id'] as String,
      };
      final result = await rebase(
        base: base.state,
        seq: base.seq,
        numbered: numbered,
        waiting: [
          for (final r in rows)
            SyncAction(
              mutationId: r['mutation_id'] as String,
              path: r['path'] as String,
              actorId: r['actor_id'] as String,
              body: (jsonDecode(r['body'] as String) as Map)
                  .cast<String, dynamic>(),
              appliedAt: DateTime.parse(r['applied_at'] as String),
            ),
        ],
        authors: authors,
        users: current['users'],
        until: until,
      );
      await HousekeepingStore.saveSyncBase(tx, result.base, result.seq);
      await HousekeepingStore.writeState(tx, result.current);
      for (final id in result.confirmed) {
        await tx.delete(
          'housekeeping_sync_outbox',
          where: "mutation_id = ? AND status <> 'rejected'",
          whereArgs: [id],
        );
      }
      Future<void> log(
        SyncAction a,
        String message,
        int status,
        String resolution,
      ) => tx.insert('housekeeping_sync_conflicts', {
        'mutation_id': a.mutationId,
        'seq': a.seq ?? 0,
        'path': a.path,
        'actor_id': a.actorId,
        'actor_name': authors[a.actorId]?['full_name'],
        'applied_at': a.appliedAt.toIso8601String(),
        'message': message,
        'status': status,
        'received_at': clock().toIso8601String(),
        'own': own.contains(a.mutationId) ? 1 : 0,
        'resolution': resolution,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      for (final a in result.merged) {
        await log(a, 'Appliquée sur la dernière version.', 409, 'merged');
      }
      for (final r in result.refused) {
        final mine = own.contains(r.action.mutationId);
        await log(r.action, r.message, r.status, 'cancelled');
        // Never applied in the end: its id may be used again.
        if (mine) {
          await tx.delete(
            'housekeeping_mutations',
            where: 'id = ?',
            whereArgs: [r.action.mutationId],
          );
        }
      }
      await _pruneLog(tx);
      await _set(tx, 'last_seq', '${result.seq}');
    });
  }

  /// The log keeps its last [logSize] entries of the last [logDays] days.
  Future<void> _pruneLog(DatabaseExecutor tx) => tx.rawDelete(
    'DELETE FROM housekeeping_sync_conflicts WHERE received_at < ? OR '
    'mutation_id NOT IN (SELECT mutation_id FROM housekeeping_sync_conflicts '
    'ORDER BY received_at DESC, seq DESC LIMIT ?)',
    [
      clock().subtract(const Duration(days: logDays)).toIso8601String(),
      logSize,
    ],
  );

  /// Sends the queue. Returns true when the server refused an action.
  Future<bool> _push(Uri server, String device) async {
    var refused = false;
    while (true) {
      final rows = await store.syncLedger(
        (tx) => tx.query(
          'housekeeping_sync_outbox',
          where: "status = 'pending'",
          orderBy: 'created_at, rowid',
          limit: pageSize,
        ),
      );
      if (rows.isEmpty) return refused;
      final answer = await _postJson(server.replace(path: '/v1/sync/push'), {
        'deviceId': device,
        'mutations': [
          for (final r in rows)
            {
              'mutationId': r['mutation_id'],
              'path': r['path'],
              'body': jsonDecode(r['body'] as String),
              'actorId': r['actor_id'],
              'appliedAt': r['applied_at'],
            },
        ],
      });
      final results = {
        for (final r in (answer['results'] as List? ?? const []))
          (r as Map)['mutationId']: r,
      };
      await store.syncLedger((tx) async {
        for (final row in rows) {
          final id = row['mutation_id'];
          final result = results[id];
          final status = result?['status'];
          if (status == 'applied' || status == 'duplicate') {
            // Stays queued until the server's list confirms it.
            await tx.update(
              'housekeeping_sync_outbox',
              {'status': 'sent'},
              where: 'mutation_id = ?',
              whereArgs: [id],
            );
          } else if (status == 'rejected') {
            // Malformed: cancelled by itself, kept in the log.
            refused = true;
            await tx.delete(
              'housekeeping_sync_outbox',
              where: 'mutation_id = ?',
              whereArgs: [id],
            );
            await tx.insert('housekeeping_sync_conflicts', {
              'mutation_id': id,
              'seq': 0,
              'path': row['path'],
              'actor_id': row['actor_id'],
              'actor_name': null,
              'applied_at': row['applied_at'],
              'message': '${result?['error'] ?? 'Refusée par le serveur.'}',
              'status': 400,
              'received_at': clock().toIso8601String(),
              'own': 1,
              'resolution': 'cancelled',
            }, conflictAlgorithm: ConflictAlgorithm.replace);
            await tx.delete(
              'housekeeping_mutations',
              where: 'id = ?',
              whereArgs: [id],
            );
          } else {
            await tx.update(
              'housekeeping_sync_outbox',
              {'attempts': (row['attempts'] as int) + 1},
              where: 'mutation_id = ?',
              whereArgs: [id],
            );
          }
        }
      });
      // The server did not answer for every action: try again later.
      if (rows.any((r) => results[r['mutation_id']] == null)) {
        throw const _Unreachable('Réponse incomplète du serveur.');
      }
      if (rows.length < pageSize) return refused;
    }
  }

  // ------------------------------------------------------------------ HTTP

  Future<Map<String, dynamic>> _getJson(Uri uri, {Duration? timeout}) => _send(
    () => _client.get(uri, headers: {'accept': 'application/json'}),
    timeout: timeout,
  );

  Future<Map<String, dynamic>> _postJson(Uri uri, Object body) => _send(
    () => _client.post(
      uri,
      headers: {
        'accept': 'application/json',
        'content-type': 'application/json',
      },
      body: jsonEncode(body),
    ),
  );

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request, {
    Duration? timeout,
  }) async {
    final response = await guardedRequest(
      request,
      timeout: timeout ?? this.timeout,
      fail: (failure) => throw _Unreachable(switch (failure) {
        NetworkFailure.timeout => 'Le serveur ne répond pas (délai dépassé).',
        NetworkFailure.offline =>
          'Serveur injoignable. Vérifiez le Wi-Fi et l’adresse.',
      }, network: true),
    );
    if (response.statusCode != 200) {
      throw _Unreachable('Erreur du serveur (${response.statusCode}).');
    }
    return jsonObject(response) ??
        (throw const _Unreachable('Réponse illisible du serveur.'));
  }
}
