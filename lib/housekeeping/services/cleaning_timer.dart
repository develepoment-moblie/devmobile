// Cleaning timer on the persisted state. A timer is a list of segments
// (running stretches) of one cleaning; an open segment (ended_at null) means
// the timer runs. Elapsed time is the sum of the segments, so pauses, app
// restarts and midnight need no special handling.

List<Map<String, dynamic>> segmentsOf(
  Map<String, dynamic> state,
  String cleaningId,
) => [
  for (final t in state['timerSegments'] as List? ?? [])
    if (t['cleaning_id'] == cleaningId) t as Map<String, dynamic>,
];

/// The agent's running segment, in any room.
Map<String, dynamic>? runningSegmentOf(
  Map<String, dynamic> state,
  String agentId,
) => (state['timerSegments'] as List? ?? [])
    .cast<Map<String, dynamic>>()
    .where((t) => t['agent_id'] == agentId && t['ended_at'] == null)
    .firstOrNull;

Duration elapsedOf(Iterable<Map<String, dynamic>> segments, DateTime now) {
  var total = Duration.zero;
  for (final t in segments) {
    final start = DateTime.parse(t['started_at'] as String);
    final end = t['ended_at'] == null
        ? now
        : DateTime.parse(t['ended_at'] as String);
    if (end.isAfter(start)) total += end.difference(start);
  }
  return total;
}

void openSegment(
  Map<String, dynamic> state,
  Map<String, dynamic> cleaning,
  String agentId,
  String id,
  DateTime now,
) => (state['timerSegments'] as List? ?? (state['timerSegments'] = [])).add({
  'id': id,
  'cleaning_id': cleaning['id'],
  'room_number': cleaning['room_number'],
  'agent_id': agentId,
  'started_at': now.toIso8601String(),
  'ended_at': null,
});

/// Closes the running segment of [cleaning]; true if one was running.
bool closeRunning(
  Map<String, dynamic> state,
  Map<String, dynamic> cleaning,
  DateTime now,
) {
  var closed = false;
  for (final t in segmentsOf(state, cleaning['id'] as String)) {
    if (t['ended_at'] == null) {
      t['ended_at'] = now.toIso8601String();
      closed = true;
    }
  }
  return closed;
}

/// Stops the timer: records finished_at and the actual duration.
void finishTimer(
  Map<String, dynamic> state,
  Map<String, dynamic> cleaning,
  DateTime now,
) {
  closeRunning(state, cleaning, now);
  cleaning['finished_at'] = now.toIso8601String();
  cleaning['duration_ms'] = elapsedOf(
    segmentsOf(state, cleaning['id'] as String),
    now,
  ).inMilliseconds;
}

/// Forgets the timer of a cleaning that is reset or reassigned.
void dropSegments(Map<String, dynamic> state, String cleaningId) =>
    (state['timerSegments'] as List? ?? []).removeWhere(
      (t) => t['cleaning_id'] == cleaningId,
    );

/// What the screens need to show a room's timer.
Map<String, dynamic>? timerView(
  Map<String, dynamic> state,
  Map<String, dynamic>? cleaning,
  DateTime now,
) {
  if (cleaning == null) return null;
  final segments = segmentsOf(state, cleaning['id'] as String);
  if (segments.isEmpty) return null;
  final running = segments.where((t) => t['ended_at'] == null).firstOrNull;
  final closed = elapsedOf(segments.where((t) => t['ended_at'] != null), now);
  return {
    'state': running != null
        ? 'running'
        : cleaning['finished_at'] != null
        ? 'stopped'
        : 'paused',
    'closedMs': closed.inMilliseconds,
    'runningSince': running?['started_at'],
    'durationMs': cleaning['duration_ms'],
  };
}
