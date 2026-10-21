import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Turns a version 6 database back into version 5 (for the upgrade tests):
/// item types, the stock log, laundry, requests, minibar and stays go.
Future<void> dropVersion6(Database db) async {
  for (final table in [
    'housekeeping_stock_movements',
    'housekeeping_laundry_lines',
    'housekeeping_laundry_batches',
    'housekeeping_supply_request_lines',
    'housekeeping_supply_requests',
    'housekeeping_minibar_consumptions',
    'housekeeping_stays',
  ]) {
    await db.execute('DROP TABLE $table');
  }
  // Version 5 had no minibar items.
  await db.delete('housekeeping_supplies', where: "category = 'minibar'");
  for (final column in ['category', 'price_cents']) {
    await db.execute('ALTER TABLE housekeeping_supplies DROP COLUMN $column');
  }
  await db.execute(
    'ALTER TABLE housekeeping_notifications DROP COLUMN recipient_id',
  );
}

/// Turns a version 6 database back into version 4: version 5 also goes
/// (problem reports, found item history and settings).
Future<void> dropVersion5(Database db) async {
  await dropVersion6(db);
  for (final table in [
    'housekeeping_issue_photos',
    'housekeeping_issues',
    'housekeeping_lost_item_events',
    'housekeeping_settings',
  ]) {
    await db.execute('DROP TABLE $table');
  }
  for (final column in ['status', 'archived_at']) {
    await db.execute('ALTER TABLE housekeeping_lost_items DROP COLUMN $column');
  }
}
