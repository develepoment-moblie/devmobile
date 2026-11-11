import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../shared/models/app_user.dart';
import 'app_exception.dart';
import 'housekeeping_store.dart';

/// A backup file in the app's folder.
class BackupInfo {
  final String path;
  final DateTime createdAt;
  final int size;
  final bool automatic;
  const BackupInfo(this.path, this.createdAt, this.size, this.automatic);
  String get name => p.basename(path);
}

// Backup and restore of the housekeeping module only: every housekeeping_*
// table (photos included) and the voice note files, in one gzip JSON file.
// The other modules' tables, in the same database file, are never touched.
class HousekeepingBackup {
  static const format = 'nova-paris-housekeeping';
  static const keepAutomatic = 7;

  /// Tables with a REFERENCES to another table: dropped first.
  static const _children = {
    'housekeeping_notification_reads',
    'housekeeping_inspection_items',
    'housekeeping_issue_photos',
    'housekeeping_lost_item_events',
    'housekeeping_laundry_lines',
    'housekeeping_supply_request_lines',
  };

  /// The housekeeping tables a backup holds. The sync tables (server
  /// address, this phone's id, outbox) belong to the phone: a backup leaves
  /// them out and a restore keeps them.
  static const _moduleTables =
      "type = 'table' AND name LIKE 'housekeeping\\_%' ESCAPE '\\' "
      "AND name NOT LIKE 'housekeeping\\_sync\\_%' ESCAPE '\\'";

  final HousekeepingStore store;
  final Future<Directory> Function() _appFolder;
  final DateTime Function() clock;
  HousekeepingBackup(
    this.store, {
    Future<Directory> Function()? appFolder,
    DateTime Function()? clock,
  }) : _appFolder = appFolder ?? getApplicationDocumentsDirectory,
       clock = clock ?? DateTime.now;

  // One folder per database file: the screen tour's own database never
  // mixes its backups with the hotel's.
  Future<Directory> _folder() async {
    final dir = Directory(
      p.join(
        (await _appFolder()).path,
        'housekeeping',
        'backups',
        p.basenameWithoutExtension(store.session.database.database.path),
      ),
    );
    await dir.create(recursive: true);
    return dir;
  }

  AppUser _allowed(Set<String> roles, String message) {
    final user = store.session.user;
    if (user == null || !roles.contains(user.role)) {
      throw AppServiceException(message, 403);
    }
    return user;
  }

  static const _backupRoles = {
    AppRole.supervisor,
    AppRole.manager,
    AppRole.admin,
  };

  /// Backups are made by the supervisor, the Manager or admin.
  bool get canBackup => _backupRoles.contains(store.session.user?.role);

  /// A restore replaces everything: the Manager or admin only.
  bool get canRestore =>
      {AppRole.manager, AppRole.admin}.contains(store.session.user?.role);

  Future<Uint8List> _export(String by) async {
    final dump = await store.query((db) async {
      final tables = <String, dynamic>{};
      for (final t in await db.query(
        'sqlite_master',
        columns: ['name', 'sql'],
        where: _moduleTables,
        orderBy: 'name',
      )) {
        tables[t['name'] as String] = {
          'sql': t['sql'],
          'rows': await db.query(t['name'] as String),
        };
      }
      final version = (await db.query(
        'module_versions',
        where: "module = 'housekeeping'",
      )).single['version'];
      return {'version': version, 'tables': tables};
    });
    // The voice notes live as files: they travel inside the backup.
    final base = (await _appFolder()).path;
    final files = <String, String>{};
    final issues = (dump['tables'] as Map)['housekeeping_issues'];
    for (final row in issues?['rows'] as List? ?? []) {
      final relative = row['voice_path'] as String?;
      if (relative == null) continue;
      final file = File(p.join(base, relative));
      if (await file.exists()) {
        files[relative] = base64Encode(await file.readAsBytes());
      }
    }
    return Uint8List.fromList(
      gzip.encode(
        utf8.encode(
          jsonEncode({
            'format': format,
            'module': 'housekeeping',
            'version': dump['version'],
            'createdAt': clock().toIso8601String(),
            'createdBy': by,
            'tables': dump['tables'],
            'files': files,
          }),
        ),
      ),
    );
  }

  static String _stamp(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'
      '-${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}'
      '${d.second.toString().padLeft(2, '0')}';

  Future<BackupInfo> _write(String by, {String suffix = ''}) async {
    final bytes = await _export(by);
    final now = clock();
    final file = File(
      p.join(
        (await _folder()).path,
        'nova-paris-menage-${_stamp(now)}$suffix.json.gz',
      ),
    );
    await file.writeAsBytes(bytes, flush: true);
    return BackupInfo(file.path, now, bytes.length, suffix.isNotEmpty);
  }

  /// "Sauvegarder maintenant".
  Future<BackupInfo> backupNow() async {
    final user = _allowed(
      _backupRoles,
      'Sauvegarde réservée à la gouvernante et au manager.',
    );
    return _write(user.fullName);
  }

  /// The backups in the app's folder, newest first.
  Future<List<BackupInfo>> list() async {
    final found = <BackupInfo>[];
    await for (final f in (await _folder()).list()) {
      if (f is! File || !f.path.endsWith('.json.gz')) continue;
      final name = p.basename(f.path);
      final match = RegExp(
        r'^nova-paris-menage-(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})(\d{2})',
      ).firstMatch(name);
      if (match == null) continue;
      final g = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
      found.add(
        BackupInfo(
          f.path,
          DateTime(g[0], g[1], g[2], g[3], g[4], g[5]),
          await f.length(),
          name.contains('-auto') || name.contains('-avant-restauration'),
        ),
      );
    }
    return found..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// One automatic backup per day, on the first opening of the module; the
  /// last [keepAutomatic] are kept. Returns the new backup, if any.
  Future<BackupInfo?> dailyBackup() async {
    if (store.session.user == null) return null;
    final now = clock();
    final today = DateTime(now.year, now.month, now.day);
    final all = await list();
    if (all.any((b) => b.automatic && !b.createdAt.isBefore(today))) {
      return null;
    }
    final made = await _write('Sauvegarde automatique', suffix: '-auto');
    final automatic = [
      for (final b in await list())
        if (b.automatic) b,
    ];
    for (final old in automatic.skip(keepAutomatic)) {
      await File(old.path).delete();
    }
    return made;
  }

  /// Checks a backup file; returns its contents.
  Map<String, dynamic> _read(Uint8List bytes) {
    Map<String, dynamic>? backup;
    try {
      backup =
          jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;
    } catch (_) {
      throw const AppServiceException(
        'Fichier illisible : ce n’est pas une sauvegarde du ménage.',
      );
    }
    if (backup['format'] != format || backup['module'] != 'housekeeping') {
      throw const AppServiceException(
        'Ce fichier n’est pas une sauvegarde du module ménage.',
      );
    }
    final version = backup['version'];
    if (version is! int || version < 1) {
      throw const AppServiceException('Sauvegarde endommagée.');
    }
    if (version > housekeepingSchema.version) {
      throw AppServiceException(
        'Sauvegarde faite avec une version plus récente de l’application '
        '($version > ${housekeepingSchema.version}). Mettez l’application à jour.',
      );
    }
    final tables = backup['tables'];
    if (tables is! Map ||
        tables.isEmpty ||
        tables.keys.any((t) => !'$t'.startsWith('housekeeping_')) ||
        tables.values.any(
          (t) =>
              t is! Map ||
              t['sql'] is! String ||
              !(t['sql'] as String).startsWith('CREATE TABLE') ||
              t['rows'] is! List,
        )) {
      throw const AppServiceException('Sauvegarde endommagée.');
    }
    return backup;
  }

  /// Replaces all housekeeping data with [bytes] (a backup file). A safety
  /// backup is made first. An older backup is upgraded in place with the
  /// module's usual migration steps. All or nothing.
  Future<void> restore(Uint8List bytes) async {
    final user = _allowed({
      AppRole.manager,
      AppRole.admin,
    }, 'Restauration réservée au manager.');
    final backup = _read(bytes);
    await _write(user.fullName, suffix: '-avant-restauration');
    final version = backup['version'] as int;
    final tables = (backup['tables'] as Map).cast<String, dynamic>();
    await store.replaceAll((tx) async {
      final current =
          [
            for (final t in await tx.query(
              'sqlite_master',
              columns: ['name'],
              where: _moduleTables,
            ))
              t['name'] as String,
          ]..sort(
            (a, b) =>
                (_children.contains(a) ? 0 : 1) -
                (_children.contains(b) ? 0 : 1),
          );
      for (final t in current) {
        await tx.execute('DROP TABLE $t');
      }
      // The backup's own schema, then its rows: parents before children.
      final ordered = tables.keys.toList()
        ..sort(
          (a, b) =>
              (_children.contains(a) ? 1 : 0) - (_children.contains(b) ? 1 : 0),
        );
      for (final name in ordered) {
        await tx.execute(tables[name]['sql'] as String);
      }
      for (final name in ordered) {
        final batch = tx.batch();
        for (final row in tables[name]['rows'] as List) {
          batch.insert(name, (row as Map).cast<String, Object?>());
        }
        await batch.commit(noResult: true);
      }
      // An older backup goes through the steps after its version.
      if (version < housekeepingSchema.version) {
        await housekeepingSchema.migrate(
          tx,
          version,
          housekeepingSchema.version,
        );
      }
      // Sync: actions made after the backup are gone with the data, so they
      // are not sent. The confirmed version starts again from the restored
      // data and the server's list is read from the start (the actions
      // already in the backup change nothing).
      await tx.delete('housekeeping_sync_outbox');
      await tx.delete('housekeeping_sync_conflicts');
      await tx.delete('housekeeping_sync_base');
      await tx.insert('housekeeping_sync_state', {
        'key': 'last_seq',
        'value': '0',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    // The restored data is the new starting point of the sync.
    await store.ensureSyncBase(0, onlyWhenSyncing: true);
    final base = (await _appFolder()).path;
    for (final e in (backup['files'] as Map? ?? {}).entries) {
      final relative = e.key as String;
      if (!relative.startsWith('housekeeping/voice/') ||
          relative.contains('..')) {
        continue;
      }
      final file = File(p.join(base, relative));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(base64Decode(e.value as String), flush: true);
    }
  }

  /// The contents of a backup kept in the app's folder.
  Future<Uint8List> readFile(String path) => File(path).readAsBytes();
}
