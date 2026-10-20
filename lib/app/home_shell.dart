import 'package:flutter/material.dart';

import '../shared/custom/app_theme.dart';
import '../shared/custom/app_widgets.dart';
import '../shared/custom/nova_logo.dart';
import '../shared/models/nova_module.dart';
import '../shared/services/app_session.dart';
import 'modules.dart';

// Home screen: the modules the signed-in role can open.
class HomeShell extends StatelessWidget {
  final AppSession session;
  const HomeShell({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final user = session.user!;
    final visible = [
      for (final module in novaModules)
        if (user.hasAnyRole(module.roles)) module,
    ];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: const Row(
          children: [
            NovaLogo(size: 36),
            SizedBox(width: 9),
            Text('NOVA PARIS', style: TextStyle(letterSpacing: 1)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Mon profil',
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (context) =>
                    userManagement.buildProfile(context, session),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            'Bonjour ${user.firstName}.',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(user.roleLabel, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 20),
          if (visible.isEmpty)
            const EmptyState(
              'Aucun module',
              'Aucun module n’est encore disponible pour votre rôle.',
            ),
          for (final module in visible)
            _ModuleCard(module: module, session: session),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final NovaModule module;
  final AppSession session;
  const _ModuleCard({required this.module, required this.session});

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      contentPadding: const EdgeInsets.all(12),
      leading: CircleAvatar(
        backgroundColor: AppColors.greenLight,
        foregroundColor: AppColors.primary,
        child: Icon(module.icon),
      ),
      title: Text(
        module.title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(module.description),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (context) => module.buildHome(context, session),
        ),
      ),
    ),
  );
}
