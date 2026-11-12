import 'package:flutter/material.dart';

import '../shared/models/app_user.dart';
import '../shared/models/nova_module.dart';
import '../shared/services/app_session.dart';
import 'screens/billing_home_screen.dart';

// Entry point of the Facturation et rapports module. Owner: à compléter.
// Everything for this module lives in lib/billing/. See lib/billing/README.md.
class BillingModule extends NovaModule {
  const BillingModule();
  @override
  String get id => 'billing';
  @override
  String get title => 'Facturation et rapports';
  @override
  String get description => 'Factures, paiements, tableau de bord et exports.';
  @override
  IconData get icon => Icons.receipt_long_outlined;
  @override
  String get owner => 'à compléter';
  @override
  Set<String> get roles => {
    AppRole.receptionist,
    AppRole.manager,
    AppRole.admin,
  };

  // Add your tables here when you need them, for example:
  // @override
  // ModuleSchema get schema => ModuleSchema(
  //   module: id,
  //   version: 1,
  //   migrate: (tx, from, to) async {
  //     if (from < 1) {
  //       await tx.execute('CREATE TABLE billing_items (id TEXT PRIMARY KEY, ...)');
  //     }
  //   },
  // );

  @override
  Widget buildHome(BuildContext context, AppSession session) =>
      BillingHomeScreen(session: session);
}
