import 'package:flutter/material.dart';

import '../../shared/custom/app_widgets.dart';
import '../../shared/services/app_session.dart';

// First screen of the Utilisateurs module. Replace the placeholder with your work.
class UserManagementHomeScreen extends StatelessWidget {
  final AppSession session;
  const UserManagementHomeScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) => const ModulePlaceholder(
    title: 'Utilisateurs',
    owner: 'Skander256',
    icon: Icons.people_alt_outlined,
  );
}
