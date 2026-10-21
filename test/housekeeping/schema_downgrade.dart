import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Turns a version 7 database back into version 6 (for the upgrade tests):
/// notification categories, preferences and late flags go.
Future<void> dropVersion7(Database db) async {
  await db.execute('DROP TABLE housekeeping_notification_prefs');
  await db.execute(
    'ALTER TABLE housekeeping_notifications DROP COLUMN category',
  );
  await db.execute(
    'ALTER TABLE housekeeping_cleanings DROP COLUMN late_notified_at',
  );
}

/// Back to version 5: item types, the stock log, laundry, requests,
/// minibar and stays go too.
Future<void> dropVersion6(Database db) async {
  await dropVersion7(db);
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

/// Back to version 4: version 5 also goes
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
