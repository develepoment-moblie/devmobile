class AppUser {
  final String id;
  final String fullName;      // login key (email)
  final String displayName;   // real name shown in UI
  final String role;
  final int points;

  AppUser({
    required this.id,
    required this.fullName,
    required this.displayName,
    required this.role,
    required this.points,
  });

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
    id: m['id'].toString(),
    fullName: m['full_name'] ?? '',
    displayName: m['display_name'] ?? m['full_name'] ?? '',
    role: m['role'] ?? 'guest',
    points: m['points'] ?? 0,
  );

  String get firstName {
    final source = displayName.trim().isEmpty ? fullName : displayName;
    if (source.trim().isEmpty) return 'Invité';
    return source.split(' ').first;
  }
}