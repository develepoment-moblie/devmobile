import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../custom/draft_guard.dart';
import '../custom/housekeeping_widgets.dart';
import '../custom/voice_note_recorder.dart';
import '../models/hotel_data.dart';
import '../models/issue.dart';
import '../models/room.dart';
import '../services/task_photo_picker.dart';
import '../services/voice_notes.dart';

// Reports a broken item of [room]: category, description, priority, photos,
// optional voice note, and optionally takes the room out of service.
// Returns true once saved.
class ReportIssueScreen extends StatefulWidget {
  final HotelData data;
  final Room room;
  const ReportIssueScreen({super.key, required this.data, required this.room});
  @override
  State<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends State<ReportIssueScreen> {
  final _form = GlobalKey<FormState>();
  final _description = TextEditingController();
  late final TaskPhotoPicker _picker = widget.data.createPhotoPicker();
  late final VoiceNotes _voice = widget.data.createVoiceNotes();
  IssueCategory? _category;
  var _priority = IssuePriority.normal;
  bool _outOfService = false, _busy = false, _sent = false;
  final _photos = <Uint8List>[];
  String? _voicePath, _error;
  int _voiceSeconds = 0;

  @override
  void dispose() {
    _description.dispose();
    // A note recorded for a report that was not sent is not kept.
    if (!_sent && _voicePath != null) unawaited(_voice.delete(_voicePath!));
    _voice.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _description.text.isNotEmpty ||
      _category != null ||
      _photos.isNotEmpty ||
      _voicePath != null;

  Future<void> _pick(bool camera) async {
    try {
      final photo = await _picker.pick(camera: camera);
      if (photo != null && mounted) setState(() => _photos.add(photo));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final valid = _form.currentState!.validate();
    if (_category == null) {
      setState(() => _error = 'Choisissez une catégorie.');
      return;
    }
    if (!valid) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.data.reportIssue(
        widget.room,
        category: _category!,
        description: _description.text.trim(),
        priority: _priority,
        outOfService: _outOfService,
        photos: _photos,
        voicePath: _voicePath,
        voiceSeconds: _voicePath == null ? null : _voiceSeconds,
      );
      _sent = true;
      if (!mounted) return;
      _description.clear();
      _photos.clear();
      _category = null;
      _voicePath = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _title(String text) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final canStop = widget.data.canTakeOutOfService(room);
    return DraftGuard(
      dirty: _dirty,
      busy: _busy,
      child: Scaffold(
        appBar: AppBar(title: Text('Signaler un problème · ${room.number}')),
        body: Form(
          key: _form,
          onChanged: () => setState(() {}),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
            children: [
              if (_busy) const LinearProgressIndicator(),
              const Text(
                'La gouvernante et la maintenance sont prévenues dès l’envoi.',
                style: TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
              _title('Catégorie'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in IssueCategory.values)
                    ChoiceChip(
                      avatar: Icon(c.icon, size: 18),
                      label: Text(c.label),
                      selected: _category == c,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                              _category = c;
                              _error = null;
                            }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                enabled: !_busy,
                maxLength: 300,
                maxLines: 4,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Fuite sous le lavabo, ampoule grillée…',
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Décrivez le problème.'
                    : null,
              ),
              _title('Priorité'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in IssuePriority.values)
                    ChoiceChip(
                      label: Text(p.label),
                      selected: _priority == p,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() => _priority = p),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _outOfService && canStop,
                onChanged: _busy || !canStop
                    ? null
                    : (v) => setState(() => _outOfService = v),
                title: const Text('Mettre la chambre hors service'),
                subtitle: Text(switch (room.status) {
                  RoomStatus.occupied =>
                    'Chambre occupée : elle reste au client pendant le séjour.',
                  RoomStatus.maintenance => 'La chambre est déjà hors service.',
                  _ =>
                    'Elle passe en maintenance et sort du planning de ménage.',
                }, style: const TextStyle(fontSize: 12)),
              ),
              _title('Photos (${_photos.length}/$maxIssuePhotos)'),
              if (_photos.isNotEmpty)
                SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _photos.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            _photos[i],
                            width: 96,
                            height: 96,
                            fit: BoxFit.cover,
                            semanticLabel: 'Photo ${i + 1} du problème',
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: IconButton.filledTonal(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Retirer la photo ${i + 1}',
                            onPressed: _busy
                                ? null
                                : () => setState(() => _photos.removeAt(i)),
                            icon: const Icon(Icons.close, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_photos.length < maxIssuePhotos)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _pick(true),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Photo'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _pick(false),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Galerie'),
                      ),
                    ],
                  ),
                ),
              _title('Note vocale (facultatif)'),
              VoiceNoteRecorder(
                voice: _voice,
                enabled: !_busy,
                onChanged: (path, seconds) => setState(() {
                  _voicePath = path;
                  _voiceSeconds = seconds;
                }),
              ),
              const SizedBox(height: 20),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.red),
                    ),
                  ),
                ),
              NovaButton(
                'Envoyer le signalement',
                onPressed: _busy ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
