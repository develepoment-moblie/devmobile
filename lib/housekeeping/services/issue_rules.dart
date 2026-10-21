import 'mutation_meta.dart';
import 'room_rules.dart';

// Problem reports (housekeeping_issues) and found items: state changes shared
// by user actions, other modules' events, the migration and the seed.

const issueCategories = [
  'climatisation',
  'eclairage',
  'plomberie',
  'television',
  'mobilier',
  'autre',
];
const issuePriorities = ['low', 'normal', 'high', 'urgent'];
const issueCategoryLabels = {
  'climatisation': 'Climatisation',
  'eclairage': 'Éclairage',
  'plomberie': 'Plomberie',
  'television': 'Télévision',
  'mobilier': 'Mobilier',
  'autre': 'Autre',
};

/// A voice note path as the app writes it, relative to its documents folder.
final voicePathPattern = RegExp(
  r'^housekeeping/voice/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.m4a$',
);

List<Map<String, dynamic>> issuesOf(Map<String, dynamic> state) =>
    (state['issues'] as List? ?? (state['issues'] = []))
        .cast<Map<String, dynamic>>();

Map<String, dynamic> newIssue({
  required String roomNumber,
  required String category,
  required String description,
  required String priority,
  required bool outOfService,
  required String reportedBy,
  required String reportedByName,
  required DateTime at,
  String status = 'open',
  List<String> photos = const [],
  String? voicePath,
  int? voiceSeconds,
}) => {
  'id': uuidV4(),
  'room_number': roomNumber,
  'category': category,
  'description': description,
  'priority': priority,
  'out_of_service': outOfService,
  'status': status,
  'reported_by': reportedBy,
  'reported_by_name': reportedByName,
  'reported_at': at.toIso8601String(),
  'resolved_at': status == 'open' ? null : at.toIso8601String(),
  'closed_at': null,
  'closed_by_name': null,
  'voice_path': voicePath,
  'voice_seconds': voiceSeconds,
  'photos': photos,
  'version': 1,
};

/// The report behind a room already in maintenance (before reports existed,
/// or sent by another module): it lets the supervisor follow it up.
Map<String, dynamic> legacyIssue(Map<String, dynamic> room, DateTime at) =>
    newIssue(
      roomNumber: room['number'] as String,
      category: 'autre',
      description: switch ((room['note'] as String? ?? '').trim()) {
        '' => 'Intervention de maintenance',
        final note => note.length > 300 ? note.substring(0, 300) : note,
      },
      priority: room['urgent'] == true ? 'urgent' : 'normal',
      outOfService: true,
      reportedBy: 'system',
      reportedByName: 'Maintenance',
      at: at,
    );

/// MaintenanceResolved: the room's open reports are resolved. The room stays
/// in maintenance until the supervisor brings it back to cleaning.
/// Returns how many reports were resolved.
int resolveIssues(Map<String, dynamic> state, String number, DateTime now) {
  final room = activeRoom(state, number);
  final issues = issuesOf(state);
  var open = [
    for (final i in issues)
      if (i['room_number'] == number && i['status'] == 'open') i,
  ];
  // A room in maintenance always gets a report to bring it back from.
  if (open.isEmpty && room?['status'] == 'maintenance') {
    final legacy = legacyIssue(room!, now);
    issues.add(legacy);
    open = [legacy];
  }
  for (final issue in open) {
    issue['status'] = 'resolved';
    issue['resolved_at'] = now.toIso8601String();
    bumpVersion(issue);
  }
  return open.length;
}

// ------------------------------------------------------------ lost and found
const contactChannels = ['phone', 'email', 'sms', 'inPerson'];
const contactChannelLabels = {
  'phone': 'téléphone',
  'email': 'e-mail',
  'sms': 'SMS',
  'inPerson': 'en personne',
};
const defaultLostArchiveDays = 30;
const lostArchiveDaysSetting = 'lostArchiveDays';

/// Days after which an item nobody claimed is archived (supervisor setting).
int lostArchiveDays(Map<String, dynamic> state) =>
    int.tryParse(
      '${((state['settings'] as Map?)?[lostArchiveDaysSetting] as Map?)?['value']}',
    ) ??
    defaultLostArchiveDays;

void addLostEvent(
  Map<String, dynamic> item,
  String kind,
  DateTime at, {
  required String? actorId,
  required String actorName,
  String? channel,
  String? message,
}) => (item['events'] as List? ?? (item['events'] = [])).add({
  'id': uuidV4(),
  'kind': kind,
  'at': at.toIso8601String(),
  'actor_id': actorId,
  'actor_name': actorName,
  'channel': channel,
  'message': message,
});

/// Archives the items still kept after the delay. Returns their ids.
List<String> archiveExpiredLostItems(Map<String, dynamic> state, DateTime now) {
  final limit = now.subtract(Duration(days: lostArchiveDays(state)));
  final archived = <String>[];
  for (final item
      in (state['lostItems'] as List? ?? []).cast<Map<String, dynamic>>()) {
    final status = item['status'] ?? 'found';
    if (status != 'found' && status != 'notified') continue;
    if (DateTime.parse(item['found_at'] as String).isAfter(limit)) continue;
    item['status'] = 'archived';
    item['archived_at'] = now.toIso8601String();
    addLostEvent(
      item,
      'archived',
      now,
      actorId: null,
      actorName: 'Archivage automatique',
      message: 'Non réclamé après ${lostArchiveDays(state)} jours',
    );
    bumpVersion(item);
    archived.add(item['id'] as String);
  }
  return archived;
}
