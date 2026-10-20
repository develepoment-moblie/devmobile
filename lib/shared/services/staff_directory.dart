import '../models/app_user.dart';

// Who works at the hotel, as other modules need it (for example the agents a
// supervisor can assign). Implemented by the user_management module; other
// modules only read it through session.staff.
abstract interface class StaffDirectory {
  /// Active accounts, optionally limited to some roles, sorted by name.
  Future<List<AppUser>> users({Set<String>? roles});
}
