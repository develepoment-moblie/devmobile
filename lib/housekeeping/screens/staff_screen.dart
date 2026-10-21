import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../custom/housekeeping_widgets.dart';
import '../models/hotel_data.dart';
import '../models/issue.dart';
import 'dashboard_screen.dart';
import 'issues_screen.dart';
import '../models/dashboard_data.dart';
import '../services/housekeeping_store.dart';
import '../services/sqlite_housekeeping.dart';
import 'lost_items_screen.dart';
import 'stats_screen.dart';

class StaffScreen extends StatelessWidget {
  final HotelData data;
  final ValueChanged<int> navigate;
  final VoidCallback onHousekeeping;
  const StaffScreen({
    super.key,
    required this.data,
    required this.navigate,
    required this.onHousekeeping,
  });
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(18, 7, 18, 24),
    children: [
      StaffBanner(
        title: 'Bonjour ${data.currentUser}.',
        label: 'ESPACE PERSONNEL',
      ),
      const SizedBox(height: 16),
      const Text(
        'Service du matin · 07:00 — 15:00',
        style: TextStyle(color: AppColors.muted, fontSize: 11),
      ),
      const SizedBox(height: 24),
      const Text(
        'Accès rapide',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      ...[
        if (data.api case SqliteHousekeeping(
          store: final HousekeepingStore store,
        ))
          (
            'Tableau de bord',
            'Chambres, agents et signalements en direct',
            Icons.space_dashboard_outlined,
            () => openDashboard(context, store),
          ),
        (
          'Chambres',
          '${data.rooms.length} chambres',
          Icons.bed_outlined,
          () => navigate(2),
        ),
        (
          'Ménage',
          '${data.remaining} restantes',
          Icons.cleaning_services_outlined,
          onHousekeeping,
        ),
        (
          'Départs',
          'Préparer les prochaines arrivées',
          Icons.calendar_month_outlined,
          () => navigate(1),
        ),
        (
          'Linge & produits',
          '${data.supplies.where((s) => s.isLow).length} stock bas',
          Icons.inventory_2_outlined,
          () => navigate(3),
        ),
        (
          'Signalements',
          '${data.issues.where((i) => i.status == IssueStatus.open).length} en attente · ${data.issues.where((i) => i.status == IssueStatus.resolved).length} résolus',
          Icons.report_outlined,
          () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => IssuesScreen(data: data)),
          ),
        ),
        (
          'Objets trouvés',
          '${data.lostItems.where((i) => i.status.kept).length} à rendre',
          Icons.search,
          () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => LostItemsScreen(data: data),
            ),
          ),
        ),
        (
          'Statistiques',
          '${data.statsSince(DateTime.now().copyWith(hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0)).approved} validés aujourd’hui',
          Icons.insights_outlined,
          () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => StatsScreen(data: data)),
          ),
        ),
      ].map(
        (item) => Card(
          elevation: 0,
          color: Colors.white,
          child: ListTile(
            leading: Icon(item.$3, color: AppColors.primary),
            title: Text(
              item.$1,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(item.$2, style: const TextStyle(fontSize: 11)),
            trailing: const Icon(Icons.chevron_right),
            onTap: item.$4,
          ),
        ),
      ),
      const SizedBox(height: 24),
      const Text(
        'Priorités du jour',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          '${data.reviews} nettoyage${data.reviews > 1 ? 's' : ''} à valider',
        ),
        subtitle: const Text('Contrôle de la gouvernante'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onHousekeeping,
      ),
    ],
  );
}

/// Opens the live dashboard; its controller lives as long as the screen.
Future<void> openDashboard(BuildContext context, HousekeepingStore store) {
  final dashboard = DashboardData(store);
  return Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => DashboardScreen(dashboard: dashboard),
    ),
  ).whenComplete(dashboard.dispose);
}
