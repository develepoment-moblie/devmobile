import 'package:flutter/material.dart';

import '../../shared/custom/app_widgets.dart';
import '../services/guest_service_store.dart';

class KitchenStockScreen extends StatefulWidget {
  final GuestServiceStore store;
  const KitchenStockScreen({super.key, required this.store});

  @override
  State<KitchenStockScreen> createState() => _KitchenStockScreenState();
}

class _KitchenStockScreenState extends State<KitchenStockScreen> {
  late Future<List<Map<String, Object?>>> stock = widget.store.kitchenStock();
  bool busy = false;

  void refresh() {
    setState(() {
      stock = widget.store.kitchenStock();
    });
  }

  Future<void> edit(Map<String, Object?> row) async {
    setState(() => busy = true);
    try {
      final update = await showDialog<(int, bool)>(
        context: context,
        builder: (_) => _StockDialog(row: row),
      );
      if (update == null || !mounted) return;
      await widget.store.updateStock(
        row['id'] as String,
        version: row['version'] as int,
        portions: update.$1,
        enabled: update.$2,
      );
      if (mounted) refresh();
    } on StateError catch (e) {
      if (mounted) {
        showFeedback(context, e.message);
        refresh();
      }
    } catch (_) {
      if (mounted) showFeedback(context, 'Impossible d’enregistrer le stock.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Cuisine · Stock'),
      actions: [
        IconButton(
          onPressed: busy ? null : refresh,
          tooltip: 'Actualiser',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder(
      future: stock,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: refresh,
              child: const Text('Stock indisponible. Réessayer'),
            ),
          );
        }
        final rows = snapshot.data!;
        if (rows.isEmpty) {
          return const EmptyState(
            'Aucun plat',
            'La direction doit d’abord ajouter des plats à la carte.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final row = rows[i];
            final count = row['portions'] as int;
            final status = row['available'] != 1
                ? 'En pause'
                : count == 0
                ? 'Épuisé'
                : 'Disponible';
            return Card(
              child: ListTile(
                title: Text(row['name'] as String),
                subtitle: Text(
                  '${row['category']} · $count portion(s) libre(s) · $status',
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: busy ? null : () => edit(row),
              ),
            );
          },
        );
      },
    ),
  );
}

class _StockDialog extends StatefulWidget {
  final Map<String, Object?> row;
  const _StockDialog({required this.row});

  @override
  State<_StockDialog> createState() => _StockDialogState();
}

class _StockDialogState extends State<_StockDialog> {
  final form = GlobalKey<FormState>();
  late String count = '${widget.row['portions']}';
  late bool enabled = widget.row['available'] == 1;

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.row['name'] as String),
    content: Form(
      key: form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            initialValue: count,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Portions libres'),
            onChanged: (value) => count = value,
            validator: (value) {
              final portions = int.tryParse(value?.trim() ?? '');
              return portions == null || portions < 0 || portions > 1000000
                  ? 'Saisissez un entier entre 0 et 1 000 000.'
                  : null;
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'Comptez uniquement les portions qui ne sont pas déjà réservées.',
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Autoriser les commandes'),
            value: enabled,
            onChanged: (value) => setState(() => enabled = value),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Revenir'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, (int.parse(count.trim()), enabled));
          }
        },
        child: const Text('Enregistrer'),
      ),
    ],
  );
}
