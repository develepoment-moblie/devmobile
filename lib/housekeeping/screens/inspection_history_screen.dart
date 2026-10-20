import 'package:flutter/material.dart';

import '../../shared/custom/animations.dart';
import '../../shared/custom/app_theme.dart';
import '../custom/housekeeping_widgets.dart';
import '../models/hotel_data.dart';
import '../models/inspection.dart';
import '../services/inspection_scoring.dart';

// Every inspection round of a room, newest first.
class InspectionHistoryScreen extends StatelessWidget {
  final HotelData data;
  final String roomNumber;
  const InspectionHistoryScreen({
    super.key,
    required this.data,
    required this.roomNumber,
  });

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} · '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final rounds = data.inspectionsOf(roomNumber);
    return Scaffold(
      appBar: AppBar(title: Text('Inspections · $roomNumber')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        children: [
          if (rounds.isEmpty)
            const EmptyState(
              'Aucune inspection',
              'Les inspections de cette chambre apparaîtront ici.',
            ),
          for (final (i, round) in rounds.indexed)
            FadeSlideIn(
              index: i,
              child: InspectionCard(data: data, round: round),
            ),
        ],
      ),
    );
  }
}

/// One round: outcome, score and the items that were not OK.
class InspectionCard extends StatelessWidget {
  final HotelData data;
  final Inspection round;
  const InspectionCard({super.key, required this.data, required this.round});

  @override
  Widget build(BuildContext context) {
    final color = round.approved ? AppColors.green : AppColors.red;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
          Row(
            children: [
              Icon(
                round.approved ? Icons.verified_outlined : Icons.replay_rounded,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${round.approved ? 'Validé' : 'Renvoyé en nettoyage'} · passage ${round.round}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
              ),
              if (round.score != null)
                Text(
                  '${round.score}/100',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${round.inspectorName} · ${InspectionHistoryScreen._date(round.inspectedAt)} · seuil ${round.threshold}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          if (round.comment != null) ...[
            const SizedBox(height: 8),
            Text(round.comment!),
          ],
          for (final item in round.failed) ...[
            const SizedBox(height: 8),
            FailedItemRow(data: data, round: round, item: item),
          ],
        ],
      ),
    );
  }
}

/// A failed or partial item, with the supervisor's comment and photo.
class FailedItemRow extends StatelessWidget {
  final HotelData data;
  final Inspection round;
  final InspectionItem item;
  const FailedItemRow({
    super.key,
    required this.data,
    required this.round,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final failed = item.rating == InspectionRating.failed;
    final color = failed ? AppColors.red : AppColors.orange;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: failed ? AppColors.redLight : AppColors.orangeLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            item.rating.label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (item.comment != null) Text(item.comment!),
            ],
          ),
        ),
        if (item.photoId != null)
          IconButton(
            tooltip: 'Photo de la gouvernante',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(item.label),
                content: FutureBuilder(
                  future: data.inspectionPhoto(round, item),
                  builder: (context, snap) => snap.hasData
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.memory(snap.data!, fit: BoxFit.contain),
                        )
                      : snap.hasError
                      ? Text('${snap.error}')
                      : const SizedBox(
                          height: 120,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Fermer'),
                  ),
                ],
              ),
            ),
            icon: const Icon(Icons.image_outlined),
          ),
      ],
    );
  }
}
