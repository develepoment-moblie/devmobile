import 'dart:typed_data';

import '../services/inspection_scoring.dart';

/// One rated checklist item of an inspection round.
class InspectionItem {
  final String id, taskId, label;
  final int weight;
  final InspectionRating rating;
  final String? comment, photoId;
  const InspectionItem({
    required this.id,
    required this.taskId,
    required this.label,
    required this.weight,
    required this.rating,
    this.comment,
    this.photoId,
  });
  factory InspectionItem.fromMap(Map m) => InspectionItem(
    id: m['id'] as String,
    taskId: m['task_id'] as String,
    label: m['label'] as String,
    weight: m['weight'] as int,
    rating: InspectionRating.parse(m['rating']) ?? InspectionRating.ok,
    comment: m['comment'] as String?,
    photoId: m['photo_id'] as String?,
  );
}

/// One inspection round of a room: approved or sent back.
class Inspection {
  final String id, roomNumber, inspectorName;
  final String? agentId, comment;
  final int round, threshold;
  final int? score;
  final bool approved;
  final DateTime inspectedAt;
  final List<InspectionItem> items;
  const Inspection({
    required this.id,
    required this.roomNumber,
    required this.inspectorName,
    required this.round,
    required this.threshold,
    required this.approved,
    required this.inspectedAt,
    required this.items,
    this.agentId,
    this.comment,
    this.score,
  });

  /// Items rated partiel or non conforme.
  List<InspectionItem> get failed => [
    for (final i in items)
      if (i.rating != InspectionRating.ok) i,
  ];

  factory Inspection.fromMap(Map m) => Inspection(
    id: m['id'] as String,
    roomNumber: m['room_number'] as String,
    inspectorName: m['inspector_name'] as String,
    agentId: m['agent_id'] as String?,
    round: m['round'] as int,
    threshold: m['threshold'] as int,
    score: m['score'] as int?,
    approved: m['outcome'] == 'approved',
    comment: m['comment'] as String?,
    inspectedAt: DateTime.parse(m['inspected_at'] as String),
    items: [
      for (final i in m['items'] as List? ?? [])
        InspectionItem.fromMap(i as Map),
    ],
  );
}

/// The supervisor's rating of one task, before saving.
class ItemRating {
  final String taskId;
  InspectionRating rating;
  String comment;
  Uint8List? photo;
  ItemRating(
    this.taskId, {
    this.rating = InspectionRating.ok,
    this.comment = '',
    this.photo,
  });
}
