import 'package:flutter/material.dart';

import '../../shared/custom/app_widgets.dart';
import '../../shared/services/app_session.dart';

// First screen of the Maintenance module. Replace the placeholder with your work.
class MaintenanceHomeScreen extends StatelessWidget {
  final AppSession session;
  const MaintenanceHomeScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) => const ModulePlaceholder(
    title: 'Maintenance',
    owner: 'à compléter',
    icon: Icons.build_outlined,
  );
}
