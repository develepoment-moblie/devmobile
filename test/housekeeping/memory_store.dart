import 'dart:convert';

import 'package:nova_paris/housekeeping/models/hotel_data.dart';
import 'package:nova_paris/housekeeping/services/app_exception.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_store.dart';
import 'package:nova_paris/housekeeping/services/local_attachment_store.dart';
import 'package:nova_paris/housekeeping/services/local_session_store.dart';
import 'package:nova_paris/housekeeping/services/sqlite_housekeeping.dart';

import 'photo_fixture.dart';

// Runs the module's real rules (SqliteHousekeeping) on an in-memory state,
// so widget tests need neither SQLite nor real time.
class MemoryStore implements LocalSessionStore, LocalAttachmentStore {
  Map<String, dynamic> state = housekeepingSeedState();
  final photos = <String, String>{};
  Map<String, dynamic>? user;

  static const staff = [
    {'id': 'amina', 'full_name': 'Amina', 'role': 'supervisor'},
    {'id': 'sarah', 'full_name': 'Sarah', 'role': 'staff'},
    {'id': 'lina', 'full_name': 'Lina', 'role': 'staff'},
    {'id': 'youssef', 'full_name': 'Youssef', 'role': 'staff'},
  ];

  void signIn(String id) =>
      user = Map.of(staff.firstWhere((u) => u['id'] == id));

  Map<String, dynamic> room(String number) => (state['rooms'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((r) => r['number'] == number);

  /// Puts [number] in "awaiting approval" for [agent], with photo evidence.
  void submitted(String number, String agent) {
    final r = room(number);
    r['employeeId'] = agent;
    r['cleaning'] = 'review';
    r['checklist'] = List.filled((r['tasks'] as List).length, true);
    for (final task in r['tasks'] as List) {
      task['photoId'] = 'fixture-photo';
    }
    photos['fixture-photo'] = photoBase64();
  }

  Map<String, dynamic> _copy(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

  @override
  Future<Map<String, dynamic>> readState() async => _copy(state)
    ..['users'] = [
      for (final u in staff) {...u, 'deleted': false},
    ];

  @override
  Future<void> change(void Function(Map<String, dynamic>) action) async {
    final next = await readState();
    action(next);
    photos.addAll(
      (next.remove('_photoWrites') as Map? ?? {}).cast<String, String>(),
    );
    next.remove('users');
    state = next;
  }

  @override
  Map<String, dynamic> actor(Map<String, dynamic> state) =>
      user ?? fail('Session expirée.', 403);

  @override
  Never fail(String message, [int status = 400]) =>
      throw AppServiceException(message, status);

  @override
  Future<String> readAttachment(String id) async =>
      photos[id] ?? fail('Photo indisponible.', 404);
}

/// HotelData for [id], loaded from [store].
Future<HotelData> loadAs(MemoryStore store, String id) async {
  store.signIn(id);
  final data = HotelData(api: SqliteHousekeeping(store));
  await data.refresh();
  return data;
}
