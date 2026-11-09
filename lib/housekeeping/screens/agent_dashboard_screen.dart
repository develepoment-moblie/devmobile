import 'package:flutter/material.dart';

import '../../shared/custom/animations.dart';

import '../../shared/custom/app_theme.dart';
import '../custom/housekeeping_widgets.dart';
import '../custom/agent_room_card.dart';
import '../models/agent_workload.dart';
import '../models/hotel_data.dart';
import '../models/room.dart';
import 'agent_rooms_screen.dart';
import 'details_screen.dart';
import 'issues_screen.dart';
import 'supply_requests_screen.dart';

class AgentDashboardScreen extends StatelessWidget {
  final HotelData data;
  final VoidCallback onRooms;
  const AgentDashboardScreen({
    super.key,
    required this.data,
    required this.onRooms,
  });
  void _status(BuildContext context, CleaningStatus status) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) =>
          AgentRoomsScreen(data: data, initialStatus: status, standalone: true),
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: data,
    builder: (context, _) {
      final work = AgentWorkload(data);
      final next = work.next;
      final waiting = work.withStatus(CleaningStatus.waiting).length;
      final active = work.withStatus(CleaningStatus.inProgress).length;
      final reviews = work.withStatus(CleaningStatus.review).length;
      final completed = work.withStatus(CleaningStatus.completed).length;
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 7, 18, 24),
        children: [
          StaffBanner(
            title: 'Bonjour ${data.currentUser}.',
            label: 'MON SERVICE · AGENT D’ÉTAGE',
          ),
          const SizedBox(height: 20),
          Text(
            work.pending.isEmpty
                ? 'Votre planning est à jour.'
                : '${work.pending.length} chambre${work.pending.length > 1 ? 's' : ''} à prendre en charge',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            work.urgent > 0
                ? '${work.urgent} attribution${work.urgent > 1 ? 's' : ''} prioritaire${work.urgent > 1 ? 's' : ''} · Consultez les consignes de la gouvernante.'
                : 'Vos chambres, vos consignes et votre progression au même endroit.',
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final item in [
                  (CleaningStatus.waiting, waiting, 'À faire'),
                  (CleaningStatus.inProgress, active, 'En cours'),
                  (CleaningStatus.review, reviews, 'À valider'),
                  (CleaningStatus.completed, completed, 'Validées'),
                ])
                  SizedBox(
                    width: (constraints.maxWidth - 10) / 2,
                    child: OutlinedButton(
                      onPressed: () => _status(context, item.$1),
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.all(14),
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedCount(
                            item.$2,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(item.$3, style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (next != null) ...[
            Text(
              next.cleaning == CleaningStatus.inProgress
                  ? 'À reprendre'
                  : 'Prochaine chambre',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Les nettoyages en cours passent en premier, puis les attributions prioritaires.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            AgentRoomCard(
              room: next,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => DetailsScreen(data: data, room: next),
                ),
              ),
            ),
          ] else
            EmptyState(
              work.rooms.isEmpty
                  ? 'En attente d’attribution'
                  : 'Aucun nettoyage à démarrer',
              work.rooms.isEmpty
                  ? 'La gouvernante vous attribuera vos chambres. Tirez vers le bas pour actualiser.'
                  : reviews > 0
                  ? 'Vos nettoyages soumis attendent le contrôle de la gouvernante.'
                  : 'Vos chambres sont validées. Les prochaines attributions apparaîtront ici.',
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRooms,
            icon: const Icon(Icons.bed_outlined),
            label: const Text('Voir toutes mes chambres'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => IssuesScreen(data: data)),
            ),
            icon: const Icon(Icons.report_outlined),
            label: Text('Mes signalements · ${data.issues.length}'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => SupplyRequestsScreen(data: data),
              ),
            ),
            icon: const Icon(Icons.assignment_outlined),
            label: Text(
              'Mes demandes de fournitures · ${data.requests.where((r) => r.status.open).length}',
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Les étapes du nettoyage',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          const Text(
            'Ouvrez la chambre et lisez les consignes. Démarrez le nettoyage, effectuez chaque tâche et ajoutez sa photo, puis envoyez le nettoyage à la gouvernante pour validation.',
          ),
          const SizedBox(height: 8),
          const Text(
            '« À valider » signifie que votre travail est soumis. Seule la gouvernante peut rendre la chambre disponible.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      );
    },
  );
}
