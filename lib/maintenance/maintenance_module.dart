import 'package:flutter/material.dart';

import '../shared/models/app_user.dart';
import '../shared/models/nova_module.dart';
import '../shared/services/app_session.dart';
import 'screens/maintenance_home_screen.dart';

// Entry point of the Maintenance module. Owner: à compléter.
// Everything for this module lives in lib/maintenance/. See lib/maintenance/README.md.
class MaintenanceModule extends NovaModule {
  const MaintenanceModule();
  @override
  String get id => 'maintenance';
  @override
  String get title => 'Maintenance';
  @override
  String get description =>
      'Signalements avec photo, interventions, urgences et historique.';
  @override
  IconData get icon => Icons.build_outlined;
  @override
  String get owner => 'à compléter';
  @override
  Set<String> get roles => {
    AppRole.maintenance,
    AppRole.staff,
    AppRole.supervisor,
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
  //       await tx.execute('CREATE TABLE maintenance_items (id TEXT PRIMARY KEY, ...)');
  //     }
  //   },
  // );

  @override
  Widget buildHome(BuildContext context, AppSession session) =>
      MaintenanceHomeScreen(session: session);
}
