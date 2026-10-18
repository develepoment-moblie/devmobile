import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../../shared/custom/app_widgets.dart';
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
        const Text(
          'Linge & produits',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Suivez le stock et les consommations du service.',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        ...widget.data.supplies.map(
          (supply) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              color: Colors.white,
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      supply.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${supply.quantity} ${supply.unit}',
                      style: const TextStyle(
                        fontSize: 20,
                        color: AppColors.primary,
                      ),
                    ),
                    if (supply.isLow)
                      const Text(
                        'Stock bas · réapprovisionnement nécessaire',
                        style: TextStyle(color: AppColors.red, fontSize: 11),
                      ),
                    const SizedBox(height: 8),
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
