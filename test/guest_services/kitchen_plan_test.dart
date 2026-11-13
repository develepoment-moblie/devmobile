import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/guest_services/models/kitchen_plan.dart';

void main() {
  final now = DateTime.utc(2026, 11, 9, 12);
  Map<String, Object?> order(
    int id,
    DateTime placed,
    List<int?> minutes, {
    DateTime? started,
    String status = 'preparing',
  }) => {
    'id': id,
    'created_at': placed.toIso8601String(),
    'started_at': started?.toIso8601String(),
    'status': status,
    'lines': jsonEncode([
      for (final value in minutes) {'minutes': value},
    ]),
  };

  test(
    'prioritizes the earliest ready target and stacks preparation times',
    () {
      final jobs = [
        order(1, now.subtract(const Duration(minutes: 10)), [5, 30]),
        order(2, now.subtract(const Duration(minutes: 3)), [8, 3]),
        order(3, now.subtract(const Duration(minutes: 25)), [
          20,
        ], status: 'ready'),
      ];
      final plan = planKitchen(jobs, now);
      expect(plan.map((entry) => entry.order['id']), [2, 1, 3]);
      expect(plan[0].expectedReadyAt, now.add(const Duration(minutes: 8)));
      expect(plan[1].expectedReadyAt, now.add(const Duration(minutes: 38)));
      expect(plan[1].queuePosition, 2);
      expect(plan[2].queuePosition, isNull);
      expect(plan[2].expectedReadyAt, isNull);
    },
  );

  test('in-progress order keeps its place and uses remaining time', () {
    final jobs = [
      order(1, now.subtract(const Duration(minutes: 10)), [8]),
      order(
        2,
        now.subtract(const Duration(minutes: 5)),
        [12],
        started: now.subtract(const Duration(minutes: 4)),
      ),
    ];
    final plan = planKitchen(jobs, now);
    expect(plan.first.order['id'], 2);
    expect(plan.first.expectedReadyAt, now.add(const Duration(minutes: 8)));
    expect(plan.last.expectedReadyAt, now.add(const Duration(minutes: 16)));
    expect(plan.any((entry) => entry.canStart), isFalse);

    final overrun = planKitchen(jobs, now.add(const Duration(minutes: 9)));
    expect(overrun.first.estimateExceeded, isTrue);
    expect(overrun.map((entry) => entry.expectedReadyAt), everyElement(isNull));
  });

  test('does not invent times when earlier estimates are missing', () {
    final plan = planKitchen([
      order(1, now.subtract(const Duration(minutes: 10)), [null]),
      order(2, now, [8]),
    ], now);
    expect(plan.first.order['id'], 1);
    expect(plan.first.preparationMinutes, isNull);
    expect(plan.map((entry) => entry.expectedReadyAt), everyElement(isNull));
  });
}
