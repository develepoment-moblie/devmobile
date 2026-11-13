import 'reservation_service.dart';

// Demo bookings for the presentation, made through ReservationService's own
// rules (availability, dates). Bookings are kept in memory only, so they are
// made again at each start of a build with --dart-define=NOVA_DEMO_DATA=true.
// The first one, NP-248190, is the test account « Client Démo » in room 101:
// the same stay as in guest services and housekeeping.

/// Build option: demo data in every module.
const novaDemoData = bool.fromEnvironment('NOVA_DEMO_DATA');

/// Fills the bookings once, while there are none.
void fillDemoReservations(ReservationService service, {DateTime? now}) {
  if (service.reservations.isNotEmpty) return;
  final clock = now ?? DateTime.now();
  final today = DateTime(clock.year, clock.month, clock.day);
  DateTime day(int offset) => today.add(Duration(days: offset));

  // (room, guest, from, to, guests, then)
  const checkedIn = 'checkedIn', checkedOut = 'checkedOut';
  const cancelled = 'cancelled', confirmed = 'confirmed';
  final bookings = [
    ('101', 'Client Démo', -2, 3, 2, checkedIn),
    ('214', 'Mme Laurent', -1, 2, 2, checkedIn),
    ('118', 'M. et Mme Dubois', -4, 0, 2, checkedOut),
    ('305', 'M. Garcia', -3, 0, 3, checkedOut),
    ('118', 'M. Nguyen', 1, 4, 1, confirmed),
    ('305', 'Famille Leroy', 5, 9, 4, confirmed),
    ('214', 'Mme Chen', 7, 10, 2, confirmed),
    ('101', 'M. Durand', 10, 12, 2, cancelled),
  ];
  for (final (room, guest, from, to, guests, then) in bookings) {
    final r = service.create(
      room: service.rooms.firstWhere((r) => r.id == room),
      guestName: guest,
      checkIn: day(from),
      checkOut: day(to),
      guests: guests,
    );
    switch (then) {
      case checkedIn:
        service.checkIn(r.id);
      case checkedOut:
        service.checkIn(r.id);
        service.checkOut(r.id);
      case cancelled:
        service.cancel(r.id);
    }
  }
}
