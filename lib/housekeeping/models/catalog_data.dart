import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/mutation_meta.dart';
import '../services/room_catalog_backend.dart';
import 'room.dart';

/// Status counts of a group of rooms (a floor, or the whole hotel).
class RoomCounts {
  final int total, ready, toClean, occupied, maintenance;
  const RoomCounts({
    required this.total,
    required this.ready,
    required this.toClean,
    required this.occupied,
    required this.maintenance,
  });
  factory RoomCounts.of(Iterable<Room> rooms) => RoomCounts(
    total: rooms.length,
    ready: rooms.where((r) => r.status == RoomStatus.ready).length,
    toClean: rooms.where((r) => r.status == RoomStatus.dirty).length,
    occupied: rooms.where((r) => r.status == RoomStatus.occupied).length,
    maintenance: rooms.where((r) => r.status == RoomStatus.maintenance).length,
  );
}

/// The Manager's catalog, shared by the floor, room and template screens.
class CatalogData extends ChangeNotifier {
  final RoomCatalogBackend backend;
  CatalogData(this.backend);

  RoomCatalogSnapshot? snapshot;
  bool loading = false;
  String? error;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  List<Room> get rooms => snapshot?.rooms ?? const [];
  List<Room> roomsOn(int floor) => [
    for (final r in rooms)
      if (r.floor == floor) r,
  ];
  String floorName(int floor) => snapshot?.floorName(floor) ?? 'Étage $floor';

  Future<void> load() async {
    if (loading) return;
    loading = true;
    _notify();
    try {
      snapshot = await backend.snapshot();
      error = null;
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      _notify();
    }
  }

  /// Saves, then reloads; a failed save also reloads before rethrowing.
  Future<void> change(
    RoomCatalogAction action,
    Map<String, dynamic> body,
  ) async {
    try {
      await backend.mutate(action, {...body, ...mutationMeta()});
    } finally {
      await load();
    }
  }
}
