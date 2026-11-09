import 'package:flutter/material.dart';

import '../../shared/custom/animations.dart';
import '../../shared/custom/app_theme.dart';
import '../../shared/custom/app_widgets.dart' show InitialsAvatar;
import '../custom/busy_action.dart';
import '../custom/housekeeping_widgets.dart';
import '../custom/roomcard.dart';
import '../models/dashboard_data.dart';
import '../models/issue.dart';
import '../services/dashboard_queries.dart';

String dashboardDuration(Duration? d) {
  if (d == null) return '—';
  if (d.inMinutes < 1) return '< 1 min';
  final h = d.inHours, m = d.inMinutes % 60;
  return h == 0 ? '$m min' : '$h h ${m.toString().padLeft(2, '0')}';
}

const _statusLabels = {
  'ready': ('Libres', AppColors.green),
  'occupied': ('Occupées', AppColors.primaryLight),
  'dirty': ('À nettoyer', AppColors.orange),
  'maintenance': ('Maintenance', AppColors.red),
};

// "Tableau de bord" for the supervisor and the Manager. It refreshes by
// itself: DashboardData re-reads after every saved change.
class DashboardScreen extends StatefulWidget {
  final DashboardData dashboard;
  const DashboardScreen({super.key, required this.dashboard});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with ListenTo {
  @override
  Listenable get listenable => widget.dashboard;

  @override
  void initState() {
    super.initState();
    widget.dashboard.load();
  }

  Widget _tile(String label, String value, IconData icon, int index) =>
      FadeSlideIn(
        index: index,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.goldDeep, size: 20),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              Text(label, style: const TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
      );

  Widget _title(String text) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = widget.dashboard;
    final d = state.dashboard;
    return Scaffold(
      appBar: AppBar(title: const Text('Tableau de bord')),
      body: RefreshIndicator(
        onRefresh: state.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('Aujourd’hui')),
                ButtonSegment(value: 7, label: Text('7 jours')),
                ButtonSegment(value: 30, label: Text('30 jours')),
              ],
              selected: {state.days},
              showSelectedIcon: false,
              onSelectionChanged: (v) => state.setDays(v.first),
            ),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  state.error!,
                  style: const TextStyle(color: AppColors.red),
                ),
              ),
            if (d == null && state.error == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (d != null) ...[
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, c) {
                  final width = (c.maxWidth - 10) / 2;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final (i, t) in [
                        (
                          'Nettoyages validés',
                          '${d.cleaned}',
                          Icons.verified_outlined,
                        ),
                        (
                          'Chambres à nettoyer',
                          '${d.pending}',
                          Icons.cleaning_services_outlined,
                        ),
                        (
                          'Temps moyen (minuteur)',
                          dashboardDuration(d.averageCleaning),
                          Icons.timer_outlined,
                        ),
                        (
                          'Signalements ouverts',
                          '${d.openIssues}',
                          Icons.report_outlined,
                        ),
                      ].indexed)
                        SizedBox(
                          width: width,
                          child: _tile(t.$1, t.$2, t.$3, i),
                        ),
                    ],
                  );
                },
              ),
              _title('Chambres · ${d.rooms}'),
              for (final e in _statusLabels.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(e.value.$1)),
                          Text(
                            '${d.roomsByStatus[e.key] ?? 0}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      AnimatedProgress(
                        d.rooms == 0
                            ? 0
                            : (d.roomsByStatus[e.key] ?? 0) / d.rooms,
                        color: e.value.$2,
                        semanticsLabel: 'Chambres ${e.value.$1.toLowerCase()}',
                      ),
                    ],
                  ),
                ),
              Text(
                'À nettoyer : ${d.pendingByStage['waiting'] ?? 0} à faire · '
                '${d.pendingByStage['inProgress'] ?? 0} en cours · '
                '${d.pendingByStage['review'] ?? 0} à valider',
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
              _title('Productivité des agents'),
              if (d.agents.isEmpty)
                const Text(
                  'Aucun nettoyage validé sur la période.',
                  style: TextStyle(color: AppColors.muted),
                ),
              for (final (i, a) in d.agents.indexed)
                FadeSlideIn(
                  index: i,
                  child: _AgentRow(agent: a),
                ),
              _title('Signalements ouverts'),
              if (d.recentIssues.isEmpty)
                const EmptyState(
                  'Aucun signalement ouvert',
                  'Les problèmes signalés depuis les chambres apparaîtront ici.',
                ),
              Wrap(
                spacing: 8,
                children: [
                  if (d.issuesByStatus['open'] case final n?)
                    StatusBadge(
                      '$n en attente',
                      color: AppColors.orange,
                      background: AppColors.orangeLight,
                    ),
                  if (d.issuesByStatus['resolved'] case final n?)
                    StatusBadge(
                      '$n à remettre en service',
                      color: AppColors.green,
                      background: AppColors.greenLight,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              for (final issue in d.recentIssues)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(IssueCategory.parse(issue.category).icon),
                  title: Text(
                    'Chambre ${issue.roomNumber} · ${IssueCategory.parse(issue.category).label}',
                  ),
                  subtitle: Text(
                    '${issue.description} · ${shortDate(issue.reportedAt)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(IssueStatus.parse(issue.status).label),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AgentRow extends StatelessWidget {
  final AgentProductivity agent;
  const _AgentRow({required this.agent});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        InitialsAvatar(name: agent.name, color: AppColors.goldDeep, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                agent.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                '${agent.approved} validé${agent.approved > 1 ? 's' : ''}'
                ' · ${agent.roomsPerHour == null ? 'sans minuteur' : '${agent.roomsPerHour!.toStringAsFixed(1).replaceAll('.', ',')} ch./h'}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
            ],
          ),
        ),
        Text(
          agent.averageScore == null ? '—' : '${agent.averageScore}/100',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}
