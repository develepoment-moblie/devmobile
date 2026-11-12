import 'package:flutter/material.dart';

import '../shared/models/app_user.dart';
import '../shared/models/nova_module.dart';
import '../shared/services/app_session.dart';
import 'screens/reservations_home_screen.dart';

// Entry point of the Réservations module. Owner: à compléter.
// Everything for this module lives in lib/reservations/. See lib/reservations/README.md.
class ReservationsModule extends NovaModule {
  const ReservationsModule();
  @override
  String get id => 'reservations';
  @override
  String get title => 'Réservations';
  @override
  String get description =>
      'Réservations, disponibilités, tarifs, check-in et check-out.';
  @override
  IconData get icon => Icons.calendar_month_outlined;
  @override
  String get owner => 'à compléter';
  @override
  Set<String> get roles => {
    AppRole.receptionist,
    AppRole.manager,
    AppRole.admin,
    AppRole.guest,
  };

  // Add your tables here when you need them, for example:
  // @override
  // ModuleSchema get schema => ModuleSchema(
  //   module: id,
  //   version: 1,
  //   migrate: (tx, from, to) async {
  //     if (from < 1) {
  //       await tx.execute('CREATE TABLE reservations_items (id TEXT PRIMARY KEY, ...)');
  //     }
  //   },
  // );

  @override
  Widget buildHome(BuildContext context, AppSession session) =>
      ReservationsHomeScreen(session: session);
}
