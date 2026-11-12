import 'dart:convert';

import 'package:flutter/material.dart';

import '../../shared/custom/app_widgets.dart';
import '../models/room_service.dart';
import '../services/guest_service_store.dart';
import 'kitchen_stock_screen.dart';

class KitchenOrdersScreen extends StatefulWidget {
  final GuestServiceStore store;
  const KitchenOrdersScreen({super.key, required this.store});

  @override
  State<KitchenOrdersScreen> createState() => _KitchenOrdersScreenState();
}

class _KitchenOrdersScreenState extends State<KitchenOrdersScreen> {
  late var orders = widget.store.kitchenOrders();
  bool busy = false;

  void refresh() {
    setState(() {
      orders = widget.store.kitchenOrders();
    });
  }

  Future<void> ready(int id) async {
    if (busy) return;
    setState(() => busy = true);
    String message;
    try {
      await widget.store.markOrderReady(id);
      message = 'Commande prête à livrer.';
    } on StateError catch (e) {
      message = e.message;
    } catch (_) {
      message = 'Impossible de mettre à jour la commande.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (!mounted) return;
    refresh();
    showFeedback(context, message);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Cuisine · Commandes'),
      actions: [
        IconButton(
          onPressed: busy
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => KitchenStockScreen(store: widget.store),
                  ),
                ),
          tooltip: 'Gérer le stock',
          icon: const Icon(Icons.inventory_2_outlined),
        ),
        IconButton(
          onPressed: busy ? null : refresh,
          tooltip: 'Actualiser',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder(
      future: orders,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: refresh,
              child: const Text('Chargement impossible. Réessayer'),
            ),
          );
        }
        final rows = snapshot.data!;
        if (rows.isEmpty) {
          return const EmptyState(
            'Aucune commande',
            'Les commandes acceptées par la réception apparaîtront ici.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Commande #${row['id']} · Chambre ${row['room_number']}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Chip(
                      label: Text(
                        orderStatusLabels[row['status']] ?? '${row['status']}',
                      ),
                    ),
                    for (final line
                        in jsonDecode(row['lines'] as String) as List)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          '${line['quantity']} × ${line['name']}${(line['note'] as String? ?? '').isEmpty ? '' : '\nNote : ${line['note']}'}',
                        ),
                      ),
                    if (row['status'] != 'ready') ...[
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: busy ? null : () => ready(row['id'] as int),
                        child: const Text('Marquer prête à livrer'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
