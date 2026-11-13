import 'package:flutter/material.dart';

import '../shared/models/app_user.dart';
import '../shared/models/nova_module.dart';
import '../shared/services/app_session.dart';
import '../shared/services/app_database.dart';
import 'screens/maintenance_home_screen.dart';
import 'services/maintenance_store.dart';

// Entry point of the Maintenance module. Owner: Ayoub Belgacem.
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
  String get owner => 'Ayoub Belgacem';
  @override
  Set<String> get roles => {
    AppRole.maintenance,
    AppRole.staff,
    AppRole.supervisor,
    AppRole.receptionist,
    AppRole.manager,
    AppRole.admin,
  };

  @override
  ModuleSchema get schema => maintenanceSchema;

  @override
  Widget buildHome(BuildContext context, AppSession session) =>
      MaintenanceHomeScreen(session: session);
}
