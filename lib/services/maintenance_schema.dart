import 'package:sqflite/sqflite.dart';

/// Tables du module Maintenance.
/// Appelé par DatabaseHelper (création v7 + migration depuis v6).
class MaintenanceSchema {
  MaintenanceSchema._();

  static Future<void> create(Database db, {bool seedDemo = true}) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS interventions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      room TEXT NOT NULL,
      category TEXT NOT NULL DEFAULT 'autre',
      priority TEXT NOT NULL DEFAULT 'normal',
      status TEXT NOT NULL DEFAULT 'pending',
      reporter_id INTEGER,
      assignee_id INTEGER,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      resolved_at TEXT,
      source TEXT NOT NULL DEFAULT 'manual',
      source_key TEXT
    )
    ''');

    await db.execute('''
    CREATE TABLE IF NOT EXISTS intervention_photos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      intervention_id INTEGER NOT NULL,
      image BLOB NOT NULL,
      created_at TEXT NOT NULL
    )
    ''');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_interventions_status ON interventions (status)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_photos_intervention ON intervention_photos (intervention_id)');

    if (seedDemo) await _seedDemo(db);
  }

  /// Migration v7 → v8 : origine de l'intervention (manuelle / alerte météo).
  static Future<void> migrateToV8(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(interventions)');
    bool has(String name) => cols.any((c) => c['name'] == name);

    if (!has('source')) {
      await db.execute(
          "ALTER TABLE interventions ADD COLUMN source TEXT NOT NULL DEFAULT 'manual'");
    }
    if (!has('source_key')) {
      await db.execute('ALTER TABLE interventions ADD COLUMN source_key TEXT');
    }
  }

  /// Données de démonstration (comptes techniciens + 3 interventions).
  static Future<void> _seedDemo(Database db) async {
    final count = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM interventions')) ??
        0;
    if (count > 0) return;

    for (final t in const [
      ('thomas@novaparis.com', 'Thomas Bernard'),
      ('marc@novaparis.com', 'Marc Dubois'),
    ]) {
      await db.insert(
        'users',
        {
          'full_name': t.$1,
          'display_name': t.$2,
          'password': 'maintenance1234!',
          'role': 'maintenance',
          'points': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    Future<int?> userId(String email) async {
      final rows = await db.query('users',
          columns: ['id'], where: 'full_name = ?', whereArgs: [email], limit: 1);
      return rows.isEmpty ? null : rows.first['id'] as int;
    }

    final thomas = await userId('thomas@novaparis.com');
    final marc = await userId('marc@novaparis.com');
    final now = DateTime.now();

    Future<void> add(String title, String room, String category,
        String priority, String status, int? assignee, int minutesAgo) async {
      final created = now.subtract(Duration(minutes: minutesAgo));
      await db.insert('interventions', {
        'title': title,
        'description': '',
        'room': room,
        'category': category,
        'priority': priority,
        'status': status,
        'assignee_id': assignee,
        'created_at': created.toIso8601String(),
        'updated_at': created.toIso8601String(),
      });
    }

    await add('Climatisation en panne', '305', 'climatisation', 'urgent',
        'in_progress', thomas, 18);
    await add('Fuite sous le lavabo', '118', 'plomberie', 'high',
        'in_progress', marc, 42);
    await add('Télévision sans signal', '224', 'television', 'normal',
        'pending', null, 60);
  }
}
