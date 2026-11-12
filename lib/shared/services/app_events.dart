import 'dart:async';

// The agreed messages between modules. A module emits an event; any module
// can listen. This is how modules work together without importing each other.
// Adding an event is fine; changing or removing one needs the team's agreement.
sealed class AppEvent {
  final String roomNumber;
  const AppEvent(this.roomNumber);
}

/// Reservations → housekeeping: the room must be cleaned.
class GuestCheckedOut extends AppEvent {
  const GuestCheckedOut(super.roomNumber);
}

/// Reservations → housekeeping, billing.
class GuestCheckedIn extends AppEvent {
  final String guestName;
  const GuestCheckedIn(super.roomNumber, {required this.guestName});
}

/// Housekeeping → reservations: the room can be sold again.
class RoomReady extends AppEvent {
  const RoomReady(super.roomNumber);
}

/// Any module → maintenance: a problem was reported.
class MaintenanceRequested extends AppEvent {
  final String description;
  final bool urgent;
  const MaintenanceRequested(
    super.roomNumber, {
    required this.description,
    this.urgent = false,
  });
}

/// Maintenance → housekeeping, reservations: the room is usable again.
class MaintenanceResolved extends AppEvent {
  const MaintenanceResolved(super.roomNumber);
}

/// Guest services → billing: an extra goes on the room bill.
class ExtraCharged extends AppEvent {
  final String label;
  final int amountCents;
  const ExtraCharged(
    super.roomNumber, {
    required this.label,
    required this.amountCents,
  });
}

class AppEvents {
  final _controller = StreamController<AppEvent>.broadcast();

  void emit(AppEvent event) => _controller.add(event);

  /// Example: `session.events.on<GuestCheckedOut>().listen(...)`
  Stream<T> on<T extends AppEvent>() =>
      _controller.stream.where((e) => e is T).cast<T>();

  Future<void> dispose() => _controller.close();
}
