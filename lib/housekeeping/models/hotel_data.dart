import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/app_exception.dart';
import '../services/housekeeping_backend.dart';
import '../services/sqlite_housekeeping.dart';
import 'cleaning_stats.dart';
import 'lost_item.dart';
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

// State of the housekeeping screens, loaded from and saved through [api].
class HotelData extends ChangeNotifier {
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  final HousekeepingBackend api;
  HotelData({required this.api});

  String currentUserId = '';
  String currentUser = '';
  bool isSupervisor = false;

  /// Display names by account ID, and the agents a supervisor can assign.
  final Map<String, String> staffIds = {};
  final Map<String, String> agentOptions = {};
  final List<Room> rooms = [];
  final List<Supply> supplies = [];
  final List<HotelNotification> notifications = [];
  final List<CleaningRecord> cleanings = [];
  final List<LostItem> lostItems = [];
  final Map<int, String> floorNames = {};
  String floorName(int floor) => floorNames[floor] ?? 'Étage $floor';

  String? connectionError;
  bool _requestActive = false;
  Future<void>? _refreshing;
  bool get busy => _requestActive;
  void Function()? onChanged;
  void changed() {
    if (_disposed) return;
    onChanged?.call();
    notifyListeners();
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

  /// Ownership follows the account ID, never the display name.
  bool canClean(Room room) => !isSupervisor && room.employeeId == currentUserId;

  Future<void> refresh() async {
    if (_refreshing != null) return _refreshing!;
    if (_requestActive) return;
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
      _apply(await api.snapshot());
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
    staffIds.clear();
    agentOptions.clear();
    for (final s in json['staff'] as List) {
      staffIds[s['id'] as String] = s['name'] as String;
      if (s['role'] == 'agent') {
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
      room.feedback = r['feedback'] as String?;
      room.stayover = r['stayover'] == true;
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
      supply.name = s['name'] as String;
      supply.unit = s['unit'] as String;
      supply.minimum = s['minimum'] as int;
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
    cleanings
      ..clear()
      ..addAll([
        for (final c in json['cleanings'] as List? ?? [])
          CleaningRecord.fromMap(c as Map),
      ]);
    lostItems
      ..clear()
      ..addAll([
        for (final item in json['lostItems'] as List? ?? [])
          LostItem.fromMap(item as Map),
      ]);
    floorNames
      ..clear()
      ..addAll({
        for (final f in json['floors'] as List? ?? [])
          f['number'] as int: f['name'] as String,
      });
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
      await api.mutate(path, body);
      try {
        _apply(await api.snapshot());
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
        _apply(await api.snapshot());
      } catch (_) {
        /* Banner retains error. */
      }
      rethrow;
    } finally {
      _requestActive = false;
      changed();
    }
  }

  Future<void> setCheck(Room room, int index, bool value, {Uint8List? photo}) {
    if (!canClean(room) || room.cleaning != CleaningStatus.inProgress) {
      throw StateError('Cette tâche ne vous est pas attribuée.');
    }
    if (value && room.requiresPhotos && photo == null) {
      throw const HousekeepingException(
        'Ajoutez une photo avant de cocher cette tâche.',
      );
    }
    return _remote('/v1/rooms/${room.number}/checklist', {
      'version': room.version,
      'index': index,
      if (supportsTaskPhotos) 'taskId': room.tasks[index].id,
      'value': value,
      if (photo != null) 'photo': base64Encode(photo),
    });
  }

  bool get supportsTaskPhotos => api is TaskPhotoBackend;
  Future<void> addRoomTask(
    Room room,
    String label, {
    required int version,
  }) async {
    if (!isSupervisor || !supportsTaskPhotos) {
      throw const HousekeepingException(
        'Ajout de tâches réservé à la gouvernante.',
      );
    }
    await _remote('/v1/rooms/${room.number}/add-task', {
      'version': version,
      'label': label,
    });
  }

  Future<Uint8List> taskPhoto(Room room, RoomTask task) async {
    if (api case final TaskPhotoBackend photos) {
      return base64Decode(await photos.taskPhoto(room.number, task.id));
    }
    throw const HousekeepingException('Photos indisponibles.');
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

  Future<void> moveStock(Supply supply, int delta, {int? version}) {
    if (!isSupervisor) throw StateError('Stock réservé à la gouvernante.');
    if (delta == 0 || delta.abs() > 100000 || supply.quantity + delta < 0) {
      throw StateError('Quantité invalide.');
    }
    return _remote('/v1/supplies/${supply.id}/movement', {
      'version': version ?? supply.version,
      'delta': delta,
    });
  }

  Future<void> markRead(List<HotelNotification> items) => _remote(
    '/v1/notifications/read',
    {'ids': items.map((n) => n.id).toList()},
  );

  Future<void> assign(
    Room room,
    String employeeId,
    String note,
    bool urgent, {
    int? version,
  }) {
    if (!isSupervisor) {
      throw StateError('Attribution réservée à la gouvernante.');
    }
    return _remote('/v1/rooms/${room.number}/assign', {
      'version': version ?? room.version,
      'employeeId': employeeId,
      'note': note,
      'urgent': urgent,
    });
  }

  Future<void> startCleaning(Room room) {
    if (!canClean(room)) {
      throw StateError('Cette tâche ne vous est pas attribuée.');
    }
    return _remote('/v1/rooms/${room.number}/start', {'version': room.version});
  }

  Future<void> submitCleaning(Room room) {
    if (!canClean(room)) {
      throw StateError('Cette tâche ne vous est pas attribuée.');
    }
    return _remote('/v1/rooms/${room.number}/submit', {
      'version': room.version,
    });
  }

  Future<void> approve(Room room) =>
      _remote('/v1/rooms/${room.number}/approve', {'version': room.version});

  /// The supervisor or the assigned agent reports a problem to maintenance.
  bool canReport(Room room) =>
      room.status != RoomStatus.maintenance && (isSupervisor || canClean(room));

  Future<void> reportProblem(Room room, String description, bool urgent) =>
      _remote('/v1/rooms/${room.number}/report', {
        'version': room.version,
        'description': description,
        'urgent': urgent,
      });

  // --------------------------------------------------------- stock items
  Future<void> createSupply({
    required String name,
    required String unit,
    required int quantity,
    required int minimum,
  }) => _remote('/v1/supplies/new/create', {
    'name': name,
    'unit': unit,
    'quantity': quantity,
    'minimum': minimum,
  });

  Future<void> updateSupply(
    Supply supply, {
    required String name,
    required String unit,
    required int minimum,
    int? version,
  }) => _remote('/v1/supplies/${supply.id}/update', {
    'version': version ?? supply.version,
    'name': name,
    'unit': unit,
    'minimum': minimum,
  });

  Future<void> deleteSupply(Supply supply) =>
      _remote('/v1/supplies/${supply.id}/delete', {'version': supply.version});

  // ------------------------------------------------- refusal and recouche
  Future<void> refuse(Room room, String comment) => _remote(
    '/v1/rooms/${room.number}/refuse',
    {'version': room.version, 'comment': comment},
  );

  /// Occupied rooms where the supervisor can request or cancel a recouche.
  bool canRequestStayover(Room room) =>
      isSupervisor && room.status == RoomStatus.occupied;

  Future<void> setStayover(Room room, bool value, {String note = ''}) =>
      _remote('/v1/rooms/${room.number}/stayover', {
        'version': room.version,
        'value': value,
        'note': note,
      });

  // ------------------------------------------------------ lost and found
  bool canRecordLostItem(Room room) => isSupervisor || canClean(room);

  Future<void> recordLostItem(
    Room room,
    String description, {
    Uint8List? photo,
  }) => _remote('/v1/lost/new/create', {
    'roomNumber': room.number,
    'description': description,
    if (photo != null) 'photo': base64Encode(photo),
  });

  Future<void> returnLostItem(LostItem item, String returnedTo) => _remote(
    '/v1/lost/${item.id}/return',
    {'version': item.version, 'returnedTo': returnedTo},
  );

  Future<Uint8List> lostItemPhoto(LostItem item) async {
    final backend = api;
    if (backend is SqliteHousekeeping) {
      return base64Decode(await backend.lostItemPhoto(item.id));
    }
    throw const HousekeepingException('Photos indisponibles.');
  }

  // ----------------------------------------------------------- statistics
  CleaningStats statsSince(DateTime since) =>
      CleaningStats.compute(cleanings, staffIds, since: since);
}
