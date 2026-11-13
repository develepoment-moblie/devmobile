import 'dart:convert';

/// Operational estimates, not guaranteed delivery deadlines.
class OrderInsights {
  static const acknowledgmentMinutes = 5;
  static const deliveryAllowanceMinutes = 10;
  static const active = {
    'placed',
    'accepted',
    'preparing',
    'ready',
    'out_for_delivery',
  };
  static int age(Map<String, Object?> order, DateTime now) {
    final created = DateTime.tryParse('${order['created_at']}');
    if (created == null) {
      return 0;
    }
    return now.difference(created).inMinutes.clamp(0, 10000000);
  }

  static int? preparationMinutes(Map<String, Object?> order) {
    final lines = jsonDecode(order['lines'] as String) as List;
    final estimates = lines.map((line) => line['minutes']).toList();
    if (estimates.isEmpty || estimates.any((e) => e is! int || e <= 0)) {
      return null;
    }
    return estimates.cast<int>().reduce((a, b) => a > b ? a : b);
  }

  static int? target(Map<String, Object?> order) {
    final minutes = preparationMinutes(order);
    return minutes == null ? null : minutes + deliveryAllowanceMinutes;
  }

  static bool overdue(Map<String, Object?> order, DateTime now) {
    if (!active.contains(order['status'])) {
      return false;
    }
    final limit = order['status'] == 'placed'
        ? acknowledgmentMinutes
        : target(order);
    return limit != null && age(order, now) >= limit;
  }

  static double? averageDelivery(
    List<Map<String, Object?>> orders,
    DateTime now,
  ) {
    final durations = <int>[];
    for (final order in orders) {
      final created = DateTime.tryParse('${order['created_at']}')?.toLocal();
      final delivered = DateTime.tryParse(
        '${order['delivered_at']}',
      )?.toLocal();
      if (order['status'] == 'delivered' &&
          created != null &&
          delivered != null &&
          delivered.year == now.year &&
          delivered.month == now.month &&
          delivered.day == now.day &&
          !delivered.isBefore(created)) {
        durations.add(delivered.difference(created).inSeconds);
      }
    }
    return durations.isEmpty
        ? null
        : durations.reduce((a, b) => a + b) / durations.length / 60;
  }
}
