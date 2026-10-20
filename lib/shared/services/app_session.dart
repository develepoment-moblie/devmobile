import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import 'app_database.dart';
import 'app_events.dart';

// Passed to every module: who is signed in, the shared database and events.
class AppSession extends ChangeNotifier {
  final AppDatabase database;
  final AppEvents events;
  AppUser? _user;
  AppSession({required this.database, AppEvents? events})
    : events = events ?? AppEvents();

  AppUser? get user => _user;

  /// Called by the user_management module after a successful login.
  void signIn(AppUser user) {
    _user = user;
    notifyListeners();
  }

  void signOut() {
    _user = null;
    notifyListeners();
  }
}
