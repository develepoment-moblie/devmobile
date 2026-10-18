import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'task_schema.dart';

/// One device-local database shared by the two feature adapters.
/// No connection to, or automatic import from, any external service or the old demo.
class LocalDatabase {
  final Database database;
  LocalDatabase._(this.database);

  static Future<LocalDatabase> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final driver = factory ?? databaseFactory;
    final location =
        path ?? p.join(await driver.getDatabasesPath(), 'nova_paris.db');
    final db = await driver.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: 2,
        singleInstance: false,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('''CREATE TABLE users (
          id TEXT PRIMARY KEY, email TEXT NOT NULL UNIQUE COLLATE NOCASE,
          full_name TEXT NOT NULL, role TEXT NOT NULL CHECK(role IN
          ('guest','staff','supervisor','manager','maintenance','admin')),
          points INTEGER NOT NULL DEFAULT 0, revision INTEGER NOT NULL,
          salt TEXT NOT NULL, hash TEXT NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0 CHECK(deleted IN (0,1)))''');
          await db.execute('''CREATE TABLE rooms (
          number TEXT PRIMARY KEY, category TEXT NOT NULL,
          status TEXT NOT NULL CHECK(status IN ('ready','occupied','dirty','maintenance')),
          cleaning TEXT NOT NULL CHECK(cleaning IN ('waiting','inProgress','review','completed')),
          employeeId TEXT REFERENCES users(id), approvedBy TEXT,
          note TEXT NOT NULL, urgent INTEGER NOT NULL CHECK(urgent IN (0,1)),
          checklist TEXT NOT NULL, history TEXT NOT NULL, version INTEGER NOT NULL,
          archived INTEGER NOT NULL DEFAULT 0 CHECK(archived IN (0,1)),
          tasks TEXT NOT NULL DEFAULT '[]')''');
          await db.execute(
            'CREATE TABLE task_photos (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
          );
          await db.execute('''CREATE TABLE supplies (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, quantity INTEGER NOT NULL
          CHECK(quantity BETWEEN 0 AND 1000000), unit TEXT NOT NULL,
          minimum INTEGER NOT NULL, version INTEGER NOT NULL)''');
          await db.execute(
            '''CREATE TABLE notifications (
          id TEXT PRIMARY KEY, title TEXT NOT NULL, message TEXT NOT NULL,
          roomNumber TEXT, audience TEXT NOT NULL, position INTEGER NOT NULL)''',
          );
          await db.execute('''CREATE TABLE notification_reads (
          actor TEXT NOT NULL REFERENCES users(id),
          notification TEXT NOT NULL REFERENCES notifications(id),
          PRIMARY KEY(actor, notification))''');
          await db.execute(
            'CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              "ALTER TABLE rooms ADD COLUMN tasks TEXT NOT NULL DEFAULT '[]'",
            );
            await db.execute(
              'CREATE TABLE task_photos (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
            );
            // Test completions without photo evidence are no longer verified.
            await db.rawUpdate(
              "UPDATE rooms SET checklist = '[false,false,false,false]', cleaning = 'waiting', version = version + 1 WHERE status = 'dirty'",
            );
          }
        },
      ),
    );
    return LocalDatabase._(db);
  }

  Future<bool> initialized() async => (await database.query(
    'metadata',
    where: 'key = ?',
    whereArgs: ['initialized'],
  )).isNotEmpty;

  Future<Map<String, dynamic>> read([DatabaseExecutor? executor]) async {
    if (executor == null) return database.transaction((tx) => read(tx));
    final users = (await executor.query('users'))
        .map((row) => <String, dynamic>{...row, 'deleted': row['deleted'] == 1})
        .toList();
    final rooms = (await executor.query('rooms', orderBy: 'number'))
        .map(
          (row) => <String, dynamic>{
            ...row,
            'urgent': row['urgent'] == 1,
            'checklist': jsonDecode(row['checklist'] as String),
            'history': jsonDecode(row['history'] as String),
            'tasks': (row['tasks'] == '[]')
                ? TaskSchema.defaults()
                : jsonDecode(row['tasks'] as String),
          },
        )
        .toList();
    final reads = <String, dynamic>{};
    for (final row in await executor.query('notification_reads')) {
      (reads.putIfAbsent(row['actor'] as String, () => <dynamic>[]) as List)
          .add(row['notification']);
    }
    return {
      'users': users,
      'rooms': rooms.where((r) => r['archived'] == 0).toList(),
      'roomArchives': rooms.where((r) => r['archived'] == 1).toList(),
      'supplies': (await executor.query(
        'supplies',
        orderBy: 'rowid',
      )).map((r) => Map<String, dynamic>.from(r)).toList(),
      'notifications': (await executor.query(
        'notifications',
        orderBy: 'position',
      )).map((r) => Map<String, dynamic>.from(r)).toList(),
      'reads': reads,
    };
  }

  /// Save only changed rows. Called in the same transaction as reading and
  /// validating the current state, so stale versions cannot overwrite new data.
  Future<void> write(DatabaseExecutor tx, Map<String, dynamic> state) async {
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

    await sync('users', 'id', [
      for (final u in state['users'] as List)
        {
          for (final k in [
            'id',
            'email',
            'full_name',
            'role',
            'points',
            'revision',
            'salt',
            'hash',
          ])
            k: u[k],
          'deleted': u['deleted'] == true ? 1 : 0,
        },
    ]);
    await sync('rooms', 'number', [
      for (final archived in [false, true])
        for (final r
            in (state[archived ? 'roomArchives' : 'rooms'] as List? ?? []))
          {
            for (final k in [
              'number',
              'category',
              'status',
              'cleaning',
              'employeeId',
              'approvedBy',
              'note',
              'version',
            ])
              k: r[k],
            'urgent': r['urgent'] == true ? 1 : 0,
            'checklist': jsonEncode(r['checklist']),
            'tasks': jsonEncode(r['tasks'] ?? TaskSchema.defaults()),
            'history': jsonEncode(r['history']),
            'archived': archived ? 1 : 0,
          },
    ]);
    await sync('supplies', 'id', [
      for (final s in state['supplies'] as List)
        {
          for (final k in [
            'id',
            'name',
            'quantity',
            'unit',
            'minimum',
            'version',
          ])
            k: s[k],
        },
    ]);
    await sync('notifications', 'id', [
      for (var i = 0; i < (state['notifications'] as List).length; i++)
        {
          for (final k in ['id', 'title', 'message', 'roomNumber', 'audience'])
            k: state['notifications'][i][k],
          'position': i,
        },
    ]);
    // Read receipts are small and have a composite key.
    await tx.delete('notification_reads');
    for (final entry in (state['reads'] as Map).entries) {
      for (final id in entry.value as List) {
        await tx.insert('notification_reads', {
          'actor': entry.key,
          'notification': id,
        });
      }
    }
    await tx.insert('metadata', {
      'key': 'initialized',
      'value': '1',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final writes =
        state.remove('_photoWrites') as Map? ??
        state.remove('photoData') as Map? ??
        {};
    for (final entry in writes.entries) {
      await tx.insert('task_photos', {
        'id': entry.key,
        'data': entry.value,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    final referenced = <String>{};
    for (final room in [
      ...state['rooms'] as List,
      ...(state['roomArchives'] as List? ?? []),
    ]) {
      for (final task in room['tasks'] as List? ?? []) {
        if (task['photoId'] is String) {
          referenced.add(task['photoId'] as String);
        }
      }
    }
    for (final photo in await tx.query('task_photos', columns: ['id'])) {
      if (!referenced.contains(photo['id'])) {
        await tx.delete(
          'task_photos',
          where: 'id = ?',
          whereArgs: [photo['id']],
        );
      }
    }
  }

  Future<void> close() => database.close();
  Future<Map<String, String>> photos(DatabaseExecutor tx) async => {
    for (final row in await tx.query('task_photos'))
      row['id'] as String: row['data'] as String,
  };

  Future<String?> savedSession(DatabaseExecutor tx) async {
    final rows = await tx.query(
      'metadata',
      where: 'key = ?',
      whereArgs: ['session_user'],
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Future<void> saveSession(DatabaseExecutor tx, String? id) async {
    await tx.delete('metadata', where: 'key = ?', whereArgs: ['session_user']);
    if (id != null) {
      await tx.insert('metadata', {'key': 'session_user', 'value': id});
    }
  }

  Future<void> replace(DatabaseExecutor tx, Map<String, dynamic> state) async {
    // Children first: keep foreign keys enabled throughout the transaction.
    for (final table in [
      'notification_reads',
      'task_photos',
      'notifications',
      'rooms',
      'supplies',
      'users',
    ]) {
      await tx.delete(table);
    }
    await write(tx, state);
    await saveSession(tx, null);
  }
}
