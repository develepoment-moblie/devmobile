import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../../shared/custom/app_widgets.dart';
import '../custom/roomcard.dart';
import '../models/hotel_data.dart';
import '../models/room.dart';
import 'details_screen.dart';

class RoomsScreen extends StatefulWidget {
  final HotelData data;
  final bool departuresOnly;
  const RoomsScreen({
    super.key,
    required this.data,
    this.departuresOnly = false,
  });
  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  final search = TextEditingController();
  RoomStatus? status;
  int? floor;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final floors = widget.data.rooms.map((r) => r.floor).toSet();
    if (floor != null) floors.add(floor!);
    final orderedFloors = floors.toList()..sort();
    final rooms = widget.data.rooms
        .where(
          (r) =>
              (!widget.departuresOnly || r.status == RoomStatus.occupied) &&
              (status == null || r.status == status) &&
              (floor == null || r.floor == floor) &&
              r.number.contains(search.text.trim()),
        )
        .toList();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 7, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StaffBanner(
                title: widget.departuresOnly
                    ? 'Les départs du jour.'
                    : 'Chaque chambre, en un regard.',
                label: widget.departuresOnly
                    ? 'RÉSERVATIONS · DÉPARTS'
                    : 'CHAMBRES & MÉNAGE',
              ),
              const SizedBox(height: 18),
              TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Rechercher une chambre',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Effacer la recherche',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => search.clear()),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      key: ValueKey('floor-$floor'),
                      initialValue: floor,
                      decoration: const InputDecoration(labelText: 'Étage'),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem<int>(
                          value: null,
                          child: Text('Tous'),
                        ),
                        ...orderedFloors.map(
                          (i) => DropdownMenuItem(
                            value: i,
                            child: Text('Étage $i'),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(() => floor = value),
                    ),
                  ),
                  if (!widget.departuresOnly) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<RoomStatus>(
                        key: ValueKey('status-$status'),
                        initialValue: status,
                        decoration: const InputDecoration(labelText: 'Statut'),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<RoomStatus>(
                            value: null,
                            child: Text('Tous'),
                          ),
                          ...RoomStatus.values.map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(Room('000', status: s).statusLabel),
                            ),
                          ),
                        ],
                        onChanged: (value) => setState(() => status = value),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${rooms.length} chambre${rooms.length == 1 ? '' : 's'}',
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ],
          ),
        ),
        if (rooms.isEmpty) ...[
          const EmptyState(
            'Aucune chambre trouvée',
            'Modifiez la recherche ou réinitialisez les filtres.',
          ),
          TextButton(
            onPressed: () => setState(() {
              search.clear();
              status = null;
              floor = null;
            }),
            child: const Text('Réinitialiser les filtres'),
          ),
        ],
        ...rooms.map(
          (room) => Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Roomcard(
              room: room,
              cleaning: false,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        DetailsScreen(data: widget.data, room: room),
                  ),
                );
                if (mounted) setState(() {});
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
