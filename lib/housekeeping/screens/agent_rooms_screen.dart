import 'package:flutter/material.dart';

import '../custom/housekeeping_widgets.dart';
import '../custom/agent_room_card.dart';
import '../models/agent_workload.dart';
import '../models/hotel_data.dart';
import '../models/room.dart';
import 'details_screen.dart';

class AgentRoomsScreen extends StatefulWidget {
  final HotelData data;
  final CleaningStatus? initialStatus;
  final bool standalone;
  const AgentRoomsScreen({
    super.key,
    required this.data,
    this.initialStatus,
    this.standalone = false,
  });
  @override
  State<AgentRoomsScreen> createState() => _AgentRoomsScreenState();
}

class _AgentRoomsScreenState extends State<AgentRoomsScreen> {
  late CleaningStatus? selected = widget.initialStatus;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.data,
    builder: (context, _) {
      final work = AgentWorkload(widget.data);
      final rooms = selected == null ? work.rooms : work.withStatus(selected!);
      final content = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        children: [
          const Text(
            'Mes chambres',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Vos attributions actuelles, de la préparation à la validation.',
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ChoiceChip(
                label: Text('Toutes · ${work.rooms.length}'),
                selected: selected == null,
                onSelected: (_) => setState(() => selected = null),
              ),
              for (final status in CleaningStatus.values)
                ChoiceChip(
                  label: Text(
                    '${const ['À faire', 'En cours', 'À valider', 'Validées'][status.index]} · ${work.withStatus(status).length}',
                  ),
                  selected: selected == status,
                  onSelected: (_) => setState(() => selected = status),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (rooms.isEmpty)
            EmptyState(
              work.rooms.isEmpty
                  ? 'Aucune chambre attribuée'
                  : 'Aucune chambre dans ce statut',
              work.rooms.isEmpty
                  ? 'Vos chambres apparaîtront ici dès leur attribution par la gouvernante. Tirez vers le bas pour actualiser.'
                  : 'Choisissez un autre filtre pour retrouver vos chambres.',
            ),
          for (final room in rooms)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AgentRoomCard(
                room: room,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        DetailsScreen(data: widget.data, room: room),
                  ),
                ),
              ),
            ),
        ],
      );
      if (!widget.standalone) return content;
      return Scaffold(
        appBar: AppBar(title: const Text('Mon planning')),
        body: RefreshIndicator(
          onRefresh: () async {
            try {
              await widget.data.refresh();
            } catch (e) {
              if (context.mounted) showFeedback(context, e.toString());
            }
          },
          child: Column(
            children: [
              if (widget.data.connectionError != null)
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    widget.data.connectionError!,
                    semanticsLabel:
                        'Erreur d’actualisation : ${widget.data.connectionError}',
                  ),
                ),
              Expanded(child: content),
            ],
          ),
        ),
      );
    },
  );
}
