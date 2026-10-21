import 'cleaning_timer.dart';
import 'room_rules.dart';

// Notification categories (each user can switch one off) and the late
// cleaning check.

const notificationCategoryLabels = {
  'tasks': 'Tâches urgentes et reprises',
  'departures': 'Départs des clients',
  'inspection': 'Nettoyages à valider',
  'stock': 'Stock bas',
  'maintenance': 'Maintenance',
  'late': 'Nettoyages en retard',
  'other': 'Autres (objets trouvés, demandes)',
};

/// The categories each role receives.
const agentCategories = ['tasks', 'departures', 'other'];
const supervisorCategories = [
  'departures',
  'inspection',
  'stock',
  'maintenance',
  'late',
  'other',
];

/// The category of a notification written before categories existed.
String categoryForTitle(Object? title) => switch (title) {
  'Nettoyage à reprendre' || 'Tâche urgente' => 'tasks',
  'Départ client' => 'departures',
  'Nettoyage à valider' => 'inspection',
  'Stock bas' || 'Rupture de stock' => 'stock',
  'Maintenance' ||
  'Maintenance urgente' ||
  'Maintenance terminée' => 'maintenance',
  'Nettoyage en retard' => 'late',
  _ => 'other',
};

/// The categories [userId] switched off.
Set<String> mutedCategories(Map<String, dynamic> state, Object? userId) => {
  for (final p in state['notificationPrefs'] as List? ?? [])
    if (p['user_id'] == userId && p['enabled'] == false)
      p['category'] as String,
};

/// A cleaning is late when its timer passes the category estimate + 25 %.
const lateMargin = 1.25;

Duration lateLimit(Map<String, dynamic> state, Map<String, dynamic> room) {
  final estimate =
      ((state['estimates'] as Map? ?? {})[room['category']] as Map?)?['minutes']
          as int? ??
      30;
  final minutes = room['stayover'] == true ? (estimate / 2).ceil() : estimate;
  return Duration(seconds: (minutes * 60 * lateMargin).round());
}

/// Notifies the supervisor once per late cleaning. Returns whether anything
/// changed, and when the next running cleaning will become late.
({bool changed, DateTime? next}) checkLateCleanings(
  Map<String, dynamic> state,
  DateTime now,
) {
  var changed = false;
  DateTime? next;
  final names = {
    for (final u in state['users'] as List? ?? []) u['id']: u['full_name'],
  };
  for (final cleaning
      in (state['cleanings'] as List? ?? []).cast<Map<String, dynamic>>()) {
    if (cleaning['approved_at'] != null ||
        cleaning['finished_at'] != null ||
        cleaning['late_notified_at'] != null) {
      continue;
    }
    final room = activeRoom(state, cleaning['room_number'] as String);
    if (room == null) continue;
    final segments = segmentsOf(state, cleaning['id'] as String);
    if (segments.isEmpty) continue;
    final limit = lateLimit(state, room);
    final elapsed = elapsedOf(segments, now);
    if (elapsed >= limit) {
      cleaning['late_notified_at'] = now.toIso8601String();
      addNotification(
        state,
        title: 'Nettoyage en retard',
        message:
            'Chambre ${room['number']} : ${names[cleaning['agent_id']] ?? 'l’agent'} dépasse le temps prévu (${elapsed.inMinutes} min pour ${limit.inMinutes} min).',
        roomNumber: room['number'] as String,
        audience: 'supervisor',
        category: 'late',
      );
      changed = true;
    } else if (segments.any((t) => t['ended_at'] == null)) {
      final due = now.add(limit - elapsed);
      if (next == null || due.isBefore(next)) next = due;
    }
  }
  return (changed: changed, next: next);
}
