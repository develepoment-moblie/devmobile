import 'dart:math';

// Small state changes shared by user actions and by other modules' events.
// They work on the persisted room shape read by HousekeepingStore.

String _time() => DateTime.now().toLocal().toIso8601String().substring(0, 16);

/// The room needs a fresh cleaning: assignment, checks and photos are cleared.
void resetCleaning(Map<String, dynamic> room) {
  room['cleaning'] = 'waiting';
  room['employeeId'] = null;
  room['approvedBy'] = null;
  room['urgent'] = false;
  room['checklist'] = List.filled((room['tasks'] as List).length, false);
  for (final task in room['tasks'] as List) {
    task['photoId'] = null;
  }
}

void addHistory(Map<String, dynamic> room, String entry) =>
    (room['history'] as List).add('${_time()} · $entry');

void bumpVersion(Map<String, dynamic> room) =>
    room['version'] = (room['version'] as int) + 1;

void addNotification(
  Map<String, dynamic> state, {
  required String title,
  required String message,
  required String roomNumber,
  String audience = 'all',
}) => (state['notifications'] as List).insert(0, {
  'id':
      '$roomNumber-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}',
  'title': title,
  'message': message,
  'roomNumber': roomNumber,
  'audience': audience,
});

Map<String, dynamic>? activeRoom(Map<String, dynamic> state, String number) =>
    (state['rooms'] as List)
        .cast<Map<String, dynamic>>()
        .where((r) => r['number'] == number)
        .firstOrNull;
