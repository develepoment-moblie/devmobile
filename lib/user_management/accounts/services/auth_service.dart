import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/app_user.dart';
import 'database_helper.dart';
import 'firebase_auth_api.dart';

class AuthService {
  static AppUser? _currentUser;
  static Future<void>? _logoutInProgress;
  static AppUser? get currentUser => _currentUser;

  // === Restore the session ===
  static Future<void> initSession() async {
    final logout = _logoutInProgress;
    await logout;
    final prefs = await SharedPreferences.getInstance();
    final userId = int.tryParse(prefs.getString('logged_in_user_id') ?? '');
    if (userId == null) return;
    final user = await DatabaseHelper.instance.getUserById(userId);
    if (identical(logout, _logoutInProgress)) _currentUser = user;
  }

  /// Online, Firebase decides the password, so a reset by e-mail takes
  /// effect; the phone keeps a copy for offline logins. Offline, or for an
  /// account Firebase does not know yet, the phone decides.
  static Future<AppUser?> login(String fullName, String password) async {
    await _logoutInProgress;
    final db = DatabaseHelper.instance;
    final email = fullName.trim();
    final row = await db.getUserByEmail(email);
    AppUser? user;
    var firebase = FirebaseAnswer.unavailable;
    if (row != null && _isEmail(email)) {
      firebase = await FirebaseAuthApi.signIn(email, password);
    }
    if (firebase == FirebaseAnswer.accepted) {
      // Maybe a new password set from the reset e-mail: keep it for offline.
      await db.saveFirebasePassword(row!['id'] as int, password);
      user = AppUser.fromMap(row);
    } else if (firebase == FirebaseAnswer.refused &&
        row!['firebase_linked'] == 1) {
      // Firebase knows this account and says no: an old password, even if
      // the phone still has it, no longer opens it.
      user = null;
    } else {
      user = await db.login(email, password);
      // First login of an account Firebase does not know: create its twin,
      // so the reset e-mail can reach it next time.
      if (user != null && firebase == FirebaseAnswer.refused) {
        await _linkToFirebase(int.parse(user.id), email, password);
      }
    }
    if (user != null) {
      _currentUser = user;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('logged_in_user_id', user.id);
      await prefs.setString('logged_in_user_role', user.role);
    }
    return user;
  }

  // ===== REGISTER =====
  static Future<bool> register({
    required String fullName,
    required String displayName,
    required String password,
    required String role,
    String? securityQuestion,
    String? securityAnswer,
  }) async {
    try {
      final newUser = AppUser(
        id: '0',
        fullName: fullName,
        displayName: displayName,
        role: role,
        points: 0,
      );
      final id = await DatabaseHelper.instance.insertUser(
        newUser,
        password,
        securityQuestion: securityQuestion,
        securityAnswer: securityAnswer,
      );
      await _linkToFirebase(id, fullName, password);
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<void> logout() {
    _currentUser = null;
    return _logoutInProgress = _forgetSession();
  }

  static Future<void> _forgetSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('logged_in_user_id');
    await prefs.remove('logged_in_user_role');
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
  }

  // ===== GOOGLE LOGIN =====
  static Future<AppUser?> signInWithGoogle() async {
    await _logoutInProgress;
    final gsi = GoogleSignIn(scopes: ['email']);
    final account = await gsi.signIn();
    if (account == null) return null;

    final email = account.email.toLowerCase();
    var row = await DatabaseHelper.instance.getUserByEmail(email);

    if (row == null) {
      await register(
        fullName: email,
        displayName: account.displayName ?? email.split('@').first,
        password: 'GOOGLE_${DateTime.now().millisecondsSinceEpoch}',
        role: 'guest',
      );
      row = await DatabaseHelper.instance.getUserByEmail(email);
    }
    if (row == null) return null;

    final user = AppUser(
      id: row['id'].toString(),
      fullName: row['full_name'] as String,
      displayName: row['display_name'] as String,
      role: row['role'] as String,
      points: (row['points'] as int?) ?? 0,
    );

    _currentUser = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('logged_in_user_id', user.id);
    await prefs.setString('logged_in_user_role', user.role);
    return user;
  }

  // ===== PASSWORD RESET BY E-MAIL (Firebase) =====
  static Future<String?> sendFirebaseResetEmail(String email) =>
      FirebaseAuthApi.sendPasswordReset(email);

  // ===== ADMIN =====
  static Future<List<AppUser>> allProfiles() async {
    return await DatabaseHelper.instance.getAllUsers();
  }

  static Future<void> updateRole(String userId, String newRole) async {
    await DatabaseHelper.instance.updateRole(int.parse(userId), newRole);
  }

  static Future<void> updateUser({
    required String userId,
    required String fullName,
    required String displayName,
    required String role,
  }) async {
    final id = int.parse(userId);
    await DatabaseHelper.instance.updateRole(id, role);
    await DatabaseHelper.instance.updateDisplayName(id, displayName);
  }

  static Future<void> createUser({
    required String email,
    required String password,
    required String fullName,
    required String role,
  }) async {
    final newUser = AppUser(
      id: '0',
      fullName: email,
      displayName: fullName,
      role: role,
      points: 0,
    );
    final id = await DatabaseHelper.instance.insertUser(newUser, password);
    await _linkToFirebase(id, email, password);
  }

  // ===== FIREBASE TWIN =====
  static bool _isEmail(String s) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);

  /// Creates the account in Firebase too (best effort: offline, it is done
  /// at the next login). An account already in Firebase with another
  /// password stays unlinked until Firebase accepts a login.
  static Future<void> _linkToFirebase(
    int id,
    String email,
    String password,
  ) async {
    if (!_isEmail(email.trim())) return;
    final answer = await FirebaseAuthApi.signUp(email, password);
    if (answer == FirebaseAnswer.accepted) {
      await DatabaseHelper.instance.markFirebaseLinked(id);
    }
  }

  static Future<void> deleteProfile(String userId) async {
    await DatabaseHelper.instance.deleteUser(int.parse(userId));
  }
}
