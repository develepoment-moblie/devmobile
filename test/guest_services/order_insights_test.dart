import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/guest_services/models/order_insights.dart';

void main() {
  final now = DateTime(2026, 10, 28, 12);
  Map<String, Object?> order(
    String status,
    int minutes, {
    bool legacy = false,
  }) => {
    'status': status,
    'created_at': now.subtract(Duration(minutes: minutes)).toIso8601String(),
    'lines': jsonEncode([
      if (legacy) {} else {'minutes': 20},
      if (!legacy) {'minutes': 30},
    ]),
  };
  test('pending alerts start at five minutes and exclude terminal states', () {
    expect(OrderInsights.overdue(order('placed', 4), now), isFalse);
    expect(OrderInsights.overdue(order('placed', 5), now), isTrue);
    for (final status in ['delivered', 'rejected', 'cancelled']) {
      expect(OrderInsights.overdue(order(status, 80), now), isFalse);
    }
  });
  test('active alerts use longest saved estimate plus delivery allowance', () {
    expect(OrderInsights.target(order('accepted', 0)), 40);
    expect(OrderInsights.overdue(order('preparing', 39), now), isFalse);
    expect(OrderInsights.overdue(order('out_for_delivery', 40), now), isTrue);
    expect(OrderInsights.target(order('accepted', 90, legacy: true)), isNull);
    expect(
      OrderInsights.overdue(order('accepted', 90, legacy: true), now),
      isFalse,
    );
  });
  test(
    'average uses valid deliveries completed today and excludes missing histories',
    () {
      expect(OrderInsights.averageDelivery([], now), isNull);
      final delivered = {
        ...order('delivered', 30),
        'delivered_at': now.toIso8601String(),
      };
      expect(
        OrderInsights.averageDelivery([
          delivered,
          order('delivered', 60),
          order('cancelled', 40),
        ], now),
        30,
      );
      expect(
        OrderInsights.age({
          'created_at': now.add(const Duration(minutes: 10)).toIso8601String(),
        }, now),
        0,
      );
    },
  );
}
