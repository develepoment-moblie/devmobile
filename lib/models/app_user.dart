class AppUser {
  final String id;
  final String fullName;
  final String role;
  final int points;

  AppUser({
    required this.id,
    required this.fullName,
    required this.role,
    required this.points,
  });

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
    id: m['id'],
    fullName: m['full_name'] ?? '',
    role: m['role'] ?? 'guest',
    points: m['points'] ?? 0,
  );

  String get firstName {
    if (fullName.trim().isEmpty) return 'Invité';
    return fullName.split(' ').first;
  }
}