import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:sqflite/sqflite.dart';

import '../../shared/services/app_exception.dart';
import '../../shared/services/backup_codec.dart';
import '../../shared/services/backup_repository.dart';
import '../../shared/services/local_database.dart';
import '../../shared/services/local_seed.dart';
import '../../shared/services/local_attachment_store.dart';
import '../../shared/services/task_schema.dart';
import '../../shared/services/local_session_store.dart';
import '../models/app_user.dart';
import '../models/priority.dart';
import 'demo_accounts.dart';
import 'password_management.dart';
import 'priority_board.dart';
import 'user_repository.dart';

// Device-local course application. Permissions are enforced locally, not by a server.
class SqliteUserRepository
    implements
        UserRepository,
        DemoAccounts,
        PasswordManagement,
        PriorityBoard,
        LocalSessionStore,
        BackupRepository,
        LocalAttachmentStore {
  static const demoPassword = 'Nova123!';
  @override
  Map<String, String> get demoAccounts => const {
    'manager@nova.test': 'Manager',
    'amina@nova.test': 'Gouvernante',
    'sarah@nova.test': 'Agent',
    'guest@nova.test': 'Client',
  };
  @override
  String get demoAccountPassword => demoPassword;
  final LocalDatabase storage;
  Map<String, dynamic> _state;
  final _events = StreamController<void>.broadcast();
  Future<void> _pending = Future.value();
  String? _session;
  SqliteUserRepository._(this.storage, this._state);

  static Future<SqliteUserRepository> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final storage = await LocalDatabase.open(factory: factory, path: path);
    try {
      if (await storage.initialized()) {
        final store = SqliteUserRepository._(storage, {});
        await storage.database.transaction((tx) async {
          store._state = await storage.read(tx);
          final id = await storage.savedSession(tx);
          if (id != null &&
              (store._state['users'] as List).any(
                (u) => u['id'] == id && u['deleted'] == false,
              )) {
            store._session = id;
          } else {
            await storage.saveSession(tx, null);
          }
        });
        return store;
      }
      return await _seed(storage);
    } catch (_) {
      await storage.close();
      rethrow;
    }
  }

  static Future<SqliteUserRepository> _seed(LocalDatabase storage) async {
    final state = jsonDecode(localSeedJson) as Map<String, dynamic>;
    for (final room in state['rooms'] as List) {
      TaskSchema.ensure(room as Map<String, dynamic>);
      if (room['status'] == 'dirty') {
        room['checklist'] = List.filled(4, false);
        if (room['cleaning'] == 'review') room['cleaning'] = 'waiting';
      }
    }
    state['users'] = <dynamic>[];
    state['reads'] = <String, dynamic>{};
    state['priorities'] = seedPriorities();
    final store = SqliteUserRepository._(storage, state);

    for (final entry in {
      'manager': ['Manager Démo', 'manager'],
      'amina': ['Amina', 'supervisor'],
      'sarah': ['Sarah', 'staff'],
      'lina': ['Lina', 'staff'],
      'youssef': ['Youssef', 'staff'],
      'guest': ['Client Démo', 'guest'],
    }.entries) {
      (state['users'] as List).add({
        'id': entry.key,
        'email': '${entry.key}@nova.test',
        'full_name': entry.value[0],
        'role': entry.value[1],
        'revision': 1,
        'points': 0,
        ...store._credentials(demoPassword),
      });
    }
    store._state = await storage.database.transaction((tx) async {
      final existing = await tx.query(
        'metadata',
        where: 'key = ?',
        whereArgs: ['initialized'],
      );
      if (existing.isNotEmpty) return storage.read(tx);
      await storage.write(tx, state);
      return state;
    });
    return store;
  }

  Map<String, dynamic> _clone() =>
      jsonDecode(jsonEncode(_state)) as Map<String, dynamic>;
  Never _fail(String message, [int status = 400]) =>
      throw AppServiceException(message, status);
  Map<String, dynamic> _actor(Map<String, dynamic> state) {
    final user = (state['users'] as List)
        .cast<Map<String, dynamic>>()
        .where((u) => u['id'] == _session && u['deleted'] != true)
        .firstOrNull;
    if (user == null) {
      _fail('Ce profil n’est plus disponible. Reconnectez-vous.', 403);
    }
    return user;
  }

  void _manager(Map<String, dynamic> state) {
    if (!AppUser.fromMap(_actor(state)).canManageUsers) {
      _fail('Action réservée au manager.', 403);
    }
  }

  Future<void> _reload() async {
    await _pending;
    _state = await storage.read();
  }

  Future<void> _change(void Function(Map<String, dynamic>) change) {
    final session = _session;
    final result = _pending.then((_) async {
      try {
        final next = await storage.database.transaction((tx) async {
          if (_session != session) {
            _fail('Session modifiée. Réessayez.', 409);
          }
          final state = await storage.read(tx);
          change(state);
          await storage.write(tx, state);
          final remembered = await storage.savedSession(tx);
          if (remembered != null &&
              !(state['users'] as List).any(
                (u) => u['id'] == remembered && u['deleted'] != true,
              )) {
            await storage.saveSession(tx, null);
          }
          return state;
        });
        _state = next;
      } on DatabaseException {
        throw const AppServiceException(
          'Enregistrement local impossible. Vérifiez l’espace disponible puis réessayez.',
        );
      }
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
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

  String _hash(String password, String salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(base64Decode(salt), 100000, 32));
    return base64Encode(
      derivator.process(Uint8List.fromList(utf8.encode(password))),
    );
  }

  Map<String, String> _credentials(String password) {
    final random = Random.secure();
    final salt = base64Encode(List.generate(16, (_) => random.nextInt(256)));
    return {'salt': salt, 'hash': _hash(password, salt)};
  }

  @override
  String? get sessionUserId => _session;
  @override
  Stream<void> get sessionChanges => _events.stream;
  @override
  Future<void> login(String email, String password) => _enqueue(() async {
    final id = await storage.database.transaction((tx) async {
      final state = await storage.read(tx);
      final row = (state['users'] as List)
          .cast<Map<String, dynamic>>()
          .where(
            (u) =>
                u['email'] == email.trim().toLowerCase() &&
                u['deleted'] != true,
          )
          .firstOrNull;
      if (row == null ||
          _hash(password, row['salt'] as String) != row['hash']) {
        _fail('E-mail ou mot de passe incorrect.', 401);
      }
      final id = row['id'] as String;
      await storage.saveSession(tx, id);
      return id;
    });
    _session = id;
    _events.add(null);
  });

  @override
  Future<void> logout() => _enqueue(() async {
    await storage.database.transaction((tx) => storage.saveSession(tx, null));
    _session = null;
    _events.add(null);
  });

  @override
  Future<AppUser> currentProfile() => _enqueue(() async {
    final profile = await storage.database.transaction((tx) async {
      _state = await storage.read(tx);
      final row = (_state['users'] as List)
          .cast<Map<String, dynamic>>()
          .where((u) => u['id'] == _session && u['deleted'] != true)
          .firstOrNull;
      if (row != null) return AppUser.fromMap(row);
      if (await storage.savedSession(tx) == _session) {
        await storage.saveSession(tx, null);
      }
      return null;
    });
    if (profile == null) {
      _session = null;
      _events.add(null);
      _fail('Ce profil n’est plus disponible. Reconnectez-vous.', 403);
    }
    return profile;
  });

  @override
  Future<List<AppUser>> allProfiles() async {
    await _reload();
    _manager(_state);
    return (_state['users'] as List)
        .where((u) => u['deleted'] != true)
        .map((u) => AppUser.fromMap(u as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
  }

  void _add(
    Map<String, dynamic> state,
    String email,
    String password,
    String name,
    String role,
  ) {
    email = email.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ||
        password.length < 6) {
      _fail('E-mail valide et mot de passe de 6 caractères minimum requis.');
    }
    _validate(name, role);
    if ((state['users'] as List).any((u) => u['email'] == email)) {
      _fail('Cet e-mail existe déjà.');
    }
    (state['users'] as List).add({
      'id':
          'local-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}',
      'email': email,
      'full_name': name.trim(),
      'role': role,
      'points': 0,
      'revision': 1,
      ..._credentials(password),
    });
  }

  void _validate(String name, String role) {
    if (name.trim().isEmpty ||
        name.trim().length > 120 ||
        !AppUser.roleLabels.containsKey(role)) {
      _fail('Vérifiez le nom et le rôle saisis.');
    }
  }

  @override
  Future<void> register(String email, String password, String name) async {
    await _change((s) => _add(s, email, password, name, 'guest'));
    await login(email, password);
  }

  @override
  Future<void> createUser(
    String email,
    String password,
    String name,
    String role,
  ) => _change((s) {
    _manager(s);
    _add(s, email, password, name, role);
  });
  Map<String, dynamic> _target(Map<String, dynamic> s, AppUser original) {
    _manager(s);
    final row = (s['users'] as List)
        .cast<Map<String, dynamic>>()
        .where((u) => u['id'] == original.id && u['deleted'] != true)
        .firstOrNull;
    if (row == null || row['revision'] != original.revision) {
      _fail('Ce profil a changé. Actualisez la liste.', 409);
    }
    if (row['id'] == _session) {
      _fail('Utilisez un autre compte manager pour modifier votre profil.');
    }
    return row;
  }

  @override
  Future<void> updateUser(AppUser original, String name, String role) async {
    await _change((s) {
      _validate(name, role);
      final row = _target(s, original);
      row['full_name'] = name.trim();
      row['role'] = role;
      row['revision'] = (row['revision'] as int) + 1;
    });
    _events.add(null);
  }

  void _password(String password) {
    if (password.length < 6) {
      _fail('Utilisez un mot de passe de 6 caractères minimum.');
    }
  }

  @override
  Future<void> changePassword(String current, String next) => _change((s) {
    final row = _actor(s);
    if (_hash(current, row['salt'] as String) != row['hash']) {
      _fail('Mot de passe actuel incorrect.', 401);
    }
    _password(next);
    if (current == next) {
      _fail('Choisissez un mot de passe différent de l’actuel.');
    }
    row.addAll(_credentials(next));
    row['revision'] = (row['revision'] as int) + 1;
  });

  @override
  Future<void> resetPassword(AppUser original, String temporary) =>
      _change((s) {
        _password(temporary);
        final row = _target(s, original);
        row.addAll(_credentials(temporary));
        row['revision'] = (row['revision'] as int) + 1;
      });

  @override
  Future<List<Priority>> priorities() async {
    await _reload();
    _manager(_state);
    return [
      for (final p in _state['priorities'] as List? ?? [])
        Priority.fromMap(p as Map<String, dynamic>),
    ];
  }

  Map<String, dynamic> _priority(Map<String, dynamic> s, Priority original) {
    final row = (s['priorities'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .where((p) => p['id'] == original.id)
        .firstOrNull;
    if (row == null || row['version'] != original.version) {
      _fail('Cette priorité a changé. Actualisez la liste.', 409);
    }
    return row;
  }

  @override
  Future<void> savePriority(
    Priority? original, {
    required String icon,
    required String title,
    required String subtitle,
    required String colorType,
  }) => _change((s) {
    _manager(s);
    if (title.trim().isEmpty ||
        title.trim().length > 120 ||
        subtitle.trim().length > 200 ||
        !Priority.icons.contains(icon) ||
        !Priority.colorTypes.contains(colorType)) {
      _fail('Vérifiez le titre, les détails, l’icône et la couleur.');
    }
    final fields = {
      'icon': icon,
      'title': title.trim(),
      'subtitle': subtitle.trim(),
      'color_type': colorType,
    };
    if (original == null) {
      ((s['priorities'] ??= <dynamic>[]) as List).insert(0, {
        'id':
            'priority-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}',
        ...fields,
        'created_at': DateTime.now().toIso8601String(),
        'version': 1,
      });
    } else {
      final row = _priority(s, original);
      row.addAll(fields);
      row['version'] = (row['version'] as int) + 1;
    }
  });

  @override
  Future<void> deletePriority(Priority original) => _change((s) {
    _manager(s);
    final row = _priority(s, original);
    (s['priorities'] as List).remove(row);
  });

  @override
  Future<void> deleteProfile(AppUser original) async {
    await _change((s) {
      _target(s, original)['deleted'] = true;
    });
    _events.add(null);
  }

  @override
  Future<Map<String, dynamic>> readState() async {
    await _reload();
    return _clone();
  }

  @override
  Future<void> change(void Function(Map<String, dynamic>) action) =>
      _change(action);
  @override
  Map<String, dynamic> actor(Map<String, dynamic> state) => _actor(state);
  @override
  Never fail(String message, [int status = 400]) => _fail(message, status);

  @override
  Future<Map<String, dynamic>> backupSnapshot() => _enqueue(() async {
    return storage.database.transaction((tx) async {
      final state = await storage.read(tx);
      _manager(state);
      state['photoData'] = await storage.photos(tx);
      return state;
    });
  });

  @override
  Future<void> restoreSnapshot(Map<String, dynamic> state) {
    final replacement = jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
    BackupCodec.validate(replacement);
    final session = _session;
    return _enqueue(() async {
      await storage.database.transaction((tx) async {
        if (_session != session) _fail('Session modifiée. Réessayez.', 409);
        _manager(await storage.read(tx));
        await storage.replace(tx, replacement);
      });
      _state = replacement;
      _session = null;
      _events.add(null);
    });
  }

  Future<void> dispose() async {
    await _pending;
    await _events.close();
    await storage.close();
  }

  @override
  Future<String> readAttachment(String id) => _enqueue(() async {
    final rows = await storage.database.query(
      'task_photos',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) _fail('Photo indisponible. Actualisez la chambre.', 404);
    return rows.single['data'] as String;
  });
}
