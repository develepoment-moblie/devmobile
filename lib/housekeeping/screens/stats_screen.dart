import 'package:flutter/material.dart';

import '../../shared/custom/animations.dart';
import '../../shared/custom/app_theme.dart';
import '../custom/housekeeping_widgets.dart';
import '../models/cleaning_stats.dart';
import '../models/hotel_data.dart';

// The supervisor's figures, from the cleaning log: approved cleanings,
// average cleaning time, first-time right rate and per-agent results.
class StatsScreen extends StatefulWidget {
  final HotelData data;
  const StatsScreen({super.key, required this.data});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  int days = 1;

  DateTime get since {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day - (days - 1));
  }

  static String duration(Duration? d) {
    if (d == null) return '—';
    if (d.inMinutes < 1) return '< 1 min';
    final h = d.inHours, m = d.inMinutes % 60;
    return h == 0 ? '$m min' : '$h h ${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.data.statsSince(since);
    final best = stats.agents.isEmpty ? 1 : stats.agents.first.approved;
    return Scaffold(
      appBar: AppBar(title: const Text('Statistiques du ménage')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('Aujourd’hui')),
              ButtonSegment(value: 7, label: Text('7 jours')),
              ButtonSegment(value: 30, label: Text('30 jours')),
            ],
            selected: {days},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => days = v.first),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (i, tile) in [
                  (
                    'Nettoyages validés',
                    stats.approved,
                    '',
                    Icons.task_alt,
                    AppColors.green,
                  ),
                  (
                    'Validés du premier coup',
                    (stats.firstTimeRight * 100).round(),
                    ' %',
                    Icons.verified_outlined,
                    AppColors.primary,
                  ),
                  (
                    'Refus',
                    stats.refusals,
                    '',
                    Icons.replay_rounded,
                    AppColors.red,
                  ),
                  (
                    'Recouches',
                    stats.stayovers,
                    '',
                    Icons.bed_outlined,
                    AppColors.goldDeep,
                  ),
                ].indexed)
                  SizedBox(
                    width: (c.maxWidth - 10) / 2,
                    child: FadeSlideIn(
                      index: i,
                      child: _Tile(
                        label: tile.$1,
                        value: tile.$2,
                        suffix: tile.$3,
                        icon: tile.$4,
                        color: tile.$5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          FadeSlideIn(
            index: 4,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: AppGradients.hero,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, color: AppColors.gold),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Temps moyen de nettoyage',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  Text(
                    duration(stats.averageTime),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Par agent',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Nettoyages validés sur la période, du début du nettoyage à son envoi.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (stats.agents.isEmpty)
            const EmptyState(
              'Aucun nettoyage validé',
              'Les résultats apparaissent dès la première validation de la période.',
            ),
          for (final (i, agent) in stats.agents.indexed)
            FadeSlideIn(
              key: ValueKey('$days-${agent.agentId}'),
              index: i,
              child: _AgentBar(
                agent: agent,
                share: agent.approved / best,
                time: duration(agent.averageTime),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String label, suffix;
  final int value;
  final IconData icon;
  final Color color;
  const _Tile({
    required this.label,
    required this.value,
    required this.suffix,
    required this.icon,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.border),
      boxShadow: AppShadows.soft,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AnimatedCount(
              value,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            if (suffix.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  suffix,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
        Text(label, style: const TextStyle(fontSize: 12.5)),
      ],
    ),
  );
}

class _AgentBar extends StatelessWidget {
  final AgentStats agent;
  final double share;
  final String time;
  const _AgentBar({
    required this.agent,
    required this.share,
    required this.time,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                agent.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '${agent.approved} validé${agent.approved > 1 ? 's' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Bar length: compared with the agent with the most cleanings.
        TweenAnimationBuilder<double>(
          tween: Tween(end: share.clamp(0, 1)),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                Container(height: 12, color: AppColors.greenLight),
                FractionallySizedBox(
                  widthFactor: v,
                  child: Container(
                    height: 12,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.green, AppColors.primaryLight],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Temps moyen $time · ${agent.refusals} refus',
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ],
    ),
  );
}
