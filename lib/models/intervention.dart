enum InterventionPriority {
  urgent('urgent', 'Urgent'),
  high('high', 'Élevée'),
  normal('normal', 'Normale');

  final String dbValue;
  final String label;
  const InterventionPriority(this.dbValue, this.label);

  static InterventionPriority fromDb(String? v) =>
      InterventionPriority.values.firstWhere(
        (e) => e.dbValue == v,
        orElse: () => InterventionPriority.normal,
      );
}

enum InterventionStatus {
  pending('pending', 'En attente'),
  inProgress('in_progress', 'En cours'),
  resolved('resolved', 'Résolue');

  final String dbValue;
  final String label;
  const InterventionStatus(this.dbValue, this.label);

  static InterventionStatus fromDb(String? v) =>
      InterventionStatus.values.firstWhere(
        (e) => e.dbValue == v,
        orElse: () => InterventionStatus.pending,
      );
}

enum InterventionCategory {
  climatisation('climatisation', 'Climatisation'),
  plomberie('plomberie', 'Plomberie'),
  electricite('electricite', 'Électricité'),
  television('television', 'Télévision'),
  autre('autre', 'Autre');

  final String dbValue;
  final String label;
  const InterventionCategory(this.dbValue, this.label);

  static InterventionCategory fromDb(String? v) =>
      InterventionCategory.values.firstWhere(
        (e) => e.dbValue == v,
        orElse: () => InterventionCategory.autre,
      );
}

/// Une intervention de maintenance (ligne de la table `interventions`).
class Intervention {
  final int id;
  final String title;
  final String description;
  final String room;
  final InterventionCategory category;
  final InterventionPriority priority;
  final InterventionStatus status;
  final int? reporterId;
  final String? reporterName;
  final int? assigneeId;
  final String? assigneeName;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const Intervention({
    required this.id,
    required this.title,
    required this.description,
    required this.room,
    required this.category,
    required this.priority,
    required this.status,
    required this.createdAt,
    this.reporterId,
    this.reporterName,
    this.assigneeId,
    this.assigneeName,
    this.resolvedAt,
  });

  factory Intervention.fromMap(Map<String, Object?> m) => Intervention(
        id: m['id'] as int,
        title: (m['title'] as String?) ?? '',
        description: (m['description'] as String?) ?? '',
        room: (m['room'] as String?) ?? '',
        category: InterventionCategory.fromDb(m['category'] as String?),
        priority: InterventionPriority.fromDb(m['priority'] as String?),
        status: InterventionStatus.fromDb(m['status'] as String?),
        reporterId: m['reporter_id'] as int?,
        reporterName: m['reporter_name'] as String?,
        assigneeId: m['assignee_id'] as int?,
        assigneeName: m['assignee_name'] as String?,
        createdAt: DateTime.tryParse((m['created_at'] as String?) ?? '') ??
            DateTime.now(),
        resolvedAt: DateTime.tryParse((m['resolved_at'] as String?) ?? ''),
      );

  bool get isResolved => status == InterventionStatus.resolved;

  /// Prénom du technicien assigné (null si non assignée).
  String? get assigneeFirstName {
    final n = assigneeName?.trim() ?? '';
    return n.isEmpty ? null : n.split(' ').first;
  }

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return "À l'instant";
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours}h';
    return 'Il y a ${diff.inDays} j';
  }

  /// Ex : "Ch. 305 · Thomas · Il y a 18 min"
  String get subtitle =>
      'Ch. $room · ${assigneeFirstName ?? 'Non assignée'} · $timeAgo';
}
