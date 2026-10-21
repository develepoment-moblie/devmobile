import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/dashboard_queries.dart';
import '../services/housekeeping_store.dart';

/// The dashboard's state. Re-reads after every saved change (the store's
/// change signal), so the screen refreshes by itself without polling.
class DashboardData extends ChangeNotifier {
  final DashboardQueries queries;
  final DateTime Function() clock;
  late final StreamSubscription<void> _changes;
  DashboardData(HousekeepingStore store, {DateTime Function()? clock})
    : queries = DashboardQueries(store),
      clock = clock ?? DateTime.now {
    _changes = store.changes.listen((_) => load());
  }

  /// 1 (today), 7 or 30 days.
  int days = 1;
  Dashboard? dashboard;
  String? error;
  bool _loading = false, _again = false, _disposed = false;

  DateTime get since {
    final now = clock();
    return DateTime(now.year, now.month, now.day - (days - 1));
  }

  void setDays(int value) {
    days = value;
    load();
  }

  Future<void> load() async {
    // A change during a read: read once more at the end.
    if (_loading) {
      _again = true;
      return;
    }
    _loading = true;
    try {
      do {
        _again = false;
        dashboard = await queries.load(since);
        error = null;
      } while (_again && !_disposed);
    } catch (e) {
      error = e.toString();
    } finally {
      _loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _changes.cancel();
    super.dispose();
  }
}
