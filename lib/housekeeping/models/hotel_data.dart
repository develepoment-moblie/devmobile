import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/app_exception.dart';
import '../services/housekeeping_backend.dart';
import 'room.dart';
import 'supply.dart';

class HotelNotification {
  final String title;
  final String message;
  final String roomNumber;
  bool read = false;
  String id = '';
  HotelNotification(this.title, this.message, this.roomNumber);
}

// Same simple model for the local demo and the authenticated shared API.
class HotelData extends ChangeNotifier {
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  final HousekeepingBackend? api;
  bool get isConnected => api != null;
  String currentUserId = 'sarah';
  final Map<String, String> staffIds = {};
  final Map<String, String> agentOptions = {};
  String? connectionError;
  bool _requestActive = false;
  Future<void>? _refreshing;
  bool get busy => _requestActive;
  void changed() {
    if (_disposed) return;
    onChanged?.call();
    notifyListeners();
  }

  void Function()? onChanged;
  String currentUser = 'Sarah';
  bool isSupervisor = false;
  final employees = ['Sarah', 'Lina', 'Youssef', 'Amina'];
  final List<Room> rooms = [
    Room('305', note: 'Départ VIP · avant 12h', urgent: true),
    Room('214', cleaning: CleaningStatus.inProgress, employee: 'Sarah'),
    Room('118', note: 'Départ à 10:30'),
    Room('402', status: RoomStatus.ready, cleaning: CleaningStatus.completed),
    Room('101'),
    Room('203'),
    Room('306'),
    Room('410'),
    Room('207', cleaning: CleaningStatus.inProgress, employee: 'Lina'),
    Room('311', cleaning: CleaningStatus.inProgress, employee: 'Youssef'),
    Room('109', cleaning: CleaningStatus.review, employee: 'Sarah'),
    Room('208', cleaning: CleaningStatus.review, employee: 'Lina'),
    Room('404', cleaning: CleaningStatus.review, employee: 'Sarah'),
    Room('112', status: RoomStatus.occupied, note: 'Départ prévu à 11:00'),
    Room('224', status: RoomStatus.maintenance, note: 'Télévision sans signal'),
    Room('301', status: RoomStatus.ready, cleaning: CleaningStatus.completed),
  ];
  final supplies = [
    Supply('Draps propres', 42, 'pièces', 15),
    Supply('Serviettes', 68, 'pièces', 20),
    Supply('Taies d’oreiller', 36, 'pièces', 15),
    Supply('Nettoyant multi-surfaces', 4, 'litres', 5),
    Supply('Savon et gel douche', 84, 'unités', 25),
  ];
  final notifications = [
    HotelNotification('Départ VIP', 'Chambre 305 à préparer avant 12h.', '305'),
    HotelNotification(
      'Nettoyage à valider',
      'Chambre 109 prête pour inspection.',
      '109',
    ),
    HotelNotification(
      'Nettoyage à valider',
      'Chambre 208 prête pour inspection.',
      '208',
    ),
    HotelNotification(
      'Nettoyage à valider',
      'Chambre 404 prête pour inspection.',
      '404',
    ),
  ];
  HotelData({this.api}) {
    for (final room in rooms.where(
      (r) => r.cleaning == CleaningStatus.review,
    )) {
      room.checklist.fillRange(0, 4, true);
    }
  }
  int get remaining => rooms.where((r) => r.needsCleaning).length;
  int get waiting => rooms
      .where((r) => r.needsCleaning && r.cleaning == CleaningStatus.waiting)
      .length;
  int get inProgress => rooms
      .where((r) => r.needsCleaning && r.cleaning == CleaningStatus.inProgress)
      .length;
  int get reviews => rooms
      .where((r) => r.needsCleaning && r.cleaning == CleaningStatus.review)
      .length;
  int get unread => notifications.where((n) => !n.read).length;
  List<HotelNotification> get personalNotifications => notifications
      .where(
        (n) =>
            n.roomNumber.isEmpty ||
            rooms.any((r) => r.number == n.roomNumber && canClean(r)),
      )
      .toList();
  Room roomByNumber(String number) =>
      rooms.firstWhere((r) => r.number == number);

  bool canClean(Room room) =>
      !isSupervisor &&
      (isConnected
          ? room.employeeId == currentUserId
          : room.employee == currentUser);

  Future<void> refresh() async {
    if (_refreshing != null) return _refreshing!;
    if (api == null || _requestActive) return;
    final request = _readSnapshot();
    _refreshing = request;
    try {
      await request;
    } finally {
      _refreshing = null;
    }
  }

  Future<void> _readSnapshot() async {
    _requestActive = true;
    try {
      _apply(await api!.snapshot());
      connectionError = null;
    } catch (error) {
      connectionError = error.toString();
      rethrow;
    } finally {
      _requestActive = false;
      changed();
    }
  }

  void _apply(Map<String, dynamic> json) {
    final principal = json['principal'] as Map<String, dynamic>;
    currentUserId = principal['id'] as String;
    currentUser = principal['name'] as String;
    isSupervisor = principal['role'] == 'supervisor';
    employees.clear();
    staffIds.clear();
    agentOptions.clear();
    for (final s in json['staff'] as List) {
      staffIds[s['id'] as String] = s['name'] as String;
      if (s['role'] == 'agent') {
        employees.add(s['name'] as String);
        agentOptions[s['id'] as String] = s['name'] as String;
      }
    }
    final orderedRooms = <Room>[];
    for (final r in json['rooms'] as List) {
      final number = r['number'] as String;
      final room =
          rooms.where((r) => r.number == number).firstOrNull ??
          Room(number, category: r['category'] as String);
      room.status = RoomStatus.values.byName(r['status'] as String);
      room.category = r['category'] as String;
      room.cleaning = CleaningStatus.values.byName(r['cleaning'] as String);
      room.employeeId = r['employeeId'] as String?;
      room.employee = staffIds[room.employeeId];
      room.approvedBy = r['approvedBy'] as String?;
      room.note = r['note'] as String;
      room.urgent = r['urgent'] as bool;
      room.version = r['version'] as int;
      room.checklist
        ..clear()
        ..addAll((r['checklist'] as List).cast<bool>());
      room.applyTasks(r['tasks'] as List?);
      room.history
        ..clear()
        ..addAll((r['history'] as List).cast<String>());
      orderedRooms.add(room);
    }
    rooms
      ..clear()
      ..addAll(orderedRooms);
    final orderedSupplies = <Supply>[];
    for (final s in json['supplies'] as List) {
      final supply =
          supplies
              .where(
                (item) =>
                    item.id == s['id'] ||
                    (item.id.isEmpty && item.name == s['name']),
              )
              .firstOrNull ??
          Supply(
            s['name'] as String,
            s['quantity'] as int,
            s['unit'] as String,
            s['minimum'] as int,
          );
      supply.id = s['id'] as String;
      supply.quantity = s['quantity'] as int;
      supply.version = s['version'] as int;
      orderedSupplies.add(supply);
    }
    supplies
      ..clear()
      ..addAll(orderedSupplies);
    notifications
      ..clear()
      ..addAll(
        (json['notifications'] as List).map(
          (n) =>
              HotelNotification(
                  n['title'] as String,
                  n['message'] as String,
                  n['roomNumber'] as String,
                )
                ..id = n['id'] as String
                ..read = n['read'] as bool,
        ),
      );
  }

  Future<void> _remote(String path, Map<String, dynamic> body) async {
    // A background read should not reject a deliberate user action.
    if (_refreshing != null) await _refreshing!;
    if (_requestActive) {
      throw const HousekeepingException(
        'Enregistrement en cours. Patientez avant une autre action.',
      );
    }
    _requestActive = true;
    try {
      await api!.mutate(path, body);
      try {
        _apply(await api!.snapshot());
        connectionError = null;
      } catch (_) {
        // The write was acknowledged. Do not invite a duplicate stock movement
        // merely because the following read failed.
        connectionError = 'Enregistrement confirmé. Affichage non actualisé : actualisez avant une autre modification.';
      }
    } catch (error) {
      connectionError = error.toString();
      // Reconcile a conflict or an uncertain network result before another write.
      try {
        _apply(await api!.snapshot());
      } catch (_) {
        /* Banner retains error. */
      }
      rethrow;
    } finally {
      _requestActive = false;
      changed();
    }
  }

  FutureOr<void> setCheck(
    Room room,
    int index,
    bool value, {
    Uint8List? photo,
  }) {
    if (!canClean(room) || room.cleaning != CleaningStatus.inProgress) {
      throw StateError('Cette tâche ne vous est pas attribuée.');
    }
    if (value && room.requiresPhotos && photo == null) {
      throw const HousekeepingException(
        'Ajoutez une photo avant de cocher cette tâche.',
      );
    }
    if (api != null) {
      return _remote('/v1/rooms/${room.number}/checklist', {
        'version': room.version,
        'index': index,
        if (supportsTaskPhotos) 'taskId': room.tasks[index].id,
        'value': value,
        if (photo != null) 'photo': base64Encode(photo),
      });
    }
    room.checklist[index] = value;
    changed();
  }

  bool get supportsTaskPhotos => api is TaskPhotoBackend;
  Future<void> addRoomTask(
    Room room,
    String label, {
    required int version,
  }) async {
    if (!isSupervisor || !supportsTaskPhotos) {
      throw const HousekeepingException(
        'Ajout de tâches réservé à la gouvernante en mode SQLite.',
      );
    }
    await _remote('/v1/rooms/${room.number}/add-task', {
      'version': version,
      'label': label,
    });
  }

  Future<Uint8List> taskPhoto(Room room, RoomTask task) async {
    if (api is! TaskPhotoBackend) {
      throw const HousekeepingException(
        'Photos indisponibles dans cette démonstration.',
      );
    }
    final encoded = await (api as TaskPhotoBackend).taskPhoto(
      room.number,
      task.id,
    );
    return base64Decode(encoded);
  }

  Future<void> completeTask(
    Room room,
    String taskId,
    Uint8List photo,
    int version,
  ) => _remote('/v1/rooms/${room.number}/checklist', {
    'version': version,
    'taskId': taskId,
    'value': true,
    'photo': base64Encode(photo),
  });

  FutureOr<void> moveStock(Supply supply, int delta, {int? version}) {
    if (!isSupervisor) throw StateError('Stock réservé à la gouvernante.');
    if (delta == 0 || delta.abs() > 100000 || supply.quantity + delta < 0) {
      throw StateError('Quantité invalide.');
    }
    if (api != null) {
      return _remote('/v1/supplies/${supply.id}/movement', {
        'version': version ?? supply.version,
        'delta': delta,
      });
    }
    supply.quantity += delta;
    changed();
  }

  FutureOr<void> markRead(List<HotelNotification> items) {
    if (api != null) {
      return _remote('/v1/notifications/read', {
        'ids': items.map((n) => n.id).toList(),
      });
    }
    for (final n in items) {
      n.read = true;
    }
    changed();
  }

  FutureOr<void> assign(
    Room room,
    String employee,
    String note,
    bool urgent, {
    int? version,
  }) {
    if (!isSupervisor) {
      throw StateError('Attribution réservée à la gouvernante.');
    }
    if (api != null) {
      return _remote('/v1/rooms/${room.number}/assign', {
        'version': version ?? room.version,
        'employeeId': employee,
        'note': note,
        'urgent': urgent,
      });
    }
    if (!room.needsCleaning ||
        room.cleaning == CleaningStatus.review ||
        room.cleaning == CleaningStatus.completed) {
      throw StateError('Cette chambre ne peut pas recevoir de tâche.');
    }
    if (room.employee != employee) {
      room.cleaning = CleaningStatus.waiting;
      room.checklist.fillRange(0, 4, false);
    }
    room.employee = employee;
    room.note = note;
    room.urgent = urgent;
    room.history.add('Tâche attribuée à $employee par $currentUser');
    changed();
  }

  FutureOr<void> startCleaning(Room room) {
    if (!canClean(room)) {
      throw StateError('Cette tâche ne vous est pas attribuée.');
    }
    if (api != null) {
      return _remote('/v1/rooms/${room.number}/start', {
        'version': room.version,
      });
    }
    if (!room.needsCleaning ||
        room.cleaning != CleaningStatus.waiting ||
        room.employee == null) {
      throw StateError('Attribuez la tâche avant de démarrer le nettoyage.');
    }
    room.cleaning = CleaningStatus.inProgress;
    room.history.add('Nettoyage démarré par ${room.employee}');
    changed();
  }

  FutureOr<void> submitCleaning(Room room) {
    if (!canClean(room)) {
      throw StateError('Cette tâche ne vous est pas attribuée.');
    }
    if (api != null) {
      return _remote('/v1/rooms/${room.number}/submit', {
        'version': room.version,
      });
    }
    if (room.cleaning != CleaningStatus.inProgress ||
        room.checklist.contains(false)) {
      throw StateError('Complétez la liste de contrôle avant de terminer.');
    }
    room.cleaning = CleaningStatus.review;
    room.history.add(
      'Nettoyage terminé · validation de la gouvernante attendue',
    );
    notifications.insert(
      0,
      HotelNotification(
        'Nettoyage à valider',
        'Chambre ${room.number} prête pour inspection.',
        room.number,
      ),
    );
    changed();
  }

  FutureOr<void> approve(Room room) {
    if (api != null) {
      return _remote('/v1/rooms/${room.number}/approve', {
        'version': room.version,
      });
    }
    if (!isSupervisor || room.cleaning != CleaningStatus.review) {
      throw StateError('La validation est réservée à la gouvernante.');
    }
    room.cleaning = CleaningStatus.completed;
    room.status = RoomStatus.ready;
    room.urgent = false;
    room.history.add('Nettoyage validé par $currentUser · chambre libre');
    room.approvedBy = currentUser;
    changed();
  }

  /// The supervisor or the assigned agent reports a problem to maintenance.
  bool canReport(Room room) =>
      isConnected &&
      room.status != RoomStatus.maintenance &&
      (isSupervisor || canClean(room));

  Future<void> reportProblem(Room room, String description, bool urgent) =>
      _remote('/v1/rooms/${room.number}/report', {
        'version': room.version,
        'description': description,
        'urgent': urgent,
      });

  FutureOr<void> checkout(Room room) {
    if (api != null) {
      throw StateError('Le départ doit venir du module réservations.');
    }
    if (room.status != RoomStatus.occupied) {
      throw StateError('La chambre n’est pas occupée.');
    }
    room.status = RoomStatus.dirty;
    room.cleaning = CleaningStatus.waiting;
    room.employee = null;
    room.checklist.fillRange(0, 4, false);
    room.note = 'Le client vient de quitter la chambre';
    room.history.add('Départ enregistré · chambre à nettoyer');
    notifications.insert(
      0,
      HotelNotification(
        'Départ client',
        'Le client a quitté la chambre ${room.number}. Un nettoyage est à prévoir.',
        room.number,
      ),
    );
    changed();
  }
}
