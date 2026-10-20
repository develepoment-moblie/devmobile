// Adapted from the Gestion User branch (Skander256): manager priorities.
class Priority {
  final String id;
  final String icon;
  final String title;
  final String subtitle;
  final String colorType; // 'danger', 'success' or 'terra'
  final int version;
  const Priority({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colorType,
    this.version = 1,
  });
  factory Priority.fromMap(Map<String, dynamic> m) => Priority(
    id: m['id'] as String,
    icon: m['icon'] as String? ?? 'info',
    title: m['title'] as String? ?? '',
    subtitle: m['subtitle'] as String? ?? '',
    colorType: m['color_type'] as String? ?? 'success',
    version: (m['version'] as num?)?.toInt() ?? 1,
  );
  static const icons = [
    'ac_unit',
    'calendar',
    'bed',
    'warning',
    'cleaning',
    'people',
    'star',
    'wrench',
    'coffee',
    'restaurant',
    'spa',
    'event',
  ];
  static const colorTypes = ['danger', 'terra', 'success'];
}
