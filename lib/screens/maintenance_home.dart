import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../widgets/bottom_bar.dart';
import '../widgets/placeholder_tab.dart';
import 'maintenance/maintenance_screen.dart';
import 'tabs/profil_tab.dart';

const _cream = Color(0xFFF6F1EA);

/// Accueil du rôle `maintenance` : même structure que StaffHome
/// (onglets + BottomBar). L'onglet « Accueil » affiche le module Maintenance,
/// l'onglet « Profil » (existant) garde la déconnexion.
class MaintenanceHome extends StatefulWidget {
  final AppUser user;
  const MaintenanceHome({super.key, required this.user});

  @override
  State<MaintenanceHome> createState() => _MaintenanceHomeState();
}

class _MaintenanceHomeState extends State<MaintenanceHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: _tab,
          children: [
            const MaintenanceScreen(asTab: true),
            const PlaceholderTab(
              icon: Icons.calendar_today_outlined,
              title: 'Réservations',
            ),
            const PlaceholderTab(
              icon: Icons.meeting_room_outlined,
              title: 'Chambres',
            ),
            const PlaceholderTab(
              icon: Icons.room_service_outlined,
              title: 'Services',
            ),
            ProfilTab(user: widget.user),
          ],
        ),
      ),
      bottomNavigationBar: BottomBar(
        current: _tab,
        onTap: (i) => setState(() => _tab = i),
      ),
    );
  }
}
