import 'dart:convert';
import 'dart:math';

import '../../shared/services/app_events.dart';
import '../models/task_schema.dart';
import 'evidence_photo.dart';
import 'housekeeping_backend.dart';
import 'housekeeping_store.dart';
import 'local_attachment_store.dart';
import 'local_session_store.dart';
import 'room_rules.dart';

// The housekeeping rules. Every action re-reads the state and checks role,
// ownership and version inside one transaction (LocalSessionStore.change).
//
// Paths: /v1/rooms/<number>/<action>, /v1/supplies/<id|new>/<action>,
// /v1/lost/<id|new>/<action>, /v1/notifications/read.
class SqliteHousekeeping implements HousekeepingBackend, TaskPhotoBackend {
  final LocalSessionStore store;

  /// Where approvals and problem reports are announced to the other modules.
  final AppEvents? events;
  SqliteHousekeeping(this.store, {this.events});

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
    final supervisor = actor['role'] == 'supervisor';
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
    // Agents see only their own cleanings and found items.
    s['cleanings'] = [
      for (final c in s['cleanings'] as List? ?? [])
        if (supervisor || c['agent_id'] == actor['id']) c,
    ];
    s['lostItems'] = [
      for (final item in s['lostItems'] as List? ?? [])
        if (supervisor || item['found_by'] == actor['id']) item,
    ];
    for (final key in ['users', 'reads', 'roomArchives', 'categoryTasks']) {
      s.remove(key);
    }
    return s;
  }

  @override
  Future<void> mutate(String path, Map<String, dynamic> body) async {
    final announce = <AppEvent>[];
    await store.change((s) => _apply(s, path, body, announce));
    // Only once the change is saved.
    for (final event in announce) {
      if (event is MaintenanceRequested) {
        if (store case final HousekeepingStore own) {
          own.markOwnReport(event.roomNumber);
        }
      }
      events?.emit(event);
    }
  }

  void _apply(
    Map<String, dynamic> s,
    String path,
    Map<String, dynamic> body,
    List<AppEvent> announce,
  ) {
    final actor = _principal(s);
    final supervisor = actor['role'] == 'supervisor';
    void require(bool value, String message, [int status = 400]) {
      if (!value) store.fail(message, status);
    }

    String text(Object? value, int max, String message) {
      require(
        value is String &&
            value.trim().isNotEmpty &&
            value.trim().length <= max,
        message,
      );
      return (value as String).trim();
    }

    int amount(Object? value, String message) {
      require(value is int && value >= 0 && value <= 1000000, message);
      return value as int;
    }

    String newId(String prefix) =>
        '$prefix-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';

    String storePhoto(Object? encoded) {
      final bytes = EvidencePhoto.validate(encoded as String);
      final id = EvidencePhoto.id(bytes);
      (s.putIfAbsent('_photoWrites', () => <String, dynamic>{}) as Map)[id] =
          base64Encode(bytes);
      return id;
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
    final family = parts[2], key = parts[3], action = parts[4];

    // ---------------------------------------------------------------- stock
    if (family == 'supplies') {
      require(supervisor, 'Stock réservé à la gouvernante.', 403);
      final supplies = (s['supplies'] as List).cast<Map<String, dynamic>>();
      void unique(String name, [Object? except]) => require(
        !supplies.any(
          (o) =>
              o['id'] != except &&
              (o['name'] as String).toLowerCase() == name.toLowerCase(),
        ),
        'Un article porte déjà ce nom.',
      );
      if (key == 'new') {
        require(action == 'create', 'Action inconnue.');
        final name = text(body['name'], 80, 'Nom de 1 à 80 caractères.');
        final unit = text(body['unit'], 20, 'Unité de 1 à 20 caractères.');
        unique(name);
        supplies.add({
          'id': newId('supply'),
          'name': name,
          'unit': unit,
          'quantity': amount(body['quantity'], 'Quantité invalide.'),
          'minimum': amount(body['minimum'], 'Minimum invalide.'),
          'version': 1,
        });
        return;
      }
      final row = supplies.where((r) => r['id'] == key).firstOrNull;
      if (row == null) store.fail('Article introuvable.', 404);
      require(
        body['version'] == row['version'],
        'Ces données ont changé. Actualisez.',
        409,
      );
      switch (action) {
        case 'movement':
          final delta = body['delta'];
          require(
            delta is int && delta != 0 && delta.abs() <= 100000,
            'Quantité invalide.',
          );
          final previous = row['quantity'] as int;
          final quantity = previous + (delta as int);
          require(
            quantity >= 0 && quantity <= 1000000,
            'Stock insuffisant ou quantité trop élevée.',
          );
          row['quantity'] = quantity;
          // Alert once, when the stock falls to its minimum or below.
          final minimum = row['minimum'] as int;
          if (previous > minimum && quantity <= minimum) {
            addNotification(
              s,
              title: quantity == 0 ? 'Rupture de stock' : 'Stock bas',
              message: quantity == 0
                  ? '${row['name']} : stock épuisé (minimum $minimum). Pensez à réapprovisionner.'
                  : '${row['name']} : il reste $quantity ${row['unit']} (minimum $minimum). Pensez à réapprovisionner.',
              roomNumber: '',
              audience: 'supervisor',
            );
          }
        case 'update':
          final name = text(body['name'], 80, 'Nom de 1 à 80 caractères.');
          unique(name, key);
          row['name'] = name;
          row['unit'] = text(body['unit'], 20, 'Unité de 1 à 20 caractères.');
          row['minimum'] = amount(body['minimum'], 'Minimum invalide.');
        case 'delete':
          supplies.remove(row);
          return;
        default:
          store.fail('Action inconnue.');
      }
      bumpVersion(row);
      return;
    }

    // ------------------------------------------------------- lost and found
    if (family == 'lost') {
      final items = (s['lostItems'] as List? ?? (s['lostItems'] = []))
          .cast<Map<String, dynamic>>();
      if (key == 'new') {
        require(action == 'create', 'Action inconnue.');
        final number = body['roomNumber'];
        final room = number is String ? activeRoom(s, number) : null;
        require(room != null, 'Choisissez une chambre active.');
        require(
          supervisor || room!['employeeId'] == actor['id'],
          'Cette chambre ne vous est pas attribuée.',
          403,
        );
        final description = text(
          body['description'],
          300,
          'Décrivez l’objet en 300 caractères maximum.',
        );
        items.insert(0, {
          'id': newId('lost'),
          'room_number': number,
          'description': description,
          'photo_id': body['photo'] == null ? null : storePhoto(body['photo']),
          'found_by': actor['id'],
          'found_by_name': actor['name'],
          'found_at': DateTime.now().toIso8601String(),
          'returned_at': null,
          'returned_to': null,
          'version': 1,
        });
        addHistory(room!, '${actor['name']} · Objet trouvé : $description');
        if (!supervisor) {
          addNotification(
            s,
            title: 'Objet trouvé',
            message: 'Chambre $number : $description',
            roomNumber: number as String,
            audience: 'supervisor',
          );
        }
        return;
      }
      final item = items.where((i) => i['id'] == key).firstOrNull;
      if (item == null) store.fail('Objet introuvable.', 404);
      require(
        body['version'] == item['version'],
        'Ces données ont changé. Actualisez.',
        409,
      );
      require(action == 'return', 'Action inconnue.');
      require(supervisor, 'Restitution réservée à la gouvernante.', 403);
      require(item['returned_at'] == null, 'Objet déjà restitué.', 409);
      item['returned_to'] = text(
        body['returnedTo'],
        120,
        'Indiquez à qui l’objet est rendu.',
      );
      item['returned_at'] = DateTime.now().toIso8601String();
      bumpVersion(item);
      return;
    }

    // ---------------------------------------------------------------- rooms
    require(family == 'rooms', 'Action inconnue.');
    final row = activeRoom(s, key);
    if (row == null) store.fail('Élément introuvable.', 404);
    require(
      body['version'] == row['version'],
      'Ces données ont changé. Actualisez.',
      409,
    );
    TaskSchema.ensure(row);

    if (action == 'add-task') {
      require(supervisor, 'Ajout de tâches réservé à la gouvernante.', 403);
      final label = text(
        body['label'],
        120,
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
              label.toLowerCase(),
        ),
        'Cette tâche existe déjà dans cette chambre.',
      );
      tasks.add({'id': newId('task'), 'label': label, 'photoId': null});
      (row['checklist'] as List).add(false);
      if (row['status'] == 'ready') {
        row['status'] = 'dirty';
        row['cleaning'] = 'waiting';
        row['approvedBy'] = null;
        row['checklist'] = List.filled(tasks.length, false);
        for (final t in tasks) {
          t['photoId'] = null;
        }
      } else if (cleanable(row) &&
          ['review', 'completed'].contains(row['cleaning'])) {
        row['cleaning'] = row['employeeId'] == null ? 'waiting' : 'inProgress';
        row['approvedBy'] = null;
        openCleaning(s, key)?['submitted_at'] = null;
      }
      addHistory(row, '${actor['name']} · Tâche ajoutée : $label');
      bumpVersion(row);
      return;
    }

    if (action == 'report') {
      final description = text(
        body['description'],
        300,
        'Décrivez le problème en 300 caractères maximum.',
      );
      require(body['urgent'] is bool, 'Signalement invalide.');
      require(
        supervisor || row['employeeId'] == actor['id'],
        'Cette chambre ne vous est pas attribuée.',
        403,
      );
      require(
        row['status'] != 'maintenance',
        'Cette chambre est déjà en maintenance.',
        409,
      );
      // An occupied room stays occupied: the guest is still there.
      if (row['status'] != 'occupied') {
        row['status'] = 'maintenance';
        resetCleaning(row);
        dropOpenCleaning(s, key);
        row['note'] = description;
      }
      addHistory(row, '${actor['name']} · Problème signalé : $description');
      addNotification(
        s,
        title: body['urgent'] == true ? 'Maintenance urgente' : 'Maintenance',
        message: 'Chambre $key : $description',
        roomNumber: key,
        audience: 'supervisor',
      );
      bumpVersion(row);
      announce.add(
        MaintenanceRequested(
          key,
          description: description,
          urgent: body['urgent'] as bool,
        ),
      );
      return;
    }

    if (action == 'stayover') {
      require(supervisor, 'Recouche réservée à la gouvernante.', 403);
      require(row['status'] == 'occupied', 'La chambre n’est pas occupée.');
      final on = body['value'];
      require(on is bool, 'Demande invalide.');
      if (on == true) {
        require(row['stayover'] != true, 'Recouche déjà demandée.', 409);
        resetCleaning(row);
        row['stayover'] = true;
        row['note'] = body['note'] is String
            ? (body['note'] as String).trim()
            : '';
        addHistory(row, '${actor['name']} · Recouche demandée');
      } else {
        require(row['stayover'] == true, 'Aucune recouche en cours.', 409);
        require(
          row['cleaning'] == 'waiting',
          'Recouche déjà commencée par l’agent.',
          409,
        );
        resetCleaning(row);
        row['stayover'] = false;
        dropOpenCleaning(s, key);
        addHistory(row, '${actor['name']} · Recouche annulée');
      }
      bumpVersion(row);
      return;
    }

    require(cleanable(row), 'Cette chambre ne peut pas être nettoyée.');
    final now = DateTime.now().toIso8601String();
    switch (action) {
      case 'assign':
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
        final changed = row['employeeId'] != body['employeeId'];
        if (changed) {
          row['cleaning'] = 'waiting';
          row['checklist'] = List.filled((row['tasks'] as List).length, false);
          for (final task in row['tasks'] as List) {
            task['photoId'] = null;
          }
        }
        row['employeeId'] = body['employeeId'];
        row['note'] = body['note'];
        row['urgent'] = body['urgent'];
        final cycle = openCleaning(s, key);
        if (cycle == null) {
          (s['cleanings'] as List? ?? (s['cleanings'] = [])).add({
            'id': newId('clean'),
            'room_number': key,
            'agent_id': body['employeeId'],
            'kind': row['stayover'] == true ? 'stayover' : 'checkout',
            'assigned_at': now,
            'started_at': null,
            'submitted_at': null,
            'approved_at': null,
            'refusals': 0,
          });
        } else if (changed) {
          cycle['agent_id'] = body['employeeId'];
          cycle['started_at'] = null;
          cycle['submitted_at'] = null;
        }
      case 'approve':
        require(supervisor, 'Validation réservée à la gouvernante.', 403);
        require(row['cleaning'] == 'review', 'Inspection non disponible.');
        require(
          (row['checklist'] as List).every((v) => v == true) &&
              (row['tasks'] as List).every((t) => t['photoId'] != null),
          'Chaque tâche doit être terminée et justifiée par une photo.',
        );
        final stayover = row['stayover'] == true;
        // A recouche keeps the guest's room occupied.
        row['status'] = stayover ? 'occupied' : 'ready';
        row['stayover'] = false;
        row['cleaning'] = 'completed';
        row['urgent'] = false;
        row['feedback'] = null;
        row['approvedBy'] = actor['name'];
        openCleaning(s, key)?['approved_at'] = now;
        if (!stayover) announce.add(RoomReady(key));
      case 'refuse':
        require(supervisor, 'Refus réservé à la gouvernante.', 403);
        require(row['cleaning'] == 'review', 'Inspection non disponible.');
        final comment = text(
          body['comment'],
          300,
          'Expliquez ce qui est à reprendre (300 caractères maximum).',
        );
        row['cleaning'] = 'inProgress';
        row['feedback'] = comment;
        final cycle = openCleaning(s, key);
        if (cycle != null) {
          cycle['refusals'] = (cycle['refusals'] as int) + 1;
          cycle['submitted_at'] = null;
        }
        addNotification(
          s,
          title: 'Nettoyage à reprendre',
          message: 'Chambre $key : $comment',
          roomNumber: key,
          audience: 'agent',
        );
      default:
        require(
          !supervisor && row['employeeId'] == actor['id'],
          'Cette tâche ne vous est pas attribuée.',
          403,
        );
        if (action == 'start') {
          require(row['cleaning'] == 'waiting', 'Nettoyage déjà démarré.');
          row['cleaning'] = 'inProgress';
          openCleaning(s, key)?['started_at'] = now;
          break;
        }
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
            tasks[index as int]['photoId'] = storePhoto(body['photo']);
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
          openCleaning(s, key)?['submitted_at'] = now;
          (s['notifications'] as List).insert(0, {
            'id': 'review-$key-${row['version']}',
            'title': 'Nettoyage à valider',
            'message': 'Chambre $key prête pour inspection.',
            'roomNumber': key,
            'audience': 'supervisor',
          });
        } else {
          store.fail('Action inconnue.');
        }
    }
    addHistory(
      row,
      '${actor['name']} · ${const {'assign': 'Tâche attribuée', 'start': 'Nettoyage démarré', 'checklist': 'Contrôle mis à jour', 'submit': 'Nettoyage terminé, inspection attendue', 'approve': 'Nettoyage validé', 'refuse': 'Nettoyage refusé, à reprendre'}[action]}',
    );
    bumpVersion(row);
  }

  @override
  void close() {}

  Future<String> _attachment(String id) {
    final attachments = store;
    if (attachments is! LocalAttachmentStore) {
      store.fail('Photos indisponibles.');
    }
    return (attachments as LocalAttachmentStore).readAttachment(id);
  }

  @override
  Future<String> taskPhoto(String roomNumber, String taskId) async {
    final s = await store.readState();
    final actor = _principal(s);
    final room = activeRoom(s, roomNumber);
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
    return _attachment(task['photoId'] as String);
  }

  /// Photo of a found item: for the supervisor or the person who found it.
  Future<String> lostItemPhoto(String itemId) async {
    final s = await store.readState();
    final actor = _principal(s);
    final item = (s['lostItems'] as List? ?? [])
        .where((i) => i['id'] == itemId)
        .firstOrNull;
    if (item == null || item['photo_id'] == null) {
      store.fail('Aucune photo pour cet objet.', 404);
    }
    if (actor['role'] != 'supervisor' && item['found_by'] != actor['id']) {
      store.fail('Objet non accessible.', 403);
    }
    return _attachment(item['photo_id'] as String);
  }
}
