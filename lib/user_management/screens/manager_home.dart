import 'package:flutter/material.dart';

import '../../shared/custom/app_widgets.dart';
import '../models/app_user.dart';
import '../services/user_repository.dart';
import 'manage_users.dart';
import 'profile_screen.dart';

class ManagerHome extends StatelessWidget {
  final AppUser user;
  final UserRepository auth;
  final WidgetBuilder? roomsBuilder;
  final WidgetBuilder? backupsBuilder;
  const ManagerHome({
    super.key,
    required this.user,
    required this.auth,
    this.roomsBuilder,
    this.backupsBuilder,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        user.role == 'admin' ? 'Espace administrateur' : 'Espace manager',
      ),
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
        StaffBanner(
          title: 'Bonjour ${user.firstName}.',
          label: 'GESTION DE L’HÔTEL',
        ),
        const SizedBox(height: 24),
        const Text(
          'Utilisateurs',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text('Gérez les profils et les rôles de votre équipe.'),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ManageUsersScreen(auth: auth),
            ),
          ),
          icon: const Icon(Icons.people_alt_outlined),
          label: const Text('Gérer les utilisateurs'),
        ),
        if (roomsBuilder != null) ...[
          const SizedBox(height: 28),
          const Text(
            'Chambres',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Créez les chambres, gérez leurs catégories et conservez les chambres archivées.',
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: roomsBuilder!),
            ),
            icon: const Icon(Icons.meeting_room_outlined),
            label: const Text('Gérer les chambres'),
          ),
        ],
        if (backupsBuilder != null) ...[
          const SizedBox(height: 28),
          const Text(
            'Données locales',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Conservez une copie chiffrée ou restaurez une sauvegarde.',
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: backupsBuilder!),
            ),
            icon: const Icon(Icons.backup_outlined),
            label: const Text('Sauvegarder et restaurer'),
          ),
        ],
      ],
    ),
  );
}
