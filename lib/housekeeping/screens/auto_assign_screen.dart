import 'package:flutter/material.dart';

import '../../shared/custom/animations.dart';
import '../../shared/custom/app_theme.dart';
import '../custom/housekeeping_widgets.dart';
import '../models/hotel_data.dart';
import '../services/auto_assignment.dart';

// The supervisor reviews the automatic plan for today: who works and how
// long, the proposed rooms per housekeeper, manual moves, then applies it.
class AutoAssignScreen extends StatefulWidget {
  final HotelData data;
  final DateTime? day;
  const AutoAssignScreen({super.key, required this.data, this.day});
  @override
  State<AutoAssignScreen> createState() => _AutoAssignScreenState();
}

class _AutoAssignScreenState extends State<AutoAssignScreen> {
  late final DateTime day = widget.day ?? DateTime.now();
  HotelData get data => widget.data;

  /// Manual changes: room number -> agent id (null = leave unassigned).
  final Map<String, String?> moves = {};
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    data.addListener(_changed);
  }

  @override
  void dispose() {
    data.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  static const _hours = [2, 3, 4, 5, 6, 7, 8, 9, 10];

  Future<void> setAvailability(
    String agent,
    bool available,
    int minutes,
  ) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await data.setAvailability(
        agent,
        day,
        available: available,
        minutes: available ? minutes : 0,
      );
      moves.clear(); // A new proposal follows the new availability.
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // The plan with the supervisor's manual moves applied.
  ({
    List<PlannedAssignment> assigned,
    List<AssignableRoom> waiting,
    Map<String, int> loads,
  })
  _reviewed(AssignmentPlan plan) {
    final all = <AssignableRoom, String?>{
      for (final a in plan.assignments) a.room: a.agentId,
      for (final r in plan.unassigned) r: null,
    };
    final loads = {...plan.loads};
    for (final a in plan.assignments) {
      loads[a.agentId] = loads[a.agentId]! - a.minutes;
    }
    final assigned = <PlannedAssignment>[];
    final waiting = <AssignableRoom>[];
    for (final entry in all.entries) {
      final agent = moves.containsKey(entry.key.number)
          ? moves[entry.key.number]
          : entry.value;
      if (agent == null || !loads.containsKey(agent)) {
        waiting.add(entry.key);
        continue;
      }
      final minutes = estimateMinutes(entry.key, data.estimates);
      loads[agent] = loads[agent]! + minutes;
      assigned.add(PlannedAssignment(entry.key, agent, minutes));
    }
    return (assigned: assigned, waiting: waiting, loads: loads);
  }

  Future<void> move(AssignableRoom room, String? current) async {
    final staff = [
      for (final e in data.agentOptions.entries)
        if (data.availabilityOf(e.key, day).available) e,
    ];
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Chambre ${room.number} · à qui ?',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final e in staff)
              ListTile(
                leading: Icon(
                  e.key == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: AppColors.primary,
                ),
                title: Text(e.value),
                onTap: () => Navigator.pop(context, e.key),
              ),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('Ne pas attribuer pour l’instant'),
              onTap: () => Navigator.pop(context, ''),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => moves[room.number] = choice.isEmpty ? null : choice);
  }

  Future<void> apply(List<PlannedAssignment> assigned) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await data.applyPlan(assigned);
      if (!mounted) return;
      showFeedback(
        context,
        assigned.length == 1
            ? '1 chambre attribuée'
            : '${assigned.length} chambres attribuées',
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = data.proposePlan(day);
    final review = _reviewed(plan);
    final agents = data.agentOptions.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return Scaffold(
      appBar: AppBar(title: const Text('Attribution automatique')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          child: FilledButton.icon(
            onPressed: busy || review.assigned.isEmpty
                ? null
                : () => apply(review.assigned),
            icon: const Icon(Icons.done_all),
            label: Text(
              review.assigned.isEmpty
                  ? 'Aucune chambre à attribuer'
                  : 'Appliquer l’attribution · ${review.assigned.length} chambre${review.assigned.length > 1 ? 's' : ''}',
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(error!, style: const TextStyle(color: AppColors.red)),
            ),
          const Text(
            'Les chambres en attente sont réparties par priorité (arrivée anticipée, VIP, départ), '
            'en équilibrant la charge de chacun selon le temps estimé par type de chambre.',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'Disponibilités du jour',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final e in agents)
            _AvailabilityRow(
              name: e.value,
              availability: data.availabilityOf(e.key, day),
              hours: _hours,
              enabled: !busy,
              onChanged: (available, minutes) =>
                  setAvailability(e.key, available, minutes),
            ),
          const SizedBox(height: 18),
          const Text(
            'Proposition',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (data.unassignedRooms.isEmpty)
            const EmptyState(
              'Toutes les chambres sont attribuées',
              'Les nouvelles chambres à nettoyer apparaîtront ici.',
            ),
          for (final (i, e) in agents.indexed)
            if (review.loads.containsKey(e.key))
              FadeSlideIn(
                index: i,
                child: _AgentPlan(
                  name: e.value,
                  load: review.loads[e.key]!,
                  capacity: data.availabilityOf(e.key, day).minutes,
                  rooms: [
                    for (final a in review.assigned)
                      if (a.agentId == e.key) a.room,
                  ],
                  onTap: (room) => move(room, e.key),
                ),
              ),
          if (review.waiting.isNotEmpty)
            _AgentPlan(
              name: 'Non attribuées',
              load: 0,
              capacity: 0,
              rooms: review.waiting,
              onTap: (room) => move(room, null),
            ),
        ],
      ),
    );
  }
}

class _AvailabilityRow extends StatelessWidget {
  final String name;
  final ({bool available, int minutes}) availability;
  final List<int> hours;
  final bool enabled;
  final void Function(bool available, int minutes) onChanged;
  const _AvailabilityRow({
    required this.name,
    required this.availability,
    required this.hours,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final current = (availability.minutes / 60).round().clamp(2, 10);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (availability.available)
              DropdownButton<int>(
                value: current,
                underline: const SizedBox.shrink(),
                items: [
                  for (final h in hours)
                    DropdownMenuItem(value: h, child: Text('$h h')),
                ],
                onChanged: enabled ? (h) => onChanged(true, h! * 60) : null,
              ),
            Switch(
              value: availability.available,
              onChanged: enabled
                  ? (v) => onChanged(v, v ? current * 60 : 0)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentPlan extends StatelessWidget {
  final String name;
  final int load, capacity;
  final List<AssignableRoom> rooms;
  final void Function(AssignableRoom room) onTap;
  const _AgentPlan({
    required this.name,
    required this.load,
    required this.capacity,
    required this.rooms,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final waiting = capacity == 0;
    final over = !waiting && load > capacity;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: waiting
              ? AppColors.red.withValues(alpha: .4)
              : AppColors.border,
        ),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: waiting ? AppColors.red : AppColors.ink,
                  ),
                ),
              ),
              if (!waiting)
                Text(
                  '$load / $capacity min',
                  style: TextStyle(
                    color: over ? AppColors.red : AppColors.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
            ],
          ),
          if (!waiting) ...[
            const SizedBox(height: 8),
            AnimatedProgress(
              capacity == 0 ? 0 : load / capacity,
              color: over ? AppColors.red : AppColors.green,
              semanticsLabel: 'Charge de $name',
            ),
          ],
          const SizedBox(height: 10),
          if (rooms.isEmpty)
            const Text(
              'Aucune chambre proposée.',
              style: TextStyle(color: AppColors.muted, fontSize: 12.5),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final room in rooms)
                ActionChip(
                  avatar: room.rank < CleaningPriority.normal.index
                      ? const Icon(
                          Icons.priority_high,
                          size: 16,
                          color: AppColors.accent,
                        )
                      : null,
                  label: Text(
                    room.stayover ? '${room.number} · recouche' : room.number,
                  ),
                  tooltip:
                      '${room.category} · ${CleaningPriority.values[room.rank].label}',
                  onPressed: () => onTap(room),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
