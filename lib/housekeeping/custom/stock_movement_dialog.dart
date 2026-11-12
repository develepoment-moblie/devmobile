import 'package:flutter/material.dart';

import '../models/hotel_data.dart';
import '../models/supply.dart';
import '../services/app_exception.dart';
import 'draft_guard.dart';

class StockMovementDialog extends StatefulWidget {
  final HotelData data;
  final Supply supply;
  final bool receive;
  const StockMovementDialog({
    super.key,
    required this.data,
    required this.supply,
    required this.receive,
  });
  @override
  State<StockMovementDialog> createState() => _StockMovementDialogState();
}

class _StockMovementDialogState extends State<StockMovementDialog> {
  final form = GlobalKey<FormState>();
  final amount = TextEditingController();
  late int expectedVersion = widget.supply.version;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final quantity = int.parse(amount.text.trim());
      await widget.data.moveStock(
        widget.supply,
        widget.receive ? quantity : -quantity,
        version: expectedVersion,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          if (e is HousekeepingException && e.status == 409) {
            expectedVersion = widget.supply.version;
          }
        });
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => DraftGuard(
    dirty: amount.text.isNotEmpty,
    busy: saving,
    child: AlertDialog(
      scrollable: true,
      title: Text(
        widget.receive ? 'Réapprovisionner' : 'Enregistrer une utilisation',
      ),
      content: SingleChildScrollView(
        child: Form(
          key: form,
          onChanged: () => setState(() {}),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.supply.name} · ${widget.supply.quantity} ${widget.supply.unit} disponibles',
              ),
              const SizedBox(height: 16),
              if (error != null) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: amount,
                autofocus: true,
                enabled: !saving,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => save(),
                decoration: InputDecoration(
                  labelText: 'Quantité (${widget.supply.unit})',
                ),
                validator: (value) {
                  final number = int.tryParse(value?.trim() ?? '');
                  if (number == null || number <= 0) {
                    return 'Saisissez un entier positif.';
                  }
                  if (!widget.receive && number > widget.supply.quantity) {
                    return 'Quantité supérieure au stock disponible.';
                  }
                  if (number > 100000) {
                    return 'Saisissez une quantité inférieure à 100 001.';
                  }
                  if (widget.receive &&
                      widget.supply.quantity + number > 1000000) {
                    return 'Le stock ne peut pas dépasser 1 000 000.';
                  }
                  return null;
                },
              ),
              if (saving)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(
                    semanticsLabel: 'Enregistrement du stock',
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.maybePop(context),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: saving ? null : save,
          child: const Text('Enregistrer'),
        ),
      ],
    ),
  );
}
