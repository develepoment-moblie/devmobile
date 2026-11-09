import 'package:flutter/material.dart';

import '../../shared/custom/animations.dart';
import '../../shared/custom/app_theme.dart';
import '../custom/draft_guard.dart';
import '../custom/housekeeping_widgets.dart';
import '../custom/inspection_rules_editor.dart';
import '../custom/text_prompt_dialog.dart';
import '../models/hotel_data.dart';
import '../models/inspection.dart';
import '../models/room.dart';
import '../services/inspection_scoring.dart';
import '../services/task_photo_picker.dart';
import 'task_photo_screen.dart';

// The supervisor inspects a submitted cleaning: every checklist item is
// rated, with an optional comment and photo, then the cleaning is approved
// (score at or above the threshold) or sent back to the same agent.
class InspectionScreen extends StatefulWidget {
  final HotelData data;
  final Room room;
  final TaskPhotoPicker? picker;
  const InspectionScreen({
    super.key,
    required this.data,
    required this.room,
    this.picker,
  });
  @override
  State<InspectionScreen> createState() => _InspectionScreenState();
}

class _InspectionScreenState extends State<InspectionScreen> {
  late final _picker = widget.picker ?? NativeTaskPhotoPicker();
  late final List<ItemRating> _ratings = [
    for (final t in widget.room.tasks) ItemRating(t.id),
  ];
  bool _busy = false, _touched = false;
  String? _error;

  Room get room => widget.room;
  HotelData get data => widget.data;
  int get _score => data.scoreOf(room, _ratings);
  int get _threshold => data.rulesFor(room.category).threshold;
  bool get _passes => passes(_score, _threshold);
  List<ItemRating> get _failed => [
    for (final r in _ratings)
      if (r.rating != InspectionRating.ok) r,
  ];

  String _label(String taskId) =>
      room.tasks.firstWhere((t) => t.id == taskId).label;

  Future<void> _photo(ItemRating rating, bool camera) async {
    try {
      final photo = await _picker.pick(camera: camera);
      if (photo != null && mounted) {
        setState(() {
          rating.photo = photo;
          _touched = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      showFeedback(context, done);
      setState(() => _touched = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() => _run(
    () => data.approveInspected(room, _ratings),
    room.stayover
        ? 'Recouche validée · chambre toujours occupée'
        : 'Nettoyage validé · chambre libre',
  );

  Future<void> _sendBack() async {
    final failed = _failed;
    String? comment;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TextPromptDialog(
        title: 'Renvoyer en nettoyage',
        label: failed.isEmpty ? 'À reprendre' : 'Commentaire (facultatif)',
        message: failed.isEmpty
            ? 'Tous les points sont OK : expliquez ce qui est à reprendre.'
            : 'À refaire : ${failed.map((r) => _label(r.taskId)).join(', ')}. '
                  'La chambre revient en priorité à ${room.employee ?? 'l’agent'}.',
        action: 'Renvoyer',
        destructive: true,
        required: failed.isEmpty,
        save: (text) async => comment = text,
      ),
    );
    if (saved != true || !mounted) return;
    await _run(
      () => data.sendBack(room, _ratings, comment ?? ''),
      'Chambre renvoyée en nettoyage',
    );
  }

  Future<void> _editRules() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => InspectionRulesEditor(
          category: room.category,
          labels: [for (final t in room.tasks) t.label],
          rules: data.rulesFor(room.category),
          save: (threshold, weights) => data.setInspectionRules(
            room.category,
            threshold: threshold,
            weights: weights,
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final score = _score, threshold = _threshold;
    final color = _passes ? AppColors.green : AppColors.red;
    return DraftGuard(
      dirty: _touched,
      busy: _busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Inspection · ${room.number}'),
          actions: [
            IconButton(
              tooltip: 'Barème de la catégorie',
              onPressed: _busy ? null : _editRules,
              icon: const Icon(Icons.tune),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          children: [
            FadeSlideIn(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: .4)),
                  boxShadow: AppShadows.soft,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        AnimatedCount(
                          score,
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 6, left: 4),
                            child: Text(
                              '/ 100 · seuil $threshold',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            _passes ? 'Conforme' : 'Insuffisant',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AnimatedProgress(
                      score / 100,
                      color: color,
                      semanticsLabel: 'Score $score sur 100, seuil $threshold',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${room.category} · nettoyée par ${room.employee ?? 'Agent indisponible'}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.red),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            for (final (i, rating) in _ratings.indexed)
              FadeSlideIn(
                index: i + 1,
                child: _ItemCard(
                  label: room.tasks[i].label,
                  weight: data
                      .rulesFor(room.category)
                      .weightOf(room.tasks[i].label),
                  rating: rating,
                  enabled: !_busy,
                  onAgentPhoto: room.tasks[i].photoId == null
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
                  onChanged: () => setState(() => _touched = true),
                  onPhoto: (camera) => _photo(rating, camera),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy || !_passes ? null : _approve,
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Valider le nettoyage'),
            ),
            if (!_passes)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Score inférieur au seuil de $threshold : renvoyez la chambre en nettoyage.',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _sendBack,
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Renvoyer en nettoyage'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final String label;
  final int weight;
  final ItemRating rating;
  final bool enabled;
  final VoidCallback? onAgentPhoto;
  final VoidCallback onChanged;
  final void Function(bool camera) onPhoto;
  const _ItemCard({
    required this.label,
    required this.weight,
    required this.rating,
    required this.enabled,
    required this.onAgentPhoto,
    required this.onChanged,
    required this.onPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final problem = rating.rating != InspectionRating.ok;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: switch (rating.rating) {
            InspectionRating.ok => AppColors.border,
            InspectionRating.partial => AppColors.orange,
            InspectionRating.failed => AppColors.red,
          },
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                'poids $weight',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
          if (onAgentPhoto != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onAgentPhoto,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: const Text('Photo de l’agent'),
              ),
            ),
          const SizedBox(height: 6),
          SegmentedButton<InspectionRating>(
            segments: [
              for (final r in InspectionRating.values)
                ButtonSegment(value: r, label: Text(r.label)),
            ],
            selected: {rating.rating},
            showSelectedIcon: false,
            onSelectionChanged: enabled
                ? (v) {
                    rating.rating = v.first;
                    onChanged();
                  }
                : null,
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            child: !problem
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          initialValue: rating.comment,
                          enabled: enabled,
                          maxLength: 200,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Ce qui ne va pas',
                            counterText: '',
                          ),
                          onChanged: (v) {
                            rating.comment = v;
                            onChanged();
                          },
                        ),
                        if (rating.photo != null) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              rating.photo!,
                              height: 120,
                              fit: BoxFit.cover,
                              semanticLabel: 'Photo du point $label',
                            ),
                          ),
                        ],
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: enabled ? () => onPhoto(true) : null,
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: Text(
                                rating.photo == null ? 'Photo' : 'Reprendre',
                              ),
                            ),
                            TextButton.icon(
                              onPressed: enabled ? () => onPhoto(false) : null,
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text('Galerie'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
