// The signed-in person, as every module sees it. The user_management module
// creates it; other modules only read it.
class AppUser {
  final String id;
  final String fullName;
  final String role;
  const AppUser({required this.id, required this.fullName, required this.role});

  String get firstName => fullName.trim().isEmpty
      ? 'Invité'
      : fullName.trim().split(RegExp(r'\s+')).first;
  String get roleLabel => AppRole.labels[role] ?? 'Rôle inconnu';
  bool hasAnyRole(Set<String> roles) => roles.contains(role);
}

// Shared role names. Changing this list needs the whole team's agreement.
abstract final class AppRole {
  static const guest = 'guest';
  static const receptionist = 'receptionist';
  static const staff = 'staff';
  static const supervisor = 'supervisor';
  static const maintenance = 'maintenance';
  static const manager = 'manager';
  static const admin = 'admin';

  static const labels = {
    guest: 'Client',
    receptionist: 'Réceptionniste',
    staff: 'Agent d’étage',
    supervisor: 'Gouvernante',
    maintenance: 'Technicien de maintenance',
    manager: 'Manager',
    admin: 'Administrateur',
  };
  static const all = {
    guest,
    receptionist,
    staff,
    supervisor,
    maintenance,
    manager,
    admin,
  };
  static const management = {manager, admin};
}
