import 'dart:convert';
import 'dart:typed_data';

import '../models/intervention.dart';

/// Résultat du diagnostic IA d'une photo.
class AiDiagnosis {
  /// false si la photo ne montre aucun problème de maintenance.
  final bool isMaintenanceIssue;
  final InterventionCategory category;
  final InterventionPriority priority;
  final String title;
  final String description;

  const AiDiagnosis({
    required this.isMaintenanceIssue,
    required this.category,
    required this.priority,
    required this.title,
    required this.description,
  });
}

/// Type MIME de l'image d'après ses premiers octets (JPEG par défaut).
String detectImageMediaType(Uint8List b) {
  bool starts(List<int> sig) {
    if (b.length < sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (b[i] != sig[i]) return false;
    }
    return true;
  }

  if (starts([0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (starts([0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (starts([0x52, 0x49, 0x46, 0x46]) &&
      b.length > 11 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return 'image/webp';
  }
  return 'image/jpeg';
}

/// Lit la réponse texte du modèle (JSON, éventuellement entouré de texte
/// ou de balises ```). Renvoie null si elle est inexploitable.
AiDiagnosis? parseAiDiagnosis(String raw) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) return null;

  try {
    final map = jsonDecode(raw.substring(start, end + 1));
    if (map is! Map) return null;

    String s(String key) => (map[key] ?? '').toString().trim();

    final flag = map['is_maintenance_issue'];
    final isIssue = !(flag == false || flag == 'false');

    final category = InterventionCategory.fromDb(s('category').toLowerCase());
    final priority = _priorityFrom(s('priority'));

    var title = s('title');
    if (title.length > 60) title = '${title.substring(0, 57).trimRight()}…';
    final description = s('description');

    if (isIssue && title.isEmpty && description.isEmpty) return null;

    return AiDiagnosis(
      isMaintenanceIssue: isIssue,
      category: category,
      priority: priority,
      title: title,
      description: description,
    );
  } catch (_) {
    return null;
  }
}

InterventionPriority _priorityFrom(String v) {
  switch (v.toLowerCase()) {
    case 'urgent':
      return InterventionPriority.urgent;
    case 'high':
    case 'élevée':
    case 'elevee':
    case 'haute':
      return InterventionPriority.high;
    default:
      return InterventionPriority.normal;
  }
}
