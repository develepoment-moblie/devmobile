import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/custom/app_theme.dart';
import '../custom/draft_guard.dart';
import '../custom/housekeeping_widgets.dart';
import '../models/catalog_data.dart';
import '../models/supply.dart';
import '../services/room_catalog_backend.dart';

// The Manager's minibar catalog: items and sale prices.
class MinibarCatalogScreen extends StatelessWidget {
  final CatalogData catalog;
  const MinibarCatalogScreen({super.key, required this.catalog});

  Future<void> _edit(BuildContext context, [Supply? item]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MinibarItemDialog(catalog: catalog, item: item),
    );
    if (context.mounted && saved == true) {
      showFeedback(
        context,
        item == null ? 'Article ajouté au minibar' : 'Article mis à jour',
      );
    }
  }

  Future<void> _delete(BuildContext context, Supply item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Retirer « ${item.name} » ?'),
        content: const Text(
          'Les consommations déjà enregistrées gardent leur prix.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await catalog.change(RoomCatalogAction.deleteMinibarItem, {
        'id': item.id,
        'version': item.version,
      });
      if (context.mounted) showFeedback(context, 'Article retiré');
    } catch (e) {
      if (context.mounted) showFeedback(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: catalog,
    builder: (context, _) {
      final items = catalog.snapshot?.minibarItems ?? const <Supply>[];
      return Scaffold(
        appBar: AppBar(title: const Text('Carte du minibar')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(context),
          icon: const Icon(Icons.add),
          label: const Text('Nouvel article'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 96),
          children: [
            if (items.isEmpty)
              const EmptyState(
                'Carte vide',
                'Ajoutez les boissons et en-cas proposés dans les chambres.',
              ),
            for (final item in items)
              Card(
                color: Colors.white,
                elevation: 0,
                child: ListTile(
                  leading: const Icon(Icons.local_bar_outlined),
                  title: Text(item.name),
                  subtitle: Text(
                    '${euros(item.priceCents ?? 0)} · ${item.quantity} ${item.unit} en réserve',
                  ),
                  onTap: () => _edit(context, item),
                  trailing: IconButton(
                    tooltip: 'Retirer ${item.name}',
                    onPressed: () => _delete(context, item),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

// Creates or edits a minibar item. Returns true once saved.
class MinibarItemDialog extends StatefulWidget {
  final CatalogData catalog;
  final Supply? item;
  const MinibarItemDialog({super.key, required this.catalog, this.item});
  @override
  State<MinibarItemDialog> createState() => _MinibarItemDialogState();
}

class _MinibarItemDialogState extends State<MinibarItemDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _unit = TextEditingController(text: widget.item?.unit ?? 'unités');
  late final _price = TextEditingController(
    text: widget.item?.priceCents == null
        ? ''
        : centsText(widget.item!.priceCents!),
  );
  final _quantity = TextEditingController();
  late final _minimum = TextEditingController(
    text: '${widget.item?.minimum ?? 5}',
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _unit, _price, _quantity, _minimum]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.catalog.change(RoomCatalogAction.saveMinibarItem, {
        if (widget.item != null) 'id': widget.item!.id,
        if (widget.item != null) 'version': widget.item!.version,
        'name': _name.text.trim(),
        'unit': _unit.text.trim(),
        'priceCents': parseEuros(_price.text),
        'minimum': int.parse(_minimum.text.trim()),
        if (widget.item == null) 'quantity': int.parse(_quantity.text.trim()),
      });
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

  String? _count(String? v) {
    final n = int.tryParse(v?.trim() ?? '');
    return n == null || n < 0 || n > 1000000
        ? 'Nombre de 0 à 1 000 000.'
        : null;
  }

  @override
  Widget build(BuildContext context) => DraftGuard(
    dirty: false,
    busy: _busy,
    child: AlertDialog(
      scrollable: true,
      title: Text(
        widget.item == null ? 'Nouvel article' : 'Modifier l’article',
      ),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColors.red)),
            TextFormField(
              controller: _name,
              enabled: !_busy,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Article'),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Renseignez l’article.'
                  : null,
            ),
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
            const SizedBox(height: 8),
            TextFormField(
              controller: _unit,
              enabled: !_busy,
              maxLength: 20,
              decoration: const InputDecoration(labelText: 'Unité'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Renseignez l’unité.' : null,
            ),
            if (widget.item == null)
              TextFormField(
                controller: _quantity,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'En réserve'),
                validator: _count,
              ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _minimum,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Seuil d’alerte'),
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
          child: Text(widget.item == null ? 'Ajouter' : 'Enregistrer'),
        ),
      ],
    ),
  );
}
