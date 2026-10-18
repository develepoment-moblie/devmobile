import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../../shared/custom/app_widgets.dart';
import '../../shared/custom/nova_icon.dart';
import '../custom/roomcard.dart';
import '../models/hotel_data.dart';
import '../models/room.dart';
import 'assign_task_screen.dart';
import 'task_photo_screen.dart';
import '../custom/add_room_task_dialog.dart';
import '../../shared/custom/draft_guard.dart';

class DetailsScreen extends StatefulWidget {
  final HotelData data;
  final Room room;
  const DetailsScreen({super.key, required this.data, required this.room});
  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    widget.data.addListener(updated);
  }

  void updated() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.data.removeListener(updated);
    super.dispose();
  }

  Future<void> check(int index, bool value) async {
    if (value && widget.data.supportsTaskPhotos) {
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => TaskPhotoScreen(
            data: widget.data,
            room: widget.room,
            task: widget.room.tasks[index],
          ),
        ),
      );
      if (mounted && result == true) {
        showFeedback(context, 'Photo enregistrée · tâche terminée');
      }
    } else {
      if (!value && widget.room.tasks[index].photoId != null) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: const Text('Rouvrir cette tâche ?'),
            content: const Text(
              'La photo justificative sera retirée. Une nouvelle photo sera nécessaire pour terminer la tâche.',
            ),
            actions: [
              TextButton(
                autofocus: true,
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Conserver'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Rouvrir la tâche'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      await action(() => widget.data.setCheck(widget.room, index, value), '');
    }
  }

  Future<void> assign() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => AssignTaskScreen(data: widget.data, room: widget.room),
      ),
    );
    if (!mounted) return;
    setState(() {});
    if (result != null) showFeedback(context, result);
  }

  Future<void> action(FutureOr<void> Function() update, String message) async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await update();
      if (mounted && message.isNotEmpty) showFeedback(context, message);
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
        showFeedback(context, e.toString());
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final data = widget.data;
    if (!data.rooms.contains(room)) {
      return Scaffold(
        appBar: AppBar(title: Text('Chambre ${room.number}')),
        body: const Padding(
          padding: EdgeInsets.all(18),
          child: EmptyState(
            'Chambre retirée du planning',
            'Cette chambre a été archivée. Revenez à la liste pour voir les chambres actives.',
          ),
        ),
      );
    }
    final (color, background) = roomTone(room, cleaning: room.needsCleaning);
    return DraftGuard(
      dirty: false,
      busy: saving,
      child: Scaffold(
        appBar: AppBar(title: Text('Chambre ${room.number}')),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (saving) const LinearProgressIndicator(),
            if (error != null)
              Text(error!, style: const TextStyle(color: AppColors.red)),
            StaffBanner(
              title: 'Chambre ${room.number}',
              label: '${room.category.toUpperCase()} · ÉTAGE ${room.floor}',
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusBadge(
                  room.statusLabel,
                  color: color,
                  background: background,
                ),
                if (room.needsCleaning)
                  StatusBadge(
                    room.cleaningLabel,
                    color: color,
                    background: background,
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              room.employee == null
                  ? 'Aucun agent attribué'
                  : 'Agent d’étage · ${room.employee}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (room.note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(room.note),
            ],
            if (room.needsCleaning &&
                !data.isSupervisor &&
                !data.canClean(room))
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Consultation uniquement · cette tâche ne vous est pas attribuée.',
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ),
            const SizedBox(height: 20),
            if (data.isSupervisor && data.supportsTaskPhotos) ...[
              OutlinedButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        final saved = await showDialog<bool>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) =>
                              AddRoomTaskDialog(data: data, room: room),
                        );
                        if (context.mounted && saved == true) {
                          showFeedback(
                            context,
                            'Tâche ajoutée à la chambre ${room.number}',
                          );
                        }
                      },
                icon: const Icon(Icons.add_task),
                label: const Text('Ajouter une tâche à cette chambre'),
              ),
              const SizedBox(height: 16),
            ],
            if (room.needsCleaning || data.supportsTaskPhotos) ...[
              const Text(
                'Liste de contrôle',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...List.generate(
                room.tasks.length,
                (i) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        room.tasks[i].label,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: data.supportsTaskPhotos
                          ? Text(
                              room.tasks[i].photoId != null
                                  ? 'Photo enregistrée'
                                  : room.checklist[i]
                                  ? 'Ancien contrôle sans photo'
                                  : 'Photo obligatoire pour terminer',
                              style: const TextStyle(fontSize: 12),
                            )
                          : null,
                      value: room.checklist[i],
                      onChanged:
                          !saving &&
                              room.needsCleaning &&
                              data.canClean(room) &&
                              room.cleaning == CleaningStatus.inProgress
                          ? (value) => check(i, value!)
                          : null,
                    ),
                    if (room.tasks[i].photoId != null)
                      TextButton.icon(
                        onPressed: saving
                            ? null
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => TaskPhotoViewer(
                                    data: data,
                                    room: room,
                                    task: room.tasks[i],
                                  ),
                                ),
                              ),
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('Voir la photo'),
                      ),
                    if (data.supportsTaskPhotos &&
                        room.needsCleaning &&
                        data.canClean(room) &&
                        room.cleaning == CleaningStatus.inProgress &&
                        room.checklist[i] &&
                        room.tasks[i].photoId == null)
                      TextButton(
                        onPressed: saving ? null : () => check(i, true),
                        child: const Text('Ajouter la photo manquante'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (data.isSupervisor &&
                  (room.cleaning == CleaningStatus.waiting ||
                      room.cleaning == CleaningStatus.inProgress))
                NovaButton(
                  room.employee == null
                      ? 'Attribuer une tâche'
                      : 'Modifier l’attribution',
                  symbol: NovaSymbol.person,
                  onPressed: !saving && data.isSupervisor ? assign : null,
                ),
              if (room.needsCleaning &&
                  room.cleaning == CleaningStatus.waiting) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed:
                      saving || !data.canClean(room) || room.employee == null
                      ? null
                      : () => action(
                          () => data.startCleaning(room),
                          'Nettoyage démarré',
                        ),
                  child: const Text('Commencer le nettoyage'),
                ),
                if (room.employee == null)
                  const Text(
                    'Attribuez un agent avant de commencer.',
                    style: TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
              ],
              if (room.needsCleaning &&
                  room.cleaning == CleaningStatus.inProgress) ...[
                const SizedBox(height: 12),
                NovaButton(
                  'Terminer le nettoyage',
                  symbol: NovaSymbol.check,
                  onPressed:
                      saving || !data.canClean(room) || !room.checklistComplete
                      ? null
                      : () => action(
                          () => data.submitCleaning(room),
                          'Nettoyage envoyé pour validation',
                        ),
                ),
                if (!room.checklistComplete)
                  const Text(
                    'Terminez tous les contrôles et ajoutez les photos demandées.',
                    style: TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
              ],
              if (room.needsCleaning &&
                  room.cleaning == CleaningStatus.review) ...[
                const Text(
                  'Le nettoyage attend la validation de la gouvernante.',
                ),
                const SizedBox(height: 12),
                if (data.isSupervisor)
                  NovaButton(
                    'Valider le nettoyage',
                    symbol: NovaSymbol.check,
                    onPressed:
                        !saving && data.isSupervisor && room.checklistComplete
                        ? () => action(
                            () => data.approve(room),
                            'Nettoyage validé · chambre libre',
                          )
                        : null,
                  ),
                if (!data.isSupervisor)
                  const Text(
                    'Validation réservée à la gouvernante.',
                    style: TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
              ],
            ],
            if (room.status == RoomStatus.ready)
              const EmptyState(
                'Chambre prête',
                'Le nettoyage a été validé. La chambre est disponible.',
              ),
            if (room.status == RoomStatus.occupied && !data.isConnected) ...[
              NovaButton(
                'Enregistrer le départ',
                symbol: NovaSymbol.check,
                onPressed: () => action(
                  () => data.checkout(room),
                  'Départ enregistré · notification ajoutée',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Le départ ajoute la chambre au ménage et crée une notification locale.',
                style: TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ],
            if (room.status == RoomStatus.maintenance)
              const Text(
                'Chambre indisponible pendant l’intervention de maintenance.',
              ),
            const SizedBox(height: 28),
            const Text(
              'Historique',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ...room.history.reversed.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const NovaIcon(
                      NovaSymbol.check,
                      size: 15,
                      color: AppColors.green,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(entry, style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
