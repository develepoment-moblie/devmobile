import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/housekeeping/services/demo_hotel.dart';
import 'package:nova_paris/housekeeping/services/hotel_event_handlers.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_store.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:nova_paris/user_management/services/demo_staff_directory.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// The presentation's demo hotel builds through the real rules, on SQLite.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test('the demo hotel fills every screen with coherent data', () async {
    final dir = await Directory.systemTemp.createTemp('nova_demo_');
    addTearDown(() => dir.delete(recursive: true));
    final database = await AppDatabase.open(
      schemas: [housekeepingSchema],
      factory: databaseFactoryFfi,
      path: p.join(dir.path, 'demo.db'),
    );
    addTearDown(database.close);
    final session = AppSession(
      database: database,
      staff: const DemoStaffDirectory(),
    );
    final store = HousekeepingStore(session);
    listenToHotelEvents(session.events, store);
    await clearHousekeeping(store);
    final summary = await fillDemoHotel(session, store);
    // ignore: avoid_print
    print('DEMO $summary');
    final state = await store.readState();
    final rooms = (state['rooms'] as List).cast<Map<String, dynamic>>();
    String? cleaning(String n) =>
        rooms.firstWhere((r) => r['number'] == n)['cleaning'] as String?;
    expect(rooms, hasLength(26));
    expect(cleaning('202'), 'review');
    expect(cleaning('302'), 'inProgress');
    expect(cleaning('304'), 'waiting');
    expect(
      rooms.firstWhere((r) => r['number'] == '305')['status'],
      'maintenance',
    );
    expect((state['cleanings'] as List).length, greaterThan(25));
    expect(state['inspections'] as List, hasLength(24));
    expect((state['issues'] as List), hasLength(4));
    expect((state['lostItems'] as List), hasLength(3));
    expect((state['requests'] as List), hasLength(3));
    expect((state['minibar'] as List), hasLength(4));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
