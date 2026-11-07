import 'dart:convert';

import 'package:flutter/material.dart';

import '../../shared/custom/app_widgets.dart';
import '../services/guest_service_store.dart';
import 'service_desk_screen.dart' show serviceConfirm, serviceDate;

class AgentDeliveriesScreen extends StatefulWidget {
  final GuestServiceStore store;
  const AgentDeliveriesScreen({super.key, required this.store});

  @override
  State<AgentDeliveriesScreen> createState() => _AgentDeliveriesScreenState();
}

class _AgentDeliveriesScreenState extends State<AgentDeliveriesScreen> {
  late var deliveries = widget.store.assignedDeliveries();
  bool busy = false;

  void refresh() {
    setState(() {
      deliveries = widget.store.assignedDeliveries();
    });
  }

  Future<void> deliver(int id) async {
    if (busy) return;
    setState(() => busy = true);
    String feedback;
    try {
      final confirmed = await serviceConfirm(
        context,
        'Confirmer la livraison ?',
        'Validez uniquement après avoir remis la commande #$id au client.',
      );
      if (!mounted || !confirmed) return;
      await widget.store.confirmDelivery(id);
      feedback = 'Livraison enregistrée.';
    } on StateError catch (e) {
      feedback = e.message;
    } catch (_) {
      feedback = 'Impossible d’enregistrer la livraison.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (!mounted) return;
    refresh();
    showFeedback(context, feedback);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Mes livraisons'),
      actions: [
        IconButton(
          onPressed: busy ? null : refresh,
          tooltip: 'Actualiser',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder(
      future: deliveries,
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
            'Aucune livraison',
            'Les commandes attribuées par la réception apparaîtront ici.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            for (final row in rows)
              Card(
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
                      for (final line
                          in jsonDecode(row['lines'] as String) as List)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '${line['quantity']} × ${line['name']}${(line['note'] as String? ?? '').isEmpty ? '' : '\nNote : ${line['note']}'}',
                          ),
                        ),
                      if (row['status'] == 'delivered')
                        Text('Livrée le ${serviceDate(row['delivered_at'])}')
                      else if (GuestServiceStore.readyDeliveryStatuses.contains(
                        row['status'],
                      )) ...[
                        const Text('Prête à livrer'),
                        FilledButton(
                          onPressed: busy
                              ? null
                              : () => deliver(row['id'] as int),
                          child: const Text('Marquer comme livrée'),
                        ),
                      ] else
                        const Text(
                          'En préparation · Attendez la confirmation de la cuisine.',
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
