import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../shared/models/app_user.dart';
import '../../shared/services/app_database.dart';
import '../../shared/services/app_session.dart';
import '../models/task_schema.dart';
import 'app_exception.dart';
import 'housekeeping_seed.dart';
import 'local_attachment_store.dart';
import 'local_session_store.dart';

// The module's tables, all prefixed housekeeping_. Bump [version] and add a
// step to [migrate] for every change; never edit a step already pushed.
final housekeepingSchema = ModuleSchema(
  module: 'housekeeping',
  version: 1,
  migrate: (tx, from, to) async {
    if (from < 1) {
      await tx.execute('''CREATE TABLE housekeeping_rooms (
        number TEXT PRIMARY KEY, category TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('ready','occupied','dirty','maintenance')),
        cleaning TEXT NOT NULL CHECK(cleaning IN ('waiting','inProgress','review','completed')),
        employee_id TEXT, approved_by TEXT, note TEXT NOT NULL,
        urgent INTEGER NOT NULL CHECK(urgent IN (0,1)),
        checklist TEXT NOT NULL, tasks TEXT NOT NULL, history TEXT NOT NULL,
        version INTEGER NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0 CHECK(archived IN (0,1)))''');
      await tx.execute(
        'CREATE TABLE housekeeping_photos (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
      );
      await tx.execute('''CREATE TABLE housekeeping_supplies (
        id TEXT PRIMARY KEY, name TEXT NOT NULL,
        quantity INTEGER NOT NULL CHECK(quantity BETWEEN 0 AND 1000000),
        unit TEXT NOT NULL, minimum INTEGER NOT NULL, version INTEGER NOT NULL,
        position INTEGER NOT NULL)''');
      await tx.execute('''CREATE TABLE housekeeping_notifications (
        id TEXT PRIMARY KEY, title TEXT NOT NULL, message TEXT NOT NULL,
        room_number TEXT NOT NULL,
        audience TEXT NOT NULL CHECK(audience IN ('all','agent','supervisor')),
        position INTEGER NOT NULL)''');
      await tx.execute('''CREATE TABLE housekeeping_notification_reads (
        actor TEXT NOT NULL,
        notification TEXT NOT NULL
          REFERENCES housekeeping_notifications(id) ON DELETE CASCADE,
        PRIMARY KEY(actor, notification))''');
      final seed = jsonDecode(housekeepingSeedJson) as Map<String, dynamic>;
      for (final room in seed['rooms'] as List) {
        TaskSchema.ensure(room as Map<String, dynamic>);
        // Sample rooms have no photo evidence, so nothing awaits approval.
        if (room['status'] == 'dirty') {
          room['checklist'] = List.filled(4, false);
          if (room['cleaning'] == 'review') room['cleaning'] = 'waiting';
        }
      }
      await HousekeepingStore._write(tx, {
        'rooms': seed['rooms'],
        'roomArchives': <dynamic>[],
        'supplies': seed['supplies'],
        'notifications': seed['notifications'],
        'reads': <String, dynamic>{},
      });
    }
  },
);

/// Reads and writes the housekeeping tables for the signed-in user.
/// Every change runs in one SQLite transaction: an error leaves no partial write.
/// Permissions are local application rules (see SqliteHousekeeping).
class HousekeepingStore implements LocalSessionStore, LocalAttachmentStore {
  final AppSession session;
  Future<void> _pending = Future.value();
  final _ownReports = <String>[];
  HousekeepingStore(this.session);

  /// Remembers a maintenance report housekeeping already applied, so its own
  /// MaintenanceRequested event is not applied a second time.
  void markOwnReport(String roomNumber) => _ownReports.add(roomNumber);
  bool takeOwnReport(String roomNumber) => _ownReports.remove(roomNumber);

  Database get _db => session.database.database;

  @override
  Never fail(String message, [int status = 400]) =>
      throw AppServiceException(message, status);

  @override
  Map<String, dynamic> actor(Map<String, dynamic> state) {
    final user = session.user;
    if (user == null) fail('Session expirée. Reconnectez-vous.', 403);
    return {'id': user.id, 'full_name': user.fullName, 'role': user.role};
  }

  @override
  Future<Map<String, dynamic>> readState() =>
      _queue(() async => _read(_db, await _staff()));

  @override
  Future<void> change(void Function(Map<String, dynamic>) action) {
    final user = session.user;
    return _queue(() async {
      final staff = await _staff();
      await _db.transaction((tx) async {
        if (session.user?.id != user?.id) {
          fail('Session modifiée. Réessayez.', 409);
        }
        final state = await _read(tx, staff);
        action(state);
        await _write(tx, state);
      });
    });
  }

  /// A change made on behalf of another module (an event), without a user.
  Future<void> systemChange(void Function(Map<String, dynamic>) action) =>
      _queue(
        () => _db.transaction((tx) async {
          final state = await _read(tx, const []);
          action(state);
          await _write(tx, state);
        }),
      );

  @override
  Future<String> readAttachment(String id) => _queue(() async {
    final rows = await _db.query(
      'housekeeping_photos',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) fail('Photo indisponible. Actualisez la chambre.', 404);
    return rows.single['data'] as String;
  });

  Future<List<AppUser>> _staff() =>
      session.staff.users(roles: {AppRole.staff, AppRole.supervisor});

  // Operations run one after another so a read never sees half a change.
  Future<T> _queue<T>(Future<T> Function() operation) {
    final result = _pending.then((_) async {
      try {
        return await operation();
      } on DatabaseException {
        throw const AppServiceException(
          'Enregistrement local impossible. Vérifiez l’espace disponible puis réessayez.',
        );
      }
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static Future<Map<String, dynamic>> _read(
    DatabaseExecutor db,
    List<AppUser> staff,
  ) async {
    final rooms = [
      for (final row in await db.query('housekeeping_rooms', orderBy: 'number'))
        <String, dynamic>{
          'number': row['number'],
          'category': row['category'],
          'status': row['status'],
          'cleaning': row['cleaning'],
          'employeeId': row['employee_id'],
          'approvedBy': row['approved_by'],
          'note': row['note'],
          'urgent': row['urgent'] == 1,
          'checklist': jsonDecode(row['checklist'] as String),
          'tasks': jsonDecode(row['tasks'] as String),
          'history': jsonDecode(row['history'] as String),
          'version': row['version'],
          'archived': row['archived'] == 1,
        },
    ];
    final reads = <String, dynamic>{};
    for (final row in await db.query('housekeeping_notification_reads')) {
      (reads.putIfAbsent(row['actor'] as String, () => <dynamic>[]) as List)
          .add(row['notification']);
    }
    final active = <Map<String, dynamic>>[],
        archived = <Map<String, dynamic>>[];
    for (final room in rooms) {
      (room.remove('archived') == true ? archived : active).add(room);
    }
    return {
      'rooms': active,
      'roomArchives': archived,
      'supplies': [
        for (final row in await db.query(
          'housekeeping_supplies',
          orderBy: 'position',
        ))
          {
            for (final k in ['id', 'name', 'quantity', 'unit', 'minimum'])
              k: row[k],
            'version': row['version'],
          },
      ],
      'notifications': [
        for (final row in await db.query(
          'housekeeping_notifications',
          orderBy: 'position',
        ))
          {
            for (final k in ['id', 'title', 'message', 'audience']) k: row[k],
            'roomNumber': row['room_number'],
          },
      ],
      'reads': reads,
      // The shape the business rules expect for the staff list.
      'users': [
        for (final user in staff)
          {
            'id': user.id,
            'full_name': user.fullName,
            'role': user.role,
            'deleted': false,
          },
      ],
    };
  }

  // Saves only rows that changed, inside the caller's transaction.
  static Future<void> _write(
    DatabaseExecutor tx,
    Map<String, dynamic> state,
  ) async {
    Future<void> sync(
      String table,
      String key,
      List<Map<String, Object?>> rows,
    ) async {
      final previous = {for (final row in await tx.query(table)) row[key]: row};
      for (final row in rows) {
        final old = previous.remove(row[key]);
        if (old == null) {
          await tx.insert(table, row);
        } else if (row.entries.any((e) => old[e.key] != e.value)) {
          await tx.update(table, row, where: '$key = ?', whereArgs: [row[key]]);
        }
      }
      for (final id in previous.keys) {
        await tx.delete(table, where: '$key = ?', whereArgs: [id]);
      }
    }

    await sync('housekeeping_rooms', 'number', [
      for (final archived in [false, true])
        for (final r in state[archived ? 'roomArchives' : 'rooms'] as List)
          {
            'number': r['number'],
            'category': r['category'],
            'status': r['status'],
            'cleaning': r['cleaning'],
            'employee_id': r['employeeId'],
            'approved_by': r['approvedBy'],
            'note': r['note'] ?? '',
            'urgent': r['urgent'] == true ? 1 : 0,
            'checklist': jsonEncode(r['checklist']),
            'tasks': jsonEncode(r['tasks'] ?? TaskSchema.defaults()),
            'history': jsonEncode(r['history']),
            'version': r['version'],
            'archived': archived ? 1 : 0,
          },
    ]);
    final supplies = state['supplies'] as List;
    await sync('housekeeping_supplies', 'id', [
      for (var i = 0; i < supplies.length; i++)
        {
          for (final k in ['id', 'name', 'quantity', 'unit', 'minimum'])
            k: supplies[i][k],
          'version': supplies[i]['version'],
          'position': i,
        },
    ]);
    final notifications = state['notifications'] as List;
    await sync('housekeeping_notifications', 'id', [
      for (var i = 0; i < notifications.length; i++)
        {
          for (final k in ['id', 'title', 'message', 'audience'])
            k: notifications[i][k],
          'room_number': notifications[i]['roomNumber'],
          'position': i,
        },
    ]);
    await tx.delete('housekeeping_notification_reads');
    for (final entry in (state['reads'] as Map).entries) {
      for (final id in entry.value as List) {
        await tx.insert('housekeeping_notification_reads', {
          'actor': entry.key,
          'notification': id,
        });
      }
    }
    final photos = state.remove('_photoWrites') as Map? ?? {};
    for (final entry in photos.entries) {
      await tx.insert('housekeeping_photos', {
        'id': entry.key,
        'data': entry.value,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    // Photos no task refers to any more are deleted.
    final referenced = {
      for (final room in [
        ...state['rooms'] as List,
        ...state['roomArchives'] as List,
      ])
        for (final task in room['tasks'] as List? ?? [])
          if (task['photoId'] is String) task['photoId'] as String,
    };
    for (final photo in await tx.query(
      'housekeeping_photos',
      columns: ['id'],
    )) {
      if (!referenced.contains(photo['id'])) {
        await tx.delete(
          'housekeeping_photos',
          where: 'id = ?',
          whereArgs: [photo['id']],
        );
      }
    }
  }
}
