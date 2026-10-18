import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/app_user.dart';
import '../models/priority.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('nova_paris.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 6, // ⬅️ bumped from 5
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    // ============ USERS ============
    await db.execute('''
    CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      full_name TEXT UNIQUE NOT NULL,
      display_name TEXT NOT NULL,
      password TEXT NOT NULL,
      role TEXT NOT NULL,
      points INTEGER NOT NULL DEFAULT 0,
      security_question TEXT,
      security_answer TEXT
    )
    ''');

    // ============ PRIORITIES ============
    await db.execute('''
    CREATE TABLE priorities (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      icon TEXT NOT NULL,
      title TEXT NOT NULL,
      subtitle TEXT NOT NULL,
      color_type TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
    ''');

    // ============ STATS ============
    await db.execute('''
    CREATE TABLE stats (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      key TEXT UNIQUE NOT NULL,
      label TEXT NOT NULL,
      value TEXT NOT NULL,
      delta TEXT NOT NULL,
      delta_up INTEGER NOT NULL
    )
    ''');

    // ============ SEED: Admin user ============
    await db.insert('users', {
      'full_name': 'admin@admin.com',
      'display_name': 'Super Admin',
      'password': 'admin1234!',
      'role': 'admin',
      'points': 0,
      'security_question': 'Nom de votre premier animal ?',
      'security_answer': 'admin',
    });

    // ============ SEED: Priorities ============
    await db.insert('priorities', {
      'icon': 'ac_unit',
      'title': 'Climatisation en panne',
      'subtitle': 'Ch. 305 · Urgent',
      'color_type': 'danger',
      'created_at': DateTime.now().toIso8601String(),
    });
    await db.insert('priorities', {
      'icon': 'calendar',
      'title': 'Arrivée VIP',
      'subtitle': 'Chloé Laurent · 14:30',
      'color_type': 'success',
      'created_at': DateTime.now().toIso8601String(),
    });
    await db.insert('priorities', {
      'icon': 'bed',
      'title': 'Chambre à valider',
      'subtitle': 'Ch. 204 · Ménage',
      'color_type': 'terra',
      'created_at': DateTime.now().toIso8601String(),
    });

    // ============ SEED: Stats ============
    await db.insert('stats', {
      'key': 'occupation',
      'label': 'Occupation',
      'value': '82%',
      'delta': '6,4%',
      'delta_up': 1,
    });
    await db.insert('stats', {
      'key': 'revenue',
      'label': 'Revenu',
      'value': '24,8k€',
      'delta': '8,1%',
      'delta_up': 1,
    });
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    // Migration for existing installs (v5 → v6):
    // add security_question/security_answer to users table
    if (oldVersion < 6) {
      final columns = await db.rawQuery('PRAGMA table_info(users)');
      final hasQuestion =
      columns.any((c) => c['name'] == 'security_question');
      if (!hasQuestion) {
        await db.execute(
            'ALTER TABLE users ADD COLUMN security_question TEXT');
      }
      final hasAnswer =
      columns.any((c) => c['name'] == 'security_answer');
      if (!hasAnswer) {
        await db.execute(
            'ALTER TABLE users ADD COLUMN security_answer TEXT');
      }
    }
  }

  // ==================================================
  // ============  USERS  =============================
  // ==================================================

  Future<AppUser?> login(String fullName, String password) async {
    final db = await instance.database;
    final results = await db.query(
      'users',
      where: 'full_name = ? AND password = ?',
      whereArgs: [fullName, password],
      limit: 1,
    );
    if (results.isNotEmpty) return AppUser.fromMap(results.first);
    return null;
  }

  Future<int> insertUser(
      AppUser user,
      String password, {
        String? securityQuestion,
        String? securityAnswer,
      }) async {
    final db = await instance.database;
    return await db.insert('users', {
      'full_name': user.fullName,
      'display_name': user.displayName,
      'password': password,
      'role': user.role,
      'points': user.points,
      'security_question': securityQuestion,
      'security_answer': securityAnswer?.trim().toLowerCase(),
    });
  }

  Future<List<AppUser>> getAllUsers() async {
    final db = await instance.database;
    final results = await db.query('users', orderBy: 'display_name ASC');
    return results.map((m) => AppUser.fromMap(m)).toList();
  }

  Future<AppUser?> getUserById(int id) async {
    final db = await instance.database;
    final results = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (results.isNotEmpty) return AppUser.fromMap(results.first);
    return null;
  }

  // ===== PASSWORD RESET SUPPORT =====

  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    final db = await instance.database;
    final results = await db.query(
      'users',
      where: 'full_name = ?',
      whereArgs: [email.trim()],
      limit: 1,
    );
    return results.isEmpty ? null : results.first;
  }

  Future<bool> verifySecurityAnswer(String email, String answer) async {
    final user = await getUserByEmail(email);
    if (user == null) return false;
    final stored =
    (user['security_answer'] as String?)?.trim().toLowerCase();
    final provided = answer.trim().toLowerCase();
    return stored != null && stored.isNotEmpty && stored == provided;
  }

  Future<int> resetPassword(String email, String newPassword) async {
    final db = await instance.database;
    return await db.update(
      'users',
      {'password': newPassword},
      where: 'full_name = ?',
      whereArgs: [email.trim()],
    );
  }

  Future<int> updateRole(int id, String newRole) async {
    final db = await instance.database;
    return await db.update(
      'users',
      {'role': newRole},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateDisplayName(int id, String newDisplayName) async {
    final db = await instance.database;
    return await db.update(
      'users',
      {'display_name': newDisplayName},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updatePoints(int id, int points) async {
    final db = await instance.database;
    return await db.update(
      'users',
      {'points': points},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updatePassword(int id, String newPassword) async {
    final db = await instance.database;
    return await db.update(
      'users',
      {'password': newPassword},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteUser(int id) async {
    final db = await instance.database;
    return await db.delete('users', where: 'id = ?', whereArgs: [id]);
  }

  // ==================================================
  // ============  PRIORITIES  ========================
  // ==================================================

  Future<List<Map<String, dynamic>>> getAllPriorities() async {
    final db = await instance.database;
    return await db.query('priorities', orderBy: 'created_at DESC');
  }

  Future<int> insertPriority({
    required String icon,
    required String title,
    required String subtitle,
    required String colorType,
  }) async {
    final db = await instance.database;
    return await db.insert('priorities', {
      'icon': icon,
      'title': title,
      'subtitle': subtitle,
      'color_type': colorType,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// 🔧 update an existing priority (used by ManagePrioritiesScreen)
  Future<int> updatePriority(Priority p) async {
    if (p.id == null) return 0;
    final db = await instance.database;
    return await db.update(
      'priorities',
      {
        'icon': p.icon,
        'title': p.title,
        'subtitle': p.subtitle,
        'color_type': p.colorType,
      },
      where: 'id = ?',
      whereArgs: [p.id],
    );
  }

  Future<int> deletePriority(int id) async {
    final db = await instance.database;
    return await db.delete('priorities', where: 'id = ?', whereArgs: [id]);
  }

  // ==================================================
  // ============  STATS  =============================
  // ==================================================

  Future<List<Map<String, dynamic>>> getAllStats() async {
    final db = await instance.database;
    return await db.query('stats');
  }

  Future<int> updateStat({
    required String key,
    required String value,
  }) async {
    final db = await instance.database;
    return await db.update(
      'stats',
      {'value': value},
      where: 'key = ?',
      whereArgs: [key],
    );
  }
}