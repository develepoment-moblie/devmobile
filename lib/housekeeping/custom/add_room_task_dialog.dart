import 'package:flutter/material.dart';

import '../../shared/custom/draft_guard.dart';
import '../models/hotel_data.dart';
import '../models/room.dart';

class AddRoomTaskDialog extends StatefulWidget {
  final HotelData data;
  final Room room;
  const AddRoomTaskDialog({super.key, required this.data, required this.room});
  @override
  State<AddRoomTaskDialog> createState() => _AddRoomTaskDialogState();
}

class _AddRoomTaskDialogState extends State<AddRoomTaskDialog> {
  final _form = GlobalKey<FormState>();
  final _label = TextEditingController();
  late int _version = widget.room.version;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.data.addRoomTask(
        widget.room,
        _label.text,
        version: _version,
      );
      if (!mounted) return;
      setState(() {
        _label.clear();
        _busy = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DraftGuard(
    dirty: _label.text.isNotEmpty,
    busy: _busy,
    child: AlertDialog(
      scrollable: true,
      title: Text('Ajouter une tâche · ${widget.room.number}'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cette tâche sera ajoutée à la checklist de cette chambre et nécessitera une photo.',
            ),
            const SizedBox(height: 12),
            Text(
              widget.room.status == RoomStatus.ready
                  ? 'La chambre redeviendra à nettoyer. Toutes ses tâches devront être effectuées à nouveau.'
                  : widget.room.cleaning == CleaningStatus.review
                  ? 'Le nettoyage sera rouvert pour permettre à l’agent d’effectuer la nouvelle tâche avant validation.'
                  : widget.room.status != RoomStatus.dirty
                  ? 'La tâche sera à effectuer au prochain nettoyage. Le statut actuel de la chambre est conservé.'
                  : 'Les contrôles déjà réalisés sont conservés.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _label,
              enabled: !_busy,
              autofocus: true,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Tâche à effectuer',
                hintText: 'Ex. Nettoyer les vitres',
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Décrivez la tâche à effectuer.'
                  : null,
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          await widget.data.refresh();
                          if (mounted) {
                            setState(() {
                              _version = widget.room.version;
                              _error = null;
                            });
                          }
                        } catch (e) {
                          if (mounted) setState(() => _error = e.toString());
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                child: const Text('Actualiser avant de réessayer'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.maybePop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Ajouter la tâche'),
        ),
      ],
    ),
  );
}
