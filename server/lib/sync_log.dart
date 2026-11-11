import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

// The server's whole state: the actions of every phone, numbered in the order
// they arrived (seq). The business rules stay on the phones, which replay
// these actions through them; the server only collects and hands them out.

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

// /v1/<family>/<id|new>/<action>, /v1/notifications/read, catalog/<action>.
final _path = RegExp(
  r'^(/v1/[a-z-]+/[A-Za-z0-9._-]{1,120}/[a-z-]+|/v1/notifications/read|catalog/[A-Za-z]+)$',
);

class SyncLog {
  final Database db;
  final DateTime Function() clock;

  SyncLog(this.db, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now {
    db.execute('''CREATE TABLE IF NOT EXISTS sync_mutations (
      seq INTEGER PRIMARY KEY AUTOINCREMENT,
      mutation_id TEXT NOT NULL UNIQUE,
      device_id TEXT NOT NULL,
      path TEXT NOT NULL,
      body TEXT NOT NULL,
      actor_id TEXT NOT NULL,
      applied_at TEXT NOT NULL,
      received_at TEXT NOT NULL)''');
  }

  /// A log in a file (created if needed).
  factory SyncLog.file(String path) => SyncLog(sqlite3.open(path));

  /// A log in memory (tests).
  factory SyncLog.memory({DateTime Function()? clock}) =>
      SyncLog(sqlite3.openInMemory(), clock: clock);

  void close() => db.close();

  int get count =>
      db.select('SELECT COUNT(*) AS n FROM sync_mutations').first['n'] as int;

  int get lastSeq =>
      (db.select('SELECT MAX(seq) AS s FROM sync_mutations').first['s']
          as int?) ??
      0;

  /// Why [m] cannot be stored, or null when it is well formed.
  static String? invalid(Object? m) {
    if (m is! Map) return 'Action invalide.';
    if (m['mutationId'] is! String || !_uuid.hasMatch(m['mutationId'])) {
      return 'Identifiant (UUID) invalide.';
    }
    if (m['path'] is! String || !_path.hasMatch(m['path'])) {
      return 'Chemin inconnu.';
    }
    if (m['body'] is! Map) return 'Contenu invalide.';
    if ((m['body'] as Map)['mutationId'] != m['mutationId']) {
      return 'Identifiant différent dans le contenu.';
    }
    final actor = m['actorId'];
    if (actor is! String || actor.isEmpty || actor.length > 120) {
      return 'Auteur manquant.';
    }
    if (m['appliedAt'] is! String ||
        DateTime.tryParse(m['appliedAt']) == null) {
      return 'Date invalide.';
    }
    return null;
  }

  /// Stores the actions of [deviceId] in order, all in one transaction.
  /// Each gets applied (new), duplicate (already here) or rejected.
  List<Map<String, Object?>> push(String deviceId, List<Object?> mutations) {
    final results = <Map<String, Object?>>[];
    final insert = db.prepare(
      'INSERT OR IGNORE INTO sync_mutations '
      '(mutation_id, device_id, path, body, actor_id, applied_at, received_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
    );
    db.execute('BEGIN');
    try {
      for (final m in mutations) {
        final error = invalid(m);
        final id = m is Map ? m['mutationId'] : null;
        if (error != null) {
          results.add({'mutationId': id, 'status': 'rejected', 'error': error});
          continue;
        }
        m as Map;
        insert.execute([
          id,
          deviceId,
          m['path'],
          jsonEncode(m['body']),
          m['actorId'],
          m['appliedAt'],
          clock().toIso8601String(),
        ]);
        if (db.updatedRows == 1) {
          results.add({
            'mutationId': id,
            'status': 'applied',
            'seq': db.lastInsertRowId,
          });
        } else {
          results.add({'mutationId': id, 'status': 'duplicate'});
        }
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      insert.close();
    }
    return results;
  }

  /// Up to [limit] actions after [since], without those [deviceId] sent.
  /// [until] is the last seq looked at, so the phone moves past its own.
  ({List<Map<String, Object?>> mutations, int until, bool more}) pull(
    int since,
    String deviceId,
    int limit,
  ) {
    final rows = db.select(
      'SELECT * FROM sync_mutations WHERE seq > ? ORDER BY seq LIMIT ?',
      [since, limit],
    );
    return (
      mutations: [
        for (final r in rows)
          if (r['device_id'] != deviceId)
            {
              'seq': r['seq'],
              'mutationId': r['mutation_id'],
              'path': r['path'],
              'body': jsonDecode(r['body'] as String),
              'actorId': r['actor_id'],
              'appliedAt': r['applied_at'],
            },
      ],
      until: rows.isEmpty ? since : rows.last['seq'] as int,
      more: rows.length == limit,
    );
  }

  /// The last action received for each room (read-only view for a browser).
  List<Map<String, Object?>> roomActivity() {
    final latest = <String, Map<String, Object?>>{};
    final rows = db.select(
      "SELECT seq, path, actor_id, applied_at FROM sync_mutations "
      "WHERE path LIKE '/v1/rooms/%' ORDER BY seq",
    );
    for (final r in rows) {
      final parts = (r['path'] as String).split('/');
      if (parts.length != 5) continue;
      final room = parts[3];
      final previous = latest[room];
      latest[room] = {
        'room': room,
        'lastAction': parts[4],
        'by': r['actor_id'],
        'at': r['applied_at'],
        'seq': r['seq'],
        'actions': ((previous?['actions'] as int?) ?? 0) + 1,
      };
    }
    return latest.values.toList()
      ..sort((a, b) => (a['room'] as String).compareTo(b['room'] as String));
  }
}
