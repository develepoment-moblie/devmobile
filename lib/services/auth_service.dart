import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/app_user.dart';
import 'database_helper.dart';

class AuthService {
  static AppUser? _currentUser;
  static AppUser? get currentUser => _currentUser;

  // === Restore the session ===
  static Future<void> initSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('logged_in_user_id');

    if (userId != null) {
      _currentUser = await DatabaseHelper.instance.getUserById(int.parse(userId));
    }
  }

  static Future<AppUser?> login(String fullName, String password) async {
    final user = await DatabaseHelper.instance.login(fullName, password);
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
      await DatabaseHelper.instance.insertUser(
        newUser,
        password,
        securityQuestion: securityQuestion,
        securityAnswer: securityAnswer,
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<void> logout() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}

    _currentUser = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('logged_in_user_id');
    await prefs.remove('logged_in_user_role');
  }

  // ===== GOOGLE LOGIN =====
  static Future<AppUser?> signInWithGoogle() async {
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

  // ===== FIREBASE PASSWORD RESET (REST API) =====
  static Future<String?> sendFirebaseResetEmail(String email) async {
    // ✅ YOUR FIREBASE WEB API KEY IS NOW ADDED HERE
    const String apiKey = 'AIzaSyAkkF-vi2JbI1tHFpNSaxRpsXvHl_5zbec';

    final url = Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=$apiKey');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'requestType': 'PASSWORD_RESET',
          'email': email.trim(),
        }),
      );

      if (response.statusCode == 200) {
        return null; // SUCCESS
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['error']['message'];

        if (errorMessage == 'EMAIL_NOT_FOUND') {
          return 'Aucun compte Firebase n\'existe avec cet email.';
        } else if (errorMessage == 'INVALID_EMAIL') {
          return 'L\'adresse email est invalide.';
        } else {
          return 'Erreur: $errorMessage';
        }
      }
    } catch (e) {
      return 'Erreur réseau. Vérifiez votre connexion.';
    }
  }

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
    await DatabaseHelper.instance.insertUser(newUser, password);
  }

  static Future<void> deleteProfile(String userId) async {
    await DatabaseHelper.instance.deleteUser(int.parse(userId));
  }
}