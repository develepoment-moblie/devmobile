import 'dart:async';

import 'package:flutter/material.dart';

import '../shared/models/app_user.dart';
import '../shared/models/nova_module.dart';
import '../shared/services/app_session.dart';
import 'screens/guest_services_hub_screen.dart';
import '../shared/services/app_database.dart';
import 'services/demo_guest_services.dart';
import 'services/guest_service_store.dart';

// Entry point of the Services clients module. Owner: à compléter.
// Everything for this module lives in lib/guest_services/. See lib/guest_services/README.md.
class GuestServicesModule extends NovaModule {
  const GuestServicesModule();
  @override
  ModuleSchema get schema => GuestServiceStore.schema;
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
    AppRole.kitchen,
    AppRole.staff,
    AppRole.receptionist,
    AppRole.manager,
    AppRole.admin,
  };

  // Presentation build only (NOVA_DEMO_DATA): demo menu, orders, bookings.
  @override
  void attach(AppSession session) {
    if (!novaDemoData) return;
    unawaited(
      fillDemoGuestServices(session).then<void>(
        (_) {},
        onError: (Object e) =>
            debugPrint('guest_services: données de démonstration ($e)'),
      ),
    );
  }

  @override
  Widget buildHome(BuildContext context, AppSession session) =>
      GuestServicesHubScreen(session: session);
}
