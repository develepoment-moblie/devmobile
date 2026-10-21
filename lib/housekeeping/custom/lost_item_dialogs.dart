import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/custom/app_theme.dart';
import '../models/hotel_data.dart';
import '../models/lost_item.dart';
import 'draft_guard.dart';

// "Prévenir le client": logs the attempt (date, channel, message). The guest's
// phone and e-mail are not shared with housekeeping, so the call or message
// is made outside the app. Returns true once saved.
class NotifyOwnerDialog extends StatefulWidget {
  final HotelData data;
  final LostItem item;
  const NotifyOwnerDialog({super.key, required this.data, required this.item});
  @override
  State<NotifyOwnerDialog> createState() => _NotifyOwnerDialogState();
}

class _NotifyOwnerDialogState extends State<NotifyOwnerDialog> {
  final _form = GlobalKey<FormState>();
  late final _message = TextEditingController(
    text:
        'Bonjour, nous avons retrouvé « ${widget.item.description} » dans la chambre ${widget.item.roomNumber}. L’objet vous attend à l’hôtel Nova Paris.',
  );
  ContactChannel? _channel;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final valid = _form.currentState!.validate();
    if (_channel == null) {
      setState(() => _error = 'Choisissez comment le client a été prévenu.');
      return;
    }
    if (!valid) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.data.notifyOwner(
        widget.item,
        _channel!,
        _message.text.trim(),
      );
      if (!mounted) return;
      _channel = null;
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
    dirty: _channel != null,
    busy: _busy,
    child: AlertDialog(
      scrollable: true,
      title: const Text('Prévenir le client'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Les coordonnées du client ne sont pas transmises au module ménage. Contactez-le par la réception, puis enregistrez la tentative ici.',
              style: TextStyle(color: AppColors.muted, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in ContactChannel.values)
                  ChoiceChip(
                    label: Text(c.label),
                    selected: _channel == c,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() {
                            _channel = c;
                            _error = null;
                          }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _message,
              enabled: !_busy,
              maxLength: 500,
              maxLines: 5,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Message'),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Saisissez le message envoyé.'
                  : null,
            ),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.red),
                ),
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
          child: const Text('Enregistrer la tentative'),
        ),
      ],
    ),
  );
}

// The number of days after which an unclaimed item is archived.
class ArchiveDelayDialog extends StatefulWidget {
  final HotelData data;
  const ArchiveDelayDialog({super.key, required this.data});
  @override
  State<ArchiveDelayDialog> createState() => _ArchiveDelayDialogState();
}

class _ArchiveDelayDialogState extends State<ArchiveDelayDialog> {
  final _form = GlobalKey<FormState>();
  late final _days = TextEditingController(
    text: '${widget.data.lostArchiveDays}',
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.data.setLostArchiveDays(int.parse(_days.text.trim()));
      if (!mounted) return;
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
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Archivage automatique'),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Les objets ni remis ni réclamés passent dans les archives après ce délai.',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _days,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Délai',
              suffixText: 'jours',
            ),
            validator: (v) {
              final days = int.tryParse(v?.trim() ?? '');
              return days == null || days < 7 || days > 365
                  ? 'De 7 à 365 jours.'
                  : null;
            },
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.red)),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: const Text('Enregistrer'),
      ),
    ],
  );
}
