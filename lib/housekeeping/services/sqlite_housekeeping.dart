import '../../shared/services/local_session_store.dart';
import '../../shared/services/local_attachment_store.dart';
import '../../shared/services/evidence_photo.dart';
import '../../shared/services/task_schema.dart';

import 'dart:convert';
import 'dart:math';

import 'housekeeping_backend.dart';

class SqliteHousekeeping implements HousekeepingBackend, TaskPhotoBackend {
  final LocalSessionStore store;
  SqliteHousekeeping(this.store);
  Map<String, dynamic> _principal(Map<String, dynamic> state) {
    final actor = store.actor(state);
    if (!['staff', 'supervisor'].contains(actor['role'])) {
      store.fail('Accès ménage refusé.', 403);
    }
    return {
      'id': actor['id'],
      'name': actor['full_name'],
      'role': actor['role'] == 'staff' ? 'agent' : 'supervisor',
    };
  }

  @override
  Future<Map<String, dynamic>> snapshot() async {
    final s = await store.readState();
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
  Future<void> mutate(String path, Map<String, dynamic> body) => store.change((
    s,
  ) {
    final actor = _principal(s);
    final supervisor = actor['role'] == 'supervisor';
    void require(bool value, String message, [int status = 400]) {
      if (!value) store.fail(message, status);
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
    if (row == null) store.fail('Élément introuvable.', 404);
    require(
      body['version'] == row['version'],
      'Ces données ont changé. Actualisez.',
      409,
    );
    final action = parts[4];
    if (!stock) TaskSchema.ensure(row);
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
      if (action == 'add-task') {
        require(supervisor, 'Ajout de tâches réservé à la gouvernante.', 403);
        final label = body['label'];
        require(
          label is String &&
              label.trim().isNotEmpty &&
              label.trim().length <= 120,
          'Saisissez une tâche de 1 à 120 caractères.',
        );
        final tasks = row['tasks'] as List;
        require(
          tasks.length < 40,
          'Une chambre peut contenir 40 tâches maximum.',
        );
        require(
          !tasks.any(
            (t) =>
                (t['label'] as String).trim().toLowerCase() ==
                (label as String).trim().toLowerCase(),
          ),
          'Cette tâche existe déjà dans cette chambre.',
        );
        tasks.add({
          'id':
              'task-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}',
          'label': (label as String).trim(),
          'photoId': null,
        });
        (row['checklist'] as List).add(false);
        if (row['status'] == 'ready') {
          row['status'] = 'dirty';
          row['cleaning'] = 'waiting';
          row['approvedBy'] = null;
          row['checklist'] = List.filled(tasks.length, false);
          for (final t in tasks) {
            t['photoId'] = null;
          }
        } else if (row['status'] == 'dirty' &&
            ['review', 'completed'].contains(row['cleaning'])) {
          row['cleaning'] = row['employeeId'] == null
              ? 'waiting'
              : 'inProgress';
          row['approvedBy'] = null;
        }
        row['version'] = (row['version'] as int) + 1;
        (row['history'] as List).add(
          '${actor['name']} · Tâche ajoutée : ${(label).trim()}',
        );
        return;
      }
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
          row['checklist'] = List.filled((row['tasks'] as List).length, false);
          for (final task in row['tasks'] as List) {
            task['photoId'] = null;
          }
        }
        row['employeeId'] = body['employeeId'];
        row['note'] = body['note'];
        row['urgent'] = body['urgent'];
      } else if (action == 'approve') {
        require(supervisor, 'Validation réservée à la gouvernante.', 403);
        require(row['cleaning'] == 'review', 'Inspection non disponible.');
        require(
          (row['checklist'] as List).every((v) => v == true) &&
              (row['tasks'] as List).every((t) => t['photoId'] != null),
          'Chaque tâche doit être terminée et justifiée par une photo.',
        );
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
            final tasks = row['tasks'] as List;
            final index = body['taskId'] is String
                ? tasks.indexWhere((t) => t['id'] == body['taskId'])
                : body['index'];
            require(
              index is int &&
                  index >= 0 &&
                  index < tasks.length &&
                  body['value'] is bool,
              'Contrôle invalide.',
            );
            if (body['value'] == true) {
              require(
                body['photo'] is String,
                'Ajoutez une photo avant de cocher cette tâche.',
              );
              final bytes = EvidencePhoto.validate(body['photo'] as String);
              final id = EvidencePhoto.id(bytes);
              tasks[index as int]['photoId'] = id;
              (s.putIfAbsent('_photoWrites', () => <String, dynamic>{})
                  as Map)[id] = base64Encode(
                bytes,
              );
            } else {
              tasks[index as int]['photoId'] = null;
            }
            (row['checklist'] as List)[index] = body['value'];
          } else if (action == 'submit') {
            require(
              (row['checklist'] as List).every((v) => v == true),
              'Complétez la liste de contrôle.',
            );
            require(
              (row['tasks'] as List).every((t) => t['photoId'] != null),
              'Ajoutez une photo pour chaque tâche avant de terminer.',
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
            store.fail('Action inconnue.');
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

  @override
  Future<String> taskPhoto(String roomNumber, String taskId) async {
    final s = await store.readState();
    final actor = _principal(s);
    final room = (s['rooms'] as List)
        .where((r) => r['number'] == roomNumber)
        .firstOrNull;
    if (room == null) store.fail('Chambre indisponible.', 404);
    if (actor['role'] != 'supervisor' && room['employeeId'] != actor['id']) {
      store.fail('Cette chambre ne vous est pas attribuée.', 403);
    }
    final task = (room['tasks'] as List)
        .where((t) => t['id'] == taskId)
        .firstOrNull;
    if (task == null || task['photoId'] == null) {
      store.fail('Aucune photo pour cette tâche.', 404);
    }
    final attachments = store;
    if (attachments is! LocalAttachmentStore) {
      store.fail('Photos indisponibles dans cette démonstration.');
    }
    return (attachments as LocalAttachmentStore).readAttachment(
      task['photoId'] as String,
    );
  }
}
