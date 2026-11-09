import '../../shared/models/app_user.dart';
import '../../shared/services/staff_directory.dart';

// TEMPORARY fictional team, used by the test login and by modules that need
// the staff list. The user_management owner replaces it with real accounts
// stored in SQLite, keeping the StaffDirectory contract.
class DemoStaffDirectory implements StaffDirectory {
  const DemoStaffDirectory();

  static const people = [
    AppUser(id: 'admin', fullName: 'Administrateur', role: AppRole.admin),
    AppUser(id: 'manager', fullName: 'Manager Démo', role: AppRole.manager),
    AppUser(
      id: 'reception',
      fullName: 'Inès Réception',
      role: AppRole.receptionist,
    ),
    AppUser(id: 'amina', fullName: 'Amina', role: AppRole.supervisor),
    AppUser(id: 'sarah', fullName: 'Sarah', role: AppRole.staff),
    AppUser(id: 'lina', fullName: 'Lina', role: AppRole.staff),
    AppUser(id: 'youssef', fullName: 'Youssef', role: AppRole.staff),
    AppUser(
      id: 'karim',
      fullName: 'Karim Technicien',
      role: AppRole.maintenance,
    ),
    AppUser(id: 'guest', fullName: 'Client Démo', role: AppRole.guest),
  ];

  @override
  Future<List<AppUser>> users({Set<String>? roles}) async => [
    for (final user in people)
      if (roles == null || roles.contains(user.role)) user,
  ]..sort((a, b) => a.fullName.compareTo(b.fullName));
}
