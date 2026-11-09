/// One cleaning from assignment to approval, from the cleaning log.
class CleaningRecord {
  final String roomNumber;
  final String? agentId;
  final bool stayover;
  final DateTime assignedAt;
  final DateTime? startedAt, submittedAt, approvedAt;
  final int refusals;

  /// Timer duration (pauses excluded), when the timer was used.
  final int? durationMs;

  /// Final inspection score (0-100) and number of inspection rounds.
  final int? inspectionScore;
  final int inspectionRounds;
  const CleaningRecord({
    required this.roomNumber,
    required this.agentId,
    required this.stayover,
    required this.assignedAt,
    required this.refusals,
    this.startedAt,
    this.submittedAt,
    this.approvedAt,
    this.durationMs,
    this.inspectionScore,
    this.inspectionRounds = 0,
  });
  static DateTime? _date(Object? v) => v == null ? null : DateTime.parse('$v');
  factory CleaningRecord.fromMap(Map m) => CleaningRecord(
    roomNumber: m['room_number'] as String,
    agentId: m['agent_id'] as String?,
    stayover: m['kind'] == 'stayover',
    assignedAt: DateTime.parse(m['assigned_at'] as String),
    refusals: m['refusals'] as int,
    startedAt: _date(m['started_at']),
    submittedAt: _date(m['submitted_at']),
    approvedAt: _date(m['approved_at']),
    durationMs: m['duration_ms'] as int?,
    inspectionScore: m['inspection_score'] as int?,
    inspectionRounds: (m['inspection_rounds'] as int?) ?? 0,
  );

  /// Actual cleaning time: the timer's when available (pauses excluded),
  /// otherwise from the start to the last submission.
  Duration? get duration => durationMs != null
      ? Duration(milliseconds: durationMs!)
      : startedAt == null || submittedAt == null
      ? null
      : submittedAt!.difference(startedAt!);
}

/// The supervisor's figures for one agent over a period.
class AgentStats {
  final String agentId, name;
  final int approved, refusals;
  final Duration? averageTime;
  const AgentStats(
    this.agentId,
    this.name,
    this.approved,
    this.refusals,
    this.averageTime,
  );
}

/// Figures computed from approved cleanings since [since].
class CleaningStats {
  final List<AgentStats> agents;
  final int approved, refusals, stayovers;

  /// Approved cleanings that were never refused.
  final int firstTime;
  final Duration? averageTime;

  /// Average final inspection score of the scored cleanings (0-100).
  final int? averageScore;
  const CleaningStats({
    required this.agents,
    required this.approved,
    required this.refusals,
    required this.stayovers,
    required this.firstTime,
    required this.averageTime,
    this.averageScore,
  });

  factory CleaningStats.compute(
    List<CleaningRecord> records,
    Map<String, String> names, {
    required DateTime since,
  }) {
    final done = [
      for (final r in records)
        if (r.approvedAt != null && !r.approvedAt!.isBefore(since)) r,
    ];
    Duration? average(Iterable<CleaningRecord> items) {
      final times = [for (final r in items) ?r.duration];
      if (times.isEmpty) return null;
      return times.reduce((a, b) => a + b) ~/ times.length;
    }

    final byAgent = <String, List<CleaningRecord>>{};
    for (final r in done) {
      byAgent.putIfAbsent(r.agentId ?? '', () => []).add(r);
    }
    final agents = [
      for (final entry in byAgent.entries)
        AgentStats(
          entry.key,
          names[entry.key] ?? 'Agent indisponible',
          entry.value.length,
          entry.value.fold(0, (sum, r) => sum + r.refusals),
          average(entry.value),
        ),
    ]..sort((a, b) => b.approved.compareTo(a.approved));
    return CleaningStats(
      agents: agents,
      approved: done.length,
      refusals: done.fold(0, (sum, r) => sum + r.refusals),
      stayovers: done.where((r) => r.stayover).length,
      firstTime: done.where((r) => r.refusals == 0).length,
      averageTime: average(done),
      averageScore: () {
        final scores = [for (final r in done) ?r.inspectionScore];
        return scores.isEmpty
            ? null
            : (scores.reduce((a, b) => a + b) / scores.length).round();
      }(),
    );
  }

  /// Share of approved cleanings accepted at the first inspection (0 to 1).
  double get firstTimeRight => approved == 0 ? 0 : firstTime / approved;
}
