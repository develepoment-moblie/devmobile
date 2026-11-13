import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/maintenance/models/intervention.dart';
import 'package:nova_paris/maintenance/services/demo_interventions.dart';
import 'package:nova_paris/maintenance/services/maintenance_store.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:nova_paris/shared/services/app_session.dart';
import 'package:nova_paris/user_management/services/demo_staff_directory.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'demo interventions: every status, rooms of housekeeping, once',
    () async {
      final db = await AppDatabase.open(
        schemas: [maintenanceSchema],
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      final session = AppSession(
        database: db,
        staff: const DemoStaffDirectory(),
      );
      Future<Uint8List?> photo(String _) async => Uint8List.fromList([1, 2, 3]);

      expect(await fillDemoInterventions(session, photo: photo), 7);
      final store = MaintenanceStore(db.database);
      final active = await store.active();
      final resolved = await store.resolved();
      expect(resolved.map((i) => i.room).toSet(), {'203', '108', '106'});
      expect(active.first.room, '305'); // urgent first
      expect(active.first.status, InterventionStatus.inProgress);
      expect(active.first.assigneeName, 'Karim Technicien');
      expect(
        active.where((i) => i.status == InterventionStatus.pending).length,
        3,
      );
      final leak = active.firstWhere((i) => i.room == '207');
      expect(await store.photos(leak.id), hasLength(1));

      expect(await fillDemoInterventions(session, photo: photo), 0);
      expect(
        (await store.active()).length + (await store.resolved()).length,
        7,
      );
      await db.close();
    },
  );
}
