import 'package:flutter/foundation.dart';

import '../../shared/models/app_user.dart';
import '../../shared/services/staff_directory.dart';
import '../accounts/services/database_helper.dart';
import '../screens/account_gate.dart';
import 'demo_staff_directory.dart';

// The hotel's staff: the real accounts, plus the test team while accounts
// for every role do not exist yet (the accounts have no supervisor role).
class AccountsStaffDirectory implements StaffDirectory {
  const AccountsStaffDirectory();

  @override
  Future<List<AppUser>> users({Set<String>? roles}) async {
    final people = [...await const DemoStaffDirectory().users(roles: roles)];
    try {
      for (final account in await DatabaseHelper.instance.getAllUsers()) {
        final user = sessionUser(account);
        if (roles == null || roles.contains(user.role)) people.add(user);
      }
    } catch (e) {
      debugPrint('user_management: comptes indisponibles ($e)');
    }
    return people..sort((a, b) => a.fullName.compareTo(b.fullName));
  }
}
