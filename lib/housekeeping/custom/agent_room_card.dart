import 'package:flutter/material.dart';

import '../../shared/custom/animations.dart';
import '../../shared/custom/app_theme.dart';
import '../models/room.dart';
import 'roomcard.dart';

/// The personal queue variant keeps instructions and checklist progress readable.
class AgentRoomCard extends StatelessWidget {
  final Room room;
  final VoidCallback onTap;
  const AgentRoomCard({super.key, required this.room, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final (tone, background) = roomTone(room);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: PressableScale(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Chambre ${room.number}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  StatusBadge(
                    switch (room.cleaning) {
                      CleaningStatus.waiting => 'À faire',
                      CleaningStatus.inProgress => 'En cours',
                      CleaningStatus.review => 'À valider',
                      CleaningStatus.completed => 'Validée',
                    },
                    color: tone,
                    background: background,
                    fontSize: 11,
                    textColor: AppColors.ink,
                  ),
                  if (room.urgent && room.cleaning != CleaningStatus.completed)
                    const Text(
                      'Prioritaire',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${room.category} · Étage ${room.floor}',
                style: const TextStyle(fontSize: 12),
              ),
              if (priorityBadge(room.priority) case final badge?) ...[
                const SizedBox(height: 8),
                badge,
              ],
              if (room.timerState == 'running') ...[
                const SizedBox(height: 6),
                const Text(
                  'Minuteur en cours',
                  style: TextStyle(
                    color: AppColors.green,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ],
              if (room.stayover) ...[
                const SizedBox(height: 6),
                const Text(
                  'Recouche · le client garde la chambre',
                  style: TextStyle(
                    color: AppColors.goldDeep,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ],
              if (room.note.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(room.note),
              ],
              if (room.feedback != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.redLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'À reprendre : ${room.feedback}',
                    style: const TextStyle(
                      color: AppColors.red,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (room.cleaning == CleaningStatus.inProgress) ...[
                Text(
                  '${room.checklist.where((v) => v).length} / ${room.tasks.length} contrôles effectués',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 6),
                AnimatedProgress(
                  room.checklist.where((v) => v).length / room.tasks.length,
                  semanticsLabel:
                      'Progression du nettoyage de la chambre ${room.number}',
                ),
                const SizedBox(height: 12),
              ],
              Text(
                switch (room.cleaning) {
                  CleaningStatus.waiting => 'Voir les consignes et commencer →',
                  CleaningStatus.inProgress => 'Reprendre le nettoyage →',
                  CleaningStatus.review => 'En attente de la gouvernante →',
                  CleaningStatus.completed =>
                    'Validée par ${room.approvedBy ?? 'la gouvernante'} · Voir le détail →',
                },
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
