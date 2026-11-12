import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

// One module's tables. Each module has its own version number, so two
// teammates never edit the same version or migration.
class ModuleSchema {
  /// Must equal the module's id.
  final String module;

  /// Increase by one for every change to the module's tables.
  final int version;

  /// Brings the module's tables from [from] (0 = new install) to [to].
  /// Table names must start with `<module>_`, for example 'reservations_bookings'.
  final Future<void> Function(Transaction tx, int from, int to) migrate;

  const ModuleSchema({
    required this.module,
    required this.version,
    required this.migrate,
  });
}

// The single local database shared by all modules (nova_paris_hotel.db).
// The name differs from the earlier single-team app's nova_paris.db, so a
// phone upgraded from it keeps that old data untouched.
class AppDatabase {
  final Database database;
  AppDatabase._(this.database);

  static Future<AppDatabase> open({
    required List<ModuleSchema> schemas,
    DatabaseFactory? factory,
    String? path,
  }) async {
    final driver = factory ?? databaseFactory;
    final location =
        path ?? p.join(await driver.getDatabasesPath(), 'nova_paris_hotel.db');
    final db = await driver.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => db.execute(
          'CREATE TABLE module_versions (module TEXT PRIMARY KEY, version INTEGER NOT NULL)',
        ),
      ),
    );
    try {
      await db.transaction((tx) async {
        for (final schema in schemas) {
          final rows = await tx.query(
            'module_versions',
            where: 'module = ?',
            whereArgs: [schema.module],
          );
          final current = rows.isEmpty ? 0 : rows.single['version'] as int;
          if (current > schema.version) {
            throw StateError(
              'Les données du module ${schema.module} viennent d’une version plus récente de l’application.',
            );
          }
          if (current == schema.version) continue;
          await schema.migrate(tx, current, schema.version);
          await tx.insert('module_versions', {
            'module': schema.module,
            'version': schema.version,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
    } catch (_) {
      await db.close();
      rethrow;
    }
    return AppDatabase._(db);
  }

  Future<int> versionOf(String module) async {
    final rows = await database.query(
      'module_versions',
      where: 'module = ?',
      whereArgs: [module],
    );
    return rows.isEmpty ? 0 : rows.single['version'] as int;
  }

  Future<void> close() => database.close();
}
