import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../models/app_user.dart';
import '../models/intervention.dart';
import 'database_helper.dart';
import 'maintenance_config.dart';

/// Backend du module Maintenance (CRUD sur SQLite via DatabaseHelper).
class MaintenanceService {
  MaintenanceService._();

  static Future<Database> get _db => DatabaseHelper.instance.database;

  static const _baseSelect = '''
    SELECT i.*, r.display_name AS reporter_name, a.display_name AS assignee_name
    FROM interventions i
    LEFT JOIN users r ON r.id = i.reporter_id
    LEFT JOIN users a ON a.id = i.assignee_id
  ''';

  static const _orderByPriority = '''
    ORDER BY CASE i.priority WHEN 'urgent' THEN 0 WHEN 'high' THEN 1 ELSE 2 END,
             i.created_at DESC
  ''';

  // ------------------------------------------------------------ READ

  /// Interventions non résolues, urgentes en premier.
  static Future<List<Intervention>> getActive() async {
    final db = await _db;
    final rows = await db
        .rawQuery("$_baseSelect WHERE i.status != 'resolved' $_orderByPriority");
    return rows.map(Intervention.fromMap).toList();
  }

  /// Historique : interventions résolues, les plus récentes en premier.
  static Future<List<Intervention>> getResolved() async {
    final db = await _db;
    final rows = await db.rawQuery(
        "$_baseSelect WHERE i.status = 'resolved' ORDER BY i.resolved_at DESC");
    return rows.map(Intervention.fromMap).toList();
  }

  static Future<int> countActive() async {
    final db = await _db;
    return Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM interventions WHERE status != 'resolved'")) ??
        0;
  }

  static Future<Intervention?> getById(int id) async {
    final db = await _db;
    final rows = await db.rawQuery('$_baseSelect WHERE i.id = ? LIMIT 1', [id]);
    return rows.isEmpty ? null : Intervention.fromMap(rows.first);
  }

  static Future<List<Uint8List>> getPhotos(int interventionId) async {
    final db = await _db;
    final rows = await db.query(
      'intervention_photos',
      columns: ['image'],
      where: 'intervention_id = ?',
      whereArgs: [interventionId],
      orderBy: 'id ASC',
    );
    return rows.map((r) {
      final raw = r['image'];
      return raw is Uint8List
          ? raw
          : Uint8List.fromList(List<int>.from(raw as List));
    }).toList();
  }

  /// Utilisateurs ayant le rôle `maintenance` (pour l'attribution).
  static Future<List<AppUser>> getTechnicians() async {
    final db = await _db;
    final rows = await db.query('users',
        where: "role = 'maintenance'", orderBy: 'display_name ASC');
    return rows.map((m) => AppUser.fromMap(m)).toList();
  }

  // ------------------------------------------------------------ CREATE

  static Future<int> create({
    required String title,
    required String room,
    required InterventionCategory category,
    required InterventionPriority priority,
    String description = '',
    int? reporterId,
    List<Uint8List> photos = const [],
    String source = 'manual',
    String? sourceKey,
  }) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    return db.transaction<int>((txn) async {
      final id = await txn.insert('interventions', {
        'title': title.trim(),
        'description': description.trim(),
        'room': room.trim(),
        'category': category.dbValue,
        'priority': priority.dbValue,
        'status': InterventionStatus.pending.dbValue,
        'reporter_id': reporterId,
        'source': source,
        'source_key': sourceKey,
        'created_at': now,
        'updated_at': now,
      });
      for (final p in photos) {
        await txn.insert('intervention_photos', {
          'intervention_id': id,
          'image': p,
          'created_at': now,
        });
      }
      return id;
    });
  }

  /// Vrai s'il existe déjà une alerte automatique de ce type encore active,
  /// ou résolue depuis moins de 48 h (évite les doublons).
  static Future<bool> hasActiveOrRecentAlert({
    required String source,
    required String sourceKey,
  }) async {
    final db = await _db;
    final since =
        DateTime.now().subtract(MaintenanceConfig.alertCooldown).toIso8601String();
    final rows = await db.rawQuery(
      'SELECT 1 FROM interventions '
      'WHERE source = ? AND source_key = ? '
      "AND (status != 'resolved' OR resolved_at > ?) LIMIT 1",
      [source, sourceKey, since],
    );
    return rows.isNotEmpty;
  }

  static Future<void> addPhoto(int interventionId, Uint8List bytes) async {
    final db = await _db;
    await db.insert('intervention_photos', {
      'intervention_id': interventionId,
      'image': bytes,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // ------------------------------------------------------------ UPDATE

  /// Le technicien prend l'intervention : assignée à lui + statut "en cours".
  static Future<void> takeCharge(int id, int technicianId) async {
    final db = await _db;
    await db.update(
      'interventions',
      {
        'assignee_id': technicianId,
        'status': InterventionStatus.inProgress.dbValue,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Le manager attribue l'intervention à un technicien.
  static Future<void> assign(int id, int technicianId) async {
    final db = await _db;
    await db.update(
      'interventions',
      {
        'assignee_id': technicianId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> markResolved(int id) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'interventions',
      {
        'status': InterventionStatus.resolved.dbValue,
        'resolved_at': now,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ------------------------------------------------------------ DELETE

  static Future<void> delete(int id) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('intervention_photos',
          where: 'intervention_id = ?', whereArgs: [id]);
      await txn.delete('interventions', where: 'id = ?', whereArgs: [id]);
    });
  }
}
