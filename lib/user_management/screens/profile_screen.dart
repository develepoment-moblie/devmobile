import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../../shared/custom/nova_logo.dart';
import '../../shared/services/app_session.dart';

// Profile of the signed-in user. Owned by user_management.
class ProfileScreen extends StatelessWidget {
  final AppSession session;
  const ProfileScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final user = session.user;
    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Center(child: NovaLogo(size: 120)),
          const SizedBox(height: 20),
          Text(
            user?.fullName ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            user?.roleLabel ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
              session.signOut();
            },
            icon: const Icon(Icons.logout),
            label: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
  }
}
