import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../shared/custom/app_widgets.dart';
import '../models/kitchen_plan.dart';
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
  Timer? clock;

  @override
  void initState() {
    super.initState();
    clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && !busy) refresh();
    });
  }

  @override
  void dispose() {
    clock?.cancel();
    super.dispose();
  }

  void refresh() {
    setState(() {
      orders = widget.store.kitchenOrders();
    });
  }

  Future<void> updateOrder(int id, {required bool start}) async {
    if (busy) return;
    setState(() => busy = true);
    String message;
    try {
      if (start) {
        await widget.store.startPreparation(id);
        message = 'Préparation démarrée.';
      } else {
        await widget.store.markOrderReady(id);
        message = 'Commande prête à livrer.';
      }
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
        final plan = planKitchen(rows, DateTime.now());
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: plan.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Plan de préparation · une commande à la fois. Les heures sont indicatives et se recalculent avec la file.',
                ),
              );
            }
            final entry = plan[index - 1];
            final row = entry.order;
            final eta = entry.expectedReadyAt;
            final target = entry.readyTarget;
            final atRisk = eta != null && target != null && eta.isAfter(target);
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
                    if (entry.queuePosition != null) ...[
                      Text(
                        entry.startedAt != null
                            ? 'Préparation démarrée'
                            : entry.queuePosition == 1
                            ? 'À lancer en priorité'
                            : 'Position ${entry.queuePosition} dans la file',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (entry.preparationMinutes != null)
                        Text(
                          '${entry.preparationMinutes} min de préparation estimées',
                        ),
                      if (eta != null)
                        Text(
                          'Prête vers ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(eta.toLocal()))}${atRisk ? ' · objectif dépassé selon le plan' : ''}',
                        )
                      else if (entry.estimateExceeded)
                        const Text(
                          'Durée estimée dépassée · heure de fin à confirmer',
                        )
                      else if (entry.preparationMinutes == null)
                        const Text('Durée inconnue pour cette commande')
                      else
                        const Text(
                          'Heure de fin à confirmer après la commande précédente',
                        ),
                    ],
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
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (entry.canStart)
                            FilledButton(
                              onPressed: busy
                                  ? null
                                  : () => updateOrder(
                                      row['id'] as int,
                                      start: true,
                                    ),
                              child: const Text('Démarrer la préparation'),
                            ),
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => updateOrder(
                                    row['id'] as int,
                                    start: false,
                                  ),
                            child: const Text('Marquer prête à livrer'),
                          ),
                        ],
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
