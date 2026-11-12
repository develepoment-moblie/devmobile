import 'package:flutter/material.dart';

import '../shared/models/app_user.dart';
import '../shared/models/nova_module.dart';
import '../shared/services/app_database.dart';
import '../shared/services/app_session.dart';
import 'screens/housekeeping_home_screen.dart';
import 'services/hotel_event_handlers.dart';
import 'services/housekeeping_store.dart';

// One store per session, shared by the screens and the event listeners so
// their database operations run one after another.
final _stores = Expando<HousekeepingStore>('housekeeping store');
HousekeepingStore housekeepingStoreFor(AppSession session) =>
    _stores[session] ??= HousekeepingStore(session);

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

  // Agents and the supervisor clean; the Manager manages the room catalog.
  @override
  Set<String> get roles => {
    AppRole.staff,
    AppRole.supervisor,
    AppRole.manager,
    AppRole.admin,
  };

  @override
  ModuleSchema get schema => housekeepingSchema;

  // Check-in/out from reservations and maintenance updates change room status
  // even when nobody has the module open.
  @override
  void attach(AppSession session) =>
      listenToHotelEvents(session.events, housekeepingStoreFor(session));

  @override
  Widget buildHome(BuildContext context, AppSession session) =>
      HousekeepingHomeScreen(
        session: session,
        store: housekeepingStoreFor(session),
      );
}
