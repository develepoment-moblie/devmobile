import 'hotel_data.dart';
import 'room.dart';

/// Current assignments, not a dated shift or a lifetime performance score.
class AgentWorkload {
  final List<Room> rooms;
  AgentWorkload(HotelData data)
    : rooms =
          data.rooms
              .where(
                (room) =>
                    data.canClean(room) &&
                    (room.needsCleaning ||
                        (room.status == RoomStatus.ready &&
                            room.cleaning == CleaningStatus.completed)),
              )
              .toList()
            ..sort((a, b) {
              int rank(Room r) => switch (r.cleaning) {
                CleaningStatus.inProgress => 0,
                CleaningStatus.waiting => r.urgent ? 1 : 2,
                CleaningStatus.review => 3,
                CleaningStatus.completed => 4,
              };
              final order = rank(a).compareTo(rank(b));
              return order != 0 ? order : a.number.compareTo(b.number);
            });
  List<Room> withStatus(CleaningStatus status) =>
      rooms.where((r) => r.cleaning == status).toList();
  List<Room> get pending => rooms
      .where(
        (r) =>
            r.cleaning == CleaningStatus.waiting ||
            r.cleaning == CleaningStatus.inProgress,
      )
      .toList();
  int get urgent => pending.where((r) => r.urgent).length;
  Room? get next => pending.firstOrNull;
}
