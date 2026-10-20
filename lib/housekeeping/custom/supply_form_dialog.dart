import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../models/hotel_data.dart';
import '../models/supply.dart';
import 'draft_guard.dart';

// Creates a stock item, or edits the name, unit and minimum of [supply].
// Quantities change only through stock movements. Returns true once saved.
class SupplyFormDialog extends StatefulWidget {
  final HotelData data;
  final Supply? supply;
  const SupplyFormDialog({super.key, required this.data, this.supply});
  @override
  State<SupplyFormDialog> createState() => _SupplyFormDialogState();
}

class _SupplyFormDialogState extends State<SupplyFormDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.supply?.name ?? '');
  late final _unit = TextEditingController(text: widget.supply?.unit ?? '');
  final _quantity = TextEditingController();
  late final _minimum = TextEditingController(
    text: widget.supply == null ? '' : '${widget.supply!.minimum}',
  );
  late final int? _version = widget.supply?.version;
  bool _busy = false;
  String? _error;
  bool get _editing => widget.supply != null;
  bool get _dirty =>
      _name.text != (widget.supply?.name ?? '') ||
      _unit.text != (widget.supply?.unit ?? '') ||
      _quantity.text.isNotEmpty ||
      _minimum.text !=
          (widget.supply == null ? '' : '${widget.supply!.minimum}');

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _quantity.dispose();
    _minimum.dispose();
    super.dispose();
  }

  String? _count(String? v) {
    final n = int.tryParse(v?.trim() ?? '');
    return n == null || n < 0 || n > 1000000
        ? 'Nombre de 0 à 1 000 000.'
        : null;
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_editing) {
        await widget.data.updateSupply(
          widget.supply!,
          name: _name.text.trim(),
          unit: _unit.text.trim(),
          minimum: int.parse(_minimum.text.trim()),
          version: _version,
        );
      } else {
        await widget.data.createSupply(
          name: _name.text.trim(),
          unit: _unit.text.trim(),
          quantity: int.parse(_quantity.text.trim()),
          minimum: int.parse(_minimum.text.trim()),
        );
      }
      if (!mounted) return;
      _name.clear();
      _unit.clear();
      _quantity.clear();
      _minimum.clear();
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
    dirty: _dirty,
    busy: _busy,
    child: AlertDialog(
      scrollable: true,
      title: Text(_editing ? 'Modifier l’article' : 'Nouvel article'),
      content: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
              controller: _name,
              enabled: !_busy,
              autofocus: !_editing,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Article',
                hintText: 'Draps, serviettes, nettoyant…',
              ),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Renseignez l’article.'
                  : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _unit,
              enabled: !_busy,
              maxLength: 20,
              decoration: const InputDecoration(
                labelText: 'Unité',
                hintText: 'pièces, litres, flacons…',
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Renseignez l’unité.' : null,
            ),
            const SizedBox(height: 8),
            if (!_editing) ...[
              TextFormField(
                controller: _quantity,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantité en stock',
                ),
                validator: _count,
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _minimum,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Seuil d’alerte',
                helperText: 'Une alerte est envoyée à ce niveau.',
              ),
              validator: _count,
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
          child: Text(_editing ? 'Enregistrer' : 'Ajouter'),
        ),
      ],
    ),
  );
}
