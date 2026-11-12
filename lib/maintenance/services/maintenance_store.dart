import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../../shared/models/app_user.dart';
import '../../shared/services/app_database.dart';
import '../models/intervention.dart';

/// Tables du module Maintenance (version 1).
const maintenanceSchema = ModuleSchema(
  module: 'maintenance',
  version: 1,
  migrate: _migrate,
);

Future<void> _migrate(Transaction tx, int from, int to) async {
  if (from < 1) {
    await tx.execute('''
      CREATE TABLE maintenance_interventions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        room TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'autre',
        priority TEXT NOT NULL DEFAULT 'normal',
        status TEXT NOT NULL DEFAULT 'pending',
        reporter_id TEXT,
        reporter_name TEXT,
        assignee_id TEXT,
        assignee_name TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        resolved_at TEXT
      )''');
    await tx.execute('''
      CREATE TABLE maintenance_photos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        intervention_id INTEGER NOT NULL
          REFERENCES maintenance_interventions (id) ON DELETE CASCADE,
        image BLOB NOT NULL,
        created_at TEXT NOT NULL
      )''');
    await tx.execute(
      'CREATE INDEX maintenance_interventions_status '
      'ON maintenance_interventions (status)',
    );
    await tx.execute(
      'CREATE INDEX maintenance_photos_intervention '
      'ON maintenance_photos (intervention_id)',
    );
  }
}

/// Lecture et écriture des interventions dans la base commune.
class MaintenanceStore {
  final Database db;
  MaintenanceStore(this.db);

  static const _orderByPriority = '''
    ORDER BY CASE priority WHEN 'urgent' THEN 0 WHEN 'high' THEN 1 ELSE 2 END,
             created_at DESC''';

  /// Interventions non résolues, urgentes en premier.
  Future<List<Intervention>> active() async {
    final rows = await db.rawQuery(
      "SELECT * FROM maintenance_interventions WHERE status != 'resolved' "
      '$_orderByPriority',
    );
    return rows.map(Intervention.fromMap).toList();
  }

  /// Historique : interventions résolues, les plus récentes en premier.
  Future<List<Intervention>> resolved() async {
    final rows = await db.query(
      'maintenance_interventions',
      where: "status = 'resolved'",
      orderBy: 'resolved_at DESC',
    );
    return rows.map(Intervention.fromMap).toList();
  }

  Future<Intervention?> byId(int id) async {
    final rows = await db.query(
      'maintenance_interventions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Intervention.fromMap(rows.first);
  }

  Future<List<Uint8List>> photos(int interventionId) async {
    final rows = await db.query(
      'maintenance_photos',
      columns: ['image'],
      where: 'intervention_id = ?',
      whereArgs: [interventionId],
      orderBy: 'id ASC',
    );
    return [
      for (final r in rows)
        r['image'] is Uint8List
            ? r['image'] as Uint8List
            : Uint8List.fromList(List<int>.from(r['image'] as List)),
    ];
  }

  Future<int> create({
    required String title,
    required String room,
    required InterventionCategory category,
    required InterventionPriority priority,
    String description = '',
    AppUser? reporter,
    List<Uint8List> photos = const [],
  }) {
    final now = DateTime.now().toIso8601String();
    return db.transaction<int>((txn) async {
      final id = await txn.insert('maintenance_interventions', {
        'title': title.trim(),
        'description': description.trim(),
        'room': room.trim(),
        'category': category.dbValue,
        'priority': priority.dbValue,
        'status': InterventionStatus.pending.dbValue,
        'reporter_id': reporter?.id,
        'reporter_name': reporter?.fullName,
        'created_at': now,
        'updated_at': now,
      });
      for (final p in photos) {
        await txn.insert('maintenance_photos', {
          'intervention_id': id,
          'image': p,
          'created_at': now,
        });
      }
      return id;
    });
  }

  Future<void> addPhoto(int interventionId, Uint8List bytes) =>
      db.insert('maintenance_photos', {
        'intervention_id': interventionId,
        'image': bytes,
        'created_at': DateTime.now().toIso8601String(),
      });

  /// Le technicien prend l'intervention : assignée à lui + statut "en cours".
  Future<void> takeCharge(int id, AppUser technician) => _update(id, {
    'assignee_id': technician.id,
    'assignee_name': technician.fullName,
    'status': InterventionStatus.inProgress.dbValue,
  });

  /// Le manager attribue l'intervention à un technicien.
  Future<void> assign(int id, AppUser technician) => _update(id, {
    'assignee_id': technician.id,
    'assignee_name': technician.fullName,
  });

  Future<void> markResolved(int id) => _update(id, {
    'status': InterventionStatus.resolved.dbValue,
    'resolved_at': DateTime.now().toIso8601String(),
  });

  Future<void> delete(int id) => db.transaction((txn) async {
    await txn.delete(
      'maintenance_photos',
      where: 'intervention_id = ?',
      whereArgs: [id],
    );
    await txn.delete(
      'maintenance_interventions',
      where: 'id = ?',
      whereArgs: [id],
    );
  });

  Future<void> _update(int id, Map<String, Object?> values) => db.update(
    'maintenance_interventions',
    {...values, 'updated_at': DateTime.now().toIso8601String()},
    where: 'id = ?',
    whereArgs: [id],
  );
}
