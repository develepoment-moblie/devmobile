import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../widgets/nova_logo.dart';
import 'manage_users.dart';

class ManagerHome extends StatelessWidget {
  final AppUser user;
  const ManagerHome({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    // 👇 Affiche "ADMIN" ou "MANAGER" selon le rôle réel
    final title =
    user.role == 'admin' ? 'ESPACE ADMIN' : 'ESPACE MANAGER';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const NovaLogo(size: 28),
            const SizedBox(width: 10),
            Text(title),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: AuthService.logout,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Bonjour ${user.firstName}.',
              style: const TextStyle(fontSize: 14, color: Color(0xFFC4704F)),
            ),
            const SizedBox(height: 8),
            const Text(
              "Vue d'ensemble.",
              style: TextStyle(fontSize: 30),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              icon: const Icon(Icons.people_alt_outlined),
              label: const Text('Gérer les utilisateurs'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ManageUsersScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}