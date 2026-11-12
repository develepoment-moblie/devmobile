import 'package:flutter/material.dart';

import '../../shared/custom/app_widgets.dart';
import '../../shared/services/app_session.dart';

// First screen of the Services clients module. Replace the placeholder with your work.
class GuestServicesHomeScreen extends StatelessWidget {
  final AppSession session;
  const GuestServicesHomeScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) => const ModulePlaceholder(
    title: 'Services clients',
    owner: 'à compléter',
    icon: Icons.room_service_outlined,
  );
}
