import 'package:flutter/material.dart';

import '../../shared/custom/app_widgets.dart';
import '../../shared/services/app_session.dart';

// First screen of the Réservations module. Replace the placeholder with your work.
class ReservationsHomeScreen extends StatelessWidget {
  final AppSession session;
  const ReservationsHomeScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) => const ModulePlaceholder(
    title: 'Réservations',
    owner: 'à compléter',
    icon: Icons.calendar_month_outlined,
  );
}
