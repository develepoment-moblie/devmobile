import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/reservations/models/reservation.dart';
import 'package:nova_paris/reservations/services/demo_reservations.dart';
import 'package:nova_paris/reservations/services/reservation_service.dart';

void main() {
  test('demo bookings: every status, Client Démo in 101, filled once', () {
    final service = ReservationService.instance;
    final now = DateTime(2026, 11, 13, 9);
    fillDemoReservations(service, now: now);
    final all = service.reservations;
    expect(all, hasLength(8));
    expect({for (final r in all) r.status}, ReservationStatus.values.toSet());
    final mine = all.firstWhere((r) => r.guestName == 'Client Démo');
    expect(
      (mine.id, mine.room.id, mine.status),
      ('NP-248190', '101', ReservationStatus.checkedIn),
    );
    expect(mine.checkIn.isBefore(now) && mine.checkOut.isAfter(now), isTrue);

    fillDemoReservations(service, now: now);
    expect(service.reservations, hasLength(8));
  });
}
