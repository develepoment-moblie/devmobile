import 'package:flutter/foundation.dart';

import '../models/reservation.dart';
import '../models/room.dart';

class ReservationService extends ChangeNotifier {
  ReservationService._();

  static final ReservationService instance = ReservationService._();

  final List<Room> rooms = const [
    Room(
      id: '101',
      name: 'Chambre Deluxe',
      type: 'Double',
      description:
      'Une chambre lumineuse et chaleureuse, pensée pour ralentir.',
      capacity: 2,
      surface: 32,
      pricePerNight: 148,
      imagePath: 'assets/images/deluxe.jpg',
    ),

    Room(
      id: '214',
      name: 'Suite Parisienne',
      type: 'Suite',
      description:
      'Une suite avec salon et vue sur la ville.',
      capacity: 3,
      surface: 48,
      pricePerNight: 260,
      imagePath: 'assets/images/suite.jpg',
    ),

    Room(
      id: '305',
      name: 'Chambre Familiale',
      type: 'Famille',
      description:
      'Spacieuse, idéale pour les familles.',
      capacity: 4,
      surface: 40,
      pricePerNight: 210,
      imagePath: 'assets/images/family.jpg',
    ),

    Room(
      id: '118',
      name: 'Chambre Double Confort',
      type: 'Double',
      description:
      'Calme et confortable, au cœur de Paris.',
      capacity: 2,
      surface: 26,
      pricePerNight: 120,
      imagePath: 'assets/images/double.jpg',
    ),
  ];

  final List<Reservation> _reservations = [];

  int _counter = 248190;

  List<Reservation> get reservations =>
      List.unmodifiable(_reservations);

  bool isAvailable(
      Room room,
      DateTime checkIn,
      DateTime checkOut,
      ) {
    return !_reservations.any(
          (r) =>
      r.room.id == room.id &&
          (r.status == ReservationStatus.confirmed ||
              r.status == ReservationStatus.checkedIn) &&
          checkIn.isBefore(r.checkOut) &&
          r.checkIn.isBefore(checkOut),
    );
  }

  List<Room> availableRooms(
      DateTime checkIn,
      DateTime checkOut,
      int guests,
      ) {
    return rooms
        .where(
          (r) =>
      r.capacity >= guests &&
          isAvailable(r, checkIn, checkOut),
    )
        .toList();
  }

  Reservation create({
    required Room room,
    required String guestName,
    required DateTime checkIn,
    required DateTime checkOut,
    required int guests,
  }) {
    if (guestName.trim().isEmpty) {
      throw StateError('Le nom du client est obligatoire.');
    }

    if (!checkOut.isAfter(checkIn)) {
      throw StateError('Les dates sont invalides.');
    }

    if (!isAvailable(room, checkIn, checkOut)) {
      throw StateError('Cette chambre n\'est plus disponible.');
    }

    final r = Reservation(
      id: 'NP-${_counter++}',
      room: room,
      guestName: guestName.trim(),
      checkIn: checkIn,
      checkOut: checkOut,
      guests: guests,
    );

    _reservations.add(r);
    notifyListeners();

    return r;
  }

  void _setStatus(
      String id,
      ReservationStatus status,
      ) {
    final i = _reservations.indexWhere(
          (r) => r.id == id,
    );

    if (i == -1) return;

    _reservations[i] =
        _reservations[i].copyWith(status: status);

    notifyListeners();
  }

  void cancel(String id) =>
      _setStatus(id, ReservationStatus.cancelled);

  void checkIn(String id) =>
      _setStatus(id, ReservationStatus.checkedIn);

  void checkOut(String id) =>
      _setStatus(id, ReservationStatus.checkedOut);
}