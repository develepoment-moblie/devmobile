import 'package:nova_paris/housekeeping/services/mutation_meta.dart';
import 'package:nova_paris/housekeeping/services/room_catalog_backend.dart';
import 'package:nova_paris/housekeeping/services/sqlite_housekeeping.dart';
import 'package:nova_paris/housekeeping/services/sqlite_room_catalog.dart';

// The real rules, called like the app does: every mutation gets a fresh
// client id and timestamp (unless the test sets its own).

class TestHousekeeping extends SqliteHousekeeping {
  TestHousekeeping(super.store, {super.events, super.clock});
  @override
  Future<void> mutate(String path, Map<String, dynamic> body) =>
      super.mutate(path, {...mutationMeta(), ...body});
}

class TestCatalog extends SqliteRoomCatalog {
  TestCatalog(super.store, {super.clock});
  @override
  Future<void> mutate(RoomCatalogAction action, Map<String, dynamic> body) =>
      super.mutate(action, {...mutationMeta(), ...body});
}
