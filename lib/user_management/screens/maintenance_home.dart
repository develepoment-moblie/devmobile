import 'package:flutter/material.dart';

import '../../shared/custom/app_widgets.dart';
import '../models/app_user.dart';
import '../services/user_repository.dart';
import 'profile_screen.dart';

// Preserves the friend's maintenance landing page; interventions are another module.
class MaintenanceHome extends StatelessWidget {
  final AppUser user;
  final UserRepository auth;
  const MaintenanceHome({super.key, required this.user, required this.auth});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Maintenance'),
      actions: [
        IconButton(
          tooltip: 'Mon profil',
          icon: const Icon(Icons.person_outline),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Mon profil')),
                body: UserProfileScreen(user: user, auth: auth),
              ),
            ),
          ),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        StaffBanner(title: 'Bonjour ${user.firstName}.', label: 'MAINTENANCE'),
        const SizedBox(height: 24),
        const EmptyState(
          'Espace maintenance',
          'Les interventions seront raccordées au module de votre équipe.',
        ),
      ],
    ),
  );
}
