import 'package:flutter/material.dart';

import '../../shared/models/app_user.dart';
import '../../shared/services/app_session.dart';
import '../accounts/models/app_user.dart' as accounts;
import '../accounts/screens/login_screen.dart';
import '../accounts/services/auth_service.dart';
import 'login_screen.dart';

/// The shared app's user for an account of the accounts database.
AppUser sessionUser(accounts.AppUser account) => AppUser(
  id: 'account-${account.id}',
  fullName: account.displayName.trim().isEmpty
      ? account.fullName
      : account.displayName,
  role: AppRole.all.contains(account.role) ? account.role : AppRole.guest,
);

// What the app shows before anyone is signed in: the real login with an
// account (restored after a restart), or the test accounts.
class AccountGate extends StatefulWidget {
  final AppSession session;
  const AccountGate({super.key, required this.session});
  @override
  State<AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends State<AccountGate> {
  bool testAccounts = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  // The account signed in before the app was closed.
  Future<void> _restore() async {
    try {
      await AuthService.initSession();
      final account = AuthService.currentUser;
      if (account != null && mounted && widget.session.user == null) {
        widget.session.signIn(sessionUser(account));
      }
    } catch (e) {
      debugPrint('user_management: session non restaurée ($e)');
    }
  }

  @override
  Widget build(BuildContext context) => testAccounts
      ? LoginScreen(
          session: widget.session,
          onAccounts: () => setState(() => testAccounts = false),
        )
      : AccountLoginScreen(
          onSignedIn: (account) => widget.session.signIn(sessionUser(account)),
          onTestAccounts: () => setState(() => testAccounts = true),
        );
}
