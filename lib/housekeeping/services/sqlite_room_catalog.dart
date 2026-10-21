import '../models/task_schema.dart';
import 'inventory_rules.dart';
import 'local_session_store.dart';
import 'mutation_meta.dart';
import 'room_catalog_backend.dart';
import 'room_rules.dart';

// The Manager's catalog: rooms, floors and the task list of each category.
// Every body carries mutationId (UUID v4) and clientTimestamp; a repeated
// mutationId is ignored.
class SqliteRoomCatalog implements RoomCatalogBackend {
  final LocalSessionStore store;
  final DateTime Function() clock;
  SqliteRoomCatalog(this.store, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  void _manager(Map<String, dynamic> state) {
    if (!['manager', 'admin'].contains(store.actor(state)['role'])) {
      store.fail('Action réservée au manager.', 403);
    }
  }

  @override
  Future<RoomCatalogSnapshot> snapshot() async {
    final s = await store.readState();
    _manager(s);
    return RoomCatalogSnapshot.fromMap({
      'rooms': s['rooms'],
      'archivedRooms': s['roomArchives'] ?? [],
      'floors': s['floors'] ?? [],
      'categoryTasks': s['categoryTasks'] ?? {},
      'estimates': s['estimates'] ?? {},
      'inspectionRules': s['inspectionRules'] ?? {},
      'minibarItems': [
        for (final item in s['supplies'] as List? ?? [])
          if (item['category'] == 'minibar') item,
      ],
    });
  }

  /// Fresh tasks for a room of [category]: its template, else the defaults.
  static List<Map<String, dynamic>> tasksFor(
    Map<String, dynamic> state,
    String category,
  ) {
    final template = (state['categoryTasks'] as Map? ?? {})[category];
    if (template == null) return TaskSchema.defaults();
    final labels = (template['tasks'] as List).cast<String>();
    return [
      for (var i = 0; i < labels.length; i++)
        {'id': 'task-$i', 'label': labels[i], 'photoId': null},
    ];
  }

  // Not being cleaned now: the task list can be replaced safely.
  static bool _idle(Map<String, dynamic> room) =>
      (room['tasks'] as List? ?? []).every((t) => t['photoId'] == null) &&
      ((room['status'] == 'dirty' &&
              room['cleaning'] == 'waiting' &&
              room['employeeId'] == null) ||
          room['cleaning'] == 'completed');

  static void _setTasks(
    Map<String, dynamic> room,
    List<Map<String, dynamic>> tasks,
  ) {
    room['tasks'] = tasks;
    room['checklist'] = List.filled(
      tasks.length,
      room['cleaning'] == 'completed',
    );
  }

  @override
  Future<void> mutate(
    RoomCatalogAction action,
    Map<String, dynamic> body,
  ) => store.change((s) {
    _manager(s);
    if (!acceptMutation(
      s,
      'catalog/${action.name}',
      body,
      store.actor(s)['id'] as String,
      clock(),
      store.fail,
    )) {
      return; // Already applied.
    }
    final actor = store.actor(s)['full_name'];
    final rooms = s['rooms'] as List;
    final archives = s.putIfAbsent('roomArchives', () => <dynamic>[]) as List;
    String category([Object? value]) {
      final text = ((value ?? body['category']) as String?)?.trim();
      if (text == null || text.isEmpty || text.length > 80) {
        store.fail('Catégorie requise, 80 caractères maximum.');
      }
      return text;
    }

    bool taken(String number) =>
        [...rooms, ...archives].any((r) => r['number'] == number);
    Map<String, dynamic> newRoom(String number, String cat) {
      final tasks = tasksFor(s, cat);
      return {
        'number': number,
        'category': cat,
        'status': 'dirty',
        'cleaning': 'waiting',
        'employeeId': null,
        'approvedBy': null,
        'note': '',
        'urgent': false,
        'stayover': false,
        'feedback': null,
        'checklist': List.filled(tasks.length, false),
        'tasks': tasks,
        'version': 1,
        'history': ['Chambre créée par $actor'],
      };
    }

    switch (action) {
      case RoomCatalogAction.saveMinibarItem:
        saveMinibarItem(s, body, store.fail);
        return;
      case RoomCatalogAction.deleteMinibarItem:
        deleteMinibarItem(s, body, store.fail);
        return;
      case RoomCatalogAction.setInspectionRules:
        setInspectionRules(s, category(), body, store.fail);
        return;
      case RoomCatalogAction.setCategoryEstimate:
        final cat = category();
        final minutes = body['minutes'];
        if (minutes is! int || minutes < 5 || minutes > 480) {
          store.fail('Temps estimé de 5 à 480 minutes.');
        }
        final estimates =
            s.putIfAbsent('estimates', () => <String, dynamic>{}) as Map;
        final current = estimates[cat];
        if (current != null &&
            body['version'] != null &&
            body['version'] != current['version']) {
          store.fail('Cette estimation a changé. Actualisez.', 409);
        }
        estimates[cat] = {
          'minutes': minutes,
          'version': ((current?['version'] as int?) ?? 0) + 1,
        };
        return;
      case RoomCatalogAction.createRange:
        final floor = body['floor'], from = body['from'], to = body['to'];
        if (floor is! int || floor < 1 || floor > 9) {
          store.fail('Étage de 1 à 9 requis.');
        }
        if (from is! int || to is! int || from < 0 || to > 99 || from > to) {
          store.fail('Plage invalide : de 00 à 99, début avant la fin.');
        }
        if (to - from + 1 > 50) store.fail('50 chambres maximum à la fois.');
        final cat = category();
        final numbers = [for (var i = from; i <= to; i++) '${floor * 100 + i}'];
        final existing = numbers.where(taken).toList();
        if (existing.isNotEmpty) {
          store.fail(
            'Numéros déjà utilisés (y compris archivés) : ${existing.take(6).join(', ')}${existing.length > 6 ? '…' : ''}.',
            409,
          );
        }
        for (final number in numbers) {
          rooms.add(newRoom(number, cat));
        }
        return;
      case RoomCatalogAction.renameFloor:
        final floor = body['floor'];
        final name = (body['name'] as String?)?.trim();
        if (floor is! int || floor < 1 || floor > 9) {
          store.fail('Étage de 1 à 9 requis.');
        }
        if (name == null || name.isEmpty || name.length > 60) {
          store.fail('Nom d’étage de 1 à 60 caractères.');
        }
        final floors = s.putIfAbsent('floors', () => <dynamic>[]) as List;
        final row = floors.where((f) => f['number'] == floor).firstOrNull;
        if (row == null) {
          floors.add({'number': floor, 'name': name, 'version': 1});
        } else {
          if (body['version'] != null && body['version'] != row['version']) {
            store.fail('Cet étage a changé. Actualisez.', 409);
          }
          row['name'] = name;
          row['version'] = (row['version'] as int) + 1;
        }
        return;
      case RoomCatalogAction.setCategoryTasks:
        final cat = category();
        final labels = body['labels'];
        if (labels is! List ||
            labels.isEmpty ||
            labels.length > 40 ||
            labels.any(
              (l) => l is! String || l.trim().isEmpty || l.trim().length > 120,
            )) {
          store.fail('De 1 à 40 tâches de 1 à 120 caractères.');
        }
        final clean = [for (final l in labels) (l as String).trim()];
        if (clean.map((l) => l.toLowerCase()).toSet().length != clean.length) {
          store.fail('Chaque tâche ne doit apparaître qu’une fois.');
        }
        final templates =
            s.putIfAbsent('categoryTasks', () => <String, dynamic>{}) as Map;
        final current = templates[cat];
        if (current != null &&
            body['version'] != null &&
            body['version'] != current['version']) {
          store.fail('Ce modèle a changé. Actualisez.', 409);
        }
        templates[cat] = {
          'tasks': clean,
          'version': ((current?['version'] as int?) ?? 0) + 1,
        };
        // Rooms of the category not being cleaned get the new list now.
        for (final room in [...rooms, ...archives]) {
          if (room['category'] == cat && _idle(room)) {
            _setTasks(room, tasksFor(s, cat));
            room['version'] = (room['version'] as int) + 1;
          }
        }
        return;
      default:
        break;
    }

    final number = body['number'];
    if (number is! String || !RegExp(r'^[1-9][0-9]{2}$').hasMatch(number)) {
      store.fail('Numéro de 100 à 999 requis.');
    }
    if (action == RoomCatalogAction.create) {
      if (taken(number)) {
        store.fail('Ce numéro existe déjà, y compris dans les archives.', 409);
      }
      rooms.add(newRoom(number, category()));
      return;
    }
    final source = action == RoomCatalogAction.restore ? archives : rooms;
    final row = source
        .cast<Map<String, dynamic>>()
        .where((r) => r['number'] == number)
        .firstOrNull;
    if (row == null) store.fail('Chambre introuvable.', 404);
    if (row['version'] != body['version']) {
      store.fail('Cette chambre a changé. Actualisez.', 409);
    }
    if (action == RoomCatalogAction.archive) {
      final canArchive =
          (row['status'] == 'ready' && row['cleaning'] == 'completed') ||
          (row['status'] == 'dirty' &&
              row['cleaning'] == 'waiting' &&
              row['employeeId'] == null);
      if (!canArchive) {
        store.fail(
          'Chambre occupée, en maintenance ou avec une tâche active.',
          409,
        );
      }
      rooms.remove(row);
      archives.add(row);
    } else if (action == RoomCatalogAction.restore) {
      if (rooms.any((r) => r['number'] == number)) {
        store.fail('Numéro déjà actif.', 409);
      }
      archives.remove(row);
      rooms.add(row);
      row.addAll({
        'status': 'dirty',
        'cleaning': 'waiting',
        'employeeId': null,
        'approvedBy': null,
        'urgent': false,
        'stayover': false,
        'feedback': null,
        'note': '',
        'checklist': List.filled((row['tasks'] as List).length, false),
      });
      for (final task in row['tasks'] as List) {
        task['photoId'] = null;
      }
    } else {
      final cat = category();
      final changed = row['category'] != cat;
      row['category'] = cat;
      if (changed && _idle(row)) _setTasks(row, tasksFor(s, cat));
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
