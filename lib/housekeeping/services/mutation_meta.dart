import 'dart:math';

// Every housekeeping mutation carries a client-generated id and the client's
// clock, so an offline queue can replay it safely: a repeated id is ignored.

final _random = Random.secure();

/// A random (version 4) UUID, e.g. 3f2b8c1e-9a4d-4c7e-b1f0-6d2e8a9c0b13.
String uuidV4() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // RFC 4122 variant
  String hex(int from, int to) =>
      [for (var i = from; i < to; i++) b[i].toRadixString(16).padLeft(2, '0')]
          .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

bool isUuid(Object? value) => value is String && _uuid.hasMatch(value);

/// The fields a client adds to every mutation body.
Map<String, dynamic> mutationMeta([DateTime? clientNow]) => {
  'mutationId': uuidV4(),
  'clientTimestamp': (clientNow ?? DateTime.now()).toIso8601String(),
};

/// Checks the mutation fields and records the mutation in [state].
/// Returns false when this id was already applied: the caller must then
/// change nothing (idempotent replay).
bool acceptMutation(
  Map<String, dynamic> state,
  String path,
  Map<String, dynamic> body,
  String actorId,
  DateTime appliedAt,
  Never Function(String message, [int status]) fail,
) {
  final id = body['mutationId'];
  final clientTimestamp = body['clientTimestamp'];
  if (!isUuid(id)) fail('Identifiant de modification (UUID) manquant.');
  if (clientTimestamp is! String ||
      DateTime.tryParse(clientTimestamp) == null) {
    fail('Horodatage client manquant.');
  }
  final log = (state['mutations'] as List? ?? (state['mutations'] = []));
  if (log.any((m) => m['id'] == id)) return false;
  log.add({
    'id': id,
    'path': path,
    'actor': actorId,
    'client_timestamp': clientTimestamp,
    'applied_at': appliedAt.toIso8601String(),
  });
  return true;
}
