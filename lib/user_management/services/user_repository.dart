import '../../shared/services/app_exception.dart';
import '../models/app_user.dart';

abstract class UserRepository {
  String? get sessionUserId;
  Stream<void> get sessionChanges;
  Future<void> login(String email, String password);
  Future<void> register(String email, String password, String name);
  Future<void> logout();
  Future<AppUser> currentProfile();
  Future<List<AppUser>> allProfiles();
  Future<void> updateUser(AppUser original, String name, String role);
  Future<void> createUser(
    String email,
    String password,
    String name,
    String role,
  );
  Future<void> deleteProfile(AppUser original);
}

String userError(Object error) => error is AppServiceException
    ? error.message
    : 'Les données locales ne sont pas disponibles. Réessayez après avoir relancé l’application.';
