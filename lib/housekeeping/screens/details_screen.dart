import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../custom/housekeeping_widgets.dart';
import '../custom/nova_icon.dart';
import '../custom/roomcard.dart';
import '../models/hotel_data.dart';
import '../models/room.dart';
import 'assign_task_screen.dart';
import 'task_photo_screen.dart';
import '../custom/add_room_task_dialog.dart';
import '../custom/cleaning_timer_card.dart';
import '../services/auto_assignment.dart';
import '../custom/draft_guard.dart';
import '../custom/lost_item_dialog.dart';
import '../custom/report_problem_dialog.dart';
import '../custom/room_qr.dart';
import '../custom/text_prompt_dialog.dart';

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

  Future<void> report() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ReportProblemDialog(data: widget.data, room: widget.room),
    );
    if (mounted && saved == true) {
      showFeedback(context, 'Problème signalé à la maintenance');
    }
  }

  Future<void> prompt(TextPromptDialog dialog, String done) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => dialog,
    );
    if (mounted && saved == true) showFeedback(context, done);
  }

  Future<void> refuse() => prompt(
    TextPromptDialog(
      title: 'Refuser le nettoyage',
      label: 'À reprendre',
      hint: 'Salle de bain : traces sur le miroir…',
      message: 'L’agent reprend la chambre avec votre commentaire et la renvoie ensuite.',
      action: 'Refuser',
      destructive: true,
      save: (comment) => widget.data.refuse(widget.room, comment),
    ),
    'Nettoyage renvoyé à l’agent',
  );

  Future<void> requestStayover() => prompt(
    TextPromptDialog(
      title: 'Demander une recouche',
      label: 'Consigne (facultatif)',
      hint: 'Client absent jusqu’à 15 h…',
      message: 'La chambre reste occupée. Attribuez ensuite le nettoyage à un agent.',
      action: 'Demander',
      required: false,
      maxLength: 200,
      save: (note) => widget.data.setStayover(widget.room, true, note: note),
    ),
    'Recouche demandée',
  );

  Future<void> lostItem() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LostItemDialog(data: widget.data, room: widget.room),
    );
    if (mounted && saved == true) {
      showFeedback(context, 'Objet enregistré · la gouvernante est prévenue');
    }
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
        appBar: AppBar(
          title: Text('Chambre ${room.number}'),
          actions: [
            if (data.isSupervisor)
              IconButton(
                tooltip: 'QR code de la chambre',
                icon: const Icon(Icons.qr_code_2),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => RoomQrDialog(
                    number: room.number,
                    category: room.category,
                  ),
                ),
              ),
          ],
        ),
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
                if (room.stayover)
                  const StatusBadge(
                    'Recouche',
                    color: AppColors.goldDeep,
                    background: Color(0xFFF6EEDC),
                  ),
              ],
            ),
            if (room.feedback != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.redLight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.red.withValues(alpha: .25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.replay_rounded, color: AppColors.red),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'À reprendre',
                            style: TextStyle(
                              color: AppColors.red,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(room.feedback!),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (room.needsCleaning) CleaningTimerCard(data: data, room: room),
            if (data.isSupervisor &&
                (room.needsCleaning || room.status == RoomStatus.occupied)) ...[
              const SizedBox(height: 16),
              const Text(
                'Priorité du nettoyage',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in CleaningPriority.values)
                    ChoiceChip(
                      label: Text(p.label),
                      selected: room.priority == p.name,
                      onSelected: saving || room.priority == p.name
                          ? null
                          : (_) => action(
                              () => data.setPriority(room, p),
                              'Priorité : ${p.label}',
                            ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Text(
              room.employeeId == null
                  ? 'Aucun agent attribué'
                  : 'Agent d’étage · ${room.employee ?? 'Agent indisponible'}',
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
                  room.employeeId == null
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
                      saving || !data.canClean(room) || room.employeeId == null
                      ? null
                      : () => action(
                          () => data.startCleaning(room),
                          'Nettoyage démarré',
                        ),
                  child: const Text('Commencer le nettoyage'),
                ),
                if (room.employeeId == null)
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
                if (data.isSupervisor) ...[
                  NovaButton(
                    'Valider le nettoyage',
                    symbol: NovaSymbol.check,
                    onPressed:
                        !saving && data.isSupervisor && room.checklistComplete
                        ? () => action(
                            () => data.approve(room),
                            room.stayover
                                ? 'Recouche validée · chambre toujours occupée'
                                : 'Nettoyage validé · chambre libre',
                          )
                        : null,
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: saving ? null : refuse,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.red,
                    ),
                    icon: const Icon(Icons.replay_rounded),
                    label: const Text('Refuser et faire reprendre'),
                  ),
                ],
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
            if (room.status == RoomStatus.occupied && !room.stayover) ...[
              const Text(
                'Chambre occupée. Le départ du client, enregistré par la réception, la remettra au ménage.',
              ),
              if (data.canRequestStayover(room)) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: saving ? null : requestStayover,
                  icon: const Icon(Icons.bed_outlined),
                  label: const Text('Demander une recouche'),
                ),
              ],
            ],
            if (room.stayover &&
                data.canRequestStayover(room) &&
                room.cleaning == CleaningStatus.waiting) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: saving
                    ? null
                    : () => action(
                        () => data.setStayover(room, false),
                        'Recouche annulée',
                      ),
                icon: const Icon(Icons.close),
                label: const Text('Annuler la recouche'),
              ),
            ],
            if (room.status == RoomStatus.maintenance)
              const Text(
                'Chambre indisponible pendant l’intervention de maintenance.',
              ),
            if (data.canReport(room)) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: saving ? null : report,
                icon: const Icon(Icons.build_outlined, size: 18),
                label: const Text('Signaler un problème'),
              ),
            ],
            if (data.canRecordLostItem(room)) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: saving ? null : lostItem,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Objet trouvé'),
              ),
            ],
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
