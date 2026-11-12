import '../models/room.dart';

enum RoomCatalogAction { create, update, archive, restore }

class RoomCatalogSnapshot {
  final List<Room> rooms, archivedRooms;
  const RoomCatalogSnapshot(this.rooms, this.archivedRooms);
  factory RoomCatalogSnapshot.fromMap(Map<String, dynamic> map) =>
      RoomCatalogSnapshot(
        (map['rooms'] as List)
            .map((r) => Room.fromMap(Map<String, dynamic>.from(r as Map)))
            .toList()
          ..sort((a, b) => a.number.compareTo(b.number)),
        (map['archivedRooms'] as List? ?? [])
            .map((r) => Room.fromMap(Map<String, dynamic>.from(r as Map)))
            .toList()
          ..sort((a, b) => a.number.compareTo(b.number)),
      );
}

abstract class RoomCatalogBackend {
  Future<RoomCatalogSnapshot> snapshot();
  Future<void> mutate(RoomCatalogAction action, Map<String, dynamic> body);
}
