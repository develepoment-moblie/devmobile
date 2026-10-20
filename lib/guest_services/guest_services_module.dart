import 'package:flutter/material.dart';

import '../shared/models/app_user.dart';
import '../shared/models/nova_module.dart';
import '../shared/services/app_session.dart';
import 'screens/guest_services_home_screen.dart';

// Entry point of the Services clients module. Owner: à compléter.
// Everything for this module lives in lib/guest_services/. See lib/guest_services/README.md.
class GuestServicesModule extends NovaModule {
  const GuestServicesModule();
  @override
  String get id => 'guest_services';
  @override
  String get title => 'Services clients';
  @override
  String get description =>
      'Room service, restaurant, spa, demandes spéciales et messagerie.';
  @override
  IconData get icon => Icons.room_service_outlined;
  @override
  String get owner => 'à compléter';
  @override
  Set<String> get roles => {
    AppRole.guest,
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
  //       await tx.execute('CREATE TABLE guest_services_items (id TEXT PRIMARY KEY, ...)');
  //     }
  //   },
  // );

  @override
  Widget buildHome(BuildContext context, AppSession session) =>
      GuestServicesHomeScreen(session: session);
}
