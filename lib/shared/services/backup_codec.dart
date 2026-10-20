import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'app_exception.dart';
import 'task_schema.dart';
import 'evidence_photo.dart';

class BackupContents {
  final DateTime createdAt;
  final Map<String, dynamic> _state;
  BackupContents._(this.createdAt, this._state);
  Map<String, dynamic> get state =>
      jsonDecode(jsonEncode(_state)) as Map<String, dynamic>;
  int get users =>
      (_state['users'] as List).where((u) => u['deleted'] != true).length;
  int get rooms => (_state['rooms'] as List).length;
  int get archivedRooms => (_state['roomArchives'] as List).length;
  int get supplies => (_state['supplies'] as List).length;
}

/// Versioned, authenticated backup. No sessions or plaintext passwords exported.
class BackupCodec {
  static const maxBytes = 64 * 1024 * 1024;
  static const iterations = 210000;
  static final _aad = Uint8List.fromList(utf8.encode('nova-paris-backup:v1'));

  static Future<Uint8List> encode(
    Map<String, dynamic> state,
    String password,
  ) => Isolate.run(() => _encode(state, password));

  static Future<BackupContents> decode(Uint8List bytes, String password) =>
      Isolate.run(() => _decode(bytes, password));

  static Never _invalid() => throw const AppServiceException(
    'Sauvegarde invalide ou incompatible. Aucune donnée n’a été remplacée.',
  );

  static Uint8List _random(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }

  static Uint8List _key(String password, Uint8List salt) {
    if (password.isEmpty || password.length > 256) _invalid();
    final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, 32));
    return kdf.process(Uint8List.fromList(utf8.encode(password)));
  }

  static Uint8List _encode(Map<String, dynamic> state, String password) {
    if (password.length < 8 || password.length > 256) {
      throw const AppServiceException(
        'Choisissez un mot de passe de 8 à 256 caractères.',
      );
    }
    validate(state);
    final plain = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'state': state,
        }),
      ),
    );
    if (plain.length > maxBytes * 0.7) _invalid();
    final salt = _random(16), nonce = _random(12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(_key(password, salt)), 128, nonce, _aad),
      );
    final result = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'nova-paris-backup',
          'version': 2,
          'iterations': iterations,
          'salt': base64Encode(salt),
          'nonce': base64Encode(nonce),
          'data': base64Encode(cipher.process(plain)),
        }),
      ),
    );
    if (result.length > maxBytes) _invalid();
    return result;
  }

  static BackupContents _decode(Uint8List bytes, String password) {
    if (bytes.isEmpty || bytes.length > maxBytes) _invalid();
    try {
      final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (envelope['format'] != 'nova-paris-backup' ||
          ![1, 2].contains(envelope['version']) ||
          envelope['iterations'] != iterations) {
        _invalid();
      }
      final salt = base64Decode(envelope['salt'] as String);
      final nonce = base64Decode(envelope['nonce'] as String);
      final data = base64Decode(envelope['data'] as String);
      if (salt.length != 16 || nonce.length != 12 || data.length < 16) {
        _invalid();
      }
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(KeyParameter(_key(password, salt)), 128, nonce, _aad),
        );
      final payload =
          jsonDecode(utf8.decode(cipher.process(data))) as Map<String, dynamic>;
      final state = Map<String, dynamic>.from(payload['state'] as Map);
      validate(state);
      if (envelope['version'] == 1) {
        for (final room in [
          ...state['rooms'] as List,
          ...state['roomArchives'] as List,
        ]) {
          // Old files have no task definitions. Never reset a newer task/photo
          // payload solely because an unencrypted envelope label was changed.
          if (room['tasks'] != null) continue;
          TaskSchema.ensure(room as Map<String, dynamic>);
          if (room['status'] == 'dirty') {
            room['checklist'] = List.filled(
              (room['tasks'] as List).length,
              false,
            );
            if (room['cleaning'] == 'review') room['cleaning'] = 'waiting';
          }
        }
      }
      return BackupContents._(
        DateTime.parse(payload['createdAt'] as String),
        state,
      );
    } on InvalidCipherTextException {
      throw const AppServiceException(
        'Mot de passe incorrect ou fichier endommagé. Aucune donnée n’a été remplacée.',
      );
    } on AppServiceException {
      rethrow;
    } on Object {
      _invalid();
    }
  }

  /// Validate every imported field before the transaction can replace any row.
  static void validate(Map<String, dynamic> state) {
    bool text(dynamic v, int max, {bool empty = false}) =>
        v is String && (empty || v.trim().isNotEmpty) && v.length <= max;
    bool integer(dynamic v, int min, int max) =>
        v is int && v >= min && v <= max;
    void require(bool valid) {
      if (!valid) _invalid();
    }

    List<Map<String, dynamic>> rows(String name) {
      final value = state[name];
      require(value is List && value.length <= 20000);
      return (value as List).map((v) {
        require(v is Map);
        return Map<String, dynamic>.from(v as Map);
      }).toList();
    }

    try {
      final users = rows('users'),
          rooms = rows('rooms'),
          archives = rows('roomArchives');
      final supplies = rows('supplies'), notifications = rows('notifications');
      final ids = <String>{},
          emails = <String>{},
          numbers = <String>{},
          supplyIds = <String>{},
          notificationIds = <String>{};
      var managers = 0;
      for (final u in users) {
        require(text(u['id'], 200) && ids.add(u['id'] as String));
        require(
          text(u['email'], 254) &&
              u['email'] == (u['email'] as String).trim().toLowerCase() &&
              RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                  .hasMatch(u['email'] as String) &&
              emails.add((u['email'] as String).toLowerCase()),
        );
        require(
          text(u['full_name'], 120) &&
              [
                'guest',
                'staff',
                'supervisor',
                'manager',
                'maintenance',
                'admin',
              ].contains(u['role']),
        );
        require(
          u['deleted'] is bool &&
              integer(u['revision'], 1, 2147483647) &&
              integer(u['points'], 0, 2147483647),
        );
        require(
          base64Decode(u['salt'] as String).length == 16 &&
              base64Decode(u['hash'] as String).length == 32,
        );
        if (u['deleted'] == false && ['manager', 'admin'].contains(u['role'])) {
          managers++;
        }
      }
      require(managers > 0);
      final photoData = state['photoData'] as Map? ?? {};
      for (final entry in photoData.entries) {
        require(entry.key is String && entry.value is String);
        final bytes = EvidencePhoto.validate(entry.value as String);
        require(entry.key == EvidencePhoto.id(bytes));
      }
      final referencedPhotos = <String>{};
      for (final r in [...rooms, ...archives]) {
        require(
          r['number'] is String &&
              RegExp(r'^[1-9][0-9]{2}$').hasMatch(r['number'] as String) &&
              numbers.add(r['number'] as String),
        );
        require(
          text(r['category'], 80) &&
              [
                'ready',
                'occupied',
                'dirty',
                'maintenance',
              ].contains(r['status']) &&
              [
                'waiting',
                'inProgress',
                'review',
                'completed',
              ].contains(r['cleaning']),
        );
        require(r['employeeId'] == null || ids.contains(r['employeeId']));
        require(r['approvedBy'] == null || text(r['approvedBy'], 120));
        require(
          text(r['note'], 200, empty: true) &&
              r['urgent'] is bool &&
              integer(r['version'], 1, 2147483647),
        );
        require(
          r['checklist'] is List &&
              (r['checklist'] as List).length ==
                  ((r['tasks'] as List?)?.length ?? 4) &&
              (r['checklist'] as List).every((v) => v is bool),
        );
        if (r['tasks'] case final List tasks) {
          require(tasks.isNotEmpty && tasks.length <= 40);
          final taskIds = <String>{};
          for (var i = 0; i < tasks.length; i++) {
            final task = tasks[i];
            require(
              task is Map &&
                  text(task['id'], 200) &&
                  taskIds.add(task['id'] as String) &&
                  text(task['label'], 120),
            );
            final id = task['photoId'];
            require(id == null || id is String && photoData.containsKey(id));
            if (id is String) referencedPhotos.add(id);
            if (r['status'] == 'dirty' && r['checklist'][i] == true) {
              require(id != null);
            }
          }
        }
        require(
          r['history'] is List &&
              (r['history'] as List).length <= 20000 &&
              (r['history'] as List).every((v) => text(v, 1000)),
        );
      }
      require(photoData.keys.every(referencedPhotos.contains));
      for (final s in supplies) {
        require(
          text(s['id'], 200) &&
              supplyIds.add(s['id'] as String) &&
              text(s['name'], 200) &&
              text(s['unit'], 80),
        );
        require(
          integer(s['quantity'], 0, 1000000) &&
              integer(s['minimum'], 0, 1000000) &&
              integer(s['version'], 1, 2147483647),
        );
      }
      for (final n in notifications) {
        require(
          text(n['id'], 200) &&
              notificationIds.add(n['id'] as String) &&
              text(n['title'], 300) &&
              text(n['message'], 2000),
        );
        require(
          n['roomNumber'] == null ||
              n['roomNumber'] is String &&
                  RegExp(r'^[1-9][0-9]{2}$')
                      .hasMatch(n['roomNumber'] as String),
        );
        require(['all', 'agent', 'supervisor'].contains(n['audience']));
      }
      // Optional: backups made before manager priorities have none.
      if (state['priorities'] != null) {
        final priorityIds = <String>{};
        for (final p in rows('priorities')) {
          require(
            text(p['id'], 200) &&
                priorityIds.add(p['id'] as String) &&
                text(p['icon'], 40) &&
                text(p['title'], 120) &&
                text(p['subtitle'], 200, empty: true) &&
                ['danger', 'success', 'terra'].contains(p['color_type']) &&
                DateTime.tryParse(p['created_at'] as String) != null &&
                integer(p['version'], 1, 2147483647),
          );
        }
      }
      require(state['reads'] is Map);
      for (final entry in (state['reads'] as Map).entries) {
        require(ids.contains(entry.key) && entry.value is List);
        final reads = entry.value as List;
        require(
          reads.length <= notificationIds.length &&
              reads.every(notificationIds.contains) &&
              reads.toSet().length == reads.length,
        );
      }
    } on AppServiceException {
      rethrow;
    } on Object {
      _invalid();
    }
  }
}
