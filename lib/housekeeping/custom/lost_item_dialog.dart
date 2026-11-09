import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../models/hotel_data.dart';
import '../models/room.dart';
import '../services/task_photo_picker.dart';
import 'draft_guard.dart';

// Records an object found in [room], with an optional photo.
class LostItemDialog extends StatefulWidget {
  final HotelData data;
  final Room room;
  final TaskPhotoPicker? picker;
  const LostItemDialog({
    super.key,
    required this.data,
    required this.room,
    this.picker,
  });
  @override
  State<LostItemDialog> createState() => _LostItemDialogState();
}

class _LostItemDialogState extends State<LostItemDialog> {
  final _form = GlobalKey<FormState>();
  final _description = TextEditingController();
  late final _picker = widget.picker ?? NativeTaskPhotoPicker();
  Uint8List? _photo;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _pick(bool camera) async {
    try {
      final photo = await _picker.pick(camera: camera);
      if (photo != null && mounted) setState(() => _photo = photo);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.data.recordLostItem(
        widget.room,
        _description.text.trim(),
        photo: _photo,
      );
      if (!mounted) return;
      _description.clear();
      _photo = null;
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
    dirty: _description.text.isNotEmpty || _photo != null,
    busy: _busy,
    child: AlertDialog(
      scrollable: true,
      title: Text('Objet trouvé · ${widget.room.number}'),
      content: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'La gouvernante conserve l’objet jusqu’à sa restitution.',
              style: TextStyle(color: AppColors.muted, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.red),
                ),
              ),
            TextFormField(
              controller: _description,
              enabled: !_busy,
              autofocus: true,
              maxLength: 300,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Montre dorée sur la table de nuit…',
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Décrivez l’objet.' : null,
            ),
            const SizedBox(height: 8),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              child: _photo == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.memory(
                          _photo!,
                          height: 160,
                          fit: BoxFit.cover,
                          semanticLabel: 'Photo de l’objet trouvé',
                        ),
                      ),
                    ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(true),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(_photo == null ? 'Photo' : 'Reprendre'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(false),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Galerie'),
                ),
              ],
            ),
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
          child: const Text('Enregistrer'),
        ),
      ],
    ),
  );
}
