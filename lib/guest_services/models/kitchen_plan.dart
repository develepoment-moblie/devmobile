import 'order_insights.dart';

typedef KitchenPlanEntry = ({
  Map<String, Object?> order,
  int? queuePosition,
  int? preparationMinutes,
  DateTime? startedAt,
  DateTime? expectedReadyAt,
  DateTime? readyTarget,
  bool estimateExceeded,
  bool canStart,
});

/// Forecasts one preparation lane. Dishes within an order can be prepared in
/// parallel, so the saved duration of the longest dish is the order estimate.
List<KitchenPlanEntry> planKitchen(
  List<Map<String, Object?>> orders,
  DateTime now,
) {
  final jobs = [
    for (final order in orders)
      (
        order: order,
        ready: order['status'] == 'ready',
        started: DateTime.tryParse('${order['started_at']}'),
        created: DateTime.tryParse('${order['created_at']}'),
        minutes: OrderInsights.preparationMinutes(order),
      ),
  ];
  final last = DateTime.utc(9999);
  jobs.sort((a, b) {
    if (a.ready != b.ready) return a.ready ? 1 : -1;
    if (!a.ready && (a.started != null) != (b.started != null)) {
      return a.started != null ? -1 : 1;
    }
    // Old orders without estimates retain their arrival priority.
    final targetA = a.created?.add(Duration(minutes: a.minutes ?? 0)) ?? last;
    final targetB = b.created?.add(Duration(minutes: b.minutes ?? 0)) ?? last;
    final deadline = targetA.compareTo(targetB);
    if (deadline != 0) return deadline;
    final arrival = (a.created ?? last).compareTo(b.created ?? last);
    if (arrival != 0) return arrival;
    return (a.order['id'] as int).compareTo(b.order['id'] as int);
  });

  final laneBusy = jobs.any((job) => !job.ready && job.started != null);
  final result = <KitchenPlanEntry>[];
  DateTime? cursor = now;
  var position = 0;
  for (final job in jobs) {
    final minutes = job.minutes;
    final started = job.started;
    final target = minutes == null
        ? null
        : job.created?.add(Duration(minutes: minutes));
    final startedEstimate = minutes != null && started != null
        ? started.add(Duration(minutes: minutes))
        : null;
    final exceeded =
        !job.ready && startedEstimate != null && !startedEstimate.isAfter(now);
    DateTime? eta;
    if (!job.ready) {
      position++;
      if (minutes != null && !exceeded && cursor != null) {
        eta = startedEstimate ?? cursor.add(Duration(minutes: minutes));
      }
      // An unestimated or overrun job prevents an honest downstream forecast.
      cursor = eta;
    }
    result.add((
      order: job.order,
      queuePosition: job.ready ? null : position,
      preparationMinutes: minutes,
      startedAt: started,
      expectedReadyAt: eta,
      readyTarget: target,
      estimateExceeded: exceeded,
      canStart: !job.ready && !laneBusy,
    ));
  }
  return result;
}
