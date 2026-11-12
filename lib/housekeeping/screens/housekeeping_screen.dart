import 'package:flutter/material.dart';

import '../../shared/custom/animations.dart';
import '../../shared/custom/app_theme.dart';
import '../custom/housekeeping_widgets.dart';
import '../custom/nova_icon.dart';
import '../custom/roomcard.dart';
import '../models/hotel_data.dart';
import '../models/room.dart';
import 'assign_task_screen.dart';
import 'details_screen.dart';

class HousekeepingScreen extends StatefulWidget {
  final HotelData data;
  const HousekeepingScreen({super.key, required this.data});
  @override
  State<HousekeepingScreen> createState() => _HousekeepingScreenState();
}

class _HousekeepingScreenState extends State<HousekeepingScreen> {
  // Sans filtre : les quatre chambres mises en avant dans Figma.
  // Un deuxième appui sur un filtre restitue cette vue d'ensemble.
  int? selected;

  Future<void> openRoom(Room room) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailsScreen(data: widget.data, room: room),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final List<Room> rooms = selected == null
        ? data.rooms.take(4).toList()
        : data.rooms
              .where(
                (r) => switch (selected) {
                  0 => r.needsCleaning && r.cleaning == CleaningStatus.waiting,
                  1 =>
                    r.needsCleaning &&
                        (r.cleaning == CleaningStatus.inProgress ||
                            r.cleaning == CleaningStatus.review),
                  _ =>
                    r.status == RoomStatus.ready &&
                        r.cleaning == CleaningStatus.completed,
                },
              )
              .toList();
    final labels = [
      'À faire · ${data.waiting}',
      'En cours · ${data.inProgress + data.reviews}',
      'Terminées',
    ];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 7, 18, 24),
      children: [
        StaffBanner(
          title:
              '${data.remaining} chambre${data.remaining > 1 ? 's' : ''} restante${data.remaining > 1 ? 's' : ''}',
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.tabs,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            children: List.generate(
              3,
              (index) => Expanded(
                child: Semantics(
                  selected: selected == index,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      color: selected == index
                          ? Colors.white
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: selected == index ? AppShadows.soft : const [],
                    ),
                    child: TextButton(
                      onPressed: () => setState(
                        () => selected = selected == index ? null : index,
                      ),
                      style: TextButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        foregroundColor: selected == index
                            ? AppColors.primary
                            : AppColors.muted,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        labels[index],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected == index
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 13),
        if (rooms.isEmpty)
          const EmptyState(
            'Aucune tâche',
            'Choisissez un autre statut pour consulter les chambres.',
          ),
        for (final (i, room) in rooms.indexed)
          FadeSlideIn(
            key: ValueKey('$selected-${room.number}'),
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Roomcard(room: room, onTap: () => openRoom(room)),
            ),
          ),
        const SizedBox(height: 3),
        Align(
          alignment: Alignment.centerLeft,
          child: NovaButton(
            'Attribuer une tâche',
            symbol: NovaSymbol.plus,
            onPressed: !data.isSupervisor
                ? null
                : () async {
                    final result = await Navigator.push<String>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AssignTaskScreen(data: data),
                      ),
                    );
                    if (!context.mounted) return;
                    setState(() {});
                    if (result != null) showFeedback(context, result);
                  },
          ),
        ),
        if (!data.isSupervisor)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Attribution réservée à la gouvernante.',
              style: TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ),
      ],
    );
  }
}
