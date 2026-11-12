import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../custom/draft_guard.dart';
import '../services/app_exception.dart';
import '../models/hotel_data.dart';
import '../models/room.dart';
import '../services/task_photo_picker.dart';

class TaskPhotoScreen extends StatefulWidget {
  final HotelData data;
  final Room room;
  final RoomTask task;
  final TaskPhotoPicker? picker;
  const TaskPhotoScreen({
    super.key,
    required this.data,
    required this.room,
    required this.task,
    this.picker,
  });
  @override
  State<TaskPhotoScreen> createState() => _TaskPhotoScreenState();
}

class _TaskPhotoScreenState extends State<TaskPhotoScreen> {
  late final _picker = widget.picker ?? NativeTaskPhotoPicker();
  late int _version = widget.room.version;
  Uint8List? _photo;
  String? _error, _notice;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _recover();
  }

  String _message(Object error) => error is AppServiceException
      ? error.message
      : 'Impossible d’ouvrir la photo. Vérifiez les autorisations de Nova Paris dans les paramètres du téléphone, puis réessayez.';
  Future<void> _recover() async {
    setState(() => _busy = true);
    try {
      final photo = await _picker.recover();
      if (mounted && photo != null) {
        setState(() {
          _photo = photo;
          _notice = 'Photo récupérée après interruption. Vérifiez qu’elle correspond à cette tâche avant de confirmer.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(bool camera) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final photo = await _picker.pick(camera: camera);
      if (mounted) {
        setState(() {
          if (photo != null) {
            _photo = photo;
          } else {
            _notice = 'Sélection annulée. La tâche n’a pas été modifiée.';
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _photo == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.data.completeTask(
        widget.room,
        widget.task.id,
        _photo!,
        _version,
      );
      if (!mounted) return;
      // The image and checkbox have committed together; no draft remains.
      setState(() {
        _photo = null;
        _busy = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.data.refresh();
      if (mounted) {
        setState(() {
          _version = widget.room.version;
          _error = null;
          _notice = 'Chambre actualisée. Vérifiez la tâche et sa photo avant de confirmer à nouveau.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DraftGuard(
    dirty: _photo != null,
    busy: _busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Photo de la tâche')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            'Chambre ${widget.room.number}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            widget.task.label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const Text(
            'Une photo est obligatoire pour terminer cette tâche. Photographiez le résultat ou choisissez une image de votre galerie.',
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(
              semanticsLabel: 'Traitement de la photo en cours',
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : _refresh,
              child: const Text('Actualiser la chambre'),
            ),
          ],
          if (_notice != null) ...[
            const SizedBox(height: 12),
            Semantics(liveRegion: true, child: Text(_notice!)),
          ],
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _pick(true),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Prendre une photo'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _pick(false),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Choisir dans la galerie'),
          ),
          if (_photo != null) ...[
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(
                _photo!,
                height: 280,
                fit: BoxFit.contain,
                semanticLabel: 'Photo proposée pour ${widget.task.label}',
                errorBuilder: (_, _, _) => const Text(
                  'Cette photo ne peut pas être affichée. Choisissez une autre image.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'La photo sera enregistrée sur cet appareil et visible par la gouvernante.',
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy || _photo == null ? null : _save,
            child: const Text('Enregistrer la photo et terminer la tâche'),
          ),
        ],
      ),
    ),
  );
}

class TaskPhotoViewer extends StatefulWidget {
  final HotelData data;
  final Room room;
  final RoomTask task;
  const TaskPhotoViewer({
    super.key,
    required this.data,
    required this.room,
    required this.task,
  });
  @override
  State<TaskPhotoViewer> createState() => _TaskPhotoViewerState();
}

class _TaskPhotoViewerState extends State<TaskPhotoViewer> {
  late Future<Uint8List> _photo = widget.data.taskPhoto(
    widget.room,
    widget.task,
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Chambre ${widget.room.number} · Photo')),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          widget.task.label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 20),
        FutureBuilder<Uint8List>(
          future: _photo,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Column(
                children: [
                  Text(snapshot.error.toString()),
                  TextButton(
                    onPressed: () => setState(
                      () => _photo = widget.data.taskPhoto(
                        widget.room,
                        widget.task,
                      ),
                    ),
                    child: const Text('Réessayer'),
                  ),
                ],
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return SizedBox(
              height: 440,
              child: InteractiveViewer(
                child: Image.memory(
                  snapshot.data!,
                  fit: BoxFit.contain,
                  semanticLabel: 'Photo justificative : ${widget.task.label}',
                  errorBuilder: (_, _, _) => const Text('Photo illisible.'),
                ),
              ),
            );
          },
        ),
      ],
    ),
  );
}
