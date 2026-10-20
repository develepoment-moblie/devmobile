/// An object found in a room, kept until it is given back.
class LostItem {
  final String id, roomNumber, description, foundBy, foundByName;
  final String? photoId, returnedTo;
  final DateTime foundAt;
  final DateTime? returnedAt;
  final int version;
  const LostItem({
    required this.id,
    required this.roomNumber,
    required this.description,
    required this.foundBy,
    required this.foundByName,
    required this.foundAt,
    required this.version,
    this.photoId,
    this.returnedTo,
    this.returnedAt,
  });
  bool get returned => returnedAt != null;
  factory LostItem.fromMap(Map m) => LostItem(
    id: m['id'] as String,
    roomNumber: m['room_number'] as String,
    description: m['description'] as String,
    foundBy: m['found_by'] as String,
    foundByName: m['found_by_name'] as String,
    foundAt: DateTime.parse(m['found_at'] as String),
    version: m['version'] as int,
    photoId: m['photo_id'] as String?,
    returnedTo: m['returned_to'] as String?,
    returnedAt: m['returned_at'] == null
        ? null
        : DateTime.parse(m['returned_at'] as String),
  );
}
