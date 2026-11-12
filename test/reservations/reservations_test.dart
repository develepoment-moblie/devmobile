import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/app/modules.dart';
import 'package:nova_paris/reservations/models/reservation.dart';
import 'package:nova_paris/reservations/screens/reservations_home_screen.dart';
import 'package:nova_paris/reservations/services/reservation_service.dart';
import 'package:nova_paris/reservations/services/staying_api_service.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Yassmine's Réservations module: bookings, availability and the two tabs.
void main() {
  final service = ReservationService.instance;

  group('reservation service', () {
    // The service is shared by the whole app, so every test books its own
    // dates far in the future to stay independent.
    test('a booked room is no longer free on overlapping dates', () {
      final room = service.rooms.first;
      final from = DateTime(2030, 1, 10);
      final to = DateTime(2030, 1, 13);

      final r = service.create(
        room: room,
        guestName: '  Alice Martin ',
        checkIn: from,
        checkOut: to,
        guests: 2,
      );
      expect(r.guestName, 'Alice Martin');
      expect(r.id, startsWith('NP-'));
      expect(r.nights, 3);
      expect(r.total, 3 * room.pricePerNight);
      expect(r.status, ReservationStatus.confirmed);

      expect(service.isAvailable(room, DateTime(2030, 1, 12), to), isFalse);
      // Leaving the morning another guest arrives is not an overlap.
      expect(service.isAvailable(room, to, DateTime(2030, 1, 15)), isTrue);
      expect(
        service.availableRooms(from, to, 1).map((x) => x.id),
        isNot(contains(room.id)),
      );
      expect(
        () => service.create(
          room: room,
          guestName: 'Bob',
          checkIn: from,
          checkOut: to,
          guests: 1,
        ),
        throwsStateError,
      );
    });

    test('a cancelled booking frees the room', () {
      final room = service.rooms[1];
      final from = DateTime(2030, 2, 1);
      final to = DateTime(2030, 2, 4);
      final r = service.create(
        room: room,
        guestName: 'Chloé',
        checkIn: from,
        checkOut: to,
        guests: 2,
      );
      service.cancel(r.id);
      expect(
        service.reservations.firstWhere((x) => x.id == r.id).status,
        ReservationStatus.cancelled,
      );
      expect(service.isAvailable(room, from, to), isTrue);
    });

    test('check-in and check-out change the status', () {
      final r = service.create(
        room: service.rooms[2],
        guestName: 'David',
        checkIn: DateTime(2030, 3, 1),
        checkOut: DateTime(2030, 3, 2),
        guests: 4,
      );
      service.checkIn(r.id);
      expect(
        service.reservations.firstWhere((x) => x.id == r.id).status,
        ReservationStatus.checkedIn,
      );
      service.checkOut(r.id);
      expect(
        service.reservations.firstWhere((x) => x.id == r.id).status,
        ReservationStatus.checkedOut,
      );
    });

    test('a missing name, bad dates or too many guests are refused', () {
      final room = service.rooms.last;
      expect(
        () => service.create(
          room: room,
          guestName: ' ',
          checkIn: DateTime(2030, 4, 1),
          checkOut: DateTime(2030, 4, 2),
          guests: 1,
        ),
        throwsStateError,
      );
      expect(
        () => service.create(
          room: room,
          guestName: 'Eve',
          checkIn: DateTime(2030, 4, 2),
          checkOut: DateTime(2030, 4, 2),
          guests: 1,
        ),
        throwsStateError,
      );
      final big = service.availableRooms(
        DateTime(2030, 4, 1),
        DateTime(2030, 4, 2),
        4,
      );
      expect(big.every((r) => r.capacity >= 4), isTrue);
    });
  });

  test('without a StayingAPI key the search says so, no request sent', () {
    expect(StayingApiService.apiKey, isEmpty);
    expect(
      StayingApiService().searchHotels(
        location: 'Paris, France',
        checkIn: '2030-01-10',
        checkOut: '2030-01-13',
        adults: 2,
      ),
      throwsA(
        predicate((e) => e.toString().contains('STAYING_API_KEY')),
      ),
    );
  });

  testWidgets('the module opens on Réserver and switches to Séjours', (
    tester,
  ) async {
    late Directory dir;
    late AppSession session;
    await tester.runAsync(() async {
      sqfliteFfiInit();
      dir = await Directory.systemTemp.createTemp('nova_reservations_');
      final database = await AppDatabase.open(
        schemas: [for (final module in novaModules) ?module.schema],
        factory: databaseFactoryFfi,
        path: p.join(dir.path, 'nova.db'),
      );
      session = AppSession(
        database: database,
        staff: userManagement.staffDirectory,
      );
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        await session.database.close();
        await dir.delete(recursive: true);
      });
    });

    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: ReservationsHomeScreen(session: session)),
    );
    await tester.pump();

    expect(find.text('Réserver'), findsOneWidget);
    expect(find.text('Séjours'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Séjours'));
    await tester.pump();
    final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(nav.selectedIndex, 1);
    expect(tester.takeException(), isNull);
  });
}
