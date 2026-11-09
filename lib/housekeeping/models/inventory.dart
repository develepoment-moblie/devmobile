// Linen and amenities usage, laundry, supply requests and the minibar, as
// read from the snapshot (see services/inventory_rules.dart).

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

const movementLabels = {
  'manual': 'Mouvement manuel',
  'usage': 'Utilisation',
  'laundry_out': 'Envoi en blanchisserie',
  'laundry_in': 'Retour de blanchisserie',
  'laundry_damaged': 'Abîmé en blanchisserie',
  'laundry_lost': 'Perdu en blanchisserie',
  'request': 'Demande livrée',
  'minibar_restock': 'Réassort du minibar',
};

/// One stock change: the usage log per floor and room.
class StockMovement {
  final String id, supplyId, supplyName, reason, actorName;
  final int delta, quantity;
  final String? roomNumber;
  final int? floor;
  final DateTime at;
  const StockMovement({
    required this.id,
    required this.supplyId,
    required this.supplyName,
    required this.reason,
    required this.actorName,
    required this.delta,
    required this.quantity,
    required this.at,
    this.roomNumber,
    this.floor,
  });
  String get reasonLabel => movementLabels[reason] ?? reason;
  factory StockMovement.fromMap(Map m) => StockMovement(
    id: m['id'] as String,
    supplyId: m['supply_id'] as String,
    supplyName: m['supply_name'] as String,
    reason: m['reason'] as String,
    actorName: m['actor_name'] as String,
    delta: m['delta'] as int,
    quantity: m['quantity'] as int,
    at: DateTime.parse(m['at'] as String),
    roomNumber: m['room_number'] as String?,
    floor: m['floor'] as int?,
  );
}

class LaundryLine {
  final String supplyId, supplyName, unit;
  final int sent;
  final int? received, damaged, lost;
  const LaundryLine(
    this.supplyId,
    this.supplyName,
    this.unit,
    this.sent, {
    this.received,
    this.damaged,
    this.lost,
  });
  factory LaundryLine.fromMap(Map m) => LaundryLine(
    m['supply_id'] as String,
    m['supply_name'] as String,
    m['unit'] as String,
    m['sent'] as int,
    received: m['received'] as int?,
    damaged: m['damaged'] as int?,
    lost: m['lost'] as int?,
  );
}

/// Linen sent to the laundry, then returned (received, damaged, lost).
class LaundryBatch {
  final String id, sentByName;
  final bool returned;
  final String? note, returnedByName;
  final DateTime sentAt;
  final DateTime? returnedAt;
  final List<LaundryLine> lines;
  final int version;
  const LaundryBatch({
    required this.id,
    required this.sentByName,
    required this.returned,
    required this.sentAt,
    required this.lines,
    required this.version,
    this.note,
    this.returnedByName,
    this.returnedAt,
  });
  int get sent => lines.fold(0, (sum, l) => sum + l.sent);
  int get writtenOff =>
      lines.fold(0, (sum, l) => sum + (l.damaged ?? 0) + (l.lost ?? 0));
  factory LaundryBatch.fromMap(Map m) => LaundryBatch(
    id: m['id'] as String,
    sentByName: m['sent_by_name'] as String,
    returned: m['status'] == 'returned',
    sentAt: DateTime.parse(m['sent_at'] as String),
    returnedAt: _date(m['returned_at']),
    returnedByName: m['returned_by_name'] as String?,
    note: m['note'] as String?,
    version: m['version'] as int,
    lines: [for (final l in m['lines'] as List) LaundryLine.fromMap(l as Map)],
  );
}

enum RequestStatus {
  requested('Demandée'),
  approved('Approuvée'),
  prepared('Préparée'),
  delivered('Livrée'),
  refused('Refusée');

  final String label;
  const RequestStatus(this.label);
  bool get open => this == requested || this == approved || this == prepared;
}

class RequestLine {
  final String supplyId, supplyName, unit;
  final int requested, approved, available;
  const RequestLine(
    this.supplyId,
    this.supplyName,
    this.unit,
    this.requested,
    this.approved,
    this.available,
  );

  /// Not enough in the storeroom for what was granted.
  bool get short => available < approved;
  factory RequestLine.fromMap(Map m) => RequestLine(
    m['supply_id'] as String,
    m['supply_name'] as String,
    m['unit'] as String,
    m['requested'] as int,
    m['approved'] as int,
    m['available'] as int? ?? 0,
  );
}

/// An agent's request for items from the storeroom.
class SupplyRequest {
  final String id, agentId, agentName;
  final RequestStatus status;
  final String? note, processedByName, refusalReason;
  final DateTime createdAt;
  final DateTime? approvedAt, preparedAt, deliveredAt, refusedAt;
  final List<RequestLine> lines;
  final int version;
  const SupplyRequest({
    required this.id,
    required this.agentId,
    required this.agentName,
    required this.status,
    required this.createdAt,
    required this.lines,
    required this.version,
    this.note,
    this.processedByName,
    this.refusalReason,
    this.approvedAt,
    this.preparedAt,
    this.deliveredAt,
    this.refusedAt,
  });
  bool get short => lines.any((l) => l.approved > 0 && l.short);
  factory SupplyRequest.fromMap(Map m) => SupplyRequest(
    id: m['id'] as String,
    agentId: m['agent_id'] as String,
    agentName: m['agent_name'] as String,
    status: RequestStatus.values.byName(m['status'] as String),
    createdAt: DateTime.parse(m['created_at'] as String),
    approvedAt: _date(m['approved_at']),
    preparedAt: _date(m['prepared_at']),
    deliveredAt: _date(m['delivered_at']),
    refusedAt: _date(m['refused_at']),
    note: m['note'] as String?,
    processedByName: m['processed_by_name'] as String?,
    refusalReason: m['refusal_reason'] as String?,
    version: m['version'] as int,
    lines: [for (final l in m['lines'] as List) RequestLine.fromMap(l as Map)],
  );
}

enum MinibarStatus {
  pending('En attente'),
  billed('Facturé'),
  cancelled('Annulé');

  final String label;
  const MinibarStatus(this.label);
}

/// A minibar consumption, or a compensating entry ([correctsId]).
class MinibarEntry {
  final String id, roomNumber, label, recordedBy, recordedByName;
  final String? supplyId, correctsId, billedByName;
  final int unitPriceCents, quantity, amountCents, version;
  final MinibarStatus status;
  final DateTime recordedAt;
  final DateTime? billedAt;

  /// The guest of the entry has left: posting is refused.
  final bool stayChanged;
  const MinibarEntry({
    required this.id,
    required this.roomNumber,
    required this.label,
    required this.recordedBy,
    required this.recordedByName,
    required this.unitPriceCents,
    required this.quantity,
    required this.amountCents,
    required this.version,
    required this.status,
    required this.recordedAt,
    this.supplyId,
    this.correctsId,
    this.billedByName,
    this.billedAt,
    this.stayChanged = false,
  });
  bool get isCorrection => correctsId != null;
  factory MinibarEntry.fromMap(Map m) => MinibarEntry(
    id: m['id'] as String,
    roomNumber: m['room_number'] as String,
    label: m['label'] as String,
    recordedBy: m['recorded_by'] as String,
    recordedByName: m['recorded_by_name'] as String,
    unitPriceCents: m['unit_price_cents'] as int,
    quantity: m['quantity'] as int,
    amountCents: m['amount_cents'] as int,
    version: m['version'] as int,
    status: MinibarStatus.values.byName(m['status'] as String),
    recordedAt: DateTime.parse(m['recorded_at'] as String),
    billedAt: _date(m['billed_at']),
    billedByName: m['billed_by_name'] as String?,
    supplyId: m['supply_id'] as String?,
    correctsId: m['corrects_id'] as String?,
    stayChanged: m['stayChanged'] == true,
  );
}
