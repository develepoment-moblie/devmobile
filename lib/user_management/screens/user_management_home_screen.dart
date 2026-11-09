import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../../shared/services/app_session.dart';
import '../accounts/screens/manage_priorities.dart';
import '../accounts/screens/manage_users.dart';

// First screen of the Utilisateurs module (Manager and admin): accounts and
// the priorities shown to the teams.
class UserManagementHomeScreen extends StatelessWidget {
  final AppSession session;
  const UserManagementHomeScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Utilisateurs')),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        for (final (label, detail, icon, screen)
            in <(String, String, IconData, Widget)>[
              (
                'Gérer les utilisateurs',
                'Créer, modifier, changer le rôle ou supprimer un compte',
                Icons.manage_accounts_outlined,
                const ManageUsersScreen(),
              ),
              (
                'Gérer les priorités',
                'Les priorités du jour affichées aux équipes',
                Icons.flag_outlined,
                const ManagePrioritiesScreen(),
              ),
            ])
          Card(
            color: Colors.white,
            elevation: 0,
            child: ListTile(
              leading: Icon(icon, color: AppColors.primary),
              title: Text(label),
              subtitle: Text(detail),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => screen),
              ),
            ),
          ),
      ],
    ),
  );
}
