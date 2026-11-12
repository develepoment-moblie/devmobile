import 'agent_deliveries_screen.dart';
import 'kitchen_orders_screen.dart';
import 'service_desk_screen.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../shared/custom/app_theme.dart';
import '../../shared/custom/app_widgets.dart';
import '../../shared/models/app_user.dart';
import '../../shared/services/app_session.dart';
import '../models/room_service.dart';
import '../services/guest_service_store.dart';
import 'reception_orders_screen.dart';

class GuestServicesHomeScreen extends StatefulWidget {
  final AppSession session;
  const GuestServicesHomeScreen({super.key, required this.session});
  @override
  State<GuestServicesHomeScreen> createState() =>
      _GuestServicesHomeScreenState();
}

class _GuestServicesHomeScreenState extends State<GuestServicesHomeScreen> {
  late final store = GuestServiceStore(widget.session);
  List<CartLine> cart = [];
  List<MenuItem> catalog = [];
  Map<String, Object?>? stay;
  List<Map<String, Object?>> orders = [];
  int tab = 0;
  String category = 'Tout', search = '';
  bool vegetarian = false, loading = true, busy = false;
  String? error;
  int get total => cart.fold(0, (sum, line) => sum + line.total);
  int get count => cart.fold(0, (sum, line) => sum + line.quantity);

  @override
  void initState() {
    super.initState();
    if (widget.session.user?.role == AppRole.guest) load();
  }

  Future<void> load() async {
    try {
      final association = await store.currentStay();
      final menu = await store.menu();
      final draft = await store.loadCart();
      final history = await store.orders();
      if (mounted) {
        setState(() {
          stay = association;
          catalog = menu;
          cart = draft;
          orders = history;
          loading = false;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Impossible de charger vos services. Réessayez.';
        });
      }
    }
  }

  Future<void> updateCart(List<CartLine> next) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await store.saveCart(next);
      if (mounted) setState(() => cart = next);
    } catch (_) {
      if (mounted) {
        showFeedback(
          context,
          'Le panier n’a pas pu être enregistré. Réessayez.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  int quantityInCart(String id) => cart.fold(
    0,
    (sum, line) => sum + (line.itemId == id ? line.quantity : 0),
  );

  bool get cartHasStockIssue => cart.any(
    (line) =>
        !line.item.available ||
        quantityInCart(line.itemId) > (line.item.portions ?? (1 << 30)),
  );

  Future<void> details(MenuItem item) async {
    final remaining = ((item.portions ?? 20) - quantityInCart(item.id)).clamp(
      0,
      20,
    );
    final selection = await showModalBottomSheet<CartLine>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ItemDetails(item: item, remaining: remaining),
    );
    if (selection == null || !mounted) return;
    if (quantityInCart(item.id) + selection.quantity >
        (item.portions ?? (1 << 30))) {
      showFeedback(context, 'La quantité dépasse le stock disponible.');
      return;
    }
    final next = [...cart];
    final index = next.indexWhere(
      (line) => line.itemId == selection.itemId && line.note == selection.note,
    );
    if (index >= 0) {
      final old = next[index];
      if (old.quantity + selection.quantity > 20) {
        showFeedback(
          context,
          'Maximum 20 exemplaires par article personnalisé.',
        );
        return;
      }
      next[index] = CartLine(
        old.itemId,
        old.quantity + selection.quantity,
        old.note,
        old.item,
      );
    } else {
      next.add(selection);
    }
    await updateCart(next);
  }

  Future<void> submit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer la commande ?'),
        content: Text(
          'Total : ${euros(total)}. Cette commande sera enregistrée sur cet appareil. Chambre ${stay?['room_number'] ?? 'non associée'}. La réception peut traiter la commande sur cet appareil. Facturation non connectée.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Revenir'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || busy || cart.isEmpty) return;
    setState(() => busy = true);
    try {
      await store.submit();
      if (!mounted) return;
      setState(() {
        cart = [];
        tab = 2;
      });
      await load();
      if (mounted) {
        showFeedback(context, 'Commande enregistrée sur cet appareil.');
      }
    } on StateError catch (e) {
      if (mounted) showFeedback(context, e.message);
    } catch (_) {
      if (mounted) {
        showFeedback(
          context,
          'Impossible d’enregistrer la commande. Vérifiez votre panier et réessayez.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.session.user?.role == AppRole.staff) {
      return AgentDeliveriesScreen(store: store);
    }
    if (widget.session.user?.role == AppRole.kitchen) {
      return KitchenOrdersScreen(store: store);
    }
    if (widget.session.user?.role != AppRole.guest) {
      return ReceptionOrdersScreen(session: widget.session);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Votre conciergerie'),
        actions: [
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

          IconButton(
            tooltip: 'Actualiser',
            onPressed: busy || loading
                ? null
                : () {
                    setState(() => loading = true);
                    load();
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error!),
                  TextButton(onPressed: load, child: const Text('Réessayer')),
                ],
              ),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: switch (tab) {
                  0 => menu(),
                  1 => basket(),
                  _ => history(),
                },
              ),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.restaurant_menu),
            label: 'La carte',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: count > 0,
              label: Text('$count'),
              child: const Icon(Icons.shopping_bag_outlined),
            ),
            label: 'Mon panier',
          ),
          const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Commandes',
          ),
        ],
      ),
    );
  }

  Widget menu() {
    final items = catalog
        .where(
          (item) =>
              (category == 'Tout' || item.category == category) &&
              (!vegetarian || item.vegetarian) &&
              '${item.name} ${item.description}'.toLowerCase().contains(
                search.toLowerCase().trim(),
              ),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: AppGradients.hero,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'NOVA PARIS · ROOM SERVICE',
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 11,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Un moment à savourer.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Le plaisir d’une bonne table, dans le confort de votre chambre.',
                style: TextStyle(color: Colors.white70, height: 1.5),
              ),
              const SizedBox(height: 18),
              const Row(
                children: [
                  Icon(Icons.schedule, color: AppColors.gold, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Préparation indicative : 10 à 30 min',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Notice(
          stay == null
              ? 'Contactez la réception pour associer votre chambre avant de commander.'
              : 'Chambre ${stay!['room_number']} · association vérifiée par la réception.',
        ),
        const SizedBox(height: 22),
        Text('À votre goût', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        const Text(
          'Des petits plaisirs, du matin au soir.',
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 16),
        TextField(
          onChanged: (value) => setState(() => search = value),
          decoration: const InputDecoration(
            hintText: 'Rechercher un plat, une boisson…',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final value in [
                'Tout',
                ...catalog.map((item) => item.category).toSet(),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(value),
                    selected: category == value,
                    onSelected: (_) => setState(() => category = value),
                  ),
                ),
            ],
          ),
        ),
        FilterChip(
          avatar: const Icon(Icons.eco_outlined, size: 18),
          label: const Text('Végétarien'),
          selected: vegetarian,
          onSelected: (value) => setState(() => vegetarian = value),
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          const EmptyState(
            'Aucun résultat',
            'Essayez un autre mot ou une autre catégorie.',
          ),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: busy ? null : () => details(item),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 64,
                        height: 70,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          item.symbol,
                          style: const TextStyle(fontSize: 34),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              item.description,
                              style: const TextStyle(
                                color: AppColors.muted,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              item.available
                                  ? '${euros(item.priceCents)}  ·  ${item.minutes} min'
                                  : 'Momentanément indisponible',
                              style: TextStyle(
                                color: item.available
                                    ? AppColors.primary
                                    : AppColors.red,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        item.available
                            ? Icons.add_circle
                            : Icons.remove_circle_outline,
                        color: item.available
                            ? AppColors.accent
                            : AppColors.muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (count > 0)
          FilledButton.icon(
            onPressed: () => setState(() => tab = 1),
            icon: const Icon(Icons.shopping_bag_outlined),
            label: Text('Voir mon panier · ${euros(total)}'),
          ),
      ],
    );
  }

  Widget basket() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('Votre sélection', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text(
        'Un dernier regard avant de vous faire plaisir.',
        style: TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: 24),
      if (cart.isEmpty) ...[
        const EmptyState(
          'Votre panier vous attend',
          'Découvrez la carte et ajoutez ce qui vous fait envie.',
        ),
        OutlinedButton(
          onPressed: () => setState(() => tab = 0),
          child: const Text('Découvrir la carte'),
        ),
      ],
      for (final (index, line) in cart.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${line.item.symbol}  ${line.item.name}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(euros(line.total)),
                    ],
                  ),
                  if (line.note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        line.note,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Diminuer la quantité',
                        onPressed: busy
                            ? null
                            : () {
                                final next = [...cart];
                                if (line.quantity == 1) {
                                  next.removeAt(index);
                                } else {
                                  next[index] = CartLine(
                                    line.itemId,
                                    line.quantity - 1,
                                    line.note,
                                    line.item,
                                  );
                                }
                                updateCart(next);
                              },
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('${line.quantity}'),
                      IconButton(
                        tooltip: 'Augmenter la quantité',
                        onPressed:
                            busy ||
                                !line.item.available ||
                                line.quantity >= 20 ||
                                quantityInCart(line.itemId) >=
                                    (line.item.portions ?? (1 << 30))
                            ? null
                            : () {
                                final next = [...cart];
                                next[index] = CartLine(
                                  line.itemId,
                                  line.quantity + 1,
                                  line.note,
                                  line.item,
                                );
                                updateCart(next);
                              },
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Retirer du panier',
                        onPressed: busy
                            ? null
                            : () => updateCart([...cart]..removeAt(index)),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      if (cartHasStockIssue)
        const _Notice(
          'Stock insuffisant pour un article du panier. Ajustez la quantité ou retirez-le avant de confirmer.',
        ),
      if (cart.isNotEmpty) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            Text('Total', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            Text(euros(total), style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        const SizedBox(height: 16),
        const _Notice(
          'Prix en euros, actualisés au chargement. Vérifiez le total avant confirmation. Aucun paiement ni débit sur votre chambre à cette étape.',
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy || cartHasStockIssue ? null : submit,
          child: Text(busy ? 'Enregistrement…' : 'Confirmer · ${euros(total)}'),
        ),
      ],
    ],
  );

  Widget history() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('Mes commandes', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text(
        'Retrouvez votre sélection et son suivi.',
        style: TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: 20),
      const _Notice('Actualisez pour consulter le suivi de la réception.'),
      const SizedBox(height: 20),
      if (orders.isEmpty)
        const EmptyState(
          'Votre première envie ?',
          'Vos commandes apparaîtront ici après confirmation.',
        ),
      for (final order in orders) _orderCard(order),
    ],
  );

  Widget _orderCard(Map<String, Object?> order) {
    final lines = jsonDecode(order['lines'] as String) as List;
    final date = DateTime.parse(order['created_at'] as String).toLocal();
    final cancelled = ['cancelled', 'rejected'].contains(order['status']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Commande #${order['id']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Text(
                    euros(order['total_cents'] as int),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              Chip(
                avatar: Icon(
                  cancelled
                      ? Icons.cancel_outlined
                      : Icons.check_circle_outline,
                  size: 18,
                ),
                label: Text(
                  orderStatusLabels[order['status']] ?? 'Statut inconnu',
                ),
              ),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${line['quantity']} × ${line['name']}'),
                      if ((line['note'] as String).isNotEmpty)
                        Text(
                          line['note'] as String,
                          style: const TextStyle(color: AppColors.muted),
                        ),
                    ],
                  ),
                ),
              if (order['reason'] != null) Text('Motif : ${order['reason']}'),
              if (!cancelled) ...[
                const Divider(height: 28),
                const Text(
                  'Parcours de la commande',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'En attente → En préparation → Prête à livrer → Livrée',
                  style: TextStyle(color: AppColors.muted, height: 1.6),
                ),
                const SizedBox(height: 8),
                if (order['status'] == 'placed')
                  TextButton(
                    onPressed: busy ? null : () => cancel(order['id'] as int),
                    child: const Text('Annuler la commande'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> cancel(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler cette commande ?'),
        content: const Text(
          'Vous pourrez passer une nouvelle commande depuis la carte.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Conserver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Annuler la commande'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || busy) return;
    setState(() => busy = true);
    try {
      await store.cancel(id);
      await load();
    } catch (_) {
      if (mounted) {
        showFeedback(context, 'Impossible d’annuler cette commande.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _Notice extends StatelessWidget {
  final String text;
  const _Notice(this.text);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.greenLight,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 18, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ItemDetails extends StatefulWidget {
  final MenuItem item;
  final int remaining;
  const _ItemDetails({required this.item, required this.remaining});
  @override
  State<_ItemDetails> createState() => _ItemDetailsState();
}

class _ItemDetailsState extends State<_ItemDetails> {
  final note = TextEditingController();
  int quantity = 1;
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'Fermer',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ),
          Center(
            child: Text(item.symbol, style: const TextStyle(fontSize: 72)),
          ),
          const SizedBox(height: 20),
          Text(item.name, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),
          Text(item.description, style: const TextStyle(height: 1.6)),
          const SizedBox(height: 14),
          Text(
            '${euros(item.priceCents)} · Préparation indicative : ${item.minutes} min',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          _Notice(
            'Allergènes : ${item.allergens}. Pour toute allergie, contactez la réception avant de commander. Les adaptations doivent être confirmées par l’équipe.',
          ),
          const SizedBox(height: 20),
          TextField(
            controller: note,
            maxLength: 250,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Une préférence ?',
              hintText: 'Sauce à part, sans glaçons…',
            ),
          ),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Quantité',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Diminuer',
                onPressed: quantity > 1
                    ? () => setState(() => quantity--)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$quantity'),
              IconButton(
                tooltip: 'Augmenter',
                onPressed: quantity < widget.remaining
                    ? () => setState(() => quantity++)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: item.available && widget.remaining > 0
                  ? () => Navigator.pop(
                      context,
                      CartLine(item.id, quantity, note.text.trim(), item),
                    )
                  : null,
              child: Text(
                !item.available
                    ? 'Momentanément indisponible'
                    : widget.remaining == 0
                    ? 'Quantité disponible déjà au panier'
                    : 'Ajouter · ${euros(item.priceCents * quantity)}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
