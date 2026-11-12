import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../models/hotel_data.dart';
import '../models/room.dart';
import 'draft_guard.dart';

// Sends a problem to the maintenance module. Returns true once saved.
class ReportProblemDialog extends StatefulWidget {
  final HotelData data;
  final Room room;
  const ReportProblemDialog({
    super.key,
    required this.data,
    required this.room,
  });
  @override
  State<ReportProblemDialog> createState() => _ReportProblemDialogState();
}

class _ReportProblemDialogState extends State<ReportProblemDialog> {
  final _form = GlobalKey<FormState>();
  final _description = TextEditingController();
  bool _urgent = false, _busy = false;
  String? _error;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.data.reportProblem(
        widget.room,
        _description.text.trim(),
        _urgent,
      );
      if (!mounted) return;
      _description.clear();
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
    dirty: _description.text.isNotEmpty,
    busy: _busy,
    child: AlertDialog(
      scrollable: true,
      title: Text('Signaler un problème · ${widget.room.number}'),
      content: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.room.status == RoomStatus.occupied
                  ? 'La chambre reste occupée. La maintenance est prévenue.'
                  : 'La chambre passe en maintenance jusqu’à la fin de l’intervention.',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
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
            TextFormField(
              controller: _description,
              enabled: !_busy,
              autofocus: true,
              maxLength: 300,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Problème constaté',
                hintText: 'Climatisation, plomberie, électricité…',
              ),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Décrivez le problème.'
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _urgent,
              onChanged: _busy ? null : (v) => setState(() => _urgent = v),
              title: const Text('Urgent'),
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
          child: const Text('Signaler'),
        ),
      ],
    ),
  );
}
