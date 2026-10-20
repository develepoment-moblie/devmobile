import 'package:flutter/widgets.dart';

import '../services/app_database.dart';
import '../services/app_session.dart';

// Every feature module implements this once, in lib/<module>/<module>_module.dart.
// The app shell lists the modules in lib/app/modules.dart and shows each one to
// the roles it declares. A module never imports another module's folder.
abstract class NovaModule {
  const NovaModule();

  /// Folder name, also the prefix of the module's SQLite tables.
  String get id;
  String get title;
  String get description;
  IconData get icon;

  /// Team member responsible for the module.
  String get owner;

  /// Roles that see this module on the home screen.
  Set<String> get roles;

  /// The module's own tables, or null while it has none.
  ModuleSchema? get schema => null;

  /// Called once at startup, before anyone signs in. Subscribe to
  /// session.events here, for example to react to another module's events.
  void attach(AppSession session) {}

  /// The module's first screen, opened from the home screen.
  Widget buildHome(BuildContext context, AppSession session);
}
