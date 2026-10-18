import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../housekeeping/services/housekeeping_api.dart';
import '../housekeeping/services/housekeeping_backend.dart';
import '../housekeeping/services/room_catalog_backend.dart';
import '../user_management/models/app_user.dart';
import '../user_management/services/user_repository.dart';
import '../user_management/services/demo_accounts.dart';
import 'offline_seed.dart';

// Disposable, device-local demonstration data. This is not server security.
class OfflineStore implements UserRepository, DemoAccounts {
  static const storageKey = 'nova.offline.demo.v1';
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
  final SharedPreferences preferences;
  Map<String, dynamic> _state;
  final _events = StreamController<void>.broadcast();
  Future<void> _pending = Future.value();
  String? _session;
  OfflineStore._(this.preferences, this._state);

  static Future<OfflineStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(storageKey);
    if (saved != null) {
      // Never silently overwrite a stored demo if it cannot be read.
      return OfflineStore._(prefs, jsonDecode(saved) as Map<String, dynamic>);
    }
    final state = jsonDecode(offlineSeedJson) as Map<String, dynamic>;
    state['users'] = <dynamic>[];
    state['reads'] = <String, dynamic>{};
    final store = OfflineStore._(prefs, state);
    final credentials = store._credentials(demoPassword);
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
        ...credentials,
      });
    }
    await store._write(state);
    return store;
  }

  Map<String, dynamic> _clone() =>
      jsonDecode(jsonEncode(_state)) as Map<String, dynamic>;
  Never _fail(String message, [int status = 400]) =>
      throw HousekeepingException(message, status);
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

  Future<void> _write(Map<String, dynamic> next) async {
    if (!await preferences.setString(storageKey, jsonEncode(next))) {
      _fail('Enregistrement local impossible. Réessayez.');
    }
    _state = next;
  }

  Future<void> _change(void Function(Map<String, dynamic>) change) {
    final result = _pending.then((_) async {
      final next = _clone();
      change(next);
      await _write(next);
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
  Future<void> login(String email, String password) async {
    await _pending;
    final row = (_state['users'] as List)
        .cast<Map<String, dynamic>>()
        .where(
          (u) =>
              u['email'] == email.trim().toLowerCase() && u['deleted'] != true,
        )
        .firstOrNull;
    if (row == null || _hash(password, row['salt'] as String) != row['hash']) {
      _fail('E-mail ou mot de passe incorrect.', 401);
    }
    _session = row['id'] as String;
    _events.add(null);
  }

  @override
  Future<void> logout() async {
    _session = null;
    _events.add(null);
  }

  @override
  Future<AppUser> currentProfile() async => AppUser.fromMap(_actor(_state));
  @override
  Future<List<AppUser>> allProfiles() async {
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

  @override
  Future<void> deleteProfile(AppUser original) async {
    await _change((s) {
      _target(s, original)['deleted'] = true;
    });
    _events.add(null);
  }

  HousekeepingBackend housekeeping() => OfflineHousekeeping(this);
  RoomCatalogBackend roomCatalog() => OfflineRoomCatalog(this);
  Future<void> dispose() => _events.close();
}

class OfflineHousekeeping implements HousekeepingBackend {
  final OfflineStore store;
  OfflineHousekeeping(this.store);
  Map<String, dynamic> _principal(Map<String, dynamic> state) {
    final actor = store._actor(state);
    if (!AppUser.fromMap(actor).canUseHousekeeping) {
      store._fail('Accès ménage refusé.', 403);
    }
    return {
      'id': actor['id'],
      'name': actor['full_name'],
      'role': actor['role'] == 'staff' ? 'agent' : 'supervisor',
    };
  }

  @override
  Future<Map<String, dynamic>> snapshot() async {
    await store._pending;
    final s = store._clone();
    final actor = _principal(s);
    s['principal'] = actor;
    s['staff'] = (s['users'] as List)
        .where(
          (u) =>
              u['deleted'] != true &&
              ['staff', 'supervisor'].contains(u['role']),
        )
        .map(
          (u) => {
            'id': u['id'],
            'name': u['full_name'],
            'role': u['role'] == 'staff' ? 'agent' : 'supervisor',
          },
        )
        .toList();
    final reads = ((s['reads'] as Map)[actor['id']] as List?) ?? [];
    s['notifications'] = (s['notifications'] as List)
        .where((n) => n['audience'] == 'all' || n['audience'] == actor['role'])
        .map((n) => {...n as Map, 'read': reads.contains(n['id'])})
        .toList();
    s.remove('users');
    s.remove('reads');
    s.remove('roomArchives');
    return s;
  }

  @override
  Future<void> mutate(String path, Map<String, dynamic> body) => store._change((
    s,
  ) {
    final actor = _principal(s);
    final supervisor = actor['role'] == 'supervisor';
    void require(bool value, String message, [int status = 400]) {
      if (!value) store._fail(message, status);
    }

    if (path == '/v1/notifications/read') {
      final ids = body['ids'];
      require(
        ids is List && ids.every((id) => id is String),
        'Notifications invalides.',
      );
      final visible = (s['notifications'] as List)
          .where(
            (n) => n['audience'] == 'all' || n['audience'] == actor['role'],
          )
          .map((n) => n['id'])
          .toSet();
      final reads = (s['reads'] as Map).putIfAbsent(
        actor['id'],
        () => <dynamic>[],
      ) as List;
      for (final id in ids as List) {
        if (visible.contains(id) && !reads.contains(id)) reads.add(id);
      }
      return;
    }
    final parts = path.split('/');
    require(parts.length == 5 && parts[1] == 'v1', 'Action inconnue.');
    final stock = parts[2] == 'supplies';
    require(stock || parts[2] == 'rooms', 'Action inconnue.');
    final row = (s[stock ? 'supplies' : 'rooms'] as List)
        .cast<Map<String, dynamic>>()
        .where((r) => r[stock ? 'id' : 'number'] == parts[3])
        .firstOrNull;
    if (row == null) store._fail('Élément introuvable.', 404);
    require(
      body['version'] == row['version'],
      'Ces données ont changé. Actualisez.',
      409,
    );
    final action = parts[4];
    if (stock) {
      require(supervisor, 'Stock réservé à la gouvernante.', 403);
      final delta = body['delta'];
      require(
        action == 'movement' &&
            delta is int &&
            delta != 0 &&
            delta.abs() <= 100000,
        'Quantité invalide.',
      );
      final quantity = (row['quantity'] as int) + (delta as int);
      require(
        quantity >= 0 && quantity <= 1000000,
        'Stock insuffisant ou quantité trop élevée.',
      );
      row['quantity'] = quantity;
    } else {
      require(
        row['status'] == 'dirty',
        'Cette chambre ne peut pas être nettoyée.',
      );
      if (action == 'assign') {
        require(supervisor, 'Attribution réservée à la gouvernante.', 403);
        require(
          ['waiting', 'inProgress'].contains(row['cleaning']),
          'Tâche déjà terminée.',
        );
        require(
          (s['users'] as List).any(
            (u) =>
                u['id'] == body['employeeId'] &&
                u['role'] == 'staff' &&
                u['deleted'] != true,
          ),
          'Choisissez un agent actif.',
        );
        require(
          body['note'] is String &&
              (body['note'] as String).length <= 200 &&
              body['urgent'] is bool,
          'Consignes invalides.',
        );
        if (row['employeeId'] != body['employeeId']) {
          row['cleaning'] = 'waiting';
          row['checklist'] = List.filled(4, false);
        }
        row['employeeId'] = body['employeeId'];
        row['note'] = body['note'];
        row['urgent'] = body['urgent'];
      } else if (action == 'approve') {
        require(supervisor, 'Validation réservée à la gouvernante.', 403);
        require(row['cleaning'] == 'review', 'Inspection non disponible.');
        row['status'] = 'ready';
        row['cleaning'] = 'completed';
        row['urgent'] = false;
        row['approvedBy'] = actor['name'];
      } else {
        require(
          !supervisor && row['employeeId'] == actor['id'],
          'Cette tâche ne vous est pas attribuée.',
          403,
        );
        if (action == 'start') {
          require(row['cleaning'] == 'waiting', 'Nettoyage déjà démarré.');
          row['cleaning'] = 'inProgress';
        } else {
          require(
            row['cleaning'] == 'inProgress',
            'Démarrez le nettoyage avant de continuer.',
          );
          if (action == 'checklist') {
            final index = body['index'];
            require(
              index is int && index >= 0 && index < 4 && body['value'] is bool,
              'Contrôle invalide.',
            );
            (row['checklist'] as List)[index as int] = body['value'];
          } else if (action == 'submit') {
            require(
              (row['checklist'] as List).every((v) => v == true),
              'Complétez la liste de contrôle.',
            );
            row['cleaning'] = 'review';
            (s['notifications'] as List).insert(0, {
              'id': 'review-${parts[3]}-${row['version']}',
              'title': 'Nettoyage à valider',
              'message': 'Chambre ${parts[3]} prête pour inspection.',
              'roomNumber': parts[3],
              'audience': 'supervisor',
            });
          } else {
            store._fail('Action inconnue.');
          }
        }
      }
      (row['history'] as List).add(
        '${DateTime.now().toLocal().toIso8601String().substring(0, 16)} · ${actor['name']} · ${const {'assign': 'Tâche attribuée', 'start': 'Nettoyage démarré', 'checklist': 'Contrôle mis à jour', 'submit': 'Nettoyage terminé, inspection attendue', 'approve': 'Nettoyage validé'}[action]}',
      );
    }
    row['version'] = (row['version'] as int) + 1;
  });
  @override
  void close() {}
}

class OfflineRoomCatalog implements RoomCatalogBackend {
  final OfflineStore store;
  OfflineRoomCatalog(this.store);
  @override
  Future<RoomCatalogSnapshot> snapshot() async {
    await store._pending;
    store._manager(store._state);
    final s = store._clone();
    return RoomCatalogSnapshot.fromMap({
      'rooms': s['rooms'],
      'archivedRooms': s['roomArchives'] ?? [],
    });
  }

  @override
  Future<void> mutate(
    RoomCatalogAction action,
    Map<String, dynamic> body,
  ) => store._change((s) {
    store._manager(s);
    final number = body['number'];
    final category = (body['category'] as String?)?.trim();
    if (number is! String || !RegExp(r'^[1-9][0-9]{2}$').hasMatch(number)) {
      store._fail('Numéro de 100 à 999 requis.');
    }
    if ((action == RoomCatalogAction.create ||
            action == RoomCatalogAction.update) &&
        (category == null || category.isEmpty || category.length > 80)) {
      store._fail('Catégorie requise, 80 caractères maximum.');
    }
    final rooms = s['rooms'] as List;
    final archives = s.putIfAbsent('roomArchives', () => <dynamic>[]) as List;
    final actor = store._actor(s)['full_name'];
    if (action == RoomCatalogAction.create) {
      if ([...rooms, ...archives].any((r) => r['number'] == number)) {
        store._fail('Ce numéro existe déjà, y compris dans les archives.', 409);
      }
      rooms.add({
        'number': number,
        'category': category,
        'status': 'dirty',
        'cleaning': 'waiting',
        'employeeId': null,
        'approvedBy': null,
        'note': '',
        'urgent': false,
        'checklist': List.filled(4, false),
        'version': 1,
        'history': ['Chambre créée par $actor'],
      });
      return;
    }
    final source = action == RoomCatalogAction.restore ? archives : rooms;
    final row = source
        .cast<Map<String, dynamic>>()
        .where((r) => r['number'] == number)
        .firstOrNull;
    if (row == null) store._fail('Chambre introuvable.', 404);
    if (row['version'] != body['version']) {
      store._fail('Cette chambre a changé. Actualisez.', 409);
    }
    if (action == RoomCatalogAction.archive) {
      final canArchive =
          (row['status'] == 'ready' && row['cleaning'] == 'completed') ||
          (row['status'] == 'dirty' &&
              row['cleaning'] == 'waiting' &&
              row['employeeId'] == null);
      if (!canArchive) {
        store._fail(
          'Chambre occupée, en maintenance ou avec une tâche active.',
          409,
        );
      }
      rooms.remove(row);
      archives.add(row);
    } else if (action == RoomCatalogAction.restore) {
      if (rooms.any((r) => r['number'] == number)) {
        store._fail('Numéro déjà actif.', 409);
      }
      archives.remove(row);
      rooms.add(row);
      row.addAll({
        'status': 'dirty',
        'cleaning': 'waiting',
        'employeeId': null,
        'approvedBy': null,
        'urgent': false,
        'note': '',
        'checklist': List.filled(4, false),
      });
    } else {
      row['category'] = category;
    }
    row['version'] = (row['version'] as int) + 1;
    (row['history'] as List).add(
      '${action == RoomCatalogAction.archive
          ? 'Chambre archivée'
          : action == RoomCatalogAction.restore
          ? 'Chambre restaurée, nettoyage requis'
          : 'Catégorie modifiée'} par $actor',
    );
  });
}
