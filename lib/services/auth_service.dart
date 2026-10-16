import '../models/app_user.dart';
import 'database_helper.dart';

class AuthService {
  static AppUser? _currentUser;
  static AppUser? get currentUser => _currentUser;

  static Future<AppUser?> login(String fullName, String password) async {
    final user = await DatabaseHelper.instance.login(fullName, password);
    _currentUser = user;
    return user;
  }

  /// Register: `fullName` is the login key (email). `displayName` is the visible name.
  static Future<bool> register({
    required String fullName,
    required String displayName,
    required String password,
    required String role,
  }) async {
    try {
      final newUser = AppUser(
        id: '0',
        fullName: fullName,
        displayName: displayName,
        role: role,
        points: 0,
      );
      await DatabaseHelper.instance.insertUser(newUser, password);
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<void> logout() async {
    _currentUser = null;
  }

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
      displayName: fullName,   // the visible name
      role: role,
      points: 0,
    );
    await DatabaseHelper.instance.insertUser(newUser, password);
  }

  static Future<void> deleteProfile(String userId) async {
    await DatabaseHelper.instance.deleteUser(int.parse(userId));
  }
}