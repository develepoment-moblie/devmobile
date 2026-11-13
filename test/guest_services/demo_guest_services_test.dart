import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/guest_services/services/demo_guest_services.dart';
import 'package:nova_paris/guest_services/services/guest_service_store.dart';
import 'package:nova_paris/shared/models/app_user.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:nova_paris/user_management/services/demo_staff_directory.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late AppSession session;

  setUp(() async {
    final db = await AppDatabase.open(
      schemas: [GuestServiceStore.schema],
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    session = AppSession(database: db, staff: const DemoStaffDirectory());
  });
  tearDown(() async {
    session.dispose();
    await session.database.close();
  });

  Future<Map<String, int>> countBy(String table) async => {
    for (final row in await session.database.database.rawQuery(
      'SELECT status, COUNT(*) AS n FROM $table GROUP BY status',
    ))
      row['status'] as String: row['n'] as int,
  };

  test('fills menu, stay, orders and bookings at every step', () async {
    expect(await fillDemoGuestServices(session), isTrue);
    expect(session.user, isNull, reason: 'the phone session is not touched');
    final db = session.database.database;

    expect(await countBy('guest_services_orders'), {
      'delivered': 2,
      'ready': 1,
      'preparing': 2,
      'placed': 1,
      'cancelled': 2,
    });
    expect(await countBy('guest_services_records'), {
      'completed': 3,
      'rejected': 1,
      'in_progress': 2,
      'confirmed': 4,
      'pending': 1,
    });
    final stay = (await db.query('guest_services_stays')).single;
    expect(
      (stay['id'], stay['room_number'], stay['guest_name']),
      ('NP-248190', '101', 'Client Démo'),
    );
    expect(await db.query('guest_services_reviews'), hasLength(3));
    expect(await db.query('guest_services_messages'), hasLength(5));
    final seated = await db.query(
      'guest_services_seatings',
      where: 'released_at IS NULL',
    );
    expect(seated, hasLength(1));

    // The screens' own queries see it, as each role.
    final store = GuestServiceStore(session);
    session.signIn(
      const AppUser(id: 'kitchen', fullName: 'Cuisine', role: AppRole.kitchen),
    );
    expect(await store.kitchenOrders(), hasLength(3));
    session.signIn(
      const AppUser(id: 'guest', fullName: 'Client Démo', role: AppRole.guest),
    );
    expect(await store.currentStay(), isNotNull);
    expect(await store.orders(), hasLength(8));
    expect(
      (await store.menu()).where((item) => !item.available).map((i) => i.id),
      ['tart'],
    );
  });

  test('never over existing data', () async {
    expect(await fillDemoGuestServices(session), isTrue);
    expect(await fillDemoGuestServices(session), isFalse);
    expect(
      await session.database.database.query('guest_services_orders'),
      hasLength(8),
    );
  });
}
