import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../shared/models/app_user.dart';
import '../../shared/services/app_database.dart';
import '../../shared/services/app_session.dart';
import '../models/task_schema.dart';
import 'app_exception.dart';
import 'housekeeping_seed.dart';
import 'inventory_rules.dart';
import 'issue_rules.dart';
import 'local_attachment_store.dart';
import 'local_session_store.dart';

// The module's tables, all prefixed housekeeping_. Bump [version] and add a
// step to [migrate] for every change; never edit a step already pushed.
final housekeepingSchema = ModuleSchema(
  module: 'housekeeping',
  version: 6,
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
    }
    if (from < 2) {
      // Supervisor comment on a refused cleaning; cleaning an occupied room.
      await tx.execute(
        'ALTER TABLE housekeeping_rooms ADD COLUMN feedback TEXT',
      );
      await tx.execute(
        'ALTER TABLE housekeeping_rooms ADD COLUMN stayover INTEGER NOT NULL DEFAULT 0',
      );
      // One row per cleaning, for the supervisor's statistics.
      await tx.execute('''CREATE TABLE housekeeping_cleanings (
        id TEXT PRIMARY KEY, room_number TEXT NOT NULL, agent_id TEXT,
        kind TEXT NOT NULL CHECK(kind IN ('checkout','stayover')),
        assigned_at TEXT NOT NULL, started_at TEXT, submitted_at TEXT,
        approved_at TEXT, refusals INTEGER NOT NULL DEFAULT 0)''');
      await tx.execute('''CREATE TABLE housekeeping_lost_items (
        id TEXT PRIMARY KEY, room_number TEXT NOT NULL,
        description TEXT NOT NULL, photo_id TEXT, found_by TEXT NOT NULL,
        found_by_name TEXT NOT NULL, found_at TEXT NOT NULL,
        returned_at TEXT, returned_to TEXT, version INTEGER NOT NULL)''');
      // Default task list of each room category (JSON list of labels).
      await tx.execute('''CREATE TABLE housekeeping_category_tasks (
        category TEXT PRIMARY KEY, tasks TEXT NOT NULL,
        version INTEGER NOT NULL)''');
      await tx.execute('''CREATE TABLE housekeeping_floors (
        number INTEGER PRIMARY KEY CHECK(number BETWEEN 1 AND 9),
        name TEXT NOT NULL, version INTEGER NOT NULL)''');
    }
    if (from < 3) {
      // Cleaning priority: checkout, VIP or early check-in first.
      await tx.execute(
        "ALTER TABLE housekeeping_rooms ADD COLUMN priority TEXT NOT NULL DEFAULT 'normal' "
        "CHECK(priority IN ('normal','checkout','vip','early'))",
      );
      // Actual working time of a cleaning, pauses excluded.
      await tx.execute(
        'ALTER TABLE housekeeping_cleanings ADD COLUMN finished_at TEXT',
      );
      await tx.execute(
        'ALTER TABLE housekeeping_cleanings ADD COLUMN duration_ms INTEGER',
      );
      // One row per running stretch of a cleaning timer (start/resume to
      // pause/stop). An open row (ended_at NULL) is a running timer.
      await tx.execute('''CREATE TABLE housekeeping_timer_segments (
        id TEXT PRIMARY KEY, cleaning_id TEXT NOT NULL,
        room_number TEXT NOT NULL, agent_id TEXT NOT NULL,
        started_at TEXT NOT NULL, ended_at TEXT)''');
      await tx.execute('''CREATE TABLE housekeeping_category_estimates (
        category TEXT PRIMARY KEY,
        minutes INTEGER NOT NULL CHECK(minutes BETWEEN 5 AND 480),
        version INTEGER NOT NULL)''');
      await tx.execute('''CREATE TABLE housekeeping_availability (
        date TEXT NOT NULL, agent_id TEXT NOT NULL,
        available INTEGER NOT NULL CHECK(available IN (0,1)),
        capacity_minutes INTEGER NOT NULL CHECK(capacity_minutes BETWEEN 0 AND 720),
        PRIMARY KEY(date, agent_id))''');
      // Client mutation ids already applied (idempotent replay for sync).
      await tx.execute('''CREATE TABLE housekeeping_mutations (
        id TEXT PRIMARY KEY, path TEXT NOT NULL, actor TEXT NOT NULL,
        client_timestamp TEXT NOT NULL, applied_at TEXT NOT NULL)''');
    }
    if (from < 4) {
      // Inspection: one row per round, one row per rated checklist item.
      await tx.execute('''CREATE TABLE housekeeping_inspections (
        id TEXT PRIMARY KEY, cleaning_id TEXT, room_number TEXT NOT NULL,
        agent_id TEXT, inspector_id TEXT NOT NULL,
        inspector_name TEXT NOT NULL, round INTEGER NOT NULL,
        score INTEGER CHECK(score BETWEEN 0 AND 100),
        threshold INTEGER NOT NULL,
        outcome TEXT NOT NULL CHECK(outcome IN ('approved','sentBack')),
        comment TEXT, inspected_at TEXT NOT NULL)''');
      await tx.execute('''CREATE TABLE housekeeping_inspection_items (
        id TEXT PRIMARY KEY,
        inspection_id TEXT NOT NULL
          REFERENCES housekeeping_inspections(id) ON DELETE CASCADE,
        task_id TEXT NOT NULL, label TEXT NOT NULL,
        weight INTEGER NOT NULL CHECK(weight BETWEEN 1 AND 5),
        rating TEXT NOT NULL CHECK(rating IN ('ok','partial','failed')),
        comment TEXT, photo_id TEXT, position INTEGER NOT NULL)''');
      // Pass threshold and item weights per room category.
      await tx.execute('''CREATE TABLE housekeeping_inspection_rules (
        category TEXT PRIMARY KEY,
        threshold INTEGER NOT NULL CHECK(threshold BETWEEN 0 AND 100),
        weights TEXT NOT NULL, version INTEGER NOT NULL)''');
      // Final inspection score and number of rounds of each cleaning.
      await tx.execute(
        'ALTER TABLE housekeeping_cleanings ADD COLUMN inspection_score INTEGER',
      );
      await tx.execute(
        'ALTER TABLE housekeeping_cleanings ADD COLUMN inspection_rounds INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (from < 5) {
      // Problem reports with their photos and optional voice note (a file in
      // the app's folder: only its relative path is stored).
      await tx.execute('''CREATE TABLE housekeeping_issues (
        id TEXT PRIMARY KEY, room_number TEXT NOT NULL,
        category TEXT NOT NULL CHECK(category IN ('climatisation','eclairage','plomberie','television','mobilier','autre')),
        description TEXT NOT NULL,
        priority TEXT NOT NULL CHECK(priority IN ('low','normal','high','urgent')),
        out_of_service INTEGER NOT NULL CHECK(out_of_service IN (0,1)),
        status TEXT NOT NULL CHECK(status IN ('open','resolved','closed')),
        reported_by TEXT NOT NULL, reported_by_name TEXT NOT NULL,
        reported_at TEXT NOT NULL, resolved_at TEXT, closed_at TEXT,
        closed_by_name TEXT, voice_path TEXT,
        voice_seconds INTEGER CHECK(voice_seconds BETWEEN 1 AND 60),
        version INTEGER NOT NULL)''');
      await tx.execute('''CREATE TABLE housekeeping_issue_photos (
        issue_id TEXT NOT NULL
          REFERENCES housekeeping_issues(id) ON DELETE CASCADE,
        position INTEGER NOT NULL, photo_id TEXT NOT NULL,
        PRIMARY KEY(issue_id, position))''');
      // Found items: status flow and full history (contact attempts...).
      await tx.execute(
        "ALTER TABLE housekeeping_lost_items ADD COLUMN status TEXT NOT NULL DEFAULT 'found' "
        "CHECK(status IN ('found','notified','returned','archived'))",
      );
      await tx.execute(
        'ALTER TABLE housekeeping_lost_items ADD COLUMN archived_at TEXT',
      );
      await tx.execute(
        "UPDATE housekeeping_lost_items SET status = 'returned' WHERE returned_at IS NOT NULL",
      );
      await tx.execute('''CREATE TABLE housekeeping_lost_item_events (
        id TEXT PRIMARY KEY,
        item_id TEXT NOT NULL
          REFERENCES housekeeping_lost_items(id) ON DELETE CASCADE,
        kind TEXT NOT NULL CHECK(kind IN ('found','notified','returned','archived')),
        at TEXT NOT NULL, actor_id TEXT, actor_name TEXT NOT NULL,
        channel TEXT CHECK(channel IS NULL OR channel IN ('phone','email','sms','inPerson')),
        message TEXT)''');
      await tx.execute('''INSERT INTO housekeeping_lost_item_events
        (id, item_id, kind, at, actor_id, actor_name)
        SELECT 'found-' || id, id, 'found', found_at, found_by, found_by_name
        FROM housekeeping_lost_items''');
      await tx.execute('''INSERT INTO housekeeping_lost_item_events
        (id, item_id, kind, at, actor_name, message)
        SELECT 'returned-' || id, id, 'returned', returned_at, 'Gouvernante',
          'Rendu à ' || returned_to
        FROM housekeeping_lost_items WHERE returned_at IS NOT NULL''');
      // Module settings, e.g. the archive delay of found items.
      await tx.execute(
        '''CREATE TABLE housekeeping_settings (
        key TEXT PRIMARY KEY, value TEXT NOT NULL, version INTEGER NOT NULL)''',
      );
      // Rooms already in maintenance get a report to follow them up.
      if (from >= 1) {
        final now = DateTime.now();
        for (final room in await tx.query(
          'housekeeping_rooms',
          where: "status = 'maintenance'",
        )) {
          final issue = legacyIssue({
            'number': room['number'],
            'note': room['note'],
            'urgent': room['urgent'] == 1,
          }, now)..remove('photos');
          issue['out_of_service'] = 1;
          await tx.insert('housekeeping_issues', issue);
        }
      }
    }
    if (from < 6) {
      // Typed stock items (linen, amenities, cleaning products, minibar).
      await tx.execute(
        "ALTER TABLE housekeeping_supplies ADD COLUMN category TEXT NOT NULL DEFAULT 'entretien' "
        "CHECK(category IN ('linge','accueil','entretien','minibar'))",
      );
      await tx.execute(
        'ALTER TABLE housekeeping_supplies ADD COLUMN price_cents INTEGER '
        'CHECK(price_cents IS NULL OR price_cents BETWEEN 1 AND 100000)',
      );
      for (final row in await tx.query('housekeeping_supplies')) {
        await tx.update(
          'housekeeping_supplies',
          {'category': categoryFromName(row['name'] as String)},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
      // A notification for one account only (supply request steps).
      await tx.execute(
        'ALTER TABLE housekeeping_notifications ADD COLUMN recipient_id TEXT',
      );
      // Every stock change: the usage log per floor and room.
      await tx.execute('''CREATE TABLE housekeeping_stock_movements (
        id TEXT PRIMARY KEY, supply_id TEXT NOT NULL, supply_name TEXT NOT NULL,
        delta INTEGER NOT NULL, quantity INTEGER NOT NULL,
        reason TEXT NOT NULL CHECK(reason IN ('manual','usage','laundry_out','laundry_in','laundry_damaged','laundry_lost','request','minibar_restock')),
        room_number TEXT, floor INTEGER, actor_id TEXT NOT NULL,
        actor_name TEXT NOT NULL, ref_id TEXT, at TEXT NOT NULL)''');
      await tx.execute('''CREATE TABLE housekeeping_laundry_batches (
        id TEXT PRIMARY KEY,
        status TEXT NOT NULL CHECK(status IN ('sent','returned')),
        note TEXT, sent_at TEXT NOT NULL, sent_by_name TEXT NOT NULL,
        returned_at TEXT, returned_by_name TEXT, version INTEGER NOT NULL)''');
      await tx.execute('''CREATE TABLE housekeeping_laundry_lines (
        id TEXT PRIMARY KEY,
        batch_id TEXT NOT NULL
          REFERENCES housekeeping_laundry_batches(id) ON DELETE CASCADE,
        supply_id TEXT NOT NULL, supply_name TEXT NOT NULL, unit TEXT NOT NULL,
        sent INTEGER NOT NULL CHECK(sent > 0),
        received INTEGER, damaged INTEGER, lost INTEGER,
        position INTEGER NOT NULL)''');
      await tx.execute('''CREATE TABLE housekeeping_supply_requests (
        id TEXT PRIMARY KEY,
        status TEXT NOT NULL CHECK(status IN ('requested','approved','prepared','delivered','refused')),
        agent_id TEXT NOT NULL, agent_name TEXT NOT NULL, note TEXT,
        created_at TEXT NOT NULL, approved_at TEXT, prepared_at TEXT,
        delivered_at TEXT, refused_at TEXT, processed_by_name TEXT,
        refusal_reason TEXT, version INTEGER NOT NULL)''');
      await tx.execute('''CREATE TABLE housekeeping_supply_request_lines (
        id TEXT PRIMARY KEY,
        request_id TEXT NOT NULL
          REFERENCES housekeeping_supply_requests(id) ON DELETE CASCADE,
        supply_id TEXT NOT NULL, supply_name TEXT NOT NULL, unit TEXT NOT NULL,
        requested INTEGER NOT NULL CHECK(requested > 0),
        approved INTEGER NOT NULL CHECK(approved >= 0),
        position INTEGER NOT NULL)''');
      // Minibar consumptions: billed once; corrected after billing only by
      // a compensating entry (corrects_id).
      await tx.execute('''CREATE TABLE housekeeping_minibar_consumptions (
        id TEXT PRIMARY KEY, room_number TEXT NOT NULL, supply_id TEXT,
        label TEXT NOT NULL, unit_price_cents INTEGER NOT NULL,
        quantity INTEGER NOT NULL, amount_cents INTEGER NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('pending','billed','cancelled')),
        recorded_by TEXT NOT NULL, recorded_by_name TEXT NOT NULL,
        recorded_at TEXT NOT NULL, billed_at TEXT, billed_by_name TEXT,
        corrects_id TEXT, stay_id TEXT, version INTEGER NOT NULL)''');
      // Guest stays as told by the reservation events (room and name only).
      await tx.execute('''CREATE TABLE housekeeping_stays (
        id TEXT PRIMARY KEY, room_number TEXT NOT NULL,
        guest_name TEXT NOT NULL, checked_in_at TEXT NOT NULL,
        checked_out_at TEXT)''');
    }
    // A new install gets its starting data once every table exists.
    if (from < 1) {
      await HousekeepingStore._write(tx, housekeepingSeedState());
    }
  },
);

/// Build option: `--dart-define=HOUSEKEEPING_SAMPLE_DATA=false` starts a new
/// install with an empty hotel (no rooms, stock or notifications).
const housekeepingSampleData = bool.fromEnvironment(
  'HOUSEKEEPING_SAMPLE_DATA',
  defaultValue: true,
);

/// The fictional rooms, stock and notifications of a new install.
Map<String, dynamic> housekeepingSeedState({
  bool samples = housekeepingSampleData,
}) {
  if (!samples) {
    return {
      'rooms': <dynamic>[],
      'roomArchives': <dynamic>[],
      'supplies': <dynamic>[],
      'notifications': <dynamic>[],
      'reads': <String, dynamic>{},
      'cleanings': <dynamic>[],
      'lostItems': <dynamic>[],
      'categoryTasks': <String, dynamic>{},
      'floors': <dynamic>[],
      'timerSegments': <dynamic>[],
      'estimates': <String, dynamic>{},
      'availability': <dynamic>[],
      'mutations': <dynamic>[],
      'inspections': <dynamic>[],
      'inspectionRules': <String, dynamic>{},
      'issues': <dynamic>[],
      'settings': <String, dynamic>{},
      'stockMovements': <dynamic>[],
      'laundry': <dynamic>[],
      'requests': <dynamic>[],
      'minibar': <dynamic>[],
      'stays': <dynamic>[],
    };
  }
  final seed = jsonDecode(housekeepingSeedJson) as Map<String, dynamic>;
  for (final room in seed['rooms'] as List) {
    TaskSchema.ensure(room as Map<String, dynamic>);
    // Sample rooms have no photo evidence, so nothing awaits approval.
    if (room['status'] == 'dirty') {
      room['checklist'] = List.filled(4, false);
      if (room['cleaning'] == 'review') room['cleaning'] = 'waiting';
    }
  }
  return {
    'rooms': seed['rooms'],
    'roomArchives': <dynamic>[],
    'supplies': [
      for (final supply in seed['supplies'] as List)
        {
          ...supply as Map<String, dynamic>,
          'category': categoryFromName(supply['name'] as String),
          'priceCents': null,
        },
      for (final (id, name, price) in [
        ('minibar-water', 'Eau minérale 50 cl', 400),
        ('minibar-soda', 'Soda 33 cl', 450),
        ('minibar-chocolate', 'Tablette de chocolat', 350),
      ])
        {
          'id': id,
          'name': name,
          'quantity': 24,
          'unit': 'unités',
          'minimum': 6,
          'version': 1,
          'category': 'minibar',
          'priceCents': price,
        },
    ],
    'notifications': seed['notifications'],
    'reads': <String, dynamic>{},
    'cleanings': <dynamic>[],
    'lostItems': <dynamic>[],
    'categoryTasks': <String, dynamic>{},
    'floors': <dynamic>[
      for (var floor = 1; floor <= 4; floor++)
        {'number': floor, 'name': 'Étage $floor', 'version': 1},
    ],
    'timerSegments': <dynamic>[],
    'estimates': <String, dynamic>{},
    'availability': <dynamic>[],
    'mutations': <dynamic>[],
    'inspections': <dynamic>[],
    'inspectionRules': <String, dynamic>{},
    'issues': [
      for (final room in seed['rooms'] as List)
        if (room['status'] == 'maintenance')
          legacyIssue(room as Map<String, dynamic>, DateTime.now()),
    ],
    'settings': <String, dynamic>{},
    'stockMovements': <dynamic>[],
    'laundry': <dynamic>[],
    'requests': <dynamic>[],
    'minibar': <dynamic>[],
    'stays': <dynamic>[],
  };
}

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
          'feedback': row['feedback'],
          'stayover': row['stayover'] == 1,
          'priority': row['priority'] ?? 'normal',
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
            'category': row['category'] ?? 'entretien',
            'priceCents': row['price_cents'],
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
            'recipient': row['recipient_id'],
          },
      ],
      'reads': reads,
      'cleanings': [
        for (final row in await db.query(
          'housekeeping_cleanings',
          orderBy: 'assigned_at',
        ))
          Map<String, dynamic>.from(row),
      ],
      'lostItems': await _readLostItems(db),
      'issues': await _readIssues(db),
      'stockMovements': [
        for (final row in await db.query(
          'housekeeping_stock_movements',
          orderBy: 'at, rowid',
        ))
          Map<String, dynamic>.from(row),
      ],
      'laundry': await _withLines(
        db,
        'housekeeping_laundry_batches',
        'housekeeping_laundry_lines',
        'batch_id',
        'sent_at DESC',
      ),
      'requests': await _withLines(
        db,
        'housekeeping_supply_requests',
        'housekeeping_supply_request_lines',
        'request_id',
        'created_at DESC',
      ),
      'minibar': [
        for (final row in await db.query(
          'housekeeping_minibar_consumptions',
          orderBy: 'recorded_at DESC, rowid DESC',
        ))
          Map<String, dynamic>.from(row),
      ],
      'stays': [
        for (final row in await db.query(
          'housekeeping_stays',
          orderBy: 'checked_in_at, rowid',
        ))
          Map<String, dynamic>.from(row),
      ],
      'settings': {
        for (final row in await db.query('housekeeping_settings'))
          row['key'] as String: {
            'value': row['value'],
            'version': row['version'],
          },
      },
      'categoryTasks': {
        for (final row in await db.query('housekeeping_category_tasks'))
          row['category'] as String: {
            'tasks': jsonDecode(row['tasks'] as String),
            'version': row['version'],
          },
      },
      'floors': [
        for (final row in await db.query(
          'housekeeping_floors',
          orderBy: 'number',
        ))
          Map<String, dynamic>.from(row),
      ],
      'timerSegments': [
        for (final row in await db.query(
          'housekeeping_timer_segments',
          orderBy: 'started_at',
        ))
          Map<String, dynamic>.from(row),
      ],
      'estimates': {
        for (final row in await db.query('housekeeping_category_estimates'))
          row['category'] as String: {
            'minutes': row['minutes'],
            'version': row['version'],
          },
      },
      'availability': [
        for (final row in await db.query('housekeeping_availability'))
          {
            'date': row['date'],
            'agent_id': row['agent_id'],
            'available': row['available'] == 1,
            'capacity_minutes': row['capacity_minutes'],
          },
      ],
      'mutations': [
        for (final row in await db.query(
          'housekeeping_mutations',
          columns: ['id'],
        ))
          {'id': row['id']},
      ],
      'inspections': await _readInspections(db),
      'inspectionRules': {
        for (final row in await db.query('housekeeping_inspection_rules'))
          row['category'] as String: {
            'threshold': row['threshold'],
            'weights': jsonDecode(row['weights'] as String),
            'version': row['version'],
          },
      },
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

  // Rows of [table] with their lines (in order) under 'lines'.
  static Future<List<Map<String, dynamic>>> _withLines(
    DatabaseExecutor db,
    String table,
    String lineTable,
    String parent,
    String orderBy,
  ) async {
    final lines = <Object?, List<Map<String, dynamic>>>{};
    for (final row in await db.query(lineTable, orderBy: 'position')) {
      lines
          .putIfAbsent(row[parent], () => [])
          .add(
            Map<String, dynamic>.from(row)
              ..remove(parent)
              ..remove('position'),
          );
    }
    return [
      for (final row in await db.query(table, orderBy: orderBy))
        {...row, 'lines': lines[row['id']] ?? <Map<String, dynamic>>[]},
    ];
  }

  // Found items, newest first, each with its history (oldest first).
  static Future<List<Map<String, dynamic>>> _readLostItems(
    DatabaseExecutor db,
  ) async {
    final events = <Object?, List<Map<String, dynamic>>>{};
    for (final row in await db.query(
      'housekeeping_lost_item_events',
      orderBy: 'at, rowid',
    )) {
      events
          .putIfAbsent(row['item_id'], () => [])
          .add(Map<String, dynamic>.from(row)..remove('item_id'));
    }
    return [
      for (final row in await db.query(
        'housekeeping_lost_items',
        orderBy: 'found_at DESC',
      ))
        {...row, 'events': events[row['id']] ?? <Map<String, dynamic>>[]},
    ];
  }

  // Problem reports, newest first, with their photo ids.
  static Future<List<Map<String, dynamic>>> _readIssues(
    DatabaseExecutor db,
  ) async {
    final photos = <Object?, List<String>>{};
    for (final row in await db.query(
      'housekeeping_issue_photos',
      orderBy: 'position',
    )) {
      photos
          .putIfAbsent(row['issue_id'], () => [])
          .add(row['photo_id'] as String);
    }
    return [
      for (final row in await db.query(
        'housekeeping_issues',
        orderBy: 'reported_at DESC',
      ))
        {
          ...row,
          'out_of_service': row['out_of_service'] == 1,
          'photos': photos[row['id']] ?? <String>[],
        },
    ];
  }

  // Inspection rounds with their items, oldest first.
  static Future<List<Map<String, dynamic>>> _readInspections(
    DatabaseExecutor db,
  ) async {
    final items = <Object?, List<Map<String, dynamic>>>{};
    for (final row in await db.query(
      'housekeeping_inspection_items',
      orderBy: 'position',
    )) {
      items
          .putIfAbsent(row['inspection_id'], () => [])
          .add(Map<String, dynamic>.from(row)..remove('inspection_id'));
    }
    return [
      for (final row in await db.query(
        'housekeeping_inspections',
        orderBy: 'inspected_at, round',
      ))
        {...row, 'items': items[row['id']] ?? <Map<String, dynamic>>[]},
    ];
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
            'feedback': r['feedback'],
            'stayover': r['stayover'] == true ? 1 : 0,
            'priority': r['priority'] ?? 'normal',
          },
    ]);
    await sync('housekeeping_cleanings', 'id', [
      for (final c in state['cleanings'] as List? ?? [])
        {
          for (final k in [
            'id',
            'room_number',
            'agent_id',
            'kind',
            'assigned_at',
            'started_at',
            'submitted_at',
            'approved_at',
            'refusals',
            'finished_at',
            'duration_ms',
            'inspection_score',
          ])
            k: c[k],
          'inspection_rounds': c['inspection_rounds'] ?? 0,
        },
    ]);
    // Inspections are history: rows are added, never changed.
    final known = {
      for (final row in await tx.query(
        'housekeeping_inspections',
        columns: ['id'],
      ))
        row['id'],
    };
    for (final i in state['inspections'] as List? ?? []) {
      if (known.contains(i['id'])) continue;
      await tx.insert('housekeeping_inspections', {
        for (final k in [
          'id',
          'cleaning_id',
          'room_number',
          'agent_id',
          'inspector_id',
          'inspector_name',
          'round',
          'score',
          'threshold',
          'outcome',
          'comment',
          'inspected_at',
        ])
          k: i[k],
      });
      final items = i['items'] as List? ?? [];
      for (var n = 0; n < items.length; n++) {
        await tx.insert('housekeeping_inspection_items', {
          for (final k in [
            'id',
            'task_id',
            'label',
            'weight',
            'rating',
            'comment',
            'photo_id',
          ])
            k: items[n][k],
          'inspection_id': i['id'],
          'position': n,
        });
      }
    }
    await sync('housekeeping_inspection_rules', 'category', [
      for (final entry in (state['inspectionRules'] as Map? ?? {}).entries)
        {
          'category': entry.key,
          'threshold': entry.value['threshold'],
          'weights': jsonEncode(entry.value['weights']),
          'version': entry.value['version'],
        },
    ]);
    await sync('housekeeping_timer_segments', 'id', [
      for (final t in state['timerSegments'] as List? ?? [])
        {
          for (final k in [
            'id',
            'cleaning_id',
            'room_number',
            'agent_id',
            'started_at',
            'ended_at',
          ])
            k: t[k],
        },
    ]);
    await sync('housekeeping_category_estimates', 'category', [
      for (final entry in (state['estimates'] as Map? ?? {}).entries)
        {
          'category': entry.key,
          'minutes': entry.value['minutes'],
          'version': entry.value['version'],
        },
    ]);
    // Availability has a composite key: rewritten as a whole (small table).
    await tx.delete('housekeeping_availability');
    for (final a in state['availability'] as List? ?? []) {
      await tx.insert('housekeeping_availability', {
        'date': a['date'],
        'agent_id': a['agent_id'],
        'available': a['available'] == true ? 1 : 0,
        'capacity_minutes': a['capacity_minutes'],
      });
    }
    // The mutation log only grows: insert the new ids.
    for (final m in state['mutations'] as List? ?? []) {
      if (m['path'] == null) continue; // already stored (read as id only)
      await tx.insert('housekeeping_mutations', {
        for (final k in [
          'id',
          'path',
          'actor',
          'client_timestamp',
          'applied_at',
        ])
          k: m[k],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await sync('housekeeping_lost_items', 'id', [
      for (final item in state['lostItems'] as List? ?? [])
        {
          for (final k in [
            'id',
            'room_number',
            'description',
            'photo_id',
            'found_by',
            'found_by_name',
            'found_at',
            'returned_at',
            'returned_to',
            'version',
            'archived_at',
          ])
            k: item[k],
          'status': item['status'] ?? 'found',
        },
    ]);
    // An item's history only grows: insert the new steps.
    final knownSteps = {
      for (final row in await tx.query(
        'housekeeping_lost_item_events',
        columns: ['id'],
      ))
        row['id'],
    };
    for (final item in state['lostItems'] as List? ?? []) {
      for (final e in item['events'] as List? ?? []) {
        if (knownSteps.contains(e['id'])) continue;
        await tx.insert('housekeeping_lost_item_events', {
          for (final k in [
            'id',
            'kind',
            'at',
            'actor_id',
            'actor_name',
            'channel',
            'message',
          ])
            k: e[k],
          'item_id': item['id'],
        });
      }
    }
    await sync('housekeeping_issues', 'id', [
      for (final i in state['issues'] as List? ?? [])
        {
          for (final k in [
            'id',
            'room_number',
            'category',
            'description',
            'priority',
            'status',
            'reported_by',
            'reported_by_name',
            'reported_at',
            'resolved_at',
            'closed_at',
            'closed_by_name',
            'voice_path',
            'voice_seconds',
            'version',
          ])
            k: i[k],
          'out_of_service': i['out_of_service'] == true ? 1 : 0,
        },
    ]);
    // A report's photos are set when it is created, never changed.
    final withPhotos = {
      for (final row in await tx.query(
        'housekeeping_issue_photos',
        columns: ['issue_id'],
        distinct: true,
      ))
        row['issue_id'],
    };
    for (final i in state['issues'] as List? ?? []) {
      if (withPhotos.contains(i['id'])) continue;
      final photos = i['photos'] as List? ?? [];
      for (var n = 0; n < photos.length; n++) {
        await tx.insert('housekeeping_issue_photos', {
          'issue_id': i['id'],
          'position': n,
          'photo_id': photos[n],
        });
      }
    }
    await sync('housekeeping_settings', 'key', [
      for (final entry in (state['settings'] as Map? ?? {}).entries)
        {
          'key': entry.key,
          'value': '${entry.value['value']}',
          'version': entry.value['version'],
        },
    ]);
    await sync('housekeeping_category_tasks', 'category', [
      for (final entry in (state['categoryTasks'] as Map? ?? {}).entries)
        {
          'category': entry.key,
          'tasks': jsonEncode(entry.value['tasks']),
          'version': entry.value['version'],
        },
    ]);
    await sync('housekeeping_floors', 'number', [
      for (final f in state['floors'] as List? ?? [])
        {'number': f['number'], 'name': f['name'], 'version': f['version']},
    ]);
    final supplies = state['supplies'] as List;
    await sync('housekeeping_supplies', 'id', [
      for (var i = 0; i < supplies.length; i++)
        {
          for (final k in ['id', 'name', 'quantity', 'unit', 'minimum'])
            k: supplies[i][k],
          'version': supplies[i]['version'],
          'position': i,
          'category': supplies[i]['category'] ?? 'entretien',
          'price_cents': supplies[i]['priceCents'],
        },
    ]);
    // The stock log only grows: insert the new movements.
    final knownMoves = {
      for (final row in await tx.query(
        'housekeeping_stock_movements',
        columns: ['id'],
      ))
        row['id'],
    };
    for (final m in state['stockMovements'] as List? ?? []) {
      if (knownMoves.contains(m['id'])) continue;
      await tx.insert('housekeeping_stock_movements', {
        for (final k in [
          'id',
          'supply_id',
          'supply_name',
          'delta',
          'quantity',
          'reason',
          'room_number',
          'floor',
          'actor_id',
          'actor_name',
          'ref_id',
          'at',
        ])
          k: m[k],
      });
    }
    Future<void> withLines(
      String table,
      String lineTable,
      String parent,
      List? rows,
      List<String> columns,
      List<String> lineColumns,
    ) async {
      // Parents first: new lines refer to them.
      await sync(table, 'id', [
        for (final row in rows ?? []) {for (final k in columns) k: row[k]},
      ]);
      await sync(lineTable, 'id', [
        for (final row in rows ?? [])
          for (final (n, line) in (row['lines'] as List).indexed)
            {
              for (final k in lineColumns) k: line[k],
              parent: row['id'],
              'position': n,
            },
      ]);
    }

    await withLines(
      'housekeeping_laundry_batches',
      'housekeeping_laundry_lines',
      'batch_id',
      state['laundry'] as List?,
      [
        'id',
        'status',
        'note',
        'sent_at',
        'sent_by_name',
        'returned_at',
        'returned_by_name',
        'version',
      ],
      [
        'id',
        'supply_id',
        'supply_name',
        'unit',
        'sent',
        'received',
        'damaged',
        'lost',
      ],
    );
    await withLines(
      'housekeeping_supply_requests',
      'housekeeping_supply_request_lines',
      'request_id',
      state['requests'] as List?,
      [
        'id',
        'status',
        'agent_id',
        'agent_name',
        'note',
        'created_at',
        'approved_at',
        'prepared_at',
        'delivered_at',
        'refused_at',
        'processed_by_name',
        'refusal_reason',
        'version',
      ],
      ['id', 'supply_id', 'supply_name', 'unit', 'requested', 'approved'],
    );
    await sync('housekeeping_minibar_consumptions', 'id', [
      for (final c in state['minibar'] as List? ?? [])
        {
          for (final k in [
            'id',
            'room_number',
            'supply_id',
            'label',
            'unit_price_cents',
            'quantity',
            'amount_cents',
            'status',
            'recorded_by',
            'recorded_by_name',
            'recorded_at',
            'billed_at',
            'billed_by_name',
            'corrects_id',
            'stay_id',
            'version',
          ])
            k: c[k],
        },
    ]);
    await sync('housekeeping_stays', 'id', [
      for (final stay in state['stays'] as List? ?? [])
        {
          for (final k in [
            'id',
            'room_number',
            'guest_name',
            'checked_in_at',
            'checked_out_at',
          ])
            k: stay[k],
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
          'recipient_id': notifications[i]['recipient'],
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
      for (final item in state['lostItems'] as List? ?? [])
        if (item['photo_id'] is String) item['photo_id'] as String,
      for (final inspection in state['inspections'] as List? ?? [])
        for (final item in inspection['items'] as List? ?? [])
          if (item['photo_id'] is String) item['photo_id'] as String,
      for (final issue in state['issues'] as List? ?? [])
        for (final id in issue['photos'] as List? ?? []) id as String,
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
