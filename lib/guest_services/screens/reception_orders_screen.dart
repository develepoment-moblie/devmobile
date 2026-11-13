import 'service_room_screen.dart';
import 'service_desk_screen.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../shared/custom/app_theme.dart';
import '../../shared/custom/app_widgets.dart';
import '../../shared/services/app_session.dart';
import '../models/room_service.dart';
import '../models/order_insights.dart';
import '../../shared/models/app_user.dart';
import 'menu_management_screen.dart';
import '../services/guest_service_store.dart';

class ReceptionOrdersScreen extends StatefulWidget {
  final AppSession session;
  const ReceptionOrdersScreen({super.key, required this.session});
  @override
  State<ReceptionOrdersScreen> createState() => _ReceptionOrdersScreenState();
}

class _ReceptionOrdersScreenState extends State<ReceptionOrdersScreen> {
  late final store = GuestServiceStore(widget.session);
  List<Map<String, Object?>> orders = [];
  String filter = 'À traiter';
  Timer? clock;
  @override
  void dispose() {
    clock?.cancel();
    super.dispose();
  }

  bool loading = true, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
    clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && !busy) load();
    });
  }

  Future<void> load() async {
    try {
      final result = await store.receptionOrders();
      if (mounted) {
        setState(() {
          orders = result;
          loading = false;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Impossible de charger les commandes.';
        });
      }
    }
  }

  Future<void> change(Map<String, Object?> order, String next) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final id = order['id'] as int;
      final status = order['status'] as String;
      if (next == 'cancelled') {
        final reason = await serviceText(
          context,
          'Motif d’annulation',
          max: 250,
        );
        if (reason == null || reason.trim().isEmpty || !mounted) return;
        final confirmed = await serviceConfirm(
          context,
          'Annuler la commande ?',
          'Commande #$id',
        );
        if (!confirmed || !mounted) return;
        await store.transition(id, status, next, reason: reason);
      } else {
        final agents = await store.deliverySuggestions(id);
        if (!mounted) return;
        if (agents.isEmpty) {
          showFeedback(
            context,
            'Aucun agent d’étage disponible dans l’annuaire.',
          );
          return;
        }
        final agent = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(
              next == 'preparing'
                  ? 'Accepter et attribuer'
                  : 'Attribuer la livraison',
            ),
            children: [
              for (final (index, suggestion) in agents.indexed)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, suggestion.agent.id),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(suggestion.agent.fullName),
                      Text(
                        '${index == 0 ? 'Recommandé · ' : ''}${suggestion.activeDeliveries} livraison(s) en cours',
                      ),
                    ],
                  ),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Text(
                  'Suggestion selon les livraisons attribuées. Vérifiez la disponibilité de l’agent.',
                ),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context),
                child: const Text('Revenir'),
              ),
            ],
          ),
        );
        if (agent == null || !mounted) return;
        if (next == 'preparing') {
          await store.transition(id, status, next, agentId: agent);
        } else {
          await store.assignDelivery(
            id,
            status,
            order['delivery_agent_id'] as String?,
            agent,
          );
        }
      }
      await load();
    } on StateError catch (e) {
      if (mounted) showFeedback(context, e.message);
      await load();
    } catch (_) {
      if (mounted) showFeedback(context, 'Modification impossible. Réessayez.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> timeline(int id) async {
    try {
      final events = await store.history(id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        builder: (_) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Historique #$id',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (events.isEmpty)
              const Text('Ancienne commande : aucun historique disponible.'),
            for (final event in events)
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(
                  orderStatusLabels[event['status']] ?? '${event['status']}',
                ),
                subtitle: Text(
                  '${event['created_at']} · ${event['actor_id']}${event['reason'] == null ? '' : '\n${event['reason']}'}',
                ),
              ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) showFeedback(context, 'Historique indisponible.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = orders.where((order) {
      final status = order['status'];
      return switch (filter) {
        'En retard' => OrderInsights.overdue(order, DateTime.now()),
        'À traiter' => nextOrderStatus.containsKey(status),
        'En attente' => status == 'placed',
        'En cours' => GuestServiceStore.deliveryStatuses.contains(status),
        'Terminées' => ['delivered', 'rejected', 'cancelled'].contains(status),
        _ => true,
      };
    }).toList();
    final now = DateTime.now();
    visible.sort((a, b) {
      final activeA = OrderInsights.active.contains(a['status']);
      final activeB = OrderInsights.active.contains(b['status']);
      if (activeA != activeB) return activeA ? -1 : 1;
      if (!activeA) {
        DateTime finishedAt(Map<String, Object?> order) =>
            DateTime.tryParse('${order['delivered_at']}') ??
            DateTime.tryParse('${order['created_at']}') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final recent = finishedAt(b).compareTo(finishedAt(a));
        return recent != 0
            ? recent
            : (b['id'] as int).compareTo(a['id'] as int);
      }
      final urgent =
          (OrderInsights.overdue(b, now) ? 1 : 0) -
          (OrderInsights.overdue(a, now) ? 1 : 0);
      return urgent != 0
          ? urgent
          : '${a['created_at']}'.compareTo('${b['created_at']}');
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('Réception · Room service'),
        actions: [
          IconButton(
            tooltip: 'Chambres des clients',
            icon: const Icon(Icons.meeting_room_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ServiceRoomScreen(store: store),
              ),
            ),
          ),

          IconButton(
            tooltip: 'Services et réservations',
            icon: const Icon(Icons.room_service_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ServiceDeskScreen(session: widget.session),
              ),
            ),
          ),

          if (widget.session.user?.hasAnyRole({
                AppRole.manager,
                AppRole.admin,
              }) ??
              false)
            IconButton(
              tooltip: 'Gérer la carte',
              icon: const Icon(Icons.restaurant_menu),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MenuManagementScreen(session: widget.session),
                ),
              ),
            ),

          IconButton(
            tooltip: 'Actualiser',
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: TextButton(
                onPressed: load,
                child: Text('$error Réessayer'),
              ),
            )
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Text(
                    'Le service en un regard',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Suivi des commandes et délais de service. Les montants ne déclenchent pas de paiement automatique.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 16),
                  dashboard(),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final value in [
                        'À traiter',
                        'En attente',
                        'En cours',
                        'En retard',
                        'Terminées',
                        'Toutes',
                      ])
                        ChoiceChip(
                          label: Text(value),
                          selected: filter == value,
                          onSelected: (_) => setState(() => filter = value),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (visible.isEmpty)
                    const EmptyState(
                      'Tout est à jour',
                      'Aucune commande dans cette catégorie.',
                    ),
                  for (final order in visible)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Commande #${order['id']} · ${euros(order['total_cents'] as int)}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${order['guest_name'] ?? order['guest_id']} · Chambre ${order['room_number'] ?? 'non associée'}',
                              ),
                              Text(
                                order['stay_id'] == null
                                    ? 'Ancienne commande sans séjour — annulation uniquement'
                                    : 'Référence séjour : ${order['stay_id']}',
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                '${order['created_at']}'
                                    .replaceFirst('T', ' ')
                                    .split('.')
                                    .first,
                                style: const TextStyle(color: AppColors.muted),
                              ),
                              Chip(
                                label: Text(
                                  orderStatusLabels[order['status']] ??
                                      '${order['status']}',
                                ),
                              ),
                              if (order['delivered_by_name'] != null)
                                Text(
                                  'Livrée par ${order['delivered_by_name']} · ${serviceDate(order['delivered_at'])}',
                                )
                              else if (order['delivery_agent_name'] != null)
                                Text('Agent : ${order['delivery_agent_name']}'),
                              if (OrderInsights.active.contains(
                                order['status'],
                              ))
                                Text(
                                  '${OrderInsights.age(order, DateTime.now())} min écoulées · ${OrderInsights.overdue(order, DateTime.now()) ? "À traiter en priorité" : (order['status'] != 'placed' && OrderInsights.target(order) == null ? "Estimation indisponible" : "Dans le délai indicatif")}',
                                  style: TextStyle(
                                    color:
                                        OrderInsights.overdue(
                                          order,
                                          DateTime.now(),
                                        )
                                        ? AppColors.red
                                        : AppColors.muted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              for (final line
                                  in jsonDecode(order['lines'] as String)
                                      as List)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${line['quantity']} × ${line['name']} · ${euros((line['quantity'] as int) * (line['priceCents'] as int))}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if ((line['note'] as String).isNotEmpty)
                                        Text('Note : ${line['note']}'),
                                    ],
                                  ),
                                ),
                              if (order['reason'] != null)
                                Text(
                                  'Motif : ${order['reason']}',
                                  style: const TextStyle(color: AppColors.red),
                                ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 8,
                                children: [
                                  if (order['stay_id'] != null &&
                                      order['status'] == 'placed')
                                    FilledButton(
                                      onPressed: busy
                                          ? null
                                          : () => change(order, 'preparing'),
                                      child: const Text('Accepter'),
                                    ),
                                  if (order['stay_id'] != null &&
                                      GuestServiceStore.deliveryStatuses
                                          .contains(order['status']) &&
                                      order['delivery_agent_id'] == null)
                                    OutlinedButton(
                                      onPressed: busy
                                          ? null
                                          : () => change(order, 'assigned'),
                                      child: const Text('Attribuer un agent'),
                                    ),
                                  if (nextOrderStatus.containsKey(
                                    order['status'],
                                  ))
                                    PopupMenuButton<String>(
                                      enabled: !busy,
                                      tooltip: 'Autres actions',
                                      onSelected: (action) =>
                                          change(order, action),
                                      itemBuilder: (_) => [
                                        if (GuestServiceStore.deliveryStatuses
                                                .contains(order['status']) &&
                                            order['delivery_agent_id'] != null)
                                          const PopupMenuItem(
                                            value: 'assigned',
                                            child: Text('Changer d’agent'),
                                          ),
                                        const PopupMenuItem(
                                          value: 'cancelled',
                                          child: Text('Annuler avec motif'),
                                        ),
                                      ],
                                    ),
                                  TextButton(
                                    onPressed: () =>
                                        timeline(order['id'] as int),
                                    child: const Text('Historique'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget dashboard() {
    final now = DateTime.now();
    final average = OrderInsights.averageDelivery(orders, now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in {
              'En attente':
                  '${orders.where((o) => o['status'] == 'placed').length}',
              'En cours':
                  '${orders.where((o) => GuestServiceStore.deliveryStatuses.contains(o['status'])).length}',
              'En retard':
                  '${orders.where((o) => OrderInsights.overdue(o, now)).length}',
              'Livraison moyenne aujourd’hui': average == null
                  ? '—'
                  : '${average.toStringAsFixed(1)} min',
            }.entries)
              Chip(label: Text('${entry.key} : ${entry.value}')),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Alertes : attente ≥ 5 min ; commande acceptée ≥ préparation maximale + 10 min depuis sa création. Estimations indicatives, sans notification externe. Anciennes commandes sans estimation : alerte d’attente uniquement.',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    );
  }
}
