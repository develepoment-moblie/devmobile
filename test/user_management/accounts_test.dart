import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/shared/models/app_user.dart' show AppRole;
import 'package:nova_paris/user_management/accounts/models/app_user.dart';
import 'package:nova_paris/user_management/accounts/services/database_helper.dart';
import 'package:nova_paris/user_management/accounts/services/password_hash.dart';
import 'package:nova_paris/user_management/screens/account_gate.dart';
import 'package:nova_paris/user_management/services/accounts_staff_directory.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Skander's accounts database, as merged: passwords and security answers are
// never stored in plain text, and an older database is upgraded.
void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('hashes are salted and verified', () {
    final a = hashSecret('admin1234!'), b = hashSecret('admin1234!');
    expect(a, isNot(b), reason: 'random salt');
    expect(a, startsWith(r'pbkdf2$10000$'));
    expect(verifySecret('admin1234!', a), isTrue);
    expect(verifySecret('Admin1234!', a), isFalse);
    expect(
      verifySecret('admin1234!', 'admin1234!'),
      isFalse,
      reason: 'plain text is never accepted',
    );
  });

  test('a version 6 database with plain-text passwords is upgraded', () async {
    final directory = await Directory.systemTemp.createTemp('nova_accounts_');
    final previousPath = await getDatabasesPath();
    await databaseFactory.setDatabasesPath(directory.path);
    addTearDown(() async {
      await databaseFactory.setDatabasesPath(previousPath);
      await directory.delete(recursive: true);
    });
    final path = p.join(directory.path, 'nova_paris.db');
    final old = await openDatabase(
      path,
      version: 6,
      onCreate: (db, _) async {
        await db.execute('''CREATE TABLE users (
          id INTEGER PRIMARY KEY AUTOINCREMENT, full_name TEXT UNIQUE NOT NULL,
          display_name TEXT NOT NULL, password TEXT NOT NULL, role TEXT NOT NULL,
          points INTEGER NOT NULL DEFAULT 0, security_question TEXT,
          security_answer TEXT)''');
        await db.execute('''CREATE TABLE priorities (id INTEGER PRIMARY KEY
          AUTOINCREMENT, icon TEXT NOT NULL, title TEXT NOT NULL,
          subtitle TEXT NOT NULL, color_type TEXT NOT NULL,
          created_at TEXT NOT NULL)''');
        await db.execute(
          '''CREATE TABLE stats (id INTEGER PRIMARY KEY
          AUTOINCREMENT, key TEXT UNIQUE NOT NULL, label TEXT NOT NULL,
          value TEXT NOT NULL, delta TEXT NOT NULL, delta_up INTEGER NOT NULL)''',
        );
        await db.insert('users', {
          'full_name': 'admin@admin.com',
          'display_name': 'Super Admin',
          'password': 'admin1234!',
          'role': 'admin',
          'security_question': 'Animal ?',
          'security_answer': 'Rex',
        });
      },
    );
    await old.close();

    final helper = DatabaseHelper.instance;
    final db = await helper.database;
    final row = (await db.query('users')).single;
    expect(isHashed(row['password'] as String), isTrue);
    expect(isHashed(row['security_answer'] as String), isTrue);
    expect(
      (await helper.login('admin@admin.com', 'admin1234!'))?.role,
      'admin',
    );
    expect(await helper.login('admin@admin.com', 'mauvais'), isNull);
    expect(
      await helper.verifySecurityAnswer('admin@admin.com', ' rex '),
      isTrue,
    );

    // New accounts and password changes are hashed too.
    await helper.insertUser(
      AppUser(
        id: '0',
        fullName: 'sarah@nova.test',
        displayName: 'Sarah',
        role: 'staff',
        points: 0,
      ),
      'menage-2026',
    );
    final sarah = (await db.query(
      'users',
      where: 'full_name = ?',
      whereArgs: ['sarah@nova.test'],
    )).single;
    expect(sarah['password'], isNot('menage-2026'));
    expect(
      (await helper.login('sarah@nova.test', 'menage-2026'))?.displayName,
      'Sarah',
    );
    await helper.resetPassword('sarah@nova.test', 'nouveau-1');
    expect(await helper.login('sarah@nova.test', 'menage-2026'), isNull);
    expect(await helper.login('sarah@nova.test', 'nouveau-1'), isNotNull);

    for (final role in [AppRole.receptionist, AppRole.kitchen, AppRole.staff]) {
      final email = '$role@nova.test';
      await helper.insertUser(
        AppUser(
          id: '0',
          fullName: email,
          displayName: 'Test $role',
          role: role,
          points: 0,
        ),
        'service-2026',
      );
      final account = (await helper.login(email, 'service-2026'))!;
      final user = sessionUser(account);
      expect(user.role, role);
      expect(user.id, 'account-${account.id}');
      final roster = await const AccountsStaffDirectory().users(roles: {role});
      expect(roster.where((entry) => entry.id == user.id).single.role, role);
      expect(roster.every((entry) => entry.role == role), isTrue);
    }
    await db.close();
  });
}
