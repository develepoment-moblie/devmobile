import '../models/app_user.dart';

// Optional contract for local password changes. There is no e-mail service, so a
// forgotten password is reset by a Manager with a temporary password.
abstract interface class PasswordManagement {
  Future<void> changePassword(String current, String next);
  Future<void> resetPassword(AppUser original, String temporary);
}
