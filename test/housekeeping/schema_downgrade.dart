import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Turns a version 5 database back into version 4 (for the upgrade tests):
/// problem reports, found item history and settings are removed.
Future<void> dropVersion5(Database db) async {
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
