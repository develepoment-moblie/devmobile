import 'room.dart';

enum ReservationStatus { confirmed, checkedIn, checkedOut, cancelled }

class Reservation {
  final String id;
  final Room room;
  final String guestName;
  final DateTime checkIn;
  final DateTime checkOut;
  final int guests;
  final ReservationStatus status;

  const Reservation({
    required this.id,
    required this.room,
    required this.guestName,
    required this.checkIn,
    required this.checkOut,
    required this.guests,
    this.status = ReservationStatus.confirmed,
  });

  int get nights => checkOut.difference(checkIn).inDays;
  double get total => nights * room.pricePerNight;

  Reservation copyWith({ReservationStatus? status}) => Reservation(
    id: id,
    room: room,
    guestName: guestName,
    checkIn: checkIn,
    checkOut: checkOut,
    guests: guests,
    status: status ?? this.status,
  );
}