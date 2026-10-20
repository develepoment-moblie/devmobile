import 'local_session_store.dart';
import '../models/task_schema.dart';
import 'room_catalog_backend.dart';

class SqliteRoomCatalog implements RoomCatalogBackend {
  final LocalSessionStore store;
  SqliteRoomCatalog(this.store);
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
    });
  }

  @override
  Future<void> mutate(
    RoomCatalogAction action,
    Map<String, dynamic> body,
  ) => store.change((s) {
    _manager(s);
    final number = body['number'];
    final category = (body['category'] as String?)?.trim();
    if (number is! String || !RegExp(r'^[1-9][0-9]{2}$').hasMatch(number)) {
      store.fail('Numéro de 100 à 999 requis.');
    }
    if ((action == RoomCatalogAction.create ||
            action == RoomCatalogAction.update) &&
        (category == null || category.isEmpty || category.length > 80)) {
      store.fail('Catégorie requise, 80 caractères maximum.');
    }
    final rooms = s['rooms'] as List;
    final archives = s.putIfAbsent('roomArchives', () => <dynamic>[]) as List;
    final actor = store.actor(s)['full_name'];
    if (action == RoomCatalogAction.create) {
      if ([...rooms, ...archives].any((r) => r['number'] == number)) {
        store.fail('Ce numéro existe déjà, y compris dans les archives.', 409);
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
        'tasks': TaskSchema.defaults(),
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
        'note': '',
        'checklist': List.filled((row['tasks'] as List).length, false),
      });
      for (final task in row['tasks'] as List) {
        task['photoId'] = null;
      }
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
