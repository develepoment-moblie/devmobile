import 'package:flutter/material.dart';

import '../shared/models/app_user.dart';
import '../shared/models/nova_module.dart';
import '../shared/services/app_session.dart';
import 'screens/housekeeping_home_screen.dart';

// Entry point of the Chambres et ménage module. Owner: jassernoomani.
// Everything for this module lives in lib/housekeeping/. See lib/housekeeping/README.md.
class HousekeepingModule extends NovaModule {
  const HousekeepingModule();
  @override
  String get id => 'housekeeping';
  @override
  String get title => 'Chambres et ménage';
  @override
  String get description =>
      'Statut des chambres, attribution, validation, linge et produits.';
  @override
  IconData get icon => Icons.cleaning_services_outlined;
  @override
  String get owner => 'jassernoomani';
  @override
  Set<String> get roles => {
    AppRole.staff,
    AppRole.supervisor,
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
  //       await tx.execute('CREATE TABLE housekeeping_items (id TEXT PRIMARY KEY, ...)');
  //     }
  //   },
  // );

  @override
  Widget buildHome(BuildContext context, AppSession session) =>
      HousekeepingHomeScreen(session: session);
}
