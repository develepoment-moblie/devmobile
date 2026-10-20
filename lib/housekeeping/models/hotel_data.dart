import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/app_exception.dart';
import '../services/auto_assignment.dart';
import '../services/housekeeping_backend.dart';
import '../services/mutation_meta.dart';
import '../services/sqlite_housekeeping.dart';
import '../services/inspection_scoring.dart';
import 'cleaning_stats.dart';
import 'inspection.dart';
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
  final List<Inspection> inspections = [];
  final Map<String, InspectionRules> inspectionRules = {};
  InspectionRules rulesFor(String category) =>
      inspectionRules[category] ?? const InspectionRules();

  /// A room's inspection rounds, newest first.
  List<Inspection> inspectionsOf(String number) => [
    for (final i in inspections.reversed)
      if (i.roomNumber == number) i,
  ];

  /// The send-back the agent is working on: the latest round, when the room
  /// was sent back and is being cleaned again.
  Inspection? sentBack(Room room) {
    final latest = inspectionsOf(room.number).firstOrNull;
    return latest != null &&
            !latest.approved &&
            room.cleaning == CleaningStatus.inProgress
        ? latest
        : null;
  }

  final Map<int, String> floorNames = {};

  /// Estimated cleaning minutes per room category (Manager's settings).
  final Map<String, int> estimates = {};

  /// Availability by "yyyy-MM-dd|agentId" (supervisor only).
  final Map<String, ({bool available, int minutes})> availability = {};
  static const defaultCapacityMinutes = 420;
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
      room.priority = r['priority'] as String? ?? 'normal';
      room.applyTimer(r['timer']);
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
    inspections
      ..clear()
      ..addAll([
        for (final i in json['inspections'] as List? ?? [])
          Inspection.fromMap(i as Map),
      ]);
    inspectionRules
      ..clear()
      ..addAll({
        for (final e in (json['inspectionRules'] as Map? ?? {}).entries)
          e.key as String: InspectionRules.fromMap(e.value as Map),
      });
    floorNames
      ..clear()
      ..addAll({
        for (final f in json['floors'] as List? ?? [])
          f['number'] as int: f['name'] as String,
      });
    estimates
      ..clear()
      ..addAll({
        for (final e in (json['estimates'] as Map? ?? {}).entries)
          e.key as String: e.value['minutes'] as int,
      });
    availability
      ..clear()
      ..addAll({
        for (final a in json['availability'] as List? ?? [])
          '${a['date']}|${a['agent_id']}': (
            available: a['available'] as bool,
            minutes: a['capacity_minutes'] as int,
          ),
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
      // Client id and clock on every mutation, for offline replay.
      await api.mutate(path, {...body, ...mutationMeta()});
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

  // ---------------------------------------------------------- inspection
  List<Map<String, dynamic>> _ratings(List<ItemRating> ratings) => [
    for (final r in ratings)
      {
        'taskId': r.taskId,
        'rating': r.rating.name,
        if (r.comment.trim().isNotEmpty) 'comment': r.comment.trim(),
        if (r.photo != null) 'photo': base64Encode(r.photo!),
      },
  ];

  /// Score of [ratings] with the room's category weights.
  int scoreOf(Room room, List<ItemRating> ratings) {
    final rules = rulesFor(room.category);
    final labels = {for (final t in room.tasks) t.id: t.label};
    return inspectionScore([
      for (final r in ratings)
        (weight: rules.weightOf(labels[r.taskId] ?? ''), rating: r.rating),
    ]);
  }

  /// Approves with the inspection (score must reach the threshold).
  Future<void> approveInspected(Room room, List<ItemRating> ratings) => _remote(
    '/v1/rooms/${room.number}/approve',
    {'version': room.version, 'ratings': _ratings(ratings)},
  );

  /// "Renvoyer en nettoyage": back to the same agent with the failed items.
  Future<void> sendBack(Room room, List<ItemRating> ratings, String comment) =>
      _remote('/v1/rooms/${room.number}/refuse', {
        'version': room.version,
        'ratings': _ratings(ratings),
        if (comment.trim().isNotEmpty) 'comment': comment.trim(),
      });

  Future<void> setInspectionRules(
    String category, {
    required int threshold,
    required Map<String, int> weights,
  }) => _remote('/v1/inspection-rules/${Uri.encodeComponent(category)}/set', {
    'threshold': threshold,
    'weights': weights,
    if (inspectionRules[category] case final rules?) 'version': rules.version,
  });

  Future<Uint8List> inspectionPhoto(
    Inspection inspection,
    InspectionItem item,
  ) async {
    final backend = api;
    if (backend is SqliteHousekeeping) {
      return base64Decode(
        await backend.inspectionPhoto(inspection.id, item.id),
      );
    }
    throw const HousekeepingException('Photos indisponibles.');
  }

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

  // ------------------------------------------------------- cleaning timer
  /// The assigned agent controls the timer of a cleaning in progress.
  bool canControlTimer(Room room) =>
      canClean(room) && room.cleaning == CleaningStatus.inProgress;

  Future<void> pauseTimer(Room room) =>
      _remote('/v1/rooms/${room.number}/pause', {'version': room.version});

  Future<void> resumeTimer(Room room) =>
      _remote('/v1/rooms/${room.number}/resume', {'version': room.version});

  Future<void> stopTimer(Room room) =>
      _remote('/v1/rooms/${room.number}/stop', {'version': room.version});

  // ------------------------------------------------------------- priority
  Future<void> setPriority(Room room, CleaningPriority priority) => _remote(
    '/v1/rooms/${room.number}/priority',
    {'version': room.version, 'value': priority.name},
  );

  // ------------------------------------------------------- availability
  static String dateKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  /// Availability of an agent on [day]; available full time by default.
  ({bool available, int minutes}) availabilityOf(
    String agentId,
    DateTime day,
  ) =>
      availability['${dateKey(day)}|$agentId'] ??
      (available: true, minutes: defaultCapacityMinutes);

  Future<void> setAvailability(
    String agentId,
    DateTime day, {
    required bool available,
    required int minutes,
  }) => _remote('/v1/availability/$agentId/set', {
    'date': dateKey(day),
    'available': available,
    'capacityMinutes': minutes,
  });

  // ----------------------------------------------------- auto-assignment
  /// Rooms waiting for an agent.
  List<Room> get unassignedRooms => [
    for (final r in rooms)
      if (r.needsCleaning &&
          r.cleaning == CleaningStatus.waiting &&
          r.employeeId == null)
        r,
  ];

  AssignableRoom _assignable(Room r) => AssignableRoom(
    number: r.number,
    floor: r.floor,
    category: r.category,
    priority: CleaningPriority.parse(r.priority),
    urgent: r.urgent,
    stayover: r.stayover,
  );

  /// A proposal for [day]: unassigned rooms spread over available agents,
  /// counting the work they already have.
  AssignmentPlan proposePlan(DateTime day) {
    final staff = <Housekeeper>[];
    for (final entry in agentOptions.entries) {
      final a = availabilityOf(entry.key, day);
      if (!a.available || a.minutes == 0) continue;
      final current = [
        for (final r in rooms)
          if (r.employeeId == entry.key &&
              r.needsCleaning &&
              (r.cleaning == CleaningStatus.waiting ||
                  r.cleaning == CleaningStatus.inProgress))
            r,
      ];
      staff.add(
        Housekeeper(
          id: entry.key,
          name: entry.value,
          capacityMinutes: a.minutes,
          assignedMinutes: current.fold(
            0,
            (sum, r) => sum + estimateMinutes(_assignable(r), estimates),
          ),
          floors: {for (final r in current) r.floor},
        ),
      );
    }
    return planAssignments(
      rooms: [for (final r in unassignedRooms) _assignable(r)],
      staff: staff,
      estimates: estimates,
    );
  }

  /// Applies the reviewed plan in one step: all rooms or none.
  Future<void> applyPlan(List<PlannedAssignment> plan) =>
      _remote('/v1/plans/new/apply', {
        'assignments': [
          for (final a in plan)
            {
              'roomNumber': a.room.number,
              'employeeId': a.agentId,
              'version': roomByNumber(a.room.number).version,
            },
        ],
      });
}
