import 'package:flutter/material.dart';

import '../../shared/custom/animations.dart';
import '../../shared/custom/app_theme.dart';
import '../custom/supply_form_dialog.dart';
import '../custom/housekeeping_widgets.dart';
import '../models/hotel_data.dart';
import '../models/supply.dart';
import '../custom/stock_movement_dialog.dart';
import 'details_screen.dart';
import '../models/room.dart';

class SuppliesScreen extends StatefulWidget {
  final HotelData data;
  const SuppliesScreen({super.key, required this.data});
  @override
  State<SuppliesScreen> createState() => _SuppliesScreenState();
}

class _SuppliesScreenState extends State<SuppliesScreen> {
  bool dialogOpen = false;
  String? error;
  Future<void> movement(Supply supply, bool receive) async {
    if (dialogOpen || !widget.data.isSupervisor) return;
    setState(() => dialogOpen = true);
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StockMovementDialog(
        data: widget.data,
        supply: supply,
        receive: receive,
      ),
    );
    if (!mounted) return;
    setState(() {
      dialogOpen = false;
      error = null;
    });
    if (saved == true) {
      showFeedback(
        context,
        receive ? 'Stock réapprovisionné' : 'Utilisation enregistrée',
      );
    }
  }

  Future<void> form([Supply? supply]) async {
    if (dialogOpen || !widget.data.isSupervisor) return;
    setState(() => dialogOpen = true);
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SupplyFormDialog(data: widget.data, supply: supply),
    );
    if (!mounted) return;
    setState(() => dialogOpen = false);
    if (saved == true) {
      showFeedback(
        context,
        supply == null ? 'Article ajouté au stock' : 'Article mis à jour',
      );
    }
  }

  Future<void> remove(Supply supply) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Supprimer « ${supply.name} » ?'),
        content: const Text(
          'L’article et sa quantité seront retirés du stock.',
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
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await widget.data.deleteSupply(supply);
      if (mounted) showFeedback(context, 'Article supprimé');
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final reviewRooms = widget.data.rooms
        .where((r) => r.needsCleaning && r.cleaning == CleaningStatus.review)
        .toList();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 7, 18, 24),
      children: [
        if (error != null)
          Text(error!, style: const TextStyle(color: AppColors.red)),
        if (!widget.data.isSupervisor)
          const Text(
            'Consultation du stock · modifications réservées à la gouvernante.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        const StaffBanner(
          title: 'Le soin, dans les détails.',
          label: 'SERVICES · HOUSEKEEPING',
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Linge & produits',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Suivez le stock et les consommations du service.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (widget.data.isSupervisor)
              FilledButton.tonalIcon(
                onPressed: dialogOpen ? null : () => form(),
                icon: const Icon(Icons.add),
                label: const Text('Nouvel article'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (widget.data.supplies.isEmpty)
          const EmptyState(
            'Aucun article',
            'Ajoutez le linge et les produits suivis par le service.',
          ),
        for (final (i, supply) in widget.data.supplies.indexed)
          FadeSlideIn(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                color: Colors.white,
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              supply.name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (supply.isLow)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.redLight,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                supply.quantity == 0 ? 'Rupture' : 'Stock bas',
                                style: const TextStyle(
                                  color: AppColors.red,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          if (widget.data.isSupervisor)
                            PopupMenuButton<String>(
                              tooltip: 'Actions pour ${supply.name}',
                              enabled: !dialogOpen,
                              onSelected: (v) =>
                                  v == 'edit' ? form(supply) : remove(supply),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Modifier'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Supprimer'),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          AnimatedCount(
                            supply.quantity,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: supply.isLow
                                  ? AppColors.red
                                  : AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              '${supply.unit} · alerte à ${supply.minimum}',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Full bar = three times the alert level.
                      AnimatedProgress(
                        supply.minimum == 0
                            ? 1
                            : supply.quantity / (supply.minimum * 3),
                        color: supply.isLow ? AppColors.red : AppColors.green,
                        semanticsLabel: 'Niveau de stock de ${supply.name}',
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed:
                                dialogOpen ||
                                    !widget.data.isSupervisor ||
                                    supply.quantity == 0
                                ? null
                                : () => movement(supply, false),
                            icon: const Icon(Icons.remove, size: 16),
                            label: const Text('Utiliser'),
                          ),
                          TextButton.icon(
                            onPressed: dialogOpen || !widget.data.isSupervisor
                                ? null
                                : () => movement(supply, true),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Réapprovisionner'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 20),
        Text(
          'À valider · ${reviewRooms.length}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (reviewRooms.isEmpty)
          const EmptyState(
            'Tout est validé',
            'Aucun nettoyage en attente de contrôle.',
          ),
        ...reviewRooms.map(
          (room) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Chambre ${room.number}'),
            subtitle: Text(
              'Nettoyée par ${room.employee ?? 'Agent indisponible'}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DetailsScreen(data: widget.data, room: room),
                ),
              );
              if (mounted) setState(() {});
            },
          ),
        ),
      ],
    );
  }
}
