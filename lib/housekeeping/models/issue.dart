import 'package:flutter/material.dart';

/// What is broken, as chosen in the report.
enum IssueCategory {
  climatisation('Climatisation', Icons.ac_unit),
  eclairage('Éclairage', Icons.lightbulb_outline),
  plomberie('Plomberie', Icons.water_drop_outlined),
  television('Télévision', Icons.tv_outlined),
  mobilier('Mobilier', Icons.chair_outlined),
  autre('Autre', Icons.build_outlined);

  final String label;
  final IconData icon;
  const IssueCategory(this.label, this.icon);
  static IssueCategory parse(Object? name) =>
      values.where((c) => c.name == name).firstOrNull ?? autre;
}

enum IssuePriority {
  low('Basse'),
  normal('Normale'),
  high('Haute'),
  urgent('Urgente');

  final String label;
  const IssuePriority(this.label);

  /// What the shared MaintenanceRequested event can carry: urgent or not.
  bool get isUrgent => this == high || this == urgent;
  static IssuePriority parse(Object? name) =>
      values.where((p) => p.name == name).firstOrNull ?? normal;
}

/// Signalé → résolu (maintenance finished) → clôturé (supervisor).
enum IssueStatus {
  open('Signalé'),
  resolved('Résolu'),
  closed('Clôturé');

  final String label;
  const IssueStatus(this.label);
  static IssueStatus parse(Object? name) =>
      values.where((s) => s.name == name).firstOrNull ?? open;
}

/// The longest voice note a report can carry.
const maxVoiceSeconds = 60;

/// Photos a report can carry.
const maxIssuePhotos = 3;

/// A problem reported from a room sheet (housekeeping_issues).
class Issue {
  final String id, roomNumber, description, reportedBy, reportedByName;
  final IssueCategory category;
  final IssuePriority priority;
  final IssueStatus status;
  final bool outOfService;
  final DateTime reportedAt;
  final DateTime? resolvedAt, closedAt;
  final String? closedByName;

  /// Voice note file, relative to the app's documents folder.
  final String? voicePath;
  final int? voiceSeconds;
  final List<String> photoIds;
  final int version;

  const Issue({
    required this.id,
    required this.roomNumber,
    required this.description,
    required this.reportedBy,
    required this.reportedByName,
    required this.category,
    required this.priority,
    required this.status,
    required this.outOfService,
    required this.reportedAt,
    required this.version,
    this.resolvedAt,
    this.closedAt,
    this.closedByName,
    this.voicePath,
    this.voiceSeconds,
    this.photoIds = const [],
  });

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String);

  factory Issue.fromMap(Map m) => Issue(
    id: m['id'] as String,
    roomNumber: m['room_number'] as String,
    description: m['description'] as String,
    reportedBy: m['reported_by'] as String,
    reportedByName: m['reported_by_name'] as String,
    category: IssueCategory.parse(m['category']),
    priority: IssuePriority.parse(m['priority']),
    status: IssueStatus.parse(m['status']),
    outOfService: m['out_of_service'] == true || m['out_of_service'] == 1,
    reportedAt: DateTime.parse(m['reported_at'] as String),
    resolvedAt: _date(m['resolved_at']),
    closedAt: _date(m['closed_at']),
    closedByName: m['closed_by_name'] as String?,
    voicePath: m['voice_path'] as String?,
    voiceSeconds: m['voice_seconds'] as int?,
    photoIds: [for (final id in m['photos'] as List? ?? []) id as String],
    version: m['version'] as int,
  );
}
