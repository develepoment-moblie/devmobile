import 'package:flutter/material.dart';

import '../../shared/custom/app_widgets.dart';
import '../../shared/services/app_session.dart';

// First screen of the Facturation et rapports module. Replace the placeholder with your work.
class BillingHomeScreen extends StatelessWidget {
  final AppSession session;
  const BillingHomeScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) => const ModulePlaceholder(
    title: 'Facturation et rapports',
    owner: 'à compléter',
    icon: Icons.receipt_long_outlined,
  );
}
