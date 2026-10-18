// Adapted from devmobile-Gestion-user/lib/models/app_user.dart.
class AppUser {
  final String id;
  final String fullName;
  final String role;
  final int points;
  final int revision;
  const AppUser({
    required this.id,
    required this.fullName,
    required this.role,
    this.points = 0,
    this.revision = 1,
  });
  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
    id: m['id'] as String,
    fullName: m['full_name'] as String? ?? '',
    role: m['role'] as String? ?? 'guest',
    points: (m['points'] as num?)?.toInt() ?? 0,
    revision: (m['revision'] as num?)?.toInt() ?? 1,
  );
  String get firstName => fullName.trim().isEmpty
      ? 'Invité'
      : fullName.trim().split(RegExp(r'\s+')).first;
  bool get canManageUsers => role == 'admin' || role == 'manager';
  bool get canUseHousekeeping => role == 'staff' || role == 'supervisor';
  String get roleLabel => roleLabels[role] ?? 'Rôle inconnu';
  static const roleLabels = {
    'guest': 'Client',
    'staff': 'Agent d’étage',
    'supervisor': 'Gouvernante',
    'manager': 'Manager',
    'maintenance': 'Maintenance',
    'admin': 'Administrateur',
  };
}
