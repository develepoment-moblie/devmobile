import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/housekeeping/services/auto_assignment.dart';

// The pure assignment algorithm: no database, no widgets.
void main() {
  AssignableRoom room(
    String number, {
    String category = 'Standard',
    CleaningPriority priority = CleaningPriority.normal,
    bool urgent = false,
    bool stayover = false,
  }) => AssignableRoom(
    number: number,
    floor: int.parse(number[0]),
    category: category,
    priority: priority,
    urgent: urgent,
    stayover: stayover,
  );
  Housekeeper agent(
    String id, {
    int capacity = 420,
    int assigned = 0,
    Set<int> floors = const {},
  }) => Housekeeper(
    id: id,
    name: id,
    capacityMinutes: capacity,
    assignedMinutes: assigned,
    floors: floors,
  );
  Map<String, List<String>> byAgent(AssignmentPlan plan) {
    final result = <String, List<String>>{};
    for (final a in plan.assignments) {
      result.putIfAbsent(a.agentId, () => []).add(a.room.number);
    }
    return result;
  }

  test(
    'priority order: early check-in, VIP or urgent, checkout, then normal',
    () {
      final plan = planAssignments(
        rooms: [
          room('101'),
          room('102', priority: CleaningPriority.checkout),
          room('103', priority: CleaningPriority.vip),
          room('104', priority: CleaningPriority.early),
          room('105', urgent: true),
        ],
        // Room for only three 30-minute rooms: the last two wait.
        staff: [agent('a', capacity: 90)],
      );
      expect(plan.assignments.map((a) => a.room.number), ['104', '103', '105']);
      expect(plan.unassigned.map((r) => r.number), ['102', '101']);
    },
  );

  test('balances the workload between housekeepers', () {
    final plan = planAssignments(
      rooms: [for (var i = 1; i <= 6; i++) room('10$i')],
      staff: [agent('a'), agent('b'), agent('c')],
    );
    expect(plan.loads.values.toSet(), {60});
    expect(plan.unassigned, isEmpty);
  });

  test('uneven workloads: existing work and part-time capacity count', () {
    final plan = planAssignments(
      rooms: [for (var i = 1; i <= 9; i++) room('20$i')],
      staff: [
        agent('busy', assigned: 240), // already 4 hours of work
        agent('free'),
        agent('part', capacity: 120), // part-time: 2 hours
      ],
    );
    final load = plan.loads;
    expect(load['part'], lessThanOrEqualTo(120));
    expect(load['busy'], lessThanOrEqualTo(420));
    // Proportional balance: nobody far above the others relative to capacity.
    final ratios = [
      load['busy']! / 420,
      load['free']! / 420,
      load['part']! / 120,
    ];
    expect(
      ratios.reduce((a, b) => a > b ? a : b) -
          ratios.reduce((a, b) => a < b ? a : b),
      lessThan(.35),
    );
    expect(plan.assignments, hasLength(9));
  });

  test('keeps housekeepers on their floor when loads are close', () {
    final plan = planAssignments(
      rooms: [room('301'), room('302'), room('401'), room('402')],
      staff: [
        agent('a', floors: {3}),
        agent('b', floors: {4}),
      ],
    );
    final rooms = byAgent(plan);
    expect(rooms['a'], ['301', '302']);
    expect(rooms['b'], ['401', '402']);
  });

  test('leaves rooms unassigned when nobody has time, never overloads', () {
    final plan = planAssignments(
      rooms: [for (var i = 1; i <= 5; i++) room('50$i', category: 'Suite')],
      staff: [agent('a', capacity: 100), agent('b', capacity: 50)],
      estimates: {'Suite': 45},
    );
    expect(plan.loads['a'], lessThanOrEqualTo(100));
    expect(plan.loads['b'], lessThanOrEqualTo(50));
    expect(plan.assignments, hasLength(3));
    expect(plan.unassigned, hasLength(2));
  });

  test('no available staff: everything waits', () {
    final plan = planAssignments(
      rooms: [room('101')],
      staff: [agent('off', capacity: 0)],
    );
    expect(plan.assignments, isEmpty);
    expect(plan.unassigned.single.number, '101');
    expect(
      planAssignments(rooms: [room('101')], staff: const []).unassigned,
      hasLength(1),
    );
  });

  test('estimates by room type; a recouche takes half', () {
    final estimates = {'Suite': 60, 'Standard': 25};
    expect(estimateMinutes(room('101', category: 'Suite'), estimates), 60);
    expect(
      estimateMinutes(
        room('101', category: 'Suite', stayover: true),
        estimates,
      ),
      30,
    );
    expect(estimateMinutes(room('101', category: 'Inconnue'), estimates), 30);
    final plan = planAssignments(
      rooms: [
        room('101', category: 'Suite'),
        room('102'),
      ],
      staff: [agent('a')],
      estimates: estimates,
    );
    expect(plan.loads['a'], 85);
  });

  test('same input, same plan', () {
    AssignmentPlan run() => planAssignments(
      rooms: [for (var i = 1; i <= 8; i++) room('${1 + i % 3}0$i')],
      staff: [agent('c'), agent('a'), agent('b')],
    );
    final first = run(), second = run();
    expect(
      first.assignments.map((a) => '${a.room.number}:${a.agentId}'),
      second.assignments.map((a) => '${a.room.number}:${a.agentId}'),
    );
  });

  test('parses stored priorities, unknown values are normal', () {
    expect(CleaningPriority.parse('vip'), CleaningPriority.vip);
    expect(CleaningPriority.parse('other'), CleaningPriority.normal);
    expect(CleaningPriority.parse(null), CleaningPriority.normal);
  });
}
