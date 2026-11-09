import 'package:sqflite/sqflite.dart';

import '../../shared/models/app_user.dart';
import 'app_exception.dart';
import 'housekeeping_store.dart';

/// One agent's figures over the period.
class AgentProductivity {
  final String agentId, name;
  final int approved;

  /// Validated cleanings per hour of timer (null without timer data).
  final double? roomsPerHour;
  final int? averageScore;
  const AgentProductivity({
    required this.agentId,
    required this.name,
    required this.approved,
    this.roomsPerHour,
    this.averageScore,
  });
}

class OpenIssue {
  final String roomNumber, category, description, status;
  final DateTime reportedAt;
  const OpenIssue(
    this.roomNumber,
    this.category,
    this.description,
    this.status,
    this.reportedAt,
  );
}

/// The supervisor's and the Manager's dashboard figures.
class Dashboard {
  /// Active rooms per status (ready, occupied, dirty, maintenance).
  final Map<String, int> roomsByStatus;

  /// Cleanings validated in the period, and rooms still to clean now.
  final int cleaned, pending;

  /// Rooms still to clean, per stage (waiting, inProgress, review).
  final Map<String, int> pendingByStage;
  final Duration? averageCleaning;
  final int timedCleanings;
  final List<AgentProductivity> agents;
  final Map<String, int> issuesByStatus;
  final List<OpenIssue> recentIssues;
  const Dashboard({
    required this.roomsByStatus,
    required this.cleaned,
    required this.pending,
    required this.pendingByStage,
    required this.averageCleaning,
    required this.timedCleanings,
    required this.agents,
    required this.issuesByStatus,
    required this.recentIssues,
  });
  int get rooms => roomsByStatus.values.fold(0, (a, b) => a + b);
  int get openIssues => issuesByStatus.values.fold(0, (a, b) => a + b);
}

// SQL aggregation queries on the housekeeping tables, read-only. For the
// supervisor, the Manager and admin.
class DashboardQueries {
  final HousekeepingStore store;
  DashboardQueries(this.store);

  static const roles = {AppRole.supervisor, AppRole.manager, AppRole.admin};

  Future<Dashboard> load(DateTime since) async {
    final user = store.session.user;
    if (user == null || !roles.contains(user.role)) {
      throw const AppServiceException(
        'Tableau de bord réservé à la gouvernante et au manager.',
        403,
      );
    }
    final names = {
      for (final u in await store.session.staff.users()) u.id: u.fullName,
    };
    final from = since.toIso8601String();
    return store.query((db) async {
      Future<Map<String, int>> counts(
        String sql, [
        List<Object?>? args,
      ]) async => {
        for (final row in await db.rawQuery(sql, args))
          row['k'] as String: row['n'] as int,
      };
      Future<int> one(String sql, [List<Object?>? args]) async =>
          Sqflite.firstIntValue(await db.rawQuery(sql, args)) ?? 0;
      const toClean =
          "archived = 0 AND cleaning != 'completed' AND "
          "(status = 'dirty' OR (status = 'occupied' AND stayover = 1))";
      final average = (await db.rawQuery(
        'SELECT AVG(duration_ms) AS ms, COUNT(duration_ms) AS n '
        'FROM housekeeping_cleanings '
        'WHERE finished_at >= ? AND duration_ms IS NOT NULL',
        [from],
      )).single;
      final agents = [
        for (final row in await db.rawQuery(
          'SELECT agent_id, COUNT(*) AS approved, '
          'COUNT(duration_ms) AS timed, SUM(duration_ms) AS worked, '
          'AVG(inspection_score) AS score '
          'FROM housekeeping_cleanings '
          'WHERE approved_at >= ? AND agent_id IS NOT NULL '
          'GROUP BY agent_id ORDER BY approved DESC, agent_id',
          [from],
        ))
          AgentProductivity(
            agentId: row['agent_id'] as String,
            name: names[row['agent_id']] ?? 'Agent indisponible',
            approved: row['approved'] as int,
            roomsPerHour: (row['worked'] as num? ?? 0) > 0
                ? (row['timed'] as int) / ((row['worked'] as num) / 3600000)
                : null,
            averageScore: (row['score'] as num?)?.round(),
          ),
      ];
      return Dashboard(
        roomsByStatus: await counts(
          'SELECT status AS k, COUNT(*) AS n FROM housekeeping_rooms '
          'WHERE archived = 0 GROUP BY status',
        ),
        cleaned: await one(
          'SELECT COUNT(*) FROM housekeeping_cleanings WHERE approved_at >= ?',
          [from],
        ),
        pending: await one(
          'SELECT COUNT(*) FROM housekeeping_rooms WHERE $toClean',
        ),
        pendingByStage: await counts(
          'SELECT cleaning AS k, COUNT(*) AS n FROM housekeeping_rooms '
          'WHERE $toClean GROUP BY cleaning',
        ),
        averageCleaning: average['ms'] == null
            ? null
            : Duration(milliseconds: (average['ms'] as num).round()),
        timedCleanings: average['n'] as int,
        agents: agents,
        issuesByStatus: await counts(
          'SELECT status AS k, COUNT(*) AS n FROM housekeeping_issues '
          "WHERE status != 'closed' GROUP BY status",
        ),
        recentIssues: [
          for (final row in await db.rawQuery(
            'SELECT room_number, category, description, status, reported_at '
            "FROM housekeeping_issues WHERE status != 'closed' "
            'ORDER BY reported_at DESC LIMIT 5',
          ))
            OpenIssue(
              row['room_number'] as String,
              row['category'] as String,
              row['description'] as String,
              row['status'] as String,
              DateTime.parse(row['reported_at'] as String),
            ),
        ],
      );
    });
  }
}
