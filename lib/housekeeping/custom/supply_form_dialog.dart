import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../models/hotel_data.dart';
import '../models/supply.dart';
import '../screens/barcode_scan_screen.dart';
import '../screens/minibar_catalog_screen.dart' show ProductFound;
import '../services/product_lookup.dart';
import 'draft_guard.dart';

// Creates a stock item, or edits the name, unit and minimum of [supply].
// Quantities change only through stock movements. Returns true once saved.
// A new item can be filled in by scanning its barcode: Open Beauty Facts
// (guest amenities) first, then Open Food Facts (minibar).
class SupplyFormDialog extends StatefulWidget {
  final HotelData data;
  final Supply? supply;

  /// Replaceable in tests (no camera, no network).
  final ScanBarcode scan;
  final ProductLookup? lookup;
  const SupplyFormDialog({
    super.key,
    required this.data,
    this.supply,
    this.scan = scanProductBarcode,
    this.lookup,
  });
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
  late String _category = widget.supply?.category ?? 'entretien';
  late final _price = TextEditingController(
    text: widget.supply?.priceCents == null
        ? ''
        : centsText(widget.supply!.priceCents!),
  );
  bool _busy = false;
  String? _error;
  late final _lookup = widget.lookup ?? ProductLookup();
  ProductInfo? _found;
  String? _note;
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
    _price.dispose();
    if (widget.lookup == null) _lookup.close();
    super.dispose();
  }

  // Scan the barcode; a sheet found sets the name and the type.
  Future<void> _scan() async {
    final code = await widget.scan(context);
    if (code == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _note = null;
    });
    try {
      final product = await _lookup.find(
        code,
        sources: const [ProductSource.beauty, ProductSource.food],
      );
      if (!mounted) return;
      setState(() {
        _found = product;
        if (product == null) {
          _note = 'Produit $code introuvable : saisissez-le à la main.';
          return;
        }
        _name.text = product.label;
        final amenity = product.source == ProductSource.beauty;
        _category = amenity ? 'accueil' : 'minibar';
        if (_unit.text.trim().isEmpty) {
          _unit.text = amenity ? 'flacons' : 'unités';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
          category: _category,
          priceCents: _category == 'minibar' ? parseEuros(_price.text) : null,
        );
      } else {
        await widget.data.createSupply(
          name: _name.text.trim(),
          unit: _unit.text.trim(),
          quantity: int.parse(_quantity.text.trim()),
          minimum: int.parse(_minimum.text.trim()),
          category: _category,
          priceCents: _category == 'minibar' ? parseEuros(_price.text) : null,
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
            if (!_editing) ...[
              OutlinedButton.icon(
                onPressed: _busy ? null : _scan,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scanner le code-barres'),
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _note!,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (_found != null) ProductFound(_found!),
              const SizedBox(height: 8),
            ],
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
            DropdownButtonFormField<String>(
              key: ValueKey(_category),
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final e in supplyTypeLabels.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _category = v ?? _category),
            ),
            if (_category == 'minibar') ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _price,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Prix de vente',
                  suffixText: '€',
                  hintText: '4,50',
                ),
                validator: (v) {
                  final cents = parseEuros(v ?? '');
                  return cents == null || cents < 1 || cents > 100000
                      ? 'Prix de 0,01 à 1 000 €.'
                      : null;
                },
              ),
            ],
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
