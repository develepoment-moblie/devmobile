class Priority {
  final int? id;
  final String icon;
  final String title;
  final String subtitle;
  final String colorType; // 'danger', 'success', 'terra'

  Priority({
    this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colorType,
  });

  factory Priority.fromMap(Map<String, dynamic> m) => Priority(
    id: m['id'] as int?,
    icon: m['icon'] as String? ?? 'info',
    title: m['title'] as String? ?? '',
    subtitle: m['subtitle'] as String? ?? '',
    colorType: m['color_type'] as String? ?? 'success',
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'icon': icon,
    'title': title,
    'subtitle': subtitle,
    'color_type': colorType,
  };
}