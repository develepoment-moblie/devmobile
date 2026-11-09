// Inspection scoring. Pure Dart: no Flutter, no database.
//
// Each checklist item is rated OK (counts 1), partiel (0.5) or non conforme
// (0) and weighted 1 to 5 by its label. The score is the weighted share of
// the maximum, from 0 to 100, rounded to the nearest integer. A cleaning
// passes when its score reaches the category's threshold.

enum InspectionRating {
  ok('OK', 1),
  partial('Partiel', .5),
  failed('Non conforme', 0);

  final String label;
  final double value;
  const InspectionRating(this.label, this.value);

  static InspectionRating? parse(Object? name) =>
      values.where((r) => r.name == name).firstOrNull;
}

const defaultInspectionThreshold = 80;
const defaultItemWeight = 1;
const minItemWeight = 1, maxItemWeight = 5;

/// A category's grading: pass threshold and weight of each item label.
class InspectionRules {
  final int threshold;

  /// Weight by task label; labels not listed weigh [defaultItemWeight].
  final Map<String, int> weights;
  final int version;
  const InspectionRules({
    this.threshold = defaultInspectionThreshold,
    this.weights = const {},
    this.version = 0,
  });

  int weightOf(String label) => weights[label] ?? defaultItemWeight;

  factory InspectionRules.fromMap(Map? m) => m == null
      ? const InspectionRules()
      : InspectionRules(
          threshold: m['threshold'] as int,
          weights: (m['weights'] as Map).map(
            (k, v) => MapEntry(k as String, v as int),
          ),
          version: m['version'] as int,
        );
}

/// One rated item: its weight and rating.
typedef RatedItem = ({int weight, InspectionRating rating});

/// Weighted score from 0 to 100; 100 when nothing is rated.
int inspectionScore(Iterable<RatedItem> items) {
  var max = 0, earned = 0.0;
  for (final item in items) {
    max += item.weight;
    earned += item.weight * item.rating.value;
  }
  return max == 0 ? 100 : (earned / max * 100).round();
}

bool passes(int score, int threshold) => score >= threshold;

/// Checks a rules body (threshold 0-100, weights 1-5 per non-empty label).
/// Returns null when valid, else the reason in French.
String? invalidRules(Object? threshold, Object? weights) {
  if (threshold is! int || threshold < 0 || threshold > 100) {
    return 'Seuil de réussite de 0 à 100.';
  }
  if (weights is! Map || weights.length > 40) {
    return 'Pondérations invalides (40 tâches maximum).';
  }
  for (final e in weights.entries) {
    if (e.key is! String ||
        (e.key as String).trim().isEmpty ||
        (e.key as String).length > 120 ||
        e.value is! int ||
        (e.value as int) < minItemWeight ||
        (e.value as int) > maxItemWeight) {
      return 'Chaque tâche pèse de $minItemWeight à $maxItemWeight.';
    }
  }
  return null;
}
