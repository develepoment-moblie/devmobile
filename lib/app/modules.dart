import '../billing/billing_module.dart';
import '../guest_services/guest_services_module.dart';
import '../housekeeping/housekeeping_module.dart';
import '../maintenance/maintenance_module.dart';
import '../reservations/reservations_module.dart';
import '../shared/models/nova_module.dart';
import '../shared/services/app_session.dart';
import '../user_management/user_management_module.dart';

// All modules are already registered: you do not need to edit this file.
// Work inside your own lib/<module>/ folder.
const userManagement = UserManagementModule();

const List<NovaModule> novaModules = [
  ReservationsModule(),
  HousekeepingModule(),
  MaintenanceModule(),
  GuestServicesModule(),
  BillingModule(),
  userManagement,
];

/// Lets every module subscribe to events. Called once by main().
void attachModules(AppSession session) {
  for (final module in novaModules) {
    module.attach(session);
  }
}
