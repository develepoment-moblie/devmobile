/// Trouvé → client prévenu → remis, or archivé after the delay.
enum LostStatus {
  found('Trouvé'),
  notified('Client prévenu'),
  returned('Remis'),
  archived('Archivé');

  final String label;
  const LostStatus(this.label);
  static LostStatus parse(Object? name) =>
      values.where((s) => s.name == name).firstOrNull ?? found;

  /// Still kept at the hotel, waiting for its owner.
  bool get kept => this == found || this == notified;
}

/// How the guest was contacted.
enum ContactChannel {
  phone('Téléphone'),
  email('E-mail'),
  sms('SMS'),
  inPerson('En personne');

  final String label;
  const ContactChannel(this.label);
  static ContactChannel? parse(Object? name) =>
      values.where((c) => c.name == name).firstOrNull;
}

/// One step in an item's history (housekeeping_lost_item_events).
class LostItemEvent {
  final LostStatus kind;
  final DateTime at;
  final String actorName;
  final ContactChannel? channel;
  final String? message;
  const LostItemEvent({
    required this.kind,
    required this.at,
    required this.actorName,
    this.channel,
    this.message,
  });
  factory LostItemEvent.fromMap(Map m) => LostItemEvent(
    kind: LostStatus.parse(m['kind']),
    at: DateTime.parse(m['at'] as String),
    actorName: m['actor_name'] as String,
    channel: ContactChannel.parse(m['channel']),
    message: m['message'] as String?,
  );
}

/// An object found in a room, kept until it is given back.
class LostItem {
  final String id, roomNumber, description, foundBy, foundByName;
  final String? photoId, returnedTo;
  final DateTime foundAt;
  final DateTime? returnedAt, archivedAt;
  final LostStatus status;
  final List<LostItemEvent> events;
  final int version;
  const LostItem({
    required this.id,
    required this.roomNumber,
    required this.description,
    required this.foundBy,
    required this.foundByName,
    required this.foundAt,
    required this.version,
    this.status = LostStatus.found,
    this.events = const [],
    this.photoId,
    this.returnedTo,
    this.returnedAt,
    this.archivedAt,
  });
  bool get returned => status == LostStatus.returned;

  /// Contact attempts, oldest first.
  Iterable<LostItemEvent> get contacts =>
      events.where((e) => e.kind == LostStatus.notified);

  factory LostItem.fromMap(Map m) => LostItem(
    id: m['id'] as String,
    roomNumber: m['room_number'] as String,
    description: m['description'] as String,
    foundBy: m['found_by'] as String,
    foundByName: m['found_by_name'] as String,
    foundAt: DateTime.parse(m['found_at'] as String),
    version: m['version'] as int,
    status: m['status'] == null
        ? (m['returned_at'] == null ? LostStatus.found : LostStatus.returned)
        : LostStatus.parse(m['status']),
    events: [
      for (final e in m['events'] as List? ?? [])
        LostItemEvent.fromMap(e as Map),
    ],
    photoId: m['photo_id'] as String?,
    returnedTo: m['returned_to'] as String?,
    returnedAt: m['returned_at'] == null
        ? null
        : DateTime.parse(m['returned_at'] as String),
    archivedAt: m['archived_at'] == null
        ? null
        : DateTime.parse(m['archived_at'] as String),
  );
}
