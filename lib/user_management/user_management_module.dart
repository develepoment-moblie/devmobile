import 'package:flutter/material.dart';

import '../shared/models/app_user.dart';
import '../shared/models/nova_module.dart';
import '../shared/services/app_session.dart';
import 'screens/user_management_home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';

// Entry point of the Utilisateurs module. Owner: Skander256.
// Everything for this module lives in lib/user_management/. See lib/user_management/README.md.
class UserManagementModule extends NovaModule {
  const UserManagementModule();
  @override
  String get id => 'user_management';
  @override
  String get title => 'Utilisateurs';
  @override
  String get description =>
      'Comptes, connexion, profils et droits d’accès par rôle.';
  @override
  IconData get icon => Icons.people_alt_outlined;
  @override
  String get owner => 'Skander256';
  @override
  Set<String> get roles => AppRole.management;

  // Add your tables here when you need them, for example:
  // @override
  // ModuleSchema get schema => ModuleSchema(
  //   module: id,
  //   version: 1,
  //   migrate: (tx, from, to) async {
  //     if (from < 1) {
  //       await tx.execute('CREATE TABLE user_management_items (id TEXT PRIMARY KEY, ...)');
  //     }
  //   },
  // );

  @override
  Widget buildHome(BuildContext context, AppSession session) =>
      UserManagementHomeScreen(session: session);

  // Used by the app shell before anyone is signed in, and from the home bar.
  Widget buildLogin(BuildContext context, AppSession session) =>
      LoginScreen(session: session);
  Widget buildProfile(BuildContext context, AppSession session) =>
      ProfileScreen(session: session);
}
