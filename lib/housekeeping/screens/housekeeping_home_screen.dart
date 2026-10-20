import 'package:flutter/material.dart';

import '../../shared/custom/app_widgets.dart';
import '../../shared/services/app_session.dart';

// First screen of the Chambres et ménage module. Replace the placeholder with your work.
class HousekeepingHomeScreen extends StatelessWidget {
  final AppSession session;
  const HousekeepingHomeScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) => const ModulePlaceholder(
    title: 'Chambres et ménage',
    owner: 'jassernoomani',
    icon: Icons.cleaning_services_outlined,
  );
}
