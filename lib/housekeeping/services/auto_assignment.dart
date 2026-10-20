// Automatic assignment of rooms to housekeepers. Pure Dart: no Flutter,
// no database, so it can be tested and tuned on its own.
//
// 1. Rooms are taken by priority: early check-in, VIP (or urgent), checkout,
//    then the rest; within a priority, by floor and number.
// 2. Each room goes to the available housekeeper with the lowest projected
//    load (minutes / capacity) who can still fit it, with a small penalty for
//    changing floor, so people stay on as few floors as possible.
// 3. A room nobody can fit is left unassigned for the supervisor.
// The result is deterministic: ties are broken by housekeeper id.

enum CleaningPriority {
  early('Arrivée anticipée'),
  vip('VIP'),
  checkout('Départ'),
  normal('Normale');

  final String label;
  const CleaningPriority(this.label);

  static CleaningPriority parse(String? name) =>
      values.where((p) => p.name == name).firstOrNull ?? normal;
}

class AssignableRoom {
  final String number;
  final int floor;
  final String category;
  final CleaningPriority priority;
  final bool urgent, stayover;
  const AssignableRoom({
    required this.number,
    required this.floor,
    required this.category,
    this.priority = CleaningPriority.normal,
    this.urgent = false,
    this.stayover = false,
  });

  /// 0 = first. An urgent room counts at least as VIP.
  int get rank {
    final base = priority.index;
    return urgent && base > CleaningPriority.vip.index
        ? CleaningPriority.vip.index
        : base;
  }
}

class Housekeeper {
  final String id, name;
  final int capacityMinutes;

  /// Minutes of work already assigned and not finished.
  final int assignedMinutes;

  /// Floors where this person already has rooms.
  final Set<int> floors;
  const Housekeeper({
    required this.id,
    required this.name,
    required this.capacityMinutes,
    this.assignedMinutes = 0,
    this.floors = const {},
  });
}

class PlannedAssignment {
  final AssignableRoom room;
  final String agentId;
  final int minutes;
  const PlannedAssignment(this.room, this.agentId, this.minutes);
}

class AssignmentPlan {
  final List<PlannedAssignment> assignments;
  final List<AssignableRoom> unassigned;

  /// Projected minutes per housekeeper, existing work included.
  final Map<String, int> loads;
  const AssignmentPlan(this.assignments, this.unassigned, this.loads);

  List<PlannedAssignment> forAgent(String id) => [
    for (final a in assignments)
      if (a.agentId == id) a,
  ];
}

/// Estimated minutes for a room: its type's estimate, half for a recouche.
int estimateMinutes(
  AssignableRoom room,
  Map<String, int> estimates, {
  int fallback = 30,
}) {
  final base = estimates[room.category] ?? fallback;
  return room.stayover ? (base / 2).ceil() : base;
}

AssignmentPlan planAssignments({
  required List<AssignableRoom> rooms,
  required List<Housekeeper> staff,
  Map<String, int> estimates = const {},
  double floorChangePenalty = .08,
}) {
  final loads = {for (final h in staff) h.id: h.assignedMinutes};
  final floors = {
    for (final h in staff) h.id: {...h.floors},
  };
  final capacity = {for (final h in staff) h.id: h.capacityMinutes};
  final ordered = [...rooms]
    ..sort((a, b) {
      final byRank = a.rank.compareTo(b.rank);
      if (byRank != 0) return byRank;
      final byFloor = a.floor.compareTo(b.floor);
      return byFloor != 0 ? byFloor : a.number.compareTo(b.number);
    });
  final people = [...staff]..sort((a, b) => a.id.compareTo(b.id));
  final assignments = <PlannedAssignment>[];
  final unassigned = <AssignableRoom>[];

  for (final room in ordered) {
    final minutes = estimateMinutes(room, estimates);
    String? best;
    double? bestScore;
    for (final h in people) {
      final cap = capacity[h.id]!;
      final after = loads[h.id]! + minutes;
      if (cap <= 0 || after > cap) continue;
      final onFloor =
          floors[h.id]!.isEmpty || floors[h.id]!.contains(room.floor);
      final score = after / cap + (onFloor ? 0 : floorChangePenalty);
      if (bestScore == null || score < bestScore - 1e-9) {
        best = h.id;
        bestScore = score;
      }
    }
    if (best == null) {
      unassigned.add(room);
      continue;
    }
    loads[best] = loads[best]! + minutes;
    floors[best]!.add(room.floor);
    assignments.add(PlannedAssignment(room, best, minutes));
  }
  return AssignmentPlan(assignments, unassigned, loads);
}
