import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../../shared/models/app_user.dart';
import '../../shared/services/app_session.dart';
import '../services/guest_service_store.dart';
import '../services/service_desk_store.dart';
import 'agent_deliveries_screen.dart';
import 'guest_services_home_screen.dart';
import 'kitchen_orders_screen.dart';
import 'kitchen_stock_screen.dart';
import 'menu_management_screen.dart';
import 'reception_orders_screen.dart';
import 'service_desk_screen.dart';
import 'service_room_screen.dart';

typedef _Shortcut = ({
  String title,
  String description,
  IconData icon,
  WidgetBuilder destination,
});

class GuestServicesHubScreen extends StatelessWidget {
  const GuestServicesHubScreen({super.key, required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    final user = session.user;
    if (user == null) return const SizedBox.shrink();
    final store = GuestServiceStore(session);
    if (user.role == AppRole.staff) return AgentDeliveriesScreen(store: store);

    final isGuest = user.role == AppRole.guest;
    final isKitchen = user.role == AppRole.kitchen;
    final managesServices = user.hasAnyRole(AppRole.management);
    Widget desk(String kind) =>
        ServiceDeskScreen(session: session, initialKind: kind);

    final shortcuts = <_Shortcut>[
      if (isKitchen) ...[
        (
          title: 'Commandes cuisine',
          description: 'Préparer les commandes et les marquer prêtes.',
          icon: Icons.soup_kitchen_outlined,
          destination: (_) => KitchenOrdersScreen(store: store),
        ),
        (
          title: 'Stock',
          description: 'Ajuster les portions et la disponibilité.',
          icon: Icons.inventory_2_outlined,
          destination: (_) => KitchenStockScreen(store: store),
        ),
      ] else ...[
        if (isGuest) ...[
          (
            title: 'Room service',
            description: 'Consulter la carte et commander en chambre.',
            icon: Icons.restaurant_menu,
            destination: (_) => GuestServicesHomeScreen(session: session),
          ),
          (
            title: 'Mes commandes',
            description: 'Suivre vos commandes et consulter leur historique.',
            icon: Icons.receipt_long_outlined,
            destination: (_) =>
                GuestServicesHomeScreen(session: session, initialTab: 2),
          ),
        ] else
          (
            title: 'Commandes',
            description: 'Accepter, attribuer et suivre les livraisons.',
            icon: Icons.receipt_long_outlined,
            destination: (_) => ReceptionOrdersScreen(session: session),
          ),
        (
          title: 'Restaurant',
          description: isGuest
              ? 'Réserver une table.'
              : 'Gérer les réservations et ouvrir le plan de salle.',
          icon: Icons.table_restaurant_outlined,
          destination: (_) => desk('restaurant'),
        ),
        (
          title: 'Spa',
          description: isGuest
              ? 'Réserver un soin.'
              : 'Consulter et traiter les rendez-vous.',
          icon: Icons.spa_outlined,
          destination: (_) => desk('spa'),
        ),
        if (!isGuest)
          (
            title: 'Chambres des clients',
            description: 'Associer une chambre pour le room service.',
            icon: Icons.meeting_room_outlined,
            destination: (_) => ServiceRoomScreen(store: store),
          ),
        (
          title: 'Demandes et réclamations',
          description: isGuest
              ? 'Faire une demande ou écrire à la réception.'
              : 'Consulter les demandes, messages et réclamations.',
          icon: Icons.forum_outlined,
          destination: (_) => desk('request'),
        ),
      ],
      if (managesServices) ...[
        (
          title: 'Carte',
          description: 'Gérer les plats et les catégories.',
          icon: Icons.restaurant_menu,
          destination: (_) => MenuManagementScreen(session: session),
        ),
        (
          title: 'Créneaux du spa',
          description: 'Ouvrir les réservations de soins.',
          icon: Icons.event_available_outlined,
          destination: (_) =>
              SlotManagementScreen(store: ServiceDeskStore(session)),
        ),
      ],
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Services clients')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        itemCount: shortcuts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final shortcut = shortcuts[index];
          return Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: CircleAvatar(
                backgroundColor: AppColors.greenLight,
                foregroundColor: AppColors.primary,
                child: Icon(shortcut.icon),
              ),
              title: Text(
                shortcut.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(shortcut.description),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: shortcut.destination)),
            ),
          );
        },
      ),
    );
  }
}
